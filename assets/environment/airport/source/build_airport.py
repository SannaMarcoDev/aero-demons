"""Executed in Blender through MCP. Source recipe; delivered .blend/.glb are authoritative."""
import bpy, math, json, os
from mathutils import Vector
from collections import defaultdict
BASE = r'C:/Users/sanna/Workspace/Godot/Progetti/aero-demons'
OUT = BASE + '/assets/environment/airport'
os.makedirs(OUT+'/source/previews', exist_ok=True)
scene = bpy.data.scenes.new('airport_authoring')
bpy.context.window.scene = scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1
asset_collection = bpy.data.collections.new('airport_asset')
scene.collection.children.link(asset_collection)
def empty(name, parent=None):
    o=bpy.data.objects.new(name,None); asset_collection.objects.link(o); o.parent=parent; return o
root=empty('airport_root')
groups={n:empty(n,root) for n in ['runway','taxiways','aprons','service_roads','buildings','markings','details']}
def material(name,color,rough=.8,metal=0):
    m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=rough; p.inputs['Metallic'].default_value=metal
    return m
concrete=material('weathered_concrete',(.43,.46,.47))
asphalt=material('service_asphalt',(.12,.145,.16))
wall=material('industrial_wall',(.40,.43,.43))
metal=material('galvanized_roof',(.49,.53,.54),.64,.35)
steel=material('dark_structural_steel',(.13,.18,.20),.55,.5)
glass=material('roof_glazing',(.13,.25,.31),.36,.35)
white=material('runway_white',(.84,.85,.80))
yellow=material('taxiway_yellow',(.66,.46,.10))
rubber=material('rubber_traces',(.22,.235,.24))
collisions=[]
def mesh(name,verts,faces,mat,parent,origin=(0,0,0)):
    me=bpy.data.meshes.new(name); me.from_pydata(verts,[],faces); me.update()
    o=bpy.data.objects.new(name,me); asset_collection.objects.link(o); o.parent=parent; o.location=origin; me.materials.append(mat)
    uv=me.uv_layers.new(name='metric_uv')
    for p in me.polygons:
        axis=max(range(3),key=lambda a:abs(p.normal[a])); axes=[a for a in range(3) if a!=axis]
        for li in p.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co
            uv.data[li].uv=(co[axes[0]]/24,co[axes[1]]/24)
    return o
def box(name,loc,size,mat,parent,collision=False):
    x,y,z=(s/2 for s in size)
    v=[(-x,-y,0),(x,-y,0),(x,y,0),(-x,y,0),(-x,-y,2*z),(x,-y,2*z),(x,y,2*z),(-x,y,2*z)]
    o=mesh(name,v,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],mat,parent,loc)
    if collision: collisions.append((name,(loc[0],loc[2]+z,-loc[1]),(size[0],size[2],size[1])))
    return o
# Surface rectangles are partitioned globally: shared edges, no coplanar overlaps.
regions=[]
def region(name,group,x0,x1,y0,y1,mat): regions.append((name,group,x0,x1,y0,y1,mat))
region('runway_surface','runway',-30,30,-1200,1200,concrete)
region('parallel_taxiway','taxiways',-174,-146,-1200,1200,concrete)
for i,y in enumerate([-1180,-600,0,600,1180]): region('west_link_%02d'%i,'taxiways',-146,-30,y-20,y+20,asphalt)
region('shelter_apron','aprons',110,230,-1200,-540,concrete)
region('hangar_apron','aprons',315,535,-1200,-730,concrete)
for i,y in enumerate([-1180,-560]): region('east_link_%02d'%i,'taxiways',30,350,y-20,y+20,concrete)
region('hangar_service_link','service_roads',332,350,-730,-540,asphalt)
region('technical_apron','aprons',-525,-290,-330,-100,concrete)
region('south_service_apron','aprons',-410,-260,-900,-790,concrete)
region('north_service_apron','aprons',-300,-174,360,600,concrete)
region('radome_apron','aprons',-430,-280,900,1080,concrete)
region('radar_apron','aprons',-360,-280,740,830,concrete)
region('west_service_spine','service_roads',-280,-262,-1200,1120,asphalt)
for i,(y,x0,x1) in enumerate([(-1180,-262,-174),(-845,-262,-174),(-220,-290,-174),(785,-280,-174),(990,-280,-174),(1110,-280,-174)]):
    region('service_cross_%02d'%i,'service_roads',x0,x1,y-10,y+10,asphalt)
