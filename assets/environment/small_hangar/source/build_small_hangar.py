"""Authored with Blender MCP. Run in Blender; call blockout(), detail(), finish().
Only the SmallHangar scene is owned by this recipe; existing scenes are preserved.
"""
import bpy
import math
import json
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[4]
ASSET = ROOT / 'assets/environment/small_hangar'
SOURCE = ASSET / 'source'
PH = ROOT / 'assets/environment/airport/textures/polyhaven'
REVIEW = SOURCE / 'review'
REVIEW.mkdir(parents=True, exist_ok=True)
BATCH = {}
MATS = {}
SCENE = None
ROOT_OBJ = None


def enum(owner, prop, value):
    assert value in {e.identifier for e in owner.bl_rna.properties[prop].enum_items}, (prop, value)
    setattr(owner, prop, value)


def material(name, color, roughness=0.7, metallic=0.0, maps=None):
    mat = bpy.data.materials.new('SH_' + name)
    mat.use_nodes = True
    mat.use_backface_culling = True
    mat.diffuse_color = (*color, 1)
    bsdf = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    for socket, path in (maps or {}).items():
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(path), check_existing=True)
        if socket != 'Base Color':
            tex.image.colorspace_settings.name = 'Non-Color'
        if socket == 'Normal':
            normal = mat.node_tree.nodes.new('ShaderNodeNormalMap')
            normal.inputs['Strength'].default_value = 0.35
            mat.node_tree.links.new(tex.outputs['Color'], normal.inputs['Color'])
            mat.node_tree.links.new(normal.outputs['Normal'], bsdf.inputs['Normal'])
        else:
            mat.node_tree.links.new(tex.outputs['Color'], bsdf.inputs[socket])
    MATS[name] = mat
    return mat


def batch(name):
    return BATCH.setdefault(name, {'v': [], 'f': [], 'uv': [], 'mat': [], 'slots': []})


def shape(group, vertices, faces, mat, tile=3.0, roof_uv=False):
    b = batch(group)
    offset = len(b['v'])
    b['v'].extend(vertices)
    if mat not in b['slots']:
        b['slots'].append(mat)
    for face in faces:
        b['f'].append([offset + i for i in face])
        b['mat'].append(b['slots'].index(mat))
        p = [Vector(vertices[i]) for i in face]
        n = (p[1] - p[0]).cross(p[2] - p[0])
        axis = max(range(3), key=lambda a: abs(n[a]))
        axes = [(1, 2), (0, 2), (0, 1)][axis]
        if roof_uv and axis == 2:
            axes = (1, 0)
        b['uv'].append([(v[axes[0]] / tile, v[axes[1]] / tile) for v in p])


