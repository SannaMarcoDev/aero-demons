"""Blender 5.2 authoring source, invoked through Blender MCP; never runs in game.
Uses the CC0 atlas documented in assets/environment/garda_forest/SOURCES.md.
Call pack_garda_tree_atlas.py base, build(), bake('front'/'side'/'top'),
pack_garda_tree_atlas.py pack, finish(). See SOURCES.md for the full workflow.
Existing Blender scenes/objects are retained. Only our named studio is rebuilt.
"""
import math
import random
from pathlib import Path
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets/environment/garda_forest'
ART = ROOT / 'subagent-artifacts/garda-forest/tree-source'
STUDIO = 'Garda Broadleaf Studio'


def uv_rect(x, y, w, h):
    return [(x / 2048, 1 - (y + h) / 2048), ((x + w) / 2048, 1 - (y + h) / 2048),
            ((x + w) / 2048, 1 - y / 2048), (x / 2048, 1 - y / 2048)]


class Geometry:
    def __init__(self):
        self.vertices, self.faces, self.uvs, self.normals, self.colors = [], [], [], [], []

    def quad(self, points, uvs, normals, shade=1):
        base = len(self.vertices)
        self.vertices.extend(points)
        self.faces.append(tuple(range(base, base + 4)))
        self.uvs.extend(uvs)
        self.normals.extend(normals)
        self.colors.extend([(shade, shade, shade, 1)] * 4)

    def tube(self, points, radii, sides):
        for k in range(len(points) - 1):
            a, b = Vector(points[k]), Vector(points[k + 1])
            direction = (b - a).normalized()
            u = direction.cross(Vector((0, 1, 0))).normalized()
            v = direction.cross(u).normalized()
            for j in range(sides):
                n = [u * math.cos(t * math.tau / sides) + v * math.sin(t * math.tau / sides)
                     for t in (j, j + 1)]
                p = [a + n[0] * radii[k], a + n[1] * radii[k],
                     b + n[1] * radii[k + 1], b + n[0] * radii[k + 1]]
                self.quad(p, uv_rect(1794 + j * 248 / sides, 2, 248 / sides, 506),
                          [n[0], n[1], n[1], n[0]], .87)

    def object(self, scene, name, material):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        uv = mesh.uv_layers.new(name='UVMap')
        colors = mesh.color_attributes.new(name='TreeTint', type='FLOAT_COLOR', domain='POINT')
        for i, color in enumerate(self.colors):
            colors.data[i].color = color
        for loop in mesh.loops:
            uv.data[loop.index].uv = self.uvs[loop.vertex_index]
        for poly in mesh.polygons:
            poly.use_smooth = True
        mesh.normals_split_custom_set_from_vertices(self.normals)
        mesh.materials.append(material)
        obj = bpy.data.objects.new(name, mesh)
        scene.collection.objects.link(obj)
        return obj


