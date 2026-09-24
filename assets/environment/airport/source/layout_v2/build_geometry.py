"""Planar airport authoring: uv run --with shapely==2.1.2 --with pillow build_geometry.py.
Only authoring needs Shapely; delivered meshes have no runtime dependencies.
"""
import json
import math
from pathlib import Path
from shapely import constrained_delaunay_triangles
from shapely.geometry import box, LineString, Polygon
from shapely.ops import unary_union

OUT = Path(__file__).resolve().parent
objects = []
routes = []
placements_path = OUT/'asset_placements.json'
placements = json.loads(placements_path.read_text()) if placements_path.exists() else []
# Native hangars supply their own floor at z=0: cut only the visible apron/paint,
# retaining the continuous pavement collision beneath it.
asset_floors = unary_union([box(p['position_blender'][0]-p['foundation_size_xy'][0]/2,
    p['position_blender'][1]-p['foundation_size_xy'][1]/2,
    p['position_blender'][0]+p['foundation_size_xy'][0]/2,
    p['position_blender'][1]+p['foundation_size_xy'][1]/2) for p in placements])

def rect(x0, y0, x1, y1):
    return box(x0, y0, x1, y1)

def union(items):
    return unary_union(items)

def stroke(points, width):
    return LineString(points).buffer(width / 2, cap_style=2, join_style=1, quad_segs=16)

def rounded(points, radius):
    """Exact circular fillets, sampled at <=3 degrees; no Bezier tight spots."""
    result = [points[0]]
    for a, b, c in zip(points, points[1:], points[2:]):
        u = (a[0]-b[0], a[1]-b[1]); v = (c[0]-b[0], c[1]-b[1])
        lu, lv = math.hypot(*u), math.hypot(*v)
        u = (u[0]/lu, u[1]/lu); v = (v[0]/lv, v[1]/lv)
        theta = math.acos(max(-1, min(1, u[0]*v[0]+u[1]*v[1])))
        d = radius / math.tan(theta/2)
        assert d <= min(lu, lv)/2 + 0.001, (a,b,c,radius)
        tangent = (b[0]+u[0]*d, b[1]+u[1]*d)
        bisector = (u[0]+v[0], u[1]+v[1]); length = math.hypot(*bisector)
        center = (b[0]+bisector[0]/length*radius/math.sin(theta/2), b[1]+bisector[1]/length*radius/math.sin(theta/2))
        start = math.atan2(tangent[1]-center[1], tangent[0]-center[0])
        end = math.atan2(b[1]+v[1]*d-center[1], b[0]+v[0]*d-center[0])
        sweep = (end-start+math.pi)%(2*math.pi)-math.pi
        count = max(2, math.ceil(abs(sweep)/math.radians(3)))
        result.extend([(center[0]+radius*math.cos(start+sweep*i/count), center[1]+radius*math.sin(start+sweep*i/count)) for i in range(count+1)])
    result.append(points[-1])
    return result

def polygons(g):
    if g.is_empty: return []
    if g.geom_type == 'Polygon': return [g]
    return [p for sub in getattr(g, 'geoms', []) for p in polygons(sub)]

def add(name, group, material, geom, z=0, chunks=False):
    if group in ['APRONS', 'MARKINGS'] and placements and geom.intersects(asset_floors):
        geom = geom.difference(asset_floors)
    if chunks:
        for y in range(-1400, 1400, 200):
            piece = geom.intersection(box(-2000,y,2000,y+200))
            if not piece.is_empty: add(f'{name}_{y+1400:04d}',group,material,piece,z)
        return
    verts, faces, indices = [], [], {}
    for poly in polygons(geom):
        if poly.area < 0.000001: continue
        assert poly.is_valid, name
        for tri in constrained_delaunay_triangles(poly).geoms:
            f=[]
            coords=list(tri.exterior.coords)[:3]
            if not tri.exterior.is_ccw: coords.reverse()
            for x,y in coords:
                key=(round(x,7),round(y,7))
                if key not in indices:
                    indices[key]=len(verts); verts.append([key[0],key[1],z])
                f.append(indices[key])
            faces.append(f)
    if faces: objects.append(dict(name=name,group=group,material=material,verts=verts,faces=faces))

def paint(name, geom, material='yellow', z=0.012):
    add(name,'MARKINGS',material,geom,z)

