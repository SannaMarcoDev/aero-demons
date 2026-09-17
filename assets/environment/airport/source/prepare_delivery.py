"""Run inside the authoring namespace: clean export, dedicated Godot collision and previews."""
import re, struct
# Stable snake_case names also on mesh resources.
for o in asset_collection.objects:
    o.name=re.sub(r'[^a-z0-9_]+','_',o.name.replace('-','minus_').lower())
    if o.type=='MESH': o.data.name=o.name
# Export only this scene (the user's pre-existing scene stays in the .blend).
bpy.ops.object.select_all(action='DESELECT')
for o in asset_collection.objects: o.select_set(True)
bpy.ops.export_scene.gltf(filepath=OUT+'/airport_layout.glb',export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_cameras=False,export_lights=False)
# Generate independent static Godot collision geometry. No runtime generator.
def godot(v): return (v.x,v.z,-v.y)
def vec(v): return ', '.join(format(float(x),'.6g') for x in v)
def triangle_data(objects):
    values=[]
    for o in objects:
        o.data.calc_loop_triangles()
        for tri in o.data.loop_triangles:
            # Godot faces use clockwise winding, unlike Blender/glTF.
            for i in reversed(tri.vertices): values.extend(godot(o.matrix_world@o.data.vertices[i].co))
    return vec(values)
paving=[o for o in asset_collection.objects if o.type=='MESH' and o.parent in [groups[n] for n in ['runway','taxiways','aprons','service_roads']]]
sub=[];nodes=[]
sub.append('[sub_resource type="ConcavePolygonShape3D" id="Shape_pavement"]\ndata = PackedVector3Array('+triangle_data(paving)+')\nbackface_collision = true\n')
nodes.append('[node name="pavement" type="CollisionShape3D" parent="CollisionBodies/static_airport"]\nshape = SubResource("Shape_pavement")\n')
# Six main hangar walls/header plus a thin roof volume preserve the open portal.
solid_names=['hangar_west_wall','hangar_east_wall','hangar_back_wall','hangar_front_left','hangar_front_right','hangar_portal_header','south_operations','north_workshop','radar_equipment']+['technical_volume_%02d'%i for i in range(4)]
for name in solid_names:
    o=bpy.data.objects[name]; points=[o.matrix_world@Vector(v) for v in o.bound_box]
    lo=Vector(tuple(min(p[i] for p in points) for i in range(3)));hi=Vector(tuple(max(p[i] for p in points) for i in range(3))); size=hi-lo
    sub.append('[sub_resource type="BoxShape3D" id="Shape_'+name+'"]\nsize = Vector3('+vec((size.x,size.z,size.y))+')\n')
    nodes.append('[node name="'+name+'" type="CollisionShape3D" parent="CollisionBodies/static_airport"]\nposition = Vector3('+vec(godot((lo+hi)/2))+')\nshape = SubResource("Shape_'+name+'")\n')
for name,obs in [('hangar_roof',[bpy.data.objects['hangar_roof_bay_%02d'%i] for i in range(3)]),('radome',[bpy.data.objects['radome_shell']])]+[('shelter_%02d'%i,[o for o in bpy.data.objects['arched_shelter_%02d'%i].children if o.type=='MESH' and 'ribs' not in o.name]) for i in range(1,5)]:
    sub.append('[sub_resource type="ConcavePolygonShape3D" id="Shape_'+name+'"]\ndata = PackedVector3Array('+triangle_data(obs)+')\nbackface_collision = true\n')
    nodes.append('[node name="'+name+'" type="CollisionShape3D" parent="CollisionBodies/static_airport"]\nshape = SubResource("Shape_'+name+'")\n')
text='[gd_scene load_steps=%d format=3]\n\n'%(len(sub)+2)+'[ext_resource type="PackedScene" path="res://assets/environment/airport/airport_layout.glb" id="1_visual"]\n\n'+'\n'.join(sub)+'\n[node name="Airport" type="Node3D"]\n\n[node name="Visuals" type="Node3D" parent="."]\n\n[node name="airport_layout" parent="Visuals" instance=ExtResource("1_visual")]\n\n[node name="CollisionBodies" type="Node3D" parent="."]\n\n[node name="static_airport" type="StaticBody3D" parent="CollisionBodies"]\ncollision_layer = 1\ncollision_mask = 0\n\n'+'\n'.join(nodes)+'\n[node name="Markers" type="Node3D" parent="."]\n\n[node name="road_connection" type="Marker3D" parent="Markers"]\nposition = Vector3(-580, 0, 231)\n'
with open(BASE+'/scenes/maps/airport.tscn','w') as f:f.write(text)
# Statistics from delivered bytes, not viewport totals.
with open(OUT+'/airport_layout.glb','rb') as f:
    assert f.read(4)==b'glTF';f.read(8);length,kind=struct.unpack('<II',f.read(8));doc=json.loads(f.read(length))
assert len(doc['scenes'])==1
assert len(doc['scenes'][0]['nodes'])==1
assert doc['nodes'][doc['scenes'][0]['nodes'][0]]['name']=='airport_root'
assert not any('camera' in n or 'light' in n for n in doc['nodes'])
counts={'mesh_objects':sum('mesh' in n for n in doc['nodes']),'unique_meshes':len(doc['meshes']),'triangles_instanced':sum(sum(doc['accessors'][p['indices']]['count']//3 for p in doc['meshes'][n['mesh']]['primitives']) for n in doc['nodes'] if 'mesh' in n),'materials':len(doc['materials']),'embedded_images':len(doc.get('images',[])),'glb_bytes':os.path.getsize(OUT+'/airport_layout.glb')}
with open(OUT+'/source/export_stats.json','w') as f:json.dump(counts,f,indent=2)
# Keep temporary ground isolated, never exported; cameras use sensible clipping.
view((1250,-2250,1750),(-30,-100,0))
scene.render.resolution_percentage=100;scene.cycles.samples=24
bpy.ops.wm.save_as_mainfile(filepath=OUT+'/source/airport.blend')
print('DELIVERY_READY',counts)
