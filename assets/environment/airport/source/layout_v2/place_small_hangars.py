"""Blender MCP authoring step: replace S01-S03 with shared N26-scale assets.
Run after author_blender.build(), before surface refresh and deliver_blender.py.
The Godot assembly reuses small_hangar.tscn, including its independent moving doors.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent
SCALE = 2.0  # 23.2 m wide x 9.76 m high opening; N26: 14.08 m x 4.744 m.
SOURCE = HERE.parents[2] / 'small_hangar/source/small_hangar.blend'
scene = bpy.data.scenes['AERO_DEMONS_LAYOUT_V2']
bpy.context.window.scene = scene
names = ['S01_Shelter-col', 'S02_Shelter-col', 'S03_Shelter-col']
blocks = [bpy.data.objects.get(n) or bpy.data.objects.get(n.removesuffix('-col')) for n in names]
assert all(o is not None and o.get('category') == 'orange' for o in blocks), 'Expected the three original orange blocks; refuse duplicate placement.'
assert bpy.data.collections.get('SMALL_HANGAR_SHARED') is None
collection = bpy.data.collections.new('SMALL_HANGAR_SHARED')
asset_names = ['SmallHangar', 'HangarStatic', 'DoorUpper', 'DoorLower', 'GuideRollers', 'LiftCables']
with bpy.data.libraries.load(str(SOURCE), link=False) as (source, target):
    assert set(asset_names).issubset(source.objects)
    target.objects = asset_names
for obj in target.objects:
    collection.objects.link(obj)
assert len([o for o in collection.objects if o.type == 'MESH']) == 5
assets = bpy.data.collections.new('BUILDING_ASSETS')
bpy.data.collections['AIRPORT'].children.link(assets)
placements = []
for i, old in enumerate(blocks, 1):
    front = old.location.x + old.dimensions.x / 2
    instance = bpy.data.objects.new(f'S{i:02d}_SmallHangar', None)
    assets.objects.link(instance)
    assert 'COLLECTION' in [v.identifier for v in instance.bl_rna.properties['instance_type'].enum_items]
    instance.instance_type = 'COLLECTION'
    instance.instance_collection = collection
    instance.location = (front - 12.36*SCALE, old.location.y, 0)
    instance.rotation_euler.z = math.pi / 2
    instance.scale = (SCALE,)*3
    instance['runtime_scene'] = 'res://scenes/maps/small_hangar.tscn'
    instance['replaces'] = old.name
    instance['door_width_m'] = 11.6*SCALE
    instance['note'] = 'Uniform N26 scale; entrance +X toward apron; 4.56 m wingtip clearance per side.'
    bpy.context.view_layer.update()
    door = instance.matrix_world @ Vector((0, -12.36, 0))
    assert abs(door.x-front) < .001 and abs(door.y-old.location.y) < .001
    placements.append({'name': instance.name, 'position_blender': list(instance.location), 'yaw_blender_degrees': 90, 'scale': SCALE, 'foundation_size_xy': [24.7*SCALE,28.5*SCALE], 'front_x': front, 'scene': instance['runtime_scene']})
    bpy.data.objects.remove(old, do_unlink=True)
(HERE/'asset_placements.json').write_text(json.dumps(placements, indent=2)+'\n')
scene.render.fps = 30
scene.frame_end = 361
scene.frame_set(1)
for name, body in [('Legend_label_orange','N26 HANGAR / INSTANCED'), ('Revision','03 / N26-SCALE HANGARS')]:
    if name in scene.objects: scene.objects[name].data.body = body
print('PASS: SMALL_HANGARS_PLACED', json.dumps(placements))
