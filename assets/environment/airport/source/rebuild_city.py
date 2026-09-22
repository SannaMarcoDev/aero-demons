"""Approved catalog -> editable Godot city; run with Blender MCP/runpy.
Reads airport.blend without changing it. Exports ONLY retained infrastructure,
three original standard buildings and two dish variants. No Blender roads.
Then run tools/prepare_airport_city.gd to author the Godot scene and road graph.
"""
import bpy
import bmesh
import json
import math
import runpy
from pathlib import Path
from mathutils import Vector, Matrix

BASE = Path(__file__).resolve().parents[4]
SOURCE = BASE / 'assets/environment/airport/source'
OUT = BASE / 'assets/environment/airport/library'
SITE = json.loads((BASE / 'subagent-artifacts/city-rebuild/survey/site.json').read_text())
# Keep the delivered routing/blocks and original vegetation exclusions as input.
OLD = json.loads((SOURCE / 'city_layout.json').read_text())
METRICS = json.loads((OUT / 'metrics.json').read_text())


def height(x, z):
    u = (x-SITE['first'][0])/SITE['spacing']
    v = (z-SITE['first'][1])/SITE['spacing']
    i, j = math.floor(u), math.floor(v)
    w, h = SITE['size']
    assert 0 <= i < w-1 and 0 <= j < h-1, (x, z)
    a, b = u-i, v-j
    hh = SITE['heights']
    if a >= b:
        value = (1-a)*hh[j*w+i] + (a-b)*hh[j*w+i+1] + b*hh[(j+1)*w+i+1]
    else:
        value = (1-b)*hh[j*w+i] + (b-a)*hh[(j+1)*w+i] + a*hh[(j+1)*w+i+1]
    return value-SITE['origin'][1]


def copy_part(scene, source, name, keep=lambda p: True, origin=(0, 0, 0)):
    original = bpy.data.objects[source]
    mesh = original.data.copy()
    mesh.transform(original.matrix_world)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not keep(v.co)], context='VERTS')
    bm.to_mesh(mesh)
    bm.free()
    assert mesh.polygons, name
    for v in mesh.vertices:
        v.co -= Vector(origin)
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    return obj


def export(objects, path):
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True,
                              use_active_scene=True, export_yup=True, export_animations=False,
                              export_cameras=False, export_lights=False)


def metrics(obj):
    obj.data.calc_loop_triangles()
    points = [v.co for v in obj.data.vertices]
    low = [min(p[i] for p in points) for i in range(3)]
    high = [max(p[i] for p in points) for i in range(3)]
    return {'triangles': len(obj.data.loop_triangles), 'minimum_blender': low,
            'dimensions_blender': [high[i]-low[i] for i in range(3)]}


def retained_assets(scene):
    result = {}
    # Exact original buildings, rather than three newly invented box variants.
    source = bpy.data.objects['city_block_giardini_1_0']
    for i, (x, z) in enumerate([(-1524.2, 725.4), (-1435.8, 725.4), (-1524.2, 832.65)]):
        in_lot = lambda p: abs(p.x-x) < 36 and abs(-p.y-z) < 27
        tall_faces = []
        for face in source.data.polygons:
            ps = [source.matrix_world @ source.data.vertices[k].co for k in face.vertices]
            if all(in_lot(p) for p in ps) and max(p.z for p in ps)-min(p.z for p in ps) > 8:
                tall_faces.extend(ps)
        ground = min(p.z for p in tall_faces)
        name = 'standard_' + str(i+1)
        obj = copy_part(scene, source.name, name, lambda p: in_lot(p) and p.z >= ground-.02, (x, -z, ground))
        result[name] = metrics(obj)
        export([obj], OUT / (name+'.glb'))
        obj.location = (x, -z, ground)
    keep = []
    for stem, predicate in [
        ('city_wind_farm', lambda p: True),
        ('city_telecommunications', lambda p: abs(p.x+2740) < 7 and abs(p.y-790) < 7),
        ('city_airport_support', lambda p: p.x > 700 and 520 <= -p.y <= 560),
        ('city_waterfront', lambda p: p.x > -1450),
    ]:
        for suffix in ('', '_proxy-colonly'):
            keep.append(copy_part(scene, stem+suffix, 'retained_'+stem[5:]+suffix, predicate))
    for name in [o.name for o in bpy.data.collections['city_authored'].objects
                 if o.name.startswith('city_viaduct_structure_')]:
        keep.append(copy_part(scene, name, 'retained_'+name[5:]))
    export(keep, BASE / 'assets/environment/airport/airport_infrastructure.glb')
    # Reuse the approved solid reflector recipe. Only its elevation and metric size change.
    ns = runpy.run_path(str(SOURCE / 'build_library.py'))
    g = ns['dish'].__globals__
    names = ['limestone_plaster','cut_concrete','warm_brick','zinc_roof','blue_green_glazing',
             'graphite_frames','bronze_cladding','structural_steel','roof_gravel','reflector_enamel']
    with bpy.data.libraries.load(str(SOURCE / 'airport_asset_library.blend'), link=False) as (src, dst):
        dst.materials = [next(n for n in src.materials if n.startswith('lib_'+name)) for name in names]
    g['MATERIALS'].extend(dst.materials)
    for i, key in enumerate(['PLASTER','STONE','BRICK','ZINC','GLASS','FRAME','WARM','STEEL','GRAVEL','REFLECTOR']):
        g[key] = i
    for tilt in (15, 55):
        name = 'satellite_dish_45m_' + str(tilt)
        obj = ns['dish'](tilt).object(name, scene.collection)
        for v in obj.data.vertices:
            v.co *= 45/70
        result[name] = metrics(obj)
        export([obj], OUT / (name+'.glb'))
        obj.location = (-2840-(tilt == 55)*85, 850, height(-2840, -850))
    return result