runway=rect(-30,-1200,30,1200)
links=[-1120,-600,250,850,1120]
taxi_raw=union([rect(-191.5,-1120,-168.5,1120)]+[rect(-180,y-11.5,0,y+11.5) for y in links])
# Closing fills the inside corners with tangent 35 m fillets, not triangular flares.
movement=union([runway,taxi_raw]).buffer(35,quad_segs=24).buffer(-35,quad_segs=24)
main=Polygon([(-535,-775),(-520,-790),(-295,-790),(-280,-775),(-280,165),(-295,180),(-470,180),(-470,-255),(-535,-255)])
north=Polygon([(-490,575),(-475,560),(-295,560),(-280,575),(-280,985),(-295,1000),(-475,1000),(-490,985)])
aprons=union([main,north])
holding_paths=[rounded([(-180,y),(-280,y),(-280,y+185),(-180,y+185)],45) for y in [-1080,340]]
holding=union([stroke(p,30) for p in holding_paths]+[rect(-302,y+45,-258,y+140) for y in [-1080,340]])
feeds=[-735,-285,100,630,935]
feed_raw=union([rect(-310,y-11.5,-180,y+11.5) for y in feeds])
movement=union([movement,aprons,feed_raw,holding]).buffer(30,quad_segs=24).buffer(-30,quad_segs=24)
# Restore the exact runway rectangle; no rounded runway ends.
movement=union([movement,runway])
taxi=movement.difference(union([runway,aprons]))
shoulder=movement.buffer(5,quad_segs=12).difference(movement)
add('RWY_18_36','RUNWAY','asphalt',runway,chunks=True)
add('TWY_A_and_links','TAXIWAYS','taxi_asphalt',taxi,chunks=True)
add('APRON_main','APRONS','concrete',main,chunks=True)
add('APRON_north','APRONS','concrete',north,chunks=True)
add('Pavement_shoulders_5m','UTILITIES','shoulder',shoulder,z=-0.025,chunks=True)

# Road system stays behind the flight line. Vehicle access never uses runway links.
road_paths=[
    rounded([(-1080,-970),(-720,-970),(-720,1070),(-560,1070),(-560,1010)],24),
    rounded([(-720,-900),(-880,-900),(-880,1070),(-720,1070)],35),
    rounded([(-720,-825),(-545,-825),(-545,-730),(-515,-730)],14),
    [(-720,-300),(-520,-300)], [(-720,150),(-455,150)],
    [(-720,520),(-540,520),(-540,440)],
    [(-720,630),(-470,630)], [(-720,1005),(-485,1005)],
    [(-880,-600),(-770,-600)], [(-720,790),(-590,790)],
    [(-720,285),(-600,285)],
    [(-720,-455),(-685,-455)], [(-720,-145),(-655,-145)],
    [(-720,580),(-630,580)], [(-780,-970),(-780,-947)]
]
road_raw=union([stroke(p,9) for p in road_paths])
roads=road_raw.buffer(10,quad_segs=16).buffer(-10,quad_segs=16)
yards=union([rect(-840,-740,-755,-475),rect(-660,-35,-545,315),rect(-630,365,-500,495),rect(-660,700,-525,965)])
# Shoulder of roads is lower and stops at all aircraft pavement.
road_all=union([roads,yards]).difference(movement)
add('SERVICE_roads','ROADS','road',road_all.difference(yards),chunks=True)
add('Support_yards','APRONS','yard',yards.difference(movement),chunks=True)
add('Road_verges','UTILITIES','gravel',road_all.buffer(1.2).difference(union([road_all,movement])),z=-0.03,chunks=True)
# Clean road perimeter lines, never across driveways/intersections.
road_edge=road_all.boundary.buffer(.10).intersection(roads).difference(yards.buffer(.3))
paint('Road_edge_white',road_edge,'white')
road_dashes=[]
for p in road_paths:
    line=LineString(p)
    for i in range(0,int(line.length)-3,9):
        if yards.covers(line.interpolate(i)): continue
        road_dashes.append(stroke([line.interpolate(i).coords[0],line.interpolate(i+3).coords[0]],.14))
paint('Road_lane_dashes',union(road_dashes),'white')