def box(group, center, size, mat, tile=3.0, rot=None, roof_uv=False):
    x, y, z = [d * 0.5 for d in size]
    points = [(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
    m = rot or Matrix.Identity(3)
    vertices = [tuple(m @ Vector(p) + Vector(center)) for p in points]
    shape(group, vertices, [(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)], mat, tile, roof_uv)


def beam(group, a, b, width, depth, mat):
    direction = Vector(b) - Vector(a)
    rot = direction.to_track_quat('Z', 'Y').to_matrix()
    box(group, (Vector(a) + Vector(b)) / 2, (width, depth, direction.length), mat, rot=rot)


def cylinder(group, a, b, radius, mat, sides=8):
    direction = Vector(b) - Vector(a)
    rot = direction.to_track_quat('Z', 'Y').to_matrix()
    vertices = [tuple(rot @ Vector((radius*math.cos(i*2*math.pi/sides),radius*math.sin(i*2*math.pi/sides),z)) + Vector(a)) for z in (0, direction.length) for i in range(sides)]
    faces = [tuple(reversed(range(sides))), tuple(range(sides,2*sides))]
    faces += [(i,(i+1)%sides,(i+1)%sides+sides,i+sides) for i in range(sides)]
    shape(group, vertices, faces, mat)


def prism(group, outline, y0, y1, mat):
    count = len(outline)
    vertices = [(x,y,z) for y in (y0,y1) for x,z in outline]
    faces = [tuple(range(count)),tuple(reversed(range(count,2*count)))]
    faces += [(i,i+count,(i+1)%count+count,(i+1)%count) for i in range(count)]
    shape(group, vertices, faces, mat)


def flush(name, parent=None, pivot=(0,0,0), bevel=0):
    b = BATCH.pop(name)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([Vector(v)-Vector(pivot) for v in b['v']], [], b['f'])
    mesh.update()
    for mat in b['slots']:
        mesh.materials.append(MATS[mat])
    uv = mesh.uv_layers.new(name='UVMap')
    for poly, coords, mat in zip(mesh.polygons,b['uv'],b['mat']):
        poly.material_index = mat
        for loop, co in zip(poly.loop_indices,coords):
            uv.data[loop].uv = co
    obj = bpy.data.objects.new(name,mesh)
    SCENE.collection.objects.link(obj)
    obj.parent = parent or ROOT_OBJ
    obj.location = pivot
    if bevel:
        mod = obj.modifiers.new('Fabricated_edge_radii', 'BEVEL')
        mod.width = bevel
        mod.segments = 2
        enum(mod,'limit_method','ANGLE')
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.select_set(False)
    return obj


def aim(obj, target):
    obj.rotation_euler = (Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()


def set_camera(position=(33,-43,25), target=(0,0,3), lens=43):
    cam = SCENE.camera
    cam.location = position
    cam.data.lens = lens
    aim(cam,target)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type == 'VIEW_3D':
                area.spaces.active.region_3d.view_perspective = 'CAMERA'
                area.spaces.active.overlay.show_overlays = False
                enum(area.spaces.active.shading,'type','MATERIAL')


def render(name, position=None, target=None, lens=43):
    if position:
        set_camera(position,target or (0,0,3),lens)
    SCENE.render.filepath = str(REVIEW / (name+'.png'))
    bpy.ops.render.render(write_still=True)


def blockout():
    global SCENE, ROOT_OBJ
    if 'SmallHangar' in bpy.data.scenes:
        raise RuntimeError('SmallHangar already exists; preserve it or explicitly remove before rebuilding.')
    SCENE = bpy.data.scenes.new('SmallHangar')
    bpy.context.window.scene = SCENE
    enum(SCENE.unit_settings,'system','METRIC')
    SCENE.unit_settings.scale_length = 1.0
    ROOT_OBJ = bpy.data.objects.new('SmallHangar',None)
    SCENE.collection.objects.link(ROOT_OBJ)
    material('Concrete',(0.46,0.45,0.4))
    material('Roof',(0.39,0.43,0.43),0.65,0.25)
    material('Door',(0.15,0.2,0.18),0.6,0.15)
    material('Steel',(0.19,0.22,0.21),0.5,0.65)
    material('Rubber',(0.025,0.032,0.03),0.92)
    material('Zinc',(0.48,0.52,0.53),0.37,0.8)
    material('Yellow',(0.64,0.43,0.095),0.73)
    material('White',(0.72,0.72,0.63),0.65)
    material('Red',(0.36,0.055,0.025),0.65)
    material('Lamp',(0.8,0.81,0.67),0.3)
    bs = next(n for n in MATS['Lamp'].node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    bs.inputs['Emission Color'].default_value = (0.75,0.8,0.6,1)
    bs.inputs['Emission Strength'].default_value = 2.0
    box('Foundation',(0,0,-0.18),(28.5,24.7,0.36),'Concrete')
    # Concrete shoulders follow the A-frame down almost to grade.
    for sign in (-1,1):
        outline = [(sign*5.98,0),(sign*13.95,0),(sign*13.95,0.55),(sign*5.98,5.36)]
        if sign < 0:
            outline.reverse()
        prism('Shell',outline,-12,-11.55,'Concrete')
    prism('Shell',[(-5.98,5.18),(5.98,5.18),(5.98,5.36),(0,8.97),(-5.98,5.36)],-12,-11.55,'Concrete')
    prism('Shell',[(-13.95,0),(13.95,0),(13.95,0.55),(0,8.97),(-13.95,0.55)],11.55,12,'Concrete')
    for s in (-1,1):
        box('Shell',(s*13.73,0,0.31),(0.4,23.1,0.62),'Concrete')
        rot = Matrix.Rotation(s*math.atan2(8.45,14),3,'Y')
        box('Roof',(s*7,0,4.8),(math.hypot(14,8.45),24.65,0.16),'Roof',2.4,rot,True)
    box('DoorBlockout',(0,-12.15,2.58),(11.6,0.16,5.12),'Door')
    for name in list(BATCH):
        flush(name,bevel=0.025 if name in ('Foundation','Shell') else 0)
    world = bpy.data.worlds.new('SH_StudioWorld')
    world.use_nodes = True
    background = next(n for n in world.node_tree.nodes if n.type == 'BACKGROUND')
    background.inputs['Color'].default_value = (0.38,0.44,0.52,1)
    background.inputs['Strength'].default_value = 0.65
    SCENE.world = world
    for name,kind,loc,energy,size in [('Key','AREA',(1,-18,28),4300,22),('Fill','AREA',(-22,-4,14),2600,18),('Sun','SUN',(8,-12,22),2.5,0)]:
        data = bpy.data.lights.new('SH_'+name,kind)
        data.energy = energy
        if kind == 'AREA': data.shape = 'DISK'; data.size = size
        else: data.angle = 0.12
        obj = bpy.data.objects.new('Studio_'+name,data)
        SCENE.collection.objects.link(obj)
        obj.location = loc
        aim(obj,(0,0,0))
    camera = bpy.data.objects.new('Studio_Camera',bpy.data.cameras.new('SH_Camera'))
    SCENE.collection.objects.link(camera)
    SCENE.camera = camera
    set_camera()
    SCENE.render.resolution_x = 1400
    SCENE.render.resolution_y = 1050
    SCENE.render.resolution_percentage = 100
    SCENE.render.film_transparent = False
    enum(SCENE.render.image_settings,'file_format','PNG')
    try: SCENE.render.engine = 'CYCLES'
    except TypeError: pass
    if SCENE.render.engine == 'CYCLES': SCENE.cycles.samples = 24
    SCENE.render.fps = 30
    SCENE.frame_start = 1
    SCENE.frame_end = 361
    print('BLOCKOUT_COMPLETE: 28 x 24 m, ridge 9 m; clear door 11.6 x 5.1 m')


def maps_into(name, maps):
    mat = MATS[name]
    bs = next(n for n in mat.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    for socket,path in maps.items():
        tex = mat.node_tree.nodes.new('ShaderNodeTexImage')
        tex.image = bpy.data.images.load(str(path),check_existing=True)
        if socket != 'Base Color': tex.image.colorspace_settings.name = 'Non-Color'
        if socket == 'Normal':
            normal = mat.node_tree.nodes.new('ShaderNodeNormalMap')
            normal.inputs['Strength'].default_value = 0.3
            mat.node_tree.links.new(tex.outputs['Color'],normal.inputs['Color'])
            mat.node_tree.links.new(normal.outputs['Normal'],bs.inputs[socket])
        else: mat.node_tree.links.new(tex.outputs['Color'],bs.inputs[socket])


def text_object(name, body, position, size, mat='White'):
    curve = bpy.data.curves.new(name,'FONT')
    curve.body = body
    curve.size = size
    curve.align_x = 'CENTER'
    curve.extrude = 0.001
    curve.resolution_u = 2
    obj = bpy.data.objects.new(name,curve)
    SCENE.collection.objects.link(obj)
    obj.parent = ROOT_OBJ
    obj.location = position
    obj.rotation_euler = (math.pi/2,0,0)
    obj.data.materials.append(MATS[mat])
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.convert(target='MESH')
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    obj.select_set(False)
    return obj


def detail():
    tex = ASSET/'textures'
    maps_into('Concrete',{'Base Color':tex/'concrete_basecolor.jpg','Normal':tex/'concrete_normal.jpg','Roughness':tex/'concrete_roughness.jpg'})
    maps_into('Roof',{'Base Color':tex/'roof_basecolor.jpg','Normal':tex/'roof_normal.jpg','Roughness':tex/'roof_roughness.jpg'})
    maps_into('Door',{'Base Color':tex/'door_basecolor.jpg','Normal':tex/'door_normal.png','Roughness':tex/'door_roughness.png'})
    material('Floor',(0.4,0.4,0.36),maps={'Base Color':tex/'floor_basecolor.jpg','Normal':tex/'floor_normal.jpg','Roughness':tex/'floor_roughness.jpg'})
    SCENE.objects['Foundation'].data.materials[0] = MATS['Floor']
    maps_into('Steel',{'Roughness':tex/'door_roughness.png','Normal':tex/'door_normal.png'})
    maps_into('White',{'Roughness':tex/'door_roughness.png'})
    bpy.data.objects.remove(SCENE.objects['DoorBlockout'],do_unlink=True)
    # Corrugated sheets: raised standing seams and lapped transverse joints.
    for s in (-1,1):
        for j in range(21):
            y=-12.32+j*1.232
            beam('RoofSeams',(s*0.05,y,9.11),(s*14.06,y,0.66),0.045,0.045,'Zinc')
        for x in (4.7,9.4):
            z=9-x*8.45/14+0.11
            beam('RoofSeams',(s*x,-12.32,z),(s*x,12.32,z),0.048,0.04,'Zinc')
        # Folded ridge / gable caps, eave gutter and drains.
        for y in (-12.39,12.39):
            beam('Flashings',(s*0.02,y,9.12),(s*14.08,y,0.63),0.17,0.14,'Zinc')
        beam('Flashings',(s*0.11,-12.44,9.13),(s*0.11,12.44,9.13),0.24,0.06,'Zinc')
        box('Flashings',(s*14.03,0,0.53),(0.19,24.8,0.13),'Zinc')
        for y in (-10.7,10.7):
            cylinder('Hardware',(s*14.07,y,0.49),(s*14.07,y,0.05),0.055,'Zinc')
    # Four internal portal frames; upper chords, lower chords and open webs.
    for y in (-9,-3,3,9):
        for s in (-1,1):
            beam('Frames',(s*13.5,y,0.4),(0,y,8.58),0.18,0.25,'White')
            beam('Frames',(s*12.8,y,0.3),(0,y,8.03),0.1,0.12,'Steel')
            for x in (2.6,5.2,7.8,10.4):
                z=8.58-x*8.18/13.5
                beam('Frames',(s*x,y,z),(s*(x-0.6),y,z-0.15),0.06,0.07,'Steel')
            box('Hardware',(s*13.3,y,0.055),(0.5,0.5,0.1),'Steel')
        beam('Frames',(-4.7,y,5.68),(4.7,y,5.68),0.16,0.2,'White')
        beam('Frames',(0,y,5.68),(0,y,8.1),0.07,0.07,'Steel')
        for s in (-1,1):
            beam('Frames',(s*4.7,y,5.68),(0,y,8.1),0.065,0.065,'Steel')
    for s in (-1,1):
        for x in (2.6,5.4,8.2,11):
            z=9-x*8.45/14-0.23
            beam('Frames',(s*x,-11.55,z),(s*x,11.55,z),0.08,0.12,'Steel')
    # Concrete construction joints and regularly spaced formwork ties.
    for y in (-12.015,12.015):
        for s in (-1,1):
            for x in (7.8,10.2,12.6):
                height=9-x*8.45/14-0.12
                box('Joints',(s*x,y,height/2),(0.022,0.014,height),'Rubber')
            for x in (6.7,8.9,11.3):
                for z in (0.48,1.4):
                    if z < 9-x*8.45/14-0.3:
                        cylinder('Hardware',(s*x,y-0.013,z),(s*x,y+0.013,z),0.026,'Steel')
    # Door portal: jamb channels, lintel, seal and bolt plates.
    for s in (-1,1):
        x=s*5.96
        box('Portal',(x,-12.19,2.62),(0.22,0.38,5.24),'Steel')
        box('Portal',(s*5.79,-12.4,2.6),(0.035,0.04,5.16),'Rubber')
        box('Hardware',(x,-12.24,0.06),(0.46,0.55,0.12),'Zinc')
        for z in (0.22,1.3,2.6,3.9,5.02):
            box('Hardware',(x,-12.395,z),(0.32,0.035,0.16),'Zinc')
            for offset in (-0.09,0.09):
                cylinder('Hardware',(x+offset,-12.43,z),(x+offset,-12.405,z),0.023,'Steel',6)
        # Bottom guide tracks, drive motor and fixed gearbox.
        box('Hardware',(s*6.1,-12.47,2.56),(0.065,0.12,5.12),'Zinc')
        box('Portal',(s*5.4,-12.1,5.53),(0.5,0.42,0.35),'Steel')
        cylinder('Hardware',(s*5.13,-12.16,5.5),(s*5.66,-12.16,5.5),0.1,'Zinc',12)
    box('Portal',(0,-12.13,5.29),(12.15,0.38,0.26),'Steel')
    beam('Hardware',(-5.4,-12.15,5.53),(5.4,-12.15,5.53),0.055,0.055,'Zinc')
    # Equal-length bifold leaves. Both hinge axes run along local X.
    # Negative X rotation folds the top outward; lower relative angle is -2*top.
    # Skin and framing stay forward of the hinge plane, preventing folded overlap.
    for group,z0,z1 in [('DoorUpper',2.61,5.16),('DoorLower',0.06,2.61)]:
        for i in range(8):
            x=-5.8+(i+0.5)*1.45
            box(group,(x,-12.58,(z0+z1)/2),(1.432,0.05,2.525),'Door')
            for side in (-1,1):
                box(group,(x+side*0.704,-12.613,(z0+z1)/2),(0.026,0.024,2.52),'Door')
            for z in (z0+0.095,z1-0.095):
                cylinder(group,(x,-12.633,z),(x,-12.609,z),0.021,'Zinc',6)
        for z in (z0+0.08,z1-0.08):
            box(group,(0,-12.46,z),(11.58,0.13,0.16),'Steel')
        for x in (-5.7,-2.85,0,2.85,5.7):
            box(group,(x,-12.46,(z0+z1)/2),(0.12,0.13,2.39),'Steel')
        for i in range(4):
            x=-5.66+i*2.84
            beam(group,(x,-12.465,z0+0.18),(x+2.76,-12.465,z1-0.18),0.055,0.055,'Steel')
        # Hinge barrels distributed across the span.
        for x in (-5.5,-3.65,-1.82,0,1.82,3.65,5.5):
            cylinder(group,(x-0.1,-12.36,z1),(x+0.1,-12.36,z1),0.07,'Zinc',10)
        # Map coating to the full-height door atlas, not a repeated dirty tile.
        b=BATCH[group]
        for f,mat,uv in zip(b['f'],b['mat'],b['uv']):
            if b['slots'][mat] == 'Door':
                uv[:] = [((b['v'][v][0]+5.8)/11.6,b['v'][v][2]/5.16) for v in f]
    box('DoorLower',(0,-12.58,0.075),(11.61,0.12,0.065),'Rubber')
    for x in (-5.6,5.6):
        cylinder('DoorLower',(x,-12.54,0.32),(x,-12.54,0.67),0.022,'Zinc')
    upper=flush('DoorUpper',pivot=(0,-12.36,5.16),bevel=0.008)
    lower=flush('DoorLower',parent=upper,pivot=(0,-12.36,2.61),bevel=0.008)
    lower.location=(0,0,-2.55)
    # Roller centers travel vertically; their mesh remains separate and animated.
    for s in (-1,1):
        cylinder('GuideRollers',(s*5.86,-12.36,0.06),(s*6.15,-12.36,0.06),0.09,'Zinc',12)
    rollers=flush('GuideRollers')
    for obj in (upper,lower,rollers):
        obj.rotation_mode='XYZ'
    for frame,t in [(1,0),(31,0),(151,1),(211,1),(331,0),(361,0)]:
        angle=math.radians(90)*t
        upper.rotation_euler.x=-angle
        lower.rotation_euler.x=angle*2
        upper.keyframe_insert(data_path='rotation_euler',frame=frame,group='Bifold_X')
        lower.keyframe_insert(data_path='rotation_euler',frame=frame,group='Bifold_X')
    # Sample roller trajectory with the same smooth interpolation as the leaves.
    for frame in range(1,362):
        SCENE.frame_set(frame)
        rollers.location.z=5.1*(1-math.cos(upper.rotation_euler.x))
        rollers.keyframe_insert(data_path='location',frame=frame,group='Vertical_guides')
    for obj in (upper,lower,rollers):
        obj.animation_data.action.name='SH_'+obj.name+'_cycle'
    for name,frame in [('CLOSED',1),('OPEN_START',31),('OPEN',151),('CLOSE_START',211),('CLOSED_END',331)]:
        SCENE.timeline_markers.new(name,frame=frame)
    # Floor saw cuts, restrained guide markings and drainage across the threshold.
    for x in (-9,-3,3,9):
        box('Joints',(x,0,0.004),(0.012,23.9,0.007),'Rubber')
    for y in (-8,-4,0,4,8):
        box('Joints',(0,y,0.004),(27.4,0.012,0.007),'Rubber')
    for y in range(-10,9,2):
        box('Markings',(0,y,0.002),(0.11,1.25,0.002),'Yellow')
    for x in (-5.3,5.3):
        box('Markings',(x,-0.2,0.002),(0.065,21.5,0.002),'Yellow')
    box('Hardware',(0,-12.16,0.012),(11.55,0.17,0.02),'Steel')
    for i in range(72):
        box('Hardware',(-5.67+i*0.16,-12.16,0.025),(0.037,0.145,0.015),'Zinc')
    # Simple service interior: electrical panel, cable conduit, workbench and shelving.
    box('Interior',(8.6,9.7,0.87),(2.8,0.8,0.13),'Steel')
    for x in (7.4,9.8):
        for y in (9.4,10): box('Interior',(x,y,0.43),(0.07,0.07,0.86),'Steel')
    for z in (0.2,0.9,1.6): box('Interior',(-8.8,9.95,z),(2.5,0.7,0.065),'Steel')
    for x in (-10,-7.6):
        for y in (9.65,10.25): box('Interior',(x,y,0.95),(0.055,0.055,1.9),'Steel')
    for x in (-9.5,-8.5):
        box('Interior',(x,9.95,0.45),(0.6,0.5,0.43),'Door')
        box('Interior',(x,9.95,0.68),(0.62,0.52,0.025),'Steel')
    box('Interior',(5.4,11.27,1.45),(0.9,0.28,1.05),'Steel')
    box('Interior',(5.4,11.115,1.45),(0.8,0.035,0.96),'Door')
    cylinder('Interior',(5.77,11.075,1.35),(5.77,11.075,1.56),0.018,'Zinc')
    beam('Interior',(5.4,11.25,2),(5.4,11.25,4.8),0.038,0.038,'Zinc')
    beam('Interior',(-5.3,11.25,4.8),(5.4,11.25,4.8),0.038,0.038,'Zinc')
    # Wall vent is backed by darkness and slats, not a black painted square.
    box('Interior',(-3.2,11.28,3.3),(1.2,0.22,0.85),'Steel')
    for z in (3.0,3.13,3.26,3.39,3.52,3.65):
        box('Interior',(-3.2,11.12,z),(1.08,0.13,0.045),'Zinc')
    for y in (-7,1,9):
        box('Fixtures',(0,y,5.63),(2.2,0.26,0.14),'Steel')
        box('Fixtures',(0,y,5.55),(1.96,0.21,0.025),'Lamp')
        for x in (-0.9,0.9):
            beam('Suspensions',(x,y,5.72),(x,y,8.28),0.014,0.014,'Zinc')
    # Exterior lamps, controls and restrained identification.
    for x in (-4.5,4.5):
        box('Fixtures',(x,-12.2,5.88),(0.8,0.4,0.18),'Steel')
        box('Fixtures',(x,-12.42,5.86),(0.64,0.025,0.085),'Lamp')
    box('Fixtures',(6.38,-12.12,1.3),(0.23,0.2,0.36),'Steel')
    for z,mat in ((1.38,'White'),(1.23,'Red')):
        cylinder('Fixtures',(6.38,-12.235,z),(6.38,-12.22,z),0.035,mat,10)
    box('Fixtures',(-6.6,-12.06,1.42),(0.55,0.065,0.8),'White')
    box('Fixtures',(-6.6,-12.101,1.6),(0.49,0.02,0.32),'Yellow')
    box('Fixtures',(0,-12.04,6.58),(3.8,0.07,1.2),'Door')
    text_object('HangarIdentity','H - 01',(0,-12.085,6.27),0.74)
    text_object('ClearanceLabel','CLEAR  11.6 x 4.8 M',(0,-12.345,5.22),0.115)
    text_object('WarningLabel','KEEP\nCLEAR',(-6.6,-12.119,1.19),0.13,'Steel')
    text_object('WarningSymbol','!',(-6.6,-12.12,1.48),0.23,'Steel')
    # Grounded dirt overlays: a single shared transparent image, faded at the top.
    grime=material('GroundDirt',(0.2,0.16,0.1))
    bs=next(n for n in grime.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
    image=grime.node_tree.nodes.new('ShaderNodeTexImage')
    image.image=bpy.data.images.load(str(tex/'ground_dirt.png'),check_existing=True)
    grime.node_tree.links.new(image.outputs['Color'],bs.inputs['Base Color'])
    grime.node_tree.links.new(image.outputs['Alpha'],bs.inputs['Alpha'])
    if hasattr(grime,'surface_render_method'): enum(grime,'surface_render_method','DITHERED')
    for y in (-12.027,12.027):
        for s in (-1,1):
            points=[(s*6.18,y,0.025),(s*13.6,y,0.025),(s*13.6,y,0.64),(s*6.18,y,0.64)]
            face=(0,1,2,3) if (s>0)==(y<0) else (3,2,1,0)
            shape('GroundDirt',points,[face],'GroundDirt')
            BATCH['GroundDirt']['uv'][-1]=[(0,0),(1,0),(1,1),(0,1)] if face[0]==0 else [(0,1),(1,1),(1,0),(0,0)]
    for name in list(BATCH):
        flush(name,bevel=0.012 if name in ('Frames','Portal','Flashings','Interior','Fixtures') else 0)
    print('DETAIL_COMPLETE: UV PBR, fabricated structure, service interior, bifold cycle')


def finish():
    # Two winding lift cables connect the header drives to the guided bottom edge.
    for s in (-1,1):
        box('LiftCables',(s*6.02,-12.34,5.02),(0.012,0.012,1.0),'Zinc')
    cables=flush('LiftCables',pivot=(0,-12.34,5.52))
    for frame in range(1,362):
        SCENE.frame_set(frame)
        cables.scale.z=5.46-SCENE.objects['GuideRollers'].location.z
        cables.keyframe_insert(data_path='scale',frame=frame,group='Winding_length')
    cables.animation_data.action.name='SH_LiftCables_cycle'
    # Review lighting only: not exported with the reusable asset.
    for y in (-7,1,9):
        data=bpy.data.lights.new('SH_InteriorReview','AREA')
        data.energy=380
        data.shape='RECTANGLE'
        data.size=2.0
        data.size_y=0.35
        obj=bpy.data.objects.new('Studio_Interior',data)
        SCENE.collection.objects.link(obj)
        obj.location=(0,y,5.5)
    SCENE.cycles.samples=40
    SCENE.frame_set(1)
    # Mesh consolidation removes duplicated material surfaces/draw calls.
    bpy.ops.object.select_all(action='DESELECT')
    static=[o for o in SCENE.objects if o.type=='MESH' and o.parent==ROOT_OBJ and not o.animation_data]
    for obj in static:
        if not obj.data.uv_layers: obj.data.uv_layers.new(name='UVMap')
        obj.select_set(True)
    bpy.context.view_layer.objects.active=SCENE.objects['Shell']
    bpy.ops.object.join()
    SCENE.objects['Shell'].name='HangarStatic'
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    bpy.ops.object.select_all(action='DESELECT')
    # Construction data for collision generation; primitives preserve the opening.
    collision=[]
    for center,size in [((0,0,-0.18),(28.5,24.7,0.36)),((-13.73,0,0.31),(0.4,23.1,0.62)),((13.73,0,0.31),(0.4,23.1,0.62))]:
        collision.append({'type':'box','center':center,'size':size})
    for s in (-1,1):
        collision.append({'type':'roof','center':(s*7,0,4.8),'size':(math.hypot(14,8.45),24.65,0.16),'angle_y':s*math.atan2(8.45,14)})
        outline=[(s*5.98,0),(s*13.95,0),(s*13.95,0.55),(s*5.98,5.36)]
        collision.append({'type':'convex','points':[(x,y,z) for y in (-12,-11.55) for x,z in outline]})
    for outline,ys in [([(-5.98,5.18),(5.98,5.18),(5.98,5.36),(0,8.97),(-5.98,5.36)],(-12,-11.55)),([(-13.95,0),(13.95,0),(13.95,0.55),(0,8.97),(-13.95,0.55)],(11.55,12))]:
        collision.append({'type':'convex','points':[(x,y,z) for y in ys for x,z in outline]})
    (SOURCE/'collision.json').write_text(json.dumps(collision,indent=2))
    export_and_check()


def export_and_check():
    SCENE.frame_set(1)
    meshes=[o for o in SCENE.objects if o.type=='MESH' and (o.parent==ROOT_OBJ or o.parent==SCENE.objects['DoorUpper'])]
    triangles=0
    for obj in meshes:
        obj.data.calc_loop_triangles()
        triangles+=len(obj.data.loop_triangles)
        assert obj.data.uv_layers, obj.name
        assert all(math.isfinite(v) for p in obj.data.vertices for v in p.co)
        assert obj.scale.x==1 and obj.scale.y==1
        if obj.name!='LiftCables': assert obj.scale.z==1
    assert triangles<45000,triangles
    top=SCENE.objects['DoorUpper']; lower=SCENE.objects['DoorLower']
    for frame in range(1,362):
        SCENE.frame_set(frame)
        bpy.context.view_layer.update()
        bottom=lower.matrix_world @ Vector((0,0,-2.55))
        assert abs(bottom.y+12.36)<0.001, (frame,bottom)
        assert bottom.z>=0.059
        assert abs(SCENE.objects['GuideRollers'].location.z+0.06-bottom.z)<0.001
        assert abs(SCENE.objects['LiftCables'].scale.z-(5.52-bottom.z))<0.001
    SCENE.frame_set(181)
    bpy.context.view_layer.update()
    door_min=min((o.matrix_world@v.co).z for o in (top,lower) for v in o.data.vertices)
    assert door_min>4.8,door_min
    SCENE.frame_set(1)
    bpy.ops.object.select_all(action='DESELECT')
    ROOT_OBJ.select_set(True)
    for obj in meshes: obj.select_set(True)
    bpy.context.view_layer.objects.active=ROOT_OBJ
    # SCENE mode exports all four coordinated animated objects as ONE clip.
    bpy.ops.export_scene.gltf(filepath=str(ASSET/'small_hangar.glb'),export_format='GLB',use_selection=True,export_animations=True,export_animation_mode='SCENE',export_frame_range=True,export_force_sampling=True,export_anim_slide_to_zero=True,export_anim_scene_split_object=False,export_nla_strips_merged_animation_name='door_cycle',export_lights=False,export_cameras=False,export_extras=True)
    metrics={'triangles':triangles,'mesh_objects':len(meshes),'materials':len({m.name for o in meshes for m in o.data.materials}),'footprint_m':[28.5,24.9],'ridge_m':9.2,'door_open_clearance_m':round(door_min,3),'door_width_m':11.6,'frames':{'closed':1,'open_start':31,'open':151,'close_start':211,'closed_end':331},'fps':30,'coordinate_system':'Blender Z-up, entrance -Y; glTF/Godot Y-up, entrance +Z','collision_primitives':9,'checks':'361 frames: guided bottom, cable length, finite vertices, UV, unit non-animated scales'}
    (ASSET/'metrics.json').write_text(json.dumps(metrics,indent=2))
    set_camera((30,-41,18),(0,-1,3),43)
    # Keep the user's pre-existing scene in the .blend, but only SmallHangar exports.
    for image in bpy.data.images:
        if image.source=='FILE' and image.has_data: image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'small_hangar.blend'))
    print('PASS: SMALL_HANGAR_EXPORT',json.dumps(metrics))