def build():
    old = bpy.data.scenes.get(STUDIO)
    if old:
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.scenes.remove(old)
    scene = bpy.data.scenes.new(STUDIO)
    bpy.context.window.scene = scene
    scene.render.engine = 'BLENDER_EEVEE'
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = 'PNG'
    scene.render.image_settings.color_mode = 'RGBA'
    scene.view_settings.view_transform = 'Standard'
    scene.world = bpy.data.worlds.new('Garda Tree World')
    scene.world.color = (.25, .25, .25)
    material = bpy.data.materials.new('Garda Broadleaf Atlas')
    material.use_nodes = True
    material.surface_render_method = 'DITHERED'
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get('Principled BSDF')
    shader.inputs['Roughness'].default_value = 1
    image = nodes.new('ShaderNodeTexImage')
    image.image = bpy.data.images.load(str(ASSETS / 'garda_broadleaf_atlas.png'), check_existing=False)
    color = nodes.new('ShaderNodeVertexColor')
    color.layer_name = 'TreeTint'
    multiply = nodes.new('ShaderNodeMixRGB')
    multiply.blend_type = 'MULTIPLY'
    multiply.inputs[0].default_value = 1
    links.new(image.outputs['Color'], multiply.inputs[1])
    links.new(color.outputs['Color'], multiply.inputs[2])
    links.new(multiply.outputs[0], shader.inputs['Base Color'])
    links.new(image.outputs['Alpha'], shader.inputs['Alpha'])
    centers = []
    branches = []
    rng = random.Random(7319)
    # Layered, irregular ovoid crown, not a ring of umbrella-shaped branches.
    for i in range(18):
        angle = i * 2.39996
        height = 5.2 + i * .43
        radius = 3.8 * math.sqrt(max(.12, 1 - ((height - 8.5) / 5.5) ** 2))
        direction = Vector((math.cos(angle), math.sin(angle), 0))
        start = Vector((.1, 0, 2.8 + i * .38))
        end = direction * radius + Vector((-.25, .1, height))
        mid = start.lerp(end, .52) + Vector((0, 0, .4))
        branches.append(([start, mid, end], [.16 - i * .006, .07, .02]))
        for j in range(2):
            spin = angle + (j - .5) * .85
            tip = end + Vector((math.cos(spin) * rng.uniform(.3, 1.0),
                                math.sin(spin) * rng.uniform(.3, 1.0), rng.uniform(.1, 1.0)))
            centers.append(tip)
            branches.append(([mid, end.lerp(tip, .4), tip], [.045, .025, .008]))
    centers.extend([Vector((-.4, .1, 13.8)), Vector((.6, -.3, 10)), Vector((-.8, .7, 7.5))])
    for lod in (0, 1):
        g = Geometry()
        g.tube([(0, 0, -.18), (.13, -.05, 1.8), (-.1, .15, 4), (.18, .04, 6.2), (-.35, .1, 9.7)],
               [.48, .29, .23, .14, .025], 8 if lod == 0 else 5)
        for i, (points, radii) in enumerate(branches):
            if lod == 0 or i % 4 == 0:
                g.tube(points, radii, 5 if lod == 0 else 3)
        rng = random.Random(9123)
        for center in centers:
            for j in range(16 if lod == 0 else 5):
                delta = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-.7, .9)))
                pos = center + delta * 1.25
                angle = rng.uniform(0, math.tau)
                u = Vector((math.cos(angle), math.sin(angle), rng.uniform(-.35, .65))).normalized()
                side = u.cross(Vector((0, 0, 1))).normalized()
                roll = rng.uniform(0, math.tau)
                v = side * math.cos(roll) + u.cross(side) * math.sin(roll)
                width = rng.uniform(2.0, 3.2) * (1 if lod == 0 else 1.75)
                u *= width * .5
                v *= width * .20
                n = Vector((pos.x * .16, pos.y * .16, (pos.z - 8) * .20 + .65)).normalized()
                shade = rng.uniform(.88, 1.08) * min(1, .78 + (pos.z - 5) * .045)
                if lod == 0:
                    fold = n * .10
                    g.quad([pos-u-v, pos-v+fold, pos+v+fold, pos-u+v], uv_rect(0, 0, 768, 394), [n]*4, shade)
                    g.quad([pos-v+fold, pos+u-v, pos+u+v, pos+v+fold], uv_rect(768, 0, 768, 394), [n]*4, shade)
                else:
                    g.quad([pos-u-v, pos+u-v, pos+u+v, pos-u+v], uv_rect(0, 0, 1536, 394), [n]*4, shade)
        obj = g.object(scene, 'GardaTree_LOD' + str(lod), material)
        obj.hide_render = lod != 0
        obj.hide_set(lod != 0)
        print(obj.name, 'triangles', sum(len(p.vertices)-2 for p in obj.data.polygons))
    camera = bpy.data.objects.new('Garda Bake Camera', bpy.data.cameras.new('Garda Bake Camera'))
    scene.collection.objects.link(camera)
    scene.camera = camera
    camera.data.type = 'ORTHO'
    camera.data.ortho_scale = 16
    scene.render.resolution_x = scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    sun = bpy.data.objects.new('Garda Preview Sun', bpy.data.lights.new('Garda Preview Sun', 'SUN'))
    sun.data.energy = 2
    sun.rotation_euler = (.35, -.55, -.6)
    scene.collection.objects.link(sun)
    print('GARDA TREE BUILD PASS')