# Runway markings: 60 m / sixteen threshold stripes, 30 m dashes / 30 m gaps.
white=[]
for x in [-29.1,29.1]: white.append(rect(x-.45,-1200,x+.45,1200))
for end in [-1,1]:
    cy=end*1197
    white.append(rect(-30,cy-.9,30,cy+.9))
    for side in [-1,1]:
        for i in range(8):
            x=side*(3.0+i*3.35)
            white.append(rect(x-.9,min(end*1188,end*1158),x+.9,max(end*1188,end*1158)))
        # Aiming point 300 m from threshold.
        white.append(rect(side*18-3, min(end*900,end*855), side*18+3,max(end*900,end*855)))
        for distance in [150,450,600,750,900]:
            count=3 if distance==150 else (2 if distance in [450,600] else 1)
            for j in range(count):
                x=side*(13+j*3)
                y=end*(1200-distance)
                white.append(rect(x-.9,y-11.25,x+.9,y+11.25))
for y in range(-1080,1080,60): white.append(rect(-.45,y,.45,y+30))
paint('RWY_white_markings',union(white),'white',.015)

# Taxi centerlines and real circular turning paths. Paths are kept as editable curves too.
centerlines=[[( -180,-1120),(-180,1120)]]+holding_paths
for y in links:
    centerlines.append([(-180,y),(-65,y)])
    for direction in [-1,1]:
        # End links permit only the inward turn, without overshooting pavement.
        if y == -1120 and direction < 0 or y == 1120 and direction > 0: continue
        centerlines.append(rounded([(-180,y+direction*110),(-180,y),(0,y),(0,y+direction*110)],50))
for y in feeds:
    centerlines.append([(-405,y),(-180,y)])
    for direction in [-1,1]:
        centerlines.append(rounded([(-300,y),(-180,y),(-180,y+direction*110)],50))
# Main apron taxilane, positioned clear of both red hangar and orange shelter faces.
centerlines.extend([[(-310,-735),(-310,100)],[(-310,630),(-310,935)]])
stands=[(-452,-605,50),(-452,-405,50),(-376,-170,29),(-376,-65,29),(-376,40,29),(-408,745,40),(-408,880,40)]
for x,y,depth in stands:
    centerlines.append([(x+depth,y),(-310,y)])
    for direction in [-1,1]:
        centerlines.append(rounded([(x+depth,y),(-310,y),(-310,y+direction*60)],16))
    paint(f'Stand_stop_{y}',stroke([(x+depth+10,y-5),(x+depth+10,y+5)],.3), z=.018)
for i,p in enumerate(centerlines):
    line=LineString(p)
    # Paint and swept pavement must cover the complete path, not only sampled vertices.
    assert movement.buffer(.02).covers(line), ('uncovered route',i)
    routes.append(dict(name=f'Route_{i:02d}',points=p))
paint('Taxi_centerlines',union([stroke(p,.30) for p in centerlines]))
# Double edge lines only on exposed taxi edges, no spurious lines across intersections.
taxi_edge=movement.boundary.intersection(taxi.buffer(.01))
paint('Taxi_edge_outer',taxi_edge.buffer(.12).intersection(taxi))
paint('Taxi_edge_inner',movement.buffer(-.8).boundary.buffer(.12).intersection(taxi))
# Holding positions 90 m from runway axis: solid on approach / dashed runway side.
hold=[]
for y in links:
    for x in [-93,-92.25]: hold.append(rect(x-.15,y-11.5,x+.15,y+11.5))
    for x in [-91.5,-90.75]:
        for dy in range(-11,11,2): hold.append(rect(x-.15,y+dy,x+.15,y+dy+1))
paint('RWY_holding_positions',union(hold))
# Apron safety envelopes and concrete expansion joints (subtle, not texture noise).
safety=[]
for x,y,depth in stands:
    front=x+depth
    safety.append(stroke([(front+4,y-36),(front+52,y-36),(front+52,y+36),(front+4,y+36)],.22))
paint('Stand_safety_envelopes',union(safety).intersection(aprons),'white')
joints=[]
for x in range(-850,-270,12): joints.append(stroke([(x,-800),(x,1010)],.055))
for y in range(-800,1010,12): joints.append(stroke([(-850,y),(-275,y)],.055))
paint('Concrete_panel_joints',union(joints).intersection(union([aprons,yards])),'joint',.004)
# Vehicle bays on the operations campus and logistics yard.
parking=[]
for y in [5,260]:
    for x in range(-650,-550,4): parking.append(stroke([(x,y),(x,y+8)],.15))
for y in range(-710,-495,18): parking.append(stroke([(-830,y),(-809,y)],.15))
paint('Vehicle_parking',union(parking),'white')

