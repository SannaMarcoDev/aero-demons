"""Run in the authored Blender scene through MCP; validates, packs and exports."""
import bpy
import bmesh
import json
from pathlib import Path
from mathutils import Vector

HERE=Path(__file__).resolve().parent
scene=bpy.data.scenes['AERO_DEMONS_LAYOUT_V2']
bpy.context.window.scene=scene
airport=bpy.data.collections['AIRPORT']
root=bpy.data.objects.get('AD_MAIN_AIRPORT')
if root is None:
    root=bpy.data.objects.new('AD_MAIN_AIRPORT',None); airport.objects.link(root)
for collection in airport.children:
    group=bpy.data.objects.get('AD_'+collection.name)
    if group is None:
        group=bpy.data.objects.new('AD_'+collection.name,None); collection.objects.link(group); group.parent=root
    for obj in list(collection.objects):
        if obj.get('runtime_scene'):
            obj.parent=group
            continue
        if obj.type!='MESH': continue
        obj.parent=group
        if 'placeholder' in obj and not obj.name.endswith('-col'): obj.name+='-col'
        bm=bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=.00001)
        bmesh.ops.triangulate(bm,faces=list(bm.faces))
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(obj.data); bm.free(); obj.data.update()
        if not obj.data.uv_layers:
            uv=obj.data.uv_layers.new(name='Metric_8m')
            for loop in obj.data.loops: uv.data[loop.index].uv=obj.data.vertices[loop.vertex_index].co.xy/8
        assert all(p.area>0 for p in obj.data.polygons), ('zero area',obj.name)
        assert all(len(p.vertices)==3 for p in obj.data.polygons),obj.name
        assert obj.scale==Vector((1,1,1)),obj.name
        assert obj.data.materials and obj.data.uv_layers,obj.name
bpy.context.view_layer.update()
meshes=[o for o in airport.all_objects if o.type=='MESH']
runway=[o for o in meshes if o.name.startswith('RWY_18_36_')]
coords=[o.matrix_world@Vector(c) for o in runway for c in o.bound_box]
assert abs(max(v.y for v in coords)-min(v.y for v in coords)-2400)<.01
assert abs(max(v.x for v in coords)-min(v.x for v in coords)-60)<.01
instances=[o for o in airport.all_objects if o.get('runtime_scene')]
placeholder_count=len([o for o in meshes if o.get('placeholder')])
assert placeholder_count==26-len(instances)
assert len(instances) in (0,3)
placements=json.loads((HERE/'asset_placements.json').read_text()) if instances else []
assert len(placements)==len(instances)
for o in instances:
    p=next(p for p in placements if p['name']==o.name)
    assert o.instance_collection is not None and all(abs(s-p['scale'])<.0001 for s in o.scale)
    assert abs((o.matrix_world@Vector((0,-12.36,0))).x-p['front_x'])<.001
stats={'marker':'AIRPORT_BLENDER_CHECK_OK','mesh_objects':len(meshes),'triangles':sum(len(o.data.polygons) for o in meshes if not o.name.endswith('-colonly')),'collision_only_triangles':sum(len(o.data.polygons) for o in meshes if o.name.endswith('-colonly')),'placeholders':placeholder_count,'small_hangar_instances':len(instances),'units':'metres','runway_m':[2400,60],'collision_meshes':sum(o.name.endswith(('-col','-colonly')) for o in meshes),'materials':len({m.name for o in meshes for m in o.data.materials})}
# Isolate selection: presentation, legend, routes, lights and cameras never enter the GLB.
bpy.ops.object.select_all(action='DESELECT')
for o in airport.all_objects:
    # Native Godot scene instances retain their animation and moving collision;
    # do not bake a second, static copy into the infrastructure GLB.
    if not o.get('runtime_scene'):
        o.hide_set(False); o.select_set(True)
# export_format is a dynamic operator enum; inspect its accepted values via RNA first.
formats=[i.identifier for i in bpy.ops.export_scene.gltf.get_rna_type().properties['export_format'].enum_items]
if formats: assert 'GLB' in formats
bpy.ops.export_scene.gltf(filepath=str(HERE.parent.parent/'main_airport_layout.glb'),export_format='GLB',use_selection=True,export_extras=True,export_yup=True,export_tangents=True,export_cameras=False,export_lights=False,export_animations=False)
bpy.ops.object.select_all(action='DESELECT')
scene.camera=bpy.data.objects['01_REFERENCE_AERIAL']
scene.render.resolution_x=1920; scene.render.resolution_y=1200
for area in bpy.context.screen.areas:
    if area.type=='VIEW_3D':
        area.spaces.active.region_3d.view_perspective='CAMERA'
        area.spaces.active.clip_end=20000
bpy.ops.wm.save_as_mainfile(filepath=str(HERE/'main_airport_layout.blend'))
stats['glb_bytes']=(HERE.parent.parent/'main_airport_layout.glb').stat().st_size
(HERE/'validation.json').write_text(json.dumps(stats,indent=2)+'\n')
print(json.dumps(stats))