def bake(view):
    scene = bpy.data.scenes[STUDIO]
    bpy.context.window.scene = scene
    obj = scene.objects['GardaTree_LOD0']
    shader = obj.data.materials[0].node_tree.nodes.get('Principled BSDF')
    links = obj.data.materials[0].node_tree.links
    multiply = next(n for n in obj.data.materials[0].node_tree.nodes if n.bl_idname == 'ShaderNodeMixRGB')
    # Albedo bake: avoid baking sun shadows which would be lit a second time in Godot.
    links.new(multiply.outputs[0], shader.inputs['Emission Color'])
    shader.inputs['Emission Strength'].default_value = 1
    scene.objects['Garda Preview Sun'].hide_render = True
    scene.world.color = (0, 0, 0)
    target = Vector((0, 0, 7.8 if view != 'top' else 8))
    camera = scene.camera
    camera.location = target + {'front': Vector((0, -30, 0)), 'side': Vector((30, 0, 0)), 'top': Vector((0, 0, 30))}[view]
    camera.rotation_euler = (target - camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(ART / (view + '.png'))
    bpy.ops.render.render(write_still=True)
    print('GARDA TREE BAKE PASS', view)


def bake_normals(view):
    """Object-space crown normals for the distant flight impostor (linear RGB)."""
    scene = bpy.data.scenes[STUDIO]
    bpy.context.window.scene = scene
    material = scene.objects['GardaTree_LOD0'].data.materials[0]
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes.get('Principled BSDF')
    original = next(n for n in nodes if n.bl_idname == 'ShaderNodeMixRGB')
    geometry = nodes.new('ShaderNodeNewGeometry')
    encode = nodes.new('ShaderNodeVectorMath')
    encode.operation = 'MULTIPLY_ADD'
    encode.inputs[1].default_value = (.5, .5, .5)
    encode.inputs[2].default_value = (.5, .5, .5)
    facing = nodes.new('ShaderNodeMath')
    facing.operation = 'MULTIPLY_ADD'
    facing.inputs[1].default_value = -2
    facing.inputs[2].default_value = 1
    links.new(geometry.outputs['Backfacing'], facing.inputs[0])
    unflip = nodes.new('ShaderNodeVectorMath')
    unflip.operation = 'SCALE'
    links.new(geometry.outputs['Normal'], unflip.inputs[0])
    links.new(facing.outputs[0], unflip.inputs['Scale'])
    links.new(unflip.outputs[0], encode.inputs[0])
    links.new(encode.outputs[0], shader.inputs['Emission Color'])
    shader.inputs['Emission Strength'].default_value = 1
    shader.inputs['Base Color'].default_value = (0, 0, 0, 1)
    base_link = shader.inputs['Base Color'].links[0]
    links.remove(base_link)
    scene.objects['Garda Preview Sun'].hide_render = True
    scene.world.color = (0, 0, 0)
    scene.view_settings.view_transform = 'Raw'
    target = Vector((0, 0, 7.8 if view != 'top' else 8))
    scene.camera.location = target + {'front': Vector((0, -30, 0)), 'side': Vector((30, 0, 0)), 'top': Vector((0, 0, 30))}[view]
    scene.camera.rotation_euler = (target - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
    scene.render.filepath = str(ART / (view + '_normal.png'))
    bpy.ops.render.render(write_still=True)
    nodes.remove(geometry)
    nodes.remove(encode)
    nodes.remove(facing)
    nodes.remove(unflip)
    links.new(original.outputs[0], shader.inputs['Base Color'])
    links.new(original.outputs[0], shader.inputs['Emission Color'])
    scene.view_settings.view_transform = 'Standard'
    print('GARDA NORMAL BAKE PASS', view)


def finish():
    scene = bpy.data.scenes[STUDIO]
    bpy.context.window.scene = scene
    material = scene.objects['GardaTree_LOD0'].data.materials[0]
    image = material.node_tree.nodes.get('Image Texture').image
    if image.packed_file:
        image.unpack(method='REMOVE')
    image.filepath = str(ASSETS / 'garda_broadleaf_atlas.png')
    image.reload()
    material.node_tree.nodes.get('Principled BSDF').inputs['Emission Strength'].default_value = 0
    scene.world.color = (.25, .25, .25)
    scene.objects['Garda Preview Sun'].hide_render = False
    if 'GardaTree_LOD2' in scene.objects:
        bpy.data.objects.remove(scene.objects['GardaTree_LOD2'], do_unlink=True)
    g = Geometry()
    # Matching orthographic projections: two side cards + overhead canopy for flight.
    for side in range(2):
        points = [(-8, 0, -.2), (8, 0, -.2), (8, 0, 15.8), (-8, 0, 15.8)]
        if side:
            points = [(0, x, z) for x, _, z in points]
        normals = [Vector((x * .12, y * .12, .35 + z * .035)).normalized() for x, y, z in points]
        g.quad(points, uv_rect(side * 1024, 512, 1024, 1024), normals)
        # Crown-scale occlusion survives minification; no directional sunlight baked in.
        g.colors[-4:] = [(s, s, s, 1) for s in [.40, .40, .92, .92]]
    g.quad([(-8, -8, 8), (8, -8, 8), (8, 8, 8), (-8, 8, 8)], uv_rect(0, 1536, 512, 512), [(0, 0, 1)]*4)
    obj = g.object(scene, 'GardaTree_LOD2', material)
    for o in scene.objects:
        o.select_set(False)
    for i in range(3):
        o = scene.objects['GardaTree_LOD' + str(i)]
        o.hide_set(False)
        o.select_set(True)
    bpy.context.view_layer.objects.active = scene.objects['GardaTree_LOD0']
    bpy.ops.export_scene.gltf(filepath=str(ASSETS / 'garda_broadleaf.glb'), export_format='GLB',
                             use_selection=True, use_active_scene=True, export_yup=True, export_materials='EXPORT',
                             export_copyright='Garda generated geometry; CC0 foliage and bark, see SOURCES.md',
                             export_vertex_color='ACTIVE', export_normals=True, export_texcoords=True)
    for i in (1, 2):
        scene.objects['GardaTree_LOD' + str(i)].hide_set(True)
        scene.objects['GardaTree_LOD' + str(i)].hide_render = True
    # Explicit artifact path; never overwrite the user's open .blend.
    path = ART / 'garda_broadleaf_landscape.blend'
    material.node_tree.nodes.get('Image Texture').image.pack()
    bpy.ops.wm.save_as_mainfile(filepath=str(path), copy=True)
    print('GARDA TREE EXPORT PASS', ASSETS / 'garda_broadleaf.glb')