region('technical_access','service_roads',-580,-525,-240,-222,asphalt)
xs=sorted({r[i] for r in regions for i in [2,3]}); ys=sorted({r[i] for r in regions for i in [4,5]})
tiles=defaultdict(list)
for a,b in zip(xs,xs[1:]):
    for c,d in zip(ys,ys[1:]):
        cx,cy=(a+b)/2,(c+d)/2
        for r in regions:
            if r[2]<=cx<=r[3] and r[4]<=cy<=r[5]: tiles[r[0]].append((a,b,c,d)); break
pavement=[]
for r in regions:
    v=[]; f=[]
    for a,b,c,d in tiles[r[0]]:
        k=len(v); v.extend([(a,c,0),(b,c,0),(b,d,0),(a,d,0)]); f.append((k,k+1,k+2,k+3))
    if f: pavement.append(mesh(r[0],v,f,r[6],groups[r[1]]))
# Chamfered taxiway mouths are genuine additional pavement, not overlapping decals.
for y in [-600,0,600]:
    for sign in [-1,1]:
        verts=[(-55,y+sign*20,0),(-30,y+sign*20,0),(-30,y+sign*45,0)]
        if sign<0: verts.reverse()
        pavement.append(mesh('taxi_flare_%s_%s'%(y,sign),verts,[(0,1,2)],asphalt,groups['taxiways']))
# Main hangar: three long roof bays, genuinely open southern portal, no front cap.
h=empty('main_hangar',groups['buildings']); h.location=(425,-965,0)
def hb(name,loc,size,mat,solid=False):
    o=box(name,loc,size,mat,h)
    if solid: collisions.append((name,(425+loc[0],loc[2]+size[2]/2,965-loc[1]),(size[0],size[2],size[1])))
    return o
hb('hangar_west_wall',(-87,0,0),(2,350,27),wall,True)
hb('hangar_east_wall',(87,0,0),(2,350,27),wall,True)
hb('hangar_back_wall',(0,174,0),(172,2,27),wall,True)
hb('hangar_front_left',(-61,-174,0),(50,2,27),wall,True)
hb('hangar_front_right',(61,-174,0),(50,2,27),wall,True)
hb('hangar_portal_header',(0,-174,21),(72,2,6),wall,True)
for i,x in enumerate([-58,0,58]):
    v=[(x-29,-176,27),(x+29,-176,27),(x+29,176,27),(x-29,176,27),(x,-176,31),(x,176,31)]
    mesh('hangar_roof_bay_%02d'%i,v,[(0,4,5,3),(4,1,2,5),(0,1,4),(3,5,2)],metal,h)
# Four linked arch shelters, each open at the southern end.
def arch_mesh():
    v=[];f=[]; steps=20
    for yy in [-23,23]:
        for radius in [19,18]:
            for i in range(steps+1):
                a=math.pi*i/steps; v.append((radius*math.cos(a),yy,2+radius*.68*math.sin(a)))
    n=steps+1
    for i in range(steps):
        f.extend([(i,i+1,2*n+i+1,2*n+i),(n+i,3*n+i,3*n+i+1,n+i+1),(i,n+i,n+i+1,i+1),(2*n+i,2*n+i+1,3*n+i+1,3*n+i)])
    f.extend([(0,2*n,3*n,n),(n-1,2*n-1,4*n-1,3*n-1)])
    return v,f
