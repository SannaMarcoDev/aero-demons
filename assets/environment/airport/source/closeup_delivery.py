"""Final checks and export; run in the closeup authoring namespace after all stages."""
import re,struct,hashlib
# Cylindrical metric UVs preserve rib direction around all linked shelter shells.
seen=set()
for o in collection.objects:
    if o.type=='MESH' and o.name.startswith('shelter_skin_') and o.data not in seen:
        seen.add(o.data);uv=o.data.uv_layers.active
        for loop in o.data.loops:
            v=o.data.vertices[loop.vertex_index].co;a=math.atan2((v.z-2)/.7,v.x)
            uv.data[loop.index].uv=(a*19/3,(v.y+23)/3)
# Photographed roughness reduced to an optical glass range, baked for glTF.
glass_p=next(n for n in glass.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
rough_link=next(l for l in glass.node_tree.links if l.to_socket==glass_p.inputs['Roughness'])
im=rough_link.from_node.image
if not im.name.startswith('ph_glass_roughness'):
    values=np.empty(len(im.pixels),np.float32);im.pixels.foreach_get(values);values=values.reshape((-1,4));values[:,:3]=.06+.14*values[:,:3]
    output=bpy.data.images.new('ph_glass_roughness',width=im.size[0],height=im.size[1]);output.colorspace_settings.name='Non-Color';output.pixels.foreach_set(values.ravel());output.filepath_raw=TEX+'/ph_glass_roughness.png';output.file_format='PNG';output.save();rough_link.from_node.image=output
# Slab joints at 6 m, clipped to each existing concrete polygon; never across grass.
old=bpy.data.objects.get('concrete_slab_joints')
if old:erase(old)
b=Batch()
for o in list(collection.objects):
    if o.type!='MESH' or o.parent not in [groups[n] for n in ['runway','taxiways','aprons']]:continue
    if not any(m==floor for m in o.data.materials):continue
    for face in o.data.polygons:
        if len(face.vertices)!=4:continue
        points=[o.matrix_world@o.data.vertices[i].co for i in face.vertices]
        a,c=min(p.x for p in points),min(p.y for p in points);bb,d=max(p.x for p in points),max(p.y for p in points)
        xs=[float(x) for x in range(math.ceil(a/6)*6,math.floor(bb/6)*6+1,6) if a+.02<x<bb-.02]
        for x in xs:b.add([(x-.011,c,.018),(x+.011,c,.018),(x+.011,d,.018),(x-.011,d,.018)],[(0,1,2,3)],joint)
        intervals=list(zip([a]+[x+.011 for x in xs],[x-.011 for x in xs]+[bb]))
        for y in range(math.ceil(c/6)*6,math.floor(d/6)*6+1,6):
            if not c+.02<y<d-.02:continue
            for aa,bbb in intervals:
                b.add([(aa,y-.011,.018),(bbb,y-.011,.018),(bbb,y+.011,.018),(aa,y+.011,.018)],[(0,1,2,3)],joint)
b.mesh('concrete_slab_joints',groups['details'])
# Purge unused vertices created by batched, multi-material frame templates.
for me in {o.data for o in collection.objects if o.type=='MESH'}:
    bm=bmesh.new();bm.from_mesh(me);loose=[v for v in bm.verts if not v.link_faces]
    if loose:bmesh.ops.delete(bm,geom=loose,context='VERTS')
    # MikkTSpace requires triangles/quads; only triangulate polygonal end caps.
    bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if len(f.verts)>4])
    bm.to_mesh(me);bm.free();me.update()
    assert all(p.area>1e-9 for p in me.polygons),me.name+' has degenerate faces'
# Keep all node names stable and valid snake_case.
for o in collection.objects:
    o.name=re.sub('[^a-z0-9_]+','_',o.name.lower())
    if o.type=='MESH':assert o.data.uv_layers.active is not None,o.name
