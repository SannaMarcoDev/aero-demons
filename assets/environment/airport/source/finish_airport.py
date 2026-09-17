"""Second authoring stage; run with the build_airport namespace in Blender MCP."""
import numpy as np
# Small real, tileable PBR base-color textures; no runtime procedural nodes.
os.makedirs(OUT+'/textures',exist_ok=True)
rng=np.random.default_rng(781)
for mat,col,joints in [(concrete,(.48,.50,.49),True),(asphalt,(.19,.215,.225),False),(wall,(.49,.51,.50),False),(metal,(.57,.60,.61),False)]:
    n=512; yy,xx=np.mgrid[:n,:n]; noise=rng.normal(0,.013,(n,n))
    # Periodic low frequency variation remains seamless at tile boundaries.
    noise+=.018*np.sin(xx*math.tau/n)*np.cos(yy*math.tau/n)+.008*np.cos((xx+yy)*3*math.tau/n)
    if joints: noise[(xx%128<1)|(yy%128<1)]-=.10
    rgba=np.ones((n,n,4),dtype=np.float32)
    rgba[:,:,:3]=np.clip(np.array(col)[None,None,:]+noise[:,:,None],0,1)
    im=bpy.data.images.new(mat.name+'_albedo',width=n,height=n); im.pixels.foreach_set(rgba.ravel()); im.filepath_raw=OUT+'/textures/'+mat.name+'_albedo.png'; im.file_format='PNG'; im.save()
    tex=mat.node_tree.nodes.new('ShaderNodeTexImage'); tex.image=im; tex.extension='REPEAT'; mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
# Batched static details per zone, not one object for every stripe or mullion.
def join_objects(name,objects,parent):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects: o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]; bpy.ops.object.join(); o=objects[0]; o.name=name
    # Preserve world transform and use a convenient parent-space origin.
    mw=o.matrix_world.copy(); o.parent=parent; o.matrix_world=mw
    return o
def strips(name,rects,mat,parent,z=.055):
    v=[];f=[]
    for x,y,w,d in rects:
        k=len(v);v.extend([(x-w/2,y-d/2,z),(x+w/2,y-d/2,z),(x+w/2,y+d/2,z),(x-w/2,y+d/2,z)]);f.append((k,k+1,k+2,k+3))
    return mesh(name,v,f,mat,parent)
r=[(0,y,1.5,30) for y in range(-1080,1081,60)]
r.extend([(x,0,1.2,2390) for x in [-27.5,27.5]])
for sign in [-1,1]:
    r.extend([(x,sign*1150,2.4,40) for x in [-22,-18,-14,-10,-6,6,10,14,18,22]])
    r.extend([(x,sign*870,7,45) for x in [-19,19]])
    for y in [1000,700,550]: r.extend([(x,sign*y,2,22) for x in [-18,-14,14,18]])
strips('runway_markings',r,white,groups['markings'])
strips('taxiway_guides',[(-160,0,.5,2370)]+[(-92,y,125,.5) for y in [-1180,-600,0,600,1180]]+[(132,-1180,204,.5),(132,-560,204,.5),(140,-860,.5,600)],yellow,groups['markings'])
strips('hold_short_markings',[(x,y,1,27) for y in [-600,0,600] for x in [-67,-63]],yellow,groups['markings'])
# Modest broken touchdown traces, deliberately offset from white markings.
strips('touchdown_rubber',[(x,y,1.0,18+(i%4)*8) for i,y in enumerate(range(-1080,-760,35)) for x in [-4,4]]+[(x,y,1,22) for y in range(780,1050,42) for x in [-4,4]],rubber,groups['markings'],.065)
parts=[]
for x in [-58,0,58]:
    for y in range(-145,150,35):
        # Skylights follow the pitched bay slope and sit above the roof.
        for side in [-1,1]:
            o=hb('roof_glazing_panel',(x+side*12,y,29.45),(16,14,.35),glass); o.rotation_euler[1]=side*math.atan(4/29);parts.append(o)
            for dy in [-7,0,7]:
                o=hb('roof_glazing_mullion',(x+side*12,y+dy,29.82),(16,.35,.25),steel); o.rotation_euler[1]=side*math.atan(4/29); parts.append(o)
            for dx in [-8,-4,0,4,8]:
                parts.append(hb('roof_glazing_crossbar',(x+side*12+dx,y,29.82-side*dx*4/29),(.3,14,.25),steel))
        parts.append(hb('roof_vent',(x,y+12,31.0),(2.2,2.2,1.2),steel))
for x in [-87.8,87.8]:
    for y in range(-170,176,25): parts.append(hb('hangar_pilaster',(x,y,0),(1.5,1.8,27.4),steel))
for y in [-175,175]:
    for x in range(-80,81,16): parts.append(hb('hangar_facade_rib',(x,y,22),(1,1,5),steel))