# Blocks: front points +X toward the flight line; pivot on ground, never architectural detail.
buildings=[
 ('H01_Heavy_maintenance','red',-452,-605,100,125,23),
 ('H02_Maintenance','red',-452,-405,100,95,19),
 ('S01_Shelter','orange',-376,-170,58,55,12),
 ('S02_Shelter','orange',-376,-65,58,55,12),
 ('S03_Shelter','orange',-376,40,58,55,12),
 ('O01_Operations','blue',-597,75,78,55,14),
 ('O02_Command','blue',-590,205,80,48,16),
 ('T01_Tower_shaft','purple',-540,255,16,16,38),
 ('R01_Radar_base','purple',-558,433,65,55,12),
 ('R02_Comms','purple',-613,455,18,22,18),
 ('I01_North_workshop','yellow',-408,745,80,75,17),
 ('I02_Utilities_hangar','yellow',-408,880,80,72,17),
 ('I03_Fuel_control','yellow',-589,920,76,38,9),
 ('I04_Fuel_A','yellow',-630,747,23,23,17),
 ('I05_Fuel_B','yellow',-590,747,23,23,17),
 ('I06_Fuel_C','yellow',-550,747,23,23,17),
 ('I07_Power','yellow',-592,846,80,35,11),
 ('L01_Warehouse','green',-788,-680,52,66,13),
 ('L02_Logistics','green',-788,-555,52,50,11),
 ('L03_Support','green',-665,-455,38,64,10),
 ('U01_Gate','white_block',-780,-942,20,16,6),
 ('U02_Secondary','white_block',-643,-145,34,22,7),
 ('U03_Crew','blue',-607,-145,24,22,7),
 ('U04_Service','white_block',-620,580,30,24,7)
]
# Every block has a planned supporting pad; no isolated cubes on soil.
extra_pads=[]
for name,mat,x,y,w,d,h in buildings:
    footprint=box(x-w/2,y-d/2,x+w/2,y+d/2)
    pad=box(x-w/2-5,y-d/2-5,x+w/2+5,y+d/2+5)
    assert not footprint.intersects(taxi), name
    extra_pads.append(pad)
add('Block_foundation_pads','APRONS','yard',union(extra_pads).difference(union([movement,road_all])),z=0)
# Regression: connected vehicle access, disjoint pavement and swept aircraft corridors.
all_paved=union([movement,road_all]+extra_pads)
assert all_paved.geom_type=='Polygon', [(g.area,g.bounds) for g in polygons(all_paved)]
# One non-rendered union collider removes independent-shape seams in Jolt;
# visible runway/road/apron meshes remain modular 200 m chunks.
add('Pavement_collision-colonly','COLLISIONS','asphalt',all_paved)
assert abs(runway.area-144000)<.01
assert movement.geom_type=='Polygon' and movement.is_valid
assert runway.intersection(taxi).area < .0001
assert aprons.intersection(taxi).area < .0001
for i,p in enumerate(centerlines):
    # 7 m wheel/wing half-envelope for the project's 14.08 m N26.
    assert movement.buffer(.1).covers(stroke(p,14.1)), ('swept clearance',i)
for i,(name,mat,x,y,w,d,h) in enumerate(buildings):
    footprint=box(x-w/2,y-d/2,x+w/2,y+d/2)
    for route in centerlines:
        # Stand leads terminate at placeholder face: allow their straight final approach.
        assert footprint.intersection(stroke(route,14.1)).area < .01, ('building clearance',name)

payload=dict(objects=objects,routes=routes,buildings=buildings,dimensions=dict(runway=[2400,60],taxiway_width=23,taxiway_offset=180,road_width=9,turn_radius=50,units='metres'),checks='AIRPORT_PLAN_CHECK_OK')
(OUT/'geometry.json').write_text(json.dumps(payload,separators=(',',':')))
# Reuse project CC0 sources, reducing contrast only; no new downloaded assets.
from PIL import Image, ImageStat
for key, source, mean in [('asphalt','airport_layout_asphalt_floor_Diffuse.jpg',88),('concrete','airport_layout_ph_airfield_concrete_albedo.jpg',185),('road','airport_layout_city_road_asphalt_albedo.jpg',101)]:
    im=Image.open(OUT.parent.parent/source).convert('L').resize((1024,1024))
    average=ImageStat.Stat(im).mean[0]
    im=im.point(lambda v: int(max(0,min(255,mean+(v-average)*.3))))
    im.convert('RGB').save(OUT/(key+'_base.jpg'),quality=92)
print('AIRPORT_PLAN_CHECK_OK',len(objects),'meshes',sum(len(o['faces']) for o in objects),'triangles')