# Base color and normals remain 2K; scalar roughness/metalness masks need only 1K.
used_materials={m for o in collection.objects if o.type=='MESH' for m in o.data.materials}
mask_cache={}
for m in used_materials:
    principled=next(n for n in m.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    for link in list(m.node_tree.links):
        if link.to_socket not in [principled.inputs['Roughness'],principled.inputs['Metallic']] or link.from_node.type!='TEX_IMAGE':continue
        im=link.from_node.image
        if max(im.size)<=1024:continue
        if im not in mask_cache:
            small=im.copy();small.name=re.sub('[^a-z0-9_]+','_',im.name.lower())+'_mask_1k';small.scale(1024,1024);small.file_format='PNG';small.filepath_raw=TEX+'/'+small.name+'.png';small.save();mask_cache[im]=small
        link.from_node.image=mask_cache[im]
    for link in m.node_tree.links:
        if link.to_socket==principled.inputs['Base Color'] and link.from_node.type=='TEX_IMAGE':
            im=link.from_node.image
            if im.filepath.lower().endswith('.png'):
                im.file_format='JPEG';im.filepath_raw=os.path.splitext(bpy.path.abspath(im.filepath))[0]+'.jpg';im.save(quality=95)
seen_meshes=set()
for o in sorted(collection.objects,key=lambda o:o.name):
    if o.type=='MESH' and o.data not in seen_meshes:o.data.name='airport_'+o.name+'_mesh';seen_meshes.add(o.data)
bpy.context.view_layer.update()
bpy.ops.object.select_all(action='DESELECT')
for o in collection.objects:o.select_set(True)
bpy.context.view_layer.objects.active=root
bpy.ops.export_scene.gltf(filepath=OUT+'/airport_layout.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_apply=True,export_cameras=False,export_lights=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT')
# Scene-specific physics remains outside the imported asset. Reuse the already-tested
# original outer wall/pavement proxies; refresh shapes whose silhouettes changed.
scene_path=BASE+'/scenes/maps/airport.tscn'
text=open(scene_path).read()
def g(v):return (v[0],v[2],-v[1])
def fmt(values):return ', '.join(format(float(x),'.6g') for x in values)
def triangles(objects):
    values=[]
    for o in objects:
        o.data.calc_loop_triangles()
        for tri in o.data.loop_triangles:
            for index in reversed(tri.vertices):values.extend(g(o.matrix_world@o.data.vertices[index].co))
    return fmt(values)
for i in range(1,5):
    name='shelter_%02d'%i;parent=bpy.data.objects['arched_shelter_%02d'%i]
    data=triangles([o for o in parent.children if o.type=='MESH' and (o.name.startswith('shelter_skin') or o.name.startswith('shelter_portal'))])
    pattern=r'(\[sub_resource type="ConcavePolygonShape3D" id="Shape_'+name+r'"\]\ndata = PackedVector3Array\()[^\n]*(\)\n)'
    text,count=re.subn(pattern,lambda m:m[1]+data+m[2],text);assert count==1,name
# Dome collision uses the smooth shell, not the thousands of aesthetic panel seams.
data=triangles([bpy.data.objects['radome_shell']])
text,count=re.subn(r'(\[sub_resource type="ConcavePolygonShape3D" id="Shape_radome"\]\ndata = PackedVector3Array\()[^\n]*(\)\n)',lambda m:m[1]+data+m[2],text);assert count==1
# Idempotent extra proxies: column rows preserve the clear central taxi-in aisle.
text=re.sub(r'\n\[sub_resource type="BoxShape3D" id="Detail_[^\n]*\nsize = Vector3\([^\n]*\n','\n',text)
text=re.sub(r'\n\[node name="detail_[^\n]*\nposition = Vector3\([^\n]*\nshape = SubResource\([^\n]*\n','\n',text)
subs=[];nodes=[]
def proxy(name,pos,size):
    subs.append('\n[sub_resource type="BoxShape3D" id="Detail_'+name+'"]\nsize = Vector3('+fmt(size)+')\n')
    nodes.append('\n[node name="detail_'+name+'" type="CollisionShape3D" parent="CollisionBodies/static_airport"]\nposition = Vector3('+fmt(pos)+')\nshape = SubResource("Detail_'+name+'")\n')
for i,x in enumerate([-86.5,-29,29,86.5]):
    for j,y in enumerate(range(-170,175,34)):proxy('hangar_column_%d_%d'%(i,j),(425+x,12.4,965-y),(.9,24.8,.6))
proxy('radome_skirt',(-354,.6,-990),(72,1.2,72))
proxy('radome_access',(-354,2,-938.5),(8,4,5))
for idx,height in enumerate([40,32]):
    p=bpy.data.objects['antenna_tower_%02d'%idx].location
    proxy('tower_%d_platform'%idx,(p.x,p.z+height,-p.y),(9,.3,9))
text=text.replace('[node name="Airport"', '\n'.join(subs)+'\n[node name="Airport"',1)
text+='\n'.join(nodes)
steps=len(re.findall(r'\[sub_resource ',text))+len(re.findall(r'\[ext_resource ',text))+1
text=re.sub(r'load_steps=\d+','load_steps='+str(steps),text,1)
open(scene_path,'w').write(text)
# Statistics and audit from the exported file.
with open(OUT+'/airport_layout.glb','rb') as f:
    assert f.read(4)==b'glTF';f.read(8);size,kind=struct.unpack('<II',f.read(8));doc=json.loads(f.read(size))
assert len(doc['scenes'])==1 and len(doc['scenes'][0]['nodes'])==1
assert doc['nodes'][doc['scenes'][0]['nodes'][0]]['name']=='airport_root'
assert not any('camera' in n or 'light' in n for n in doc['nodes'])
assert all('TANGENT' in p['attributes'] for mesh in doc['meshes'] for p in mesh['primitives'])
assert all('normalTexture' in m and 'baseColorTexture' in m['pbrMetallicRoughness'] and 'metallicRoughnessTexture' in m['pbrMetallicRoughness'] for m in doc['materials'])
counts={'mesh_objects':sum('mesh' in n for n in doc['nodes']),'unique_meshes':len(doc['meshes']),'triangles_instanced':sum(sum(doc['accessors'][p['indices']]['count']//3 for p in doc['meshes'][n['mesh']]['primitives']) for n in doc['nodes'] if 'mesh' in n),'materials':len(doc['materials']),'embedded_images':len(doc.get('images',[])),'glb_bytes':os.path.getsize(OUT+'/airport_layout.glb')}
assert counts['triangles_instanced']<450000,counts
json.dump(counts,open(OUT+'/source/export_stats.json','w'),indent=2)
manifest={'license':'CC0 1.0','source':'https://polyhaven.com/license','resolution':'Albedo and OpenGL normals: 2048x2048; exported scalar masks: 1024x1024','assets':[{'id':a,'url':'https://polyhaven.com/a/'+a} for a in ['concrete_floor_01','concrete_floor_02','concrete','corrugated_iron_02','painted_metal_shutter','metal_plate','asphalt_floor']],'derivatives':'Muted albedo grades baked as JPEG quality 95; scalar masks and adjusted glass roughness as lossless PNG. Original Poly Haven 2K JPEG maps retained. No procedural shaders required.','source_files':{n:hashlib.sha256(open(TEX+'/'+n,'rb').read()).hexdigest() for n in sorted(os.listdir(TEX)) if n.endswith('.jpg')}}
json.dump(manifest,open(TEX+'/provenance.json','w'),indent=2)
for m in {m for o in collection.objects if o.type=='MESH' for m in o.data.materials}:
    for node in m.node_tree.nodes:
        if node.type=='TEX_IMAGE':
            assert os.path.exists(bpy.path.abspath(node.image.filepath)),node.image.name
            node.image.filepath=bpy.path.relpath(bpy.path.abspath(node.image.filepath),start=OUT+'/source')
# Save source after restoring a useful source-camera composition, not the last close crop.
camera=bpy.data.objects['preview_camera'];camera.location=(1250,-2250,1750);camera.rotation_euler=(Vector((-30,-100,0))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.lens=45
scene.camera=camera;scene.render.resolution_x=1600;scene.render.resolution_y=1000;scene.render.resolution_percentage=100;scene.cycles.samples=32
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/source/airport.blend')
print('CLOSEUP_EXPORT_OK',counts)
