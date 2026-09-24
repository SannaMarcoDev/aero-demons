"""Run through Blender MCP after build_geometry.py. Does not alter existing scenes.
Recipe entry point is build(); inspection/export are deliberately separate stages.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent
ASSET = HERE.parent.parent

def enum_set(owner, key, value):
    choices = [i.identifier for i in owner.bl_rna.properties[key].enum_items]
    assert value in choices, (key, value, choices)
    setattr(owner, key, value)

def material(name, color, rough=.85):
    m = bpy.data.materials.new('AD2_' + name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    image_name = {'asphalt':'asphalt','taxi_asphalt':'road','road':'road','concrete':'concrete'}.get(name)
    if image_name:
        tex=m.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image=bpy.data.images.load(str(HERE/(image_name+'_base.jpg')),check_existing=True)
        tex.image.pack()
        m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    return m

def mesh(name, vertices, faces, mat, collection, origin=(0,0,0)):
    me = bpy.data.meshes.new(name)
    me.from_pydata(vertices, [], faces)
    me.update()
    o = bpy.data.objects.new(name, me)
    collection.objects.link(o)
    o.location = origin
    me.materials.append(mat)
    uv = me.uv_layers.new(name='Metric_8m')
    for p in me.polygons:
        axis = max(range(3), key=lambda a: abs(p.normal[a]))
        axes = [a for a in range(3) if a != axis]
        for li in p.loop_indices:
            co = me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv = ((co[axes[0]]+origin[axes[0]])/8, (co[axes[1]]+origin[axes[1]])/8)
    return o

def block(name, x,y,w,d,h,mat,collection,z=0):
    v = [(-w/2,-d/2,0),(w/2,-d/2,0),(w/2,d/2,0),(-w/2,d/2,0),(-w/2,-d/2,h),(w/2,-d/2,h),(w/2,d/2,h),(-w/2,d/2,h)]
    return mesh(name,v,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],mat,collection,(x,y,z))

def text(name,body,loc,size,mat,collection,rotation=0):
    cu=bpy.data.curves.new(name,'FONT'); cu.body=body; cu.size=size
    o=bpy.data.objects.new(name,cu); collection.objects.link(o)
    o.location=loc; o.rotation_euler.z=rotation; cu.materials.append(mat)
    return o

def camera(name,loc,target,ortho=None):
    data=bpy.data.cameras.new(name); data.clip_end=20000; data.clip_start=1
    o=bpy.data.objects.new(name,data); collections['PRESENTATION'].objects.link(o)
    o.location=loc; o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    enum_set(data,'type','ORTHO' if ortho else 'PERSP')
    data.ortho_scale=ortho or 1000; data.lens=40
    return o

def build():
    global scene, collections, mats, payload
    assert 'AERO_DEMONS_LAYOUT_V2' not in bpy.data.scenes, 'Refuse to overwrite authored scene; edit it explicitly.'
    payload=json.loads((HERE/'geometry.json').read_text())
    scene=bpy.data.scenes.new('AERO_DEMONS_LAYOUT_V2'); bpy.context.window.scene=scene
    enum_set(scene.unit_settings,'system','METRIC'); scene.unit_settings.scale_length=1
    airport=bpy.data.collections.new('AIRPORT'); scene.collection.children.link(airport)
    names=['RUNWAY','TAXIWAYS','ROADS','APRONS','BUILDING_BLOCKOUTS','INDUSTRIAL_BLOCKOUTS','RADAR_BLOCKOUTS','MARKINGS','UTILITIES','COLLISIONS']
    collections={}
    for name in names:
        c=bpy.data.collections.new(name); airport.children.link(c); collections[name]=c
    for name in ['PRESENTATION','LEGEND','DESIGN_PATHS']:
        c=bpy.data.collections.new(name); scene.collection.children.link(c); collections[name]=c
    collections['DESIGN_PATHS'].hide_render=True
    colors={'asphalt':(.075,.088,.102),'taxi_asphalt':(.10,.115,.13),'road':(.12,.135,.15),
        'concrete':(.52,.53,.49),'yard':(.39,.415,.40),'shoulder':(.245,.235,.21),'gravel':(.39,.32,.225),
        'white':(.91,.93,.89),'yellow':(1,.63,.025),'joint':(.28,.295,.28),
        'red':(.70,.045,.04),'orange':(1,.245,.028),'blue':(.035,.25,.66),'purple':(.40,.085,.68),
        'white_block':(.83,.855,.85),'green':(.045,.42,.15),'ground':(.43,.30,.17),'ink':(.09,.125,.16)}
    mats={n:material(n,c) for n,c in colors.items()}
    for data in payload['objects']:
        # Local origins support modular editing without kilometre-sized local coordinates.
        x=round(sum(v[0] for v in data['verts'])/len(data['verts'])/100)*100
        y=round(sum(v[1] for v in data['verts'])/len(data['verts'])/100)*100
        vertices=[(v[0]-x,v[1]-y,v[2]) for v in data['verts']]
        o=mesh(data['name'],vertices,data['faces'],mats[data['material']],collections[data['group']],(x,y,0))
        o['role']=data['group']; o['surface_level_m']=0.0
        if data['group']=='COLLISIONS':
            o.hide_render=True; enum_set(o,'display_type','WIRE')
    for name,mat,x,y,w,d,h in payload['buildings']:
        group='INDUSTRIAL_BLOCKOUTS' if mat=='yellow' else ('RADAR_BLOCKOUTS' if mat=='purple' else 'BUILDING_BLOCKOUTS')
        o=block(name,x,y,w,d,h,mats[mat],collections[group]); o['placeholder']=True; o['category']=mat
        o['front_direction']='+X / apron'; o['dimensions_m']=[w,d,h]
    block('T01_Tower_cab_BLOCK',-540,255,24,24,8,mats['purple'],collections['RADAR_BLOCKOUTS'],38)['placeholder']=True
    # Extremely simple radome silhouette, no architectural detail.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8,radius=18,location=(-558,433,29))
    dome=bpy.context.object; dome.name='R01_Radome_BLOCK'
    for c in list(dome.users_collection): c.objects.unlink(dome)
    collections['RADAR_BLOCKOUTS'].objects.link(dome); dome.data.materials.append(mats['purple']); dome['placeholder']=True
    for route in payload['routes']:
        cu=bpy.data.curves.new(route['name'],'CURVE'); enum_set(cu,'dimensions','3D')
        s=cu.splines.new('POLY'); s.points.add(len(route['points'])-1)
        for p,co in zip(s.points,route['points']): p.co=(*co,.04,1)
        o=bpy.data.objects.new(route['name'],cu); collections['DESIGN_PATHS'].objects.link(o); o.hide_set(True)
    # Mesh runway numbers, not font objects in the game export.
    for label,y,angle in [('36',-1138,0),('18',1138,math.pi)]:
        o=text('RWY_designator_'+label,label,(0,y,.018),20,mats['white'],collections['MARKINGS'],angle)
        enum_set(o.data,'align_x','CENTER'); bpy.context.view_layer.update()
        o.scale=(14/o.dimensions.x,20/o.dimensions.y,1)
        bpy.ops.object.select_all(action='DESELECT'); o.select_set(True); bpy.context.view_layer.objects.active=o
        bpy.ops.object.convert(target='MESH'); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
        uv=o.data.uv_layers.new(name='Metric_8m')
        for loop in o.data.loops: uv.data[loop.index].uv=o.data.vertices[loop.vertex_index].co.xy/8
    # Separate review stage: never included in GLB or collisions.
    block('REVIEW_ground',-350,0,14000,14000,.10,mats['ground'],collections['PRESENTATION'],-.18)
    ld=bpy.data.lights.new('Review_sun','SUN'); ld.energy=2.7; ld.angle=.15
    light=bpy.data.objects.new('Review_sun',ld); collections['PRESENTATION'].objects.link(light); light.rotation_euler=(.42,-.55,-.5)
    scene.world=bpy.data.worlds.new('AD2_world'); scene.world.use_nodes=True
    bg=next(n for n in scene.world.node_tree.nodes if n.type=='BACKGROUND'); bg.inputs[0].default_value=(.48,.58,.72,1); bg.inputs[1].default_value=.45
    # Mild ground variation is presentation-only; infrastructure stays glTF/PBR-native.
    m=mats['ground']; p=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    n=m.node_tree.nodes.new('ShaderNodeTexNoise'); n.inputs['Scale'].default_value=450
    ramp=m.node_tree.nodes.new('ShaderNodeValToRGB'); ramp.color_ramp.elements[0].color=(.27,.175,.085,1); ramp.color_ramp.elements[1].color=(.52,.38,.215,1)
    m.node_tree.links.new(n.outputs['Fac'],ramp.inputs[0]); m.node_tree.links.new(ramp.outputs['Color'],p.inputs['Base Color'])
    scene.camera=camera('01_REFERENCE_AERIAL',(2000,-2700,2200),(-350,0,0),2950)
    camera('02_PLAN',(-430,0,3300),(-430,0,0),2850)
    camera('03_GAMEPLAY_approach',(100,-1360,160),(-60,-950,0))
    camera('04_APRON_low',(-60,-900,145),(-445,-340,0))
    camera('05_NORTH_services',(100,380,240),(-525,790,0))
    legend=collections['LEGEND']
    text('Title','AERO DEMONS',(-1190,270,.08),36,mats['ink'],legend)
    text('Subtitle','MAIN AIRFIELD  /  INFRASTRUCTURE STUDY',(-1190,235,.08),11,mats['ink'],legend)
    entries=[('red','MAINTENANCE'),('orange','AIRCRAFT SHELTERS'),('blue','OPERATIONS'),('purple','ATC / RADAR / COMMS'),('yellow','FUEL / UTILITIES'),('green','LOGISTICS'),('white_block','SECONDARY')]
    for i,(mat,label) in enumerate(entries):
        y=180-i*40
        block('Legend_'+mat,-1176,y,22,22,.08,mats[mat],legend)
        text('Legend_label_'+mat,label,(-1147,y-6,.12),14,mats['ink'],legend)
    text('Scale_caption','METRES  |  RWY 2400 x 60  |  TWY 23',(-1190,-150,.08),13,mats['ink'],legend)
    text('Revision','02 / COLOR BLOCKOUTS ONLY',(-1190,-178,.08),12,mats['ink'],legend)
    # Scale bar and north arrow live only in the authoring legend.
    block('Scale_100m',-1140,-215,100,3,.08,mats['ink'],legend)
    text('Scale_label','100 m',(-1190,-240,.08),13,mats['ink'],legend)
    text('North','N  +Y',(-1188,340,.08),20,mats['ink'],legend)
    for body,x,y in [('01  MAINTENANCE',-535,-815),('02  SHELTERS',-470,192),('03  OPERATIONS',-672,333),('04  RADAR',-637,535),('05  TECHNICAL',-493,1030),('06  LOGISTICS',-858,-770)]:
        text('Zone_'+body[:2],body,(x,y,.06),11,mats['ink'],legend)
    scene.render.resolution_x=1920; scene.render.resolution_y=1200; scene.render.resolution_percentage=100
    enum_set(scene.render.image_settings,'file_format','PNG')
    scene.render.engine='CYCLES'; scene.cycles.samples=24
    scene.cycles.use_denoising=True
    for area in bpy.context.screen.areas:
        if area.type=='VIEW_3D':
            s=area.spaces.active; s.clip_end=20000
            enum_set(s.shading,'type','MATERIAL'); s.overlay.show_overlays=False
            enum_set(s.region_3d,'view_perspective','CAMERA')
    bpy.ops.object.select_all(action='DESELECT')
    scene['layout_dimensions']=json.dumps(payload['dimensions'])
    scene['note']='New reference-driven revision. Existing airport and city are not overwritten.'
    print('AIRPORT_BUILD_OK',len(scene.objects),'objects')

def refresh_surfaces(names=None):
    payload=json.loads((HERE/'geometry.json').read_text())
    for data in payload['objects']:
        if names is not None and data['name'] not in names:
            continue
        old=bpy.data.objects.get(data['name']+'-col') or bpy.data.objects.get(data['name'])
        if old:
            col=old.users_collection[0]; mat=old.data.materials[0]; old_mesh=old.data
            bpy.data.objects.remove(old,do_unlink=True)
            if old_mesh.users==0: bpy.data.meshes.remove(old_mesh)
        else:
            assert data['group']=='COLLISIONS'
            col=bpy.data.collections.get('COLLISIONS')
            if col is None:
                col=bpy.data.collections.new('COLLISIONS'); bpy.data.collections['AIRPORT'].children.link(col)
            mat=bpy.data.materials['AD2_'+data['material']]
        # Integer metric origins keep chunk seams bit-identical after float32 glTF import.
        x=round(sum(v[0] for v in data['verts'])/len(data['verts'])/100)*100
        y=round(sum(v[1] for v in data['verts'])/len(data['verts'])/100)*100
        o=mesh(data['name'],[(v[0]-x,v[1]-y,v[2]) for v in data['verts']],data['faces'],mat,col,(x,y,0))
        o['role']=data['group']; o['surface_level_m']=0.0
        if data['group']=='COLLISIONS':
            o.hide_render=True; enum_set(o,'display_type','WIRE')
    return payload

def render(name,camera_name,width=1920,height=1200):
    scene.camera=bpy.data.objects[camera_name]
    scene.render.resolution_x=width; scene.render.resolution_y=height
    scene.render.filepath=str(HERE/(name+'.png'))
    bpy.ops.render.render(write_still=True)
    print('RENDER_OK',name)

if __name__ == '__main__':
    build()