def simplify(points, tolerance=2.5):
    """RDP in the road plane; elevation will be sampled/projected in Godot."""
    if len(points) <= 2:
        return points
    a, b = Vector(points[0][:2]), Vector(points[-1][:2])
    delta = b-a
    distances = []
    for p in points[1:-1]:
        p = Vector(p[:2])
        t = max(0, min(1, (p-a).dot(delta)/delta.length_squared)) if delta.length_squared else 0
        distances.append((p-a-t*delta).length)
    index = max(range(len(distances)), key=distances.__getitem__)
    if distances[index] <= tolerance:
        return [points[0], points[-1]]
    index += 1
    return simplify(points[:index+1], tolerance)[:-1] + simplify(points[index:], tolerance)


def road_graph(roads):
    segments = []
    for road in roads:
        points = simplify(road['points'], .05 if not road['draped'] else 2.5)
        for a, b in zip(points, points[1:]):
            if math.dist(a[:2], b[:2]) > .1:
                segments.append({'a': a, 'b': b, 'road': road, 'cuts': [0., 1.]})
    # Split crossings AND T-junctions, including collinear overlapping source routes.
    for i, s in enumerate(segments):
        a, b = Vector(s['a'][:2]), Vector(s['b'][:2])
        ab = b-a
        for t in segments[i+1:]:
            c, d = Vector(t['a'][:2]), Vector(t['b'][:2])
            cd = d-c
            cross = ab.cross(cd)
            if abs(cross) > 1e-5:
                u, v = (c-a).cross(cd)/cross, (c-a).cross(ab)/cross
                if -.00001 <= u <= 1.00001 and -.00001 <= v <= 1.00001:
                    s['cuts'].append(max(0., min(1., u)))
                    t['cuts'].append(max(0., min(1., v)))
            elif abs((c-a).cross(ab))/ab.length < .02:
                s['cuts'].extend(max(0., min(1., (p-a).dot(ab)/ab.length_squared)) for p in (c, d))
                t['cuts'].extend(max(0., min(1., (p-c).dot(cd)/cd.length_squared)) for p in (a, b))
    # The previous baked routes sampled every 18 m and occasionally skipped an
    # exact corner/T endpoint. Split nearby segments, then weld those small gaps.
    for s in segments:
        for endpoint in (s['a'], s['b']):
            p = Vector(endpoint[:2])
            for t in segments:
                if t['road']['name'] == s['road']['name']:
                    continue
                a, b = Vector(t['a'][:2]), Vector(t['b'][:2])
                delta = b-a
                u = (p-a).dot(delta)/delta.length_squared
                if .0001 < u < .9999 and (p-a-u*delta).length < 12:
                    t['cuts'].append(u)
    vertices, ids, edges = [], {}, {}
    def vertex(s, t):
        p = [s['a'][i]+t*(s['b'][i]-s['a'][i]) for i in range(3)]
        key = tuple(round(v, 2) for v in p[:2])
        if key not in ids:
            ids[key] = len(vertices)
            vertices.append([p[0], p[2], p[1]])
        return ids[key]
    for s in segments:
        cuts = sorted(set(round(t, 8) for t in s['cuts']))
        for a, b in zip(cuts, cuts[1:]):
            i, j = vertex(s, a), vertex(s, b)
            if i == j:
                continue
            key = tuple(sorted((i, j)))
            road = s['road']
            edges[key] = {'a': i, 'b': j, 'route': road['name'], 'elevated': not road['draped'],
                          'width': road['width']}
    # Collapse tiny source kinks, which otherwise put junction envelopes on top of each other.
    while True:
        short = next((key for key in edges if math.dist(vertices[key[0]][::2], vertices[key[1]][::2]) < 24), None)
        if short is None:
            active = sorted({v for edge in edges for v in edge})
            # ponytail: pairwise welding for this ~150-node site; spatial hash if expanded to a regional network.
            short = next(((a,b) for i,a in enumerate(active) for b in active[i+1:]
                          if math.dist(vertices[a][::2],vertices[b][::2]) < 12), None)
        if short is None:
            break
        a, b = short
        vertices[a] = [(x+y)/2 for x, y in zip(vertices[a], vertices[b])]
        replacement = {}
        for edge in edges.values():
            i, j = (a if edge[k] == b else edge[k] for k in ('a', 'b'))
            if i != j:
                replacement[tuple(sorted((i, j)))] = dict(edge, a=i, b=j)
        edges = replacement
    used = sorted({v for edge in edges for v in edge})
    remap = {v: i for i, v in enumerate(used)}
    result = {'vertices': [vertices[i] for i in used],
              'edges': [dict(e, a=remap[e['a']], b=remap[e['b']]) for e in edges.values()]}
    for edge in result['edges']:
        assert edge['a'] != edge['b']
    return result