v,f=arch_mesh(); prototype=None
for i,y in enumerate([-1090,-940,-790,-640]):
    s=empty('arched_shelter_%02d'%(i+1),groups['buildings']); s.location=(190,y,0)
    if prototype is None: prototype=mesh('shelter_shell_01',v,f,metal,s)
    else:
        o=bpy.data.objects.new('shelter_shell_%02d'%(i+1),prototype.data); asset_collection.objects.link(o); o.parent=s
    for side in [-1,1]:
        box('shelter_foundation_%02d_%s'%(i,side),(side*18.5,0,0),(1,46,2),wall,s)
        collisions.append(('shelter_wall_%s_%s'%(i,side),(190+side*18.5,5,-y),(1.5,10,46)))
    back=[(19,23,0),(-19,23,0)]+[(19*math.cos(math.pi-j*math.pi/20),23,2+19*.68*math.sin(math.pi-j*math.pi/20)) for j in range(21)]
    mesh('shelter_back_%02d'%i,back,[tuple(range(len(back)))],wall,s)
    collisions.append(('shelter_back_%s'%i,(190,7,-y-23),(38,14,1)))
    collisions.append(('shelter_roof_%s'%i,(190,14,-y),(24,2,46)))
# Technical complex, intentionally sparse rather than a dense base.
tech=empty('technical_complex',groups['buildings']); tech.location=(-415,-235,0)
for i,(x,y,w,d,z) in enumerate([(-40,0,42,72,64),(15,0,54,82,73),(50,12,20,52,58),(-20,50,100,30,13)]):
    box('technical_volume_%02d'%i,(x,y,0),(w,d,z),wall,tech)
    collisions.append(('technical_volume_%s'%i,(-415+x,z/2,235-y),(w,z,d)))
for name,x,y,w,d,z in [('south_operations',-342,-843,85,45,12),('north_workshop',-238,480,75,40,11),('radar_equipment',-320,785,22,24,10)]:
    box(name,(x,y,0),(w,d,z),wall,groups['buildings'],True)
# Hemisphere scaled vertically, plus low circular plinth.
bpy.ops.mesh.primitive_uv_sphere_add(segments=32,ring_count=16,radius=1,location=(-354,990,0))
dome=bpy.context.object; dome.name='radome_shell'
for c in list(dome.users_collection): c.objects.unlink(dome)
asset_collection.objects.link(dome); dome.parent=groups['buildings']
# Keep upper hemisphere only; skirt ends exactly on pavement.
import bmesh
bm=bmesh.new(); bm.from_mesh(dome.data); bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z < -0.00001],context='VERTS'); bm.to_mesh(dome.data); bm.free()
for v in dome.data.vertices: v.co.x*=51; v.co.y*=51; v.co.z*=31
for p in dome.data.polygons: p.use_smooth=True
dome.data.materials.append(metal)
collisions.append(('radome',(-354,14,-990),(78,28,78)))
# Presentation collection never exported.
presentation=bpy.data.collections.new('preview_only_excluded'); scene.collection.children.link(presentation)
def present(o):
    for c in list(o.users_collection): c.objects.unlink(o)
    presentation.objects.link(o)
bpy.ops.mesh.primitive_plane_add(size=20000,location=(0,0,-.35)); ground=bpy.context.object; ground.name='preview_ground_not_exported'; present(ground); ground.data.materials.append(material('preview_grass',(.12,.18,.12)))
bpy.ops.object.light_add(type='SUN',location=(500,-900,1600)); sun=bpy.context.object; present(sun); sun.name='preview_sun'; sun.rotation_euler=(.45,-.5,-.5); sun.data.energy=3; sun.data.angle=.12
bpy.ops.object.camera_add(); camera=bpy.context.object; present(camera); camera.name='preview_camera'; scene.camera=camera
scene.render.engine='CYCLES'; scene.cycles.samples=16
scene.render.resolution_x=1400; scene.render.resolution_y=1400; scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('airport_preview_world'); scene.world.use_nodes=True; scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.45,.55,.7,1); scene.world.node_tree.nodes['Background'].inputs[1].default_value=.5
scene.view_settings.view_transform='AgX'
def view(loc,target,ortho=None):
    camera.location=loc; camera.rotation_euler=(Vector(target)-camera.location).to_track_quat('-Z','Y').to_euler(); camera.data.type='ORTHO' if ortho else 'PERSP'; camera.data.ortho_scale=ortho or 1000; camera.data.lens=45; camera.data.clip_end=30000
view((0,0,3500),(0,0,0),2700)
scene.render.filepath=OUT+'/source/previews/blockout_top.png'
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/source/airport.blend')
print('BLOCKOUT_READY',len(pavement),'pavement meshes',len(collisions),'simple building collision volumes')