# Sliding doors stay separate for future interaction, parked outside the opening.
for x in [-57,57]: hb('hangar_sliding_door_'+('left' if x<0 else 'right'),(x,-175.4,0),(39,1.1,21),steel)
join_objects('hangar_roof_and_frame_details',parts,h)
# Technical tower facade divisions and roof equipment, grouped per complex.
parts=[]
for x,y,w,d,z in [(-40,0,42,72,64),(15,0,54,82,73),(50,12,20,52,58)]:
    parts.append(box('technical_roof',(x,y,z),(w+2,d+2,1.2),metal,tech))
    for zz in range(8,int(z),8):
        for sy in [-1,1]: parts.append(box('technical_band',(x,y+sy*(d/2+.25),zz),(w,.6,.65),steel,tech))
    for xx in range(int(x-w/2+4),int(x+w/2),9):
        for sy in [-1,1]: parts.append(box('technical_vertical',(xx,y+sy*(d/2+.5),0),(1.1,1,z),steel,tech))
    for dx in [-8,8]: parts.append(box('technical_hvac',(x+dx,y,z+1.2),(7,10,3),steel,tech))
join_objects('technical_facade_details',parts,tech)
for name in ['south_operations','north_workshop','radar_equipment']:
    b=bpy.data.objects[name]; x,y,z=b.location; w,d,hgt=b.dimensions
    parts=[box(name+'_roof',(x,y,hgt),(w+2,d+2,1),metal,groups['details'])]
    for xx in np.arange(x-w/2+8,x+w/2-4,10): parts.append(box(name+'_window',(float(xx),y-d/2-.15,4),(5,.3,3),glass,groups['details']))
    join_objects(name+'_details',parts,groups['details'])
# Low-cost lattice towers: posts and real diagonal braces, joined by tower.
def beam(name,a,b,width,parent):
    delta=Vector(b)-Vector(a); o=box(name,(0,0,0),(width,width,delta.length),steel,parent); o.location=a; o.rotation_euler=delta.to_track_quat('Z','Y').to_euler(); return o
for idx,(x,y,height) in enumerate([(-320,785,40),(-240,-430,32)]):
    base=empty('antenna_tower_%02d'%idx,groups['buildings']); base.location=(x,y,0)
    parts=[box('tower_base',(0,0,0),(12,12,3),wall,base)]
    for dx,dy in [(-3,-3),(3,-3),(3,3),(-3,3)]: parts.append(beam('tower_leg',(dx,dy,3),(dx,dy,height),.45,base))
    for z in range(4,height-5,7):
        for a,b in [((-3,-3),(3,-3)),((3,-3),(3,3)),((3,3),(-3,3)),((-3,3),(-3,-3))]:
            parts.append(beam('tower_brace',(*a,z),(*b,z+7),.22,base))
            parts.append(beam('tower_brace',(*b,z),(*a,z+7),.22,base))
    parts.append(box('tower_head',(0,0,height),(9,7,3),steel,base)); parts.append(beam('antenna',(0,0,height+3),(0,0,height+10),.25,base))
    join_objects('antenna_structure_%02d'%idx,parts,base)
# Pad and short access for the near antenna.
mesh('near_antenna_pad',[(-257,-450,0),(-215,-450,0),(-215,-410,0),(-257,-410,0)],[(0,1,2,3)],concrete,groups['aprons'])
mesh('near_antenna_access',[(-262,-434,0),(-257,-434,0),(-257,-426,0),(-262,-426,0)],[(0,1,2,3)],asphalt,groups['service_roads'])
# Roof seams on shelters, modest geometry shared by each repeated instance.
for i in range(1,5):
    shelter=bpy.data.objects['arched_shelter_%02d'%i];parts=[]
    for yy in [-22,-11,0,11,22]:
        for j in range(12):
            a=math.pi*j/12;b=math.pi*(j+1)/12
            parts.append(beam('arch_rib',(19.15*math.cos(a),yy,2+13.05*math.sin(a)),(19.15*math.cos(b),yy,2+13.05*math.sin(b)),.22,shelter))
    join_objects('shelter_ribs_%02d'%i,parts,shelter)
# Recalculate closed structural meshes; pavement retains upward winding.
import bmesh
for o in asset_collection.objects:
    if o.type=='MESH' and o.parent not in [groups[n] for n in ['runway','taxiways','aprons','service_roads','markings']]:
        bm=bmesh.new();bm.from_mesh(o.data);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(o.data);bm.free()
# Fix the two annular surfaces of open shells explicitly by face order/outward radial test.
for o in asset_collection.objects:
    if o.type=='MESH':
        o.data.update()
        assert all(p.area>1e-8 for p in o.data.polygons),o.name+' degenerate face'
bpy.context.view_layer.update()
# Export only the complete asset hierarchy; glTF's native Y-up conversion is used.
bpy.ops.object.select_all(action='DESELECT')
for o in asset_collection.objects: o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+'/airport_layout.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_apply=False,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)
# Persist images with portable paths while keeping PBR images embedded in GLB.
for im in bpy.data.images:
    if im.filepath.startswith(OUT): im.filepath=bpy.path.relpath(im.filepath,start=OUT+'/source')
view((1250,-2250,1750),(-30,-100,0))
scene.render.resolution_percentage=100;scene.cycles.samples=24
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/source/airport.blend')
print('AIRPORT_EXPORTED',OUT+'/airport_layout.glb')