def layout(extra):
    all_metrics = dict(METRICS, **extra)
    result = dict(OLD, trees=[], buildings=[], exclusions=list(OLD['exclusions']), catalog_metrics=all_metrics,
                  revision='approved-catalog-roadmanager', retained_standard_models=['standard_1','standard_2','standard_3'])
    result['landmarks'] = [v for v in OLD['landmarks'] if v['name'].startswith('turbine_') or v['name'] in ('quay','telecommunications')]
    def place(model, x, z, yaw=0, name=None):
        w, d, h = all_metrics[model]['dimensions_blender']
        # Survey all terrain triangle-grid crossings under the rectangular foundation.
        halfx, halfz = (d/2+1, w/2+1) if yaw % 180 else (w/2+1, d/2+1)
        xs = [x-halfx, x+halfx] + [SITE['first'][0]+i*SITE['spacing'] for i in range(math.ceil((x-halfx-SITE['first'][0])/SITE['spacing']), math.floor((x+halfx-SITE['first'][0])/SITE['spacing'])+1)]
        zs = [z-halfz, z+halfz] + [SITE['first'][1]+i*SITE['spacing'] for i in range(math.ceil((z-halfz-SITE['first'][1])/SITE['spacing']), math.floor((z+halfz-SITE['first'][1])/SITE['spacing'])+1)]
        heights = [height(xx, zz) for xx in xs for zz in zs]
        ground = max(heights)+.12
        item = {'name': name or model+'_%03d' % len(result['buildings']), 'model': model,
                'position': [x, ground, z], 'yaw': yaw, 'foundation_bottom': min(heights)-.2}
        result['buildings'].append(item)
        result['exclusions'].append([x-halfx-5, z-halfz-5, x+halfx+5, z+halfz+5])
        return item
    # Regular streets, irregular rooflines: new residences dominate; the three old
    # standards recur sparsely as ordinary infill, never as additional landmarks.
    palette = ['residence_gabled','residence_l','residence_gabled','standard_1',
               'residence_courtyard','residence_gabled','standard_2','residence_l',
               'residence_gabled','standard_3','residence_courtyard','residence_gabled']
    skyline = {('centro',0,1): 'residence_terraced', ('centro',1,2): 'offices_twins', ('centro',2,0): 'office_spire'}
    for block in result['blocks']:
        x, z = block['center']
        quarter, bi, bj = block['name'].rsplit('_', 2)
        key = (quarter, int(bi), int(bj))
        tower = skyline.get(key)
        index = len(result['buildings'])
        if tower:
            place(tower, x, z, name=tower+'_landmark')
            result['landmarks'].append({'name':tower,'x':x,'z':z,'height':all_metrics[tower]['dimensions_blender'][2]})
            for dx in (-42,42):
                place('residence_gabled', x+dx, z+66, 0)
        else:
            for k, (dx, dz) in enumerate([(-40,-48),(40,-48),(-40,48),(40,48)]):
                model = palette[(index+k+int(bi)*3+int(bj)) % len(palette)]
                place(model, x+dx, z+dz, 180 if k%2 else 0)
    for model, x, z, yaw, name in [
        ('research_center',-950,-650,0,'ResearchHeadquarters'),
        ('research_center',-1080,-900,0,'ResearchWest'),
        ('standard_3',-800,-900,0,'ResearchEast'),
        ('civic_canopy',-930,-410,0,'ResearchLibrary'),
        ('research_center',-920,130,180,'Hospital'),
        ('civic_canopy',-910,480,0,'CivicHall'),
        ('industrial_shed',-1090,700,90,'TransportHall'),
        ('control_tower',-520,660,0,'ControlTower'),
        ('standard_2',-500,760,0,'AirportOperations'),
        ('warehouse_vault',810,880,90,'LogisticsVaultWest'),
        ('industrial_shed',1010,880,0,'LogisticsShedEast'),
        ('industrial_shed',820,1130,90,'LogisticsShedSouth'),
        ('warehouse_vault',1040,1150,0,'LogisticsVaultSouth'),
        ('residence_gabled',-1820,-2180,0,'BayResidenceA'),
        ('residence_l',-1940,-2160,0,'BayResidenceB'),
        ('residence_courtyard',-1910,-1940,0,'BayCourtyard'),
        ('residence_gabled',-1750,-2250,0,'BayResidenceC'),
        ('industrial_shed',-2698,-760,90,'TelecomOperations'),
        ('satellite_dish_70m',-2840,-790,0,'SatelliteDish70'),
        ('satellite_dish_45m_15',-2815,-900,90,'SatelliteDish45High'),
        ('satellite_dish_45m_55',-2920,-875,180,'SatelliteDish45Low'),
    ]:
        place(model,x,z,yaw,name)
    result['road_graph'] = road_graph(result['roads'])
    graph = result['road_graph']
    # A real T connection, not two splines crossing at the user's existing endpoint.
    endpoint = min(range(len(graph['vertices'])), key=lambda i: math.dist(graph['vertices'][i][::2], [1318.484,2586.572]))
    position = list(graph['vertices'][endpoint])
    graph['vertices'][endpoint][0] -= 36
    graph['user_link_vertex'] = len(graph['vertices'])
    graph['vertices'].append(position)
    graph['edges'].append({'a':endpoint,'b':graph['user_link_vertex'],'route':'user_road_link','elevated':False,'width':10})
    result['exclusions'] = [list(rect) for rect in dict.fromkeys(map(tuple, result['exclusions']))]
    reached, pending = set(), [0]
    while pending:
        vertex = pending.pop()
        if vertex in reached:
            continue
        reached.add(vertex)
        for edge in graph['edges']:
            if vertex in (edge['a'],edge['b']):
                pending.extend(v for v in (edge['a'],edge['b']) if v not in reached)
    assert len(reached) == len(graph['vertices']), 'Disconnected native road network'
    return result


def build():
    previous = bpy.context.window.scene
    name = 'AirportCityRetained'
    if bpy.data.scenes.get(name):
        old = bpy.data.scenes[name]
        for obj in list(old.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.data.scenes.remove(old)
    scene = bpy.data.scenes.new(name)
    scene.unit_settings.system = 'METRIC'
    bpy.context.window.scene = scene
    try:
        extra = retained_assets(scene)
        manifest = layout(extra)
        bpy.data.libraries.write(str(SOURCE/'airport_city_retained.blend'), {scene}, path_remap='RELATIVE', compress=True)
        (SOURCE/'city_layout.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
        print('PASS: CITY CATALOG AUTHORING',len(manifest['buildings']),'buildings;',
              len(manifest['road_graph']['vertices']),'road vertices;',len(manifest['road_graph']['edges']),'edges')
    finally:
        bpy.context.window.scene = previous


if __name__ == '__main__':
    build()
