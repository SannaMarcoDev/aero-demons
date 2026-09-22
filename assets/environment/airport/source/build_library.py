"""Independent approval samples. Run through Blender MCP, never rebuilds the city.
Each GLB has its own origin at ground level; only this library scene is saved.
Textures reuse the documented Poly Haven source; no external downloads required.
"""
import bpy
import json
import math
from pathlib import Path
from mathutils import Vector, Matrix

BASE = Path(__file__).resolve().parents[4]
OUT = BASE / 'assets/environment/airport/library'
OUT.mkdir(parents=True, exist_ok=True)
SOURCE = BASE / 'assets/environment/airport/source'
SCENE_NAME = 'AirportAssetLibrary'
MATERIALS = []


def material(name, color, roughness=.65, metallic=0.0):
    m = bpy.data.materials.new('lib_' + name)
    m.use_nodes = True
    # Hex references are sRGB; Blender and glTF base colors are linear.
    rgb = [int(color[i:i+2], 16) / 255 for i in (0, 2, 4)]
    rgb = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in rgb]
    bsdf = m.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*rgb, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    m.diffuse_color = (*rgb, 1)
    MATERIALS.append(m)
    return len(MATERIALS) - 1


class Mesh:
    def __init__(self):
        self.vertices, self.faces, self.slots, self.smooth = [], [], [], []

    def add(self, vertices, faces, mat, smooth=False):
        offset = len(self.vertices)
        self.vertices.extend([tuple(v) for v in vertices])
        self.faces.extend([tuple(offset + i for i in f) for f in faces])
        self.slots.extend([mat] * len(faces))
        self.smooth.extend([smooth] * len(faces))

    def box(self, center, size, mat, rotation=None):
        center = Vector(center)
        v = [Vector((x*size[0]/2, y*size[1]/2, z*size[2]/2))
             for z in (-1, 1) for y in (-1, 1) for x in (-1, 1)]
        if rotation is not None:
            v = [rotation @ p for p in v]
        self.add([p + center for p in v], [(0,2,3,1),(4,5,7,6),(0,1,5,4),
                 (2,6,7,3),(0,4,6,2),(1,3,7,5)], mat)

    def beam(self, a, b, width, mat, depth=None):
        a, b = Vector(a), Vector(b)
        self.box((a+b)/2, (width, depth or width, (b-a).length), mat,
                 (b-a).to_track_quat('Z', 'Y').to_matrix())

    def cylinder(self, a, b, radius, mat, sides=24, radius_top=None):
        a, b = Vector(a), Vector(b)
        r2 = radius if radius_top is None else radius_top
        rotation = (b-a).to_track_quat('Z', 'Y').to_matrix()
        vertices = [p + rotation @ Vector((r*math.cos(i*math.tau/sides),
                    r*math.sin(i*math.tau/sides), 0))
                    for p,r in ((a,radius),(b,r2)) for i in range(sides)]
        self.add(vertices, [(i,(i+1)%sides,(i+1)%sides+sides,i+sides)
                            for i in range(sides)], mat, True)
        self.add(vertices, [tuple(reversed(range(sides))),tuple(range(sides,2*sides))], mat)

    def object(self, name, collection):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(self.vertices, [], self.faces)
        mesh.update()
        for mat in MATERIALS:
            mesh.materials.append(mat)
        for p, mat, smooth in zip(mesh.polygons, self.slots, self.smooth):
            p.material_index, p.use_smooth = mat, smooth
        uv = mesh.uv_layers.new(name='MetricUV')
        for face in mesh.polygons:
            axis = max(range(3), key=lambda i: abs(face.normal[i]))
            axes = [(1,2),(0,2),(0,1)][axis]
            for li in face.loop_indices:
                v = mesh.vertices[mesh.loops[li].vertex_index].co
                uv.data[li].uv = (v[axes[0]] / 3, v[axes[1]] / 3)
        obj = bpy.data.objects.new(name, mesh)
        collection.objects.link(obj)
        return obj


def facade(b, origin, angle, length, floors, bays, wall, floor_height=3.3, opening=.65):
    """An actual wall with recessed openings, not windows pasted onto a solid box."""
    rotation = Matrix.Rotation(angle, 3, 'Z')
    origin = Vector(origin)
    def box(p, size, mat):
        b.box(origin + rotation @ Vector(p), size, mat, rotation)
    pitch = length / bays
    window_width = pitch * opening
    pier = pitch - window_width
    for floor in range(floors):
        z = floor * floor_height
        box((0, .24, z+.48), (length, .48, .96), wall)
        box((0, .24, z+floor_height-.18), (length, .48, .36), wall)
        # Continuous stone sill; its shadow establishes real facade depth.
        box((0, .03, z+.98), (length+.08, .65, .12), STONE)
        for i in range(bays+1):
            x = -length/2 + i*pitch
            w = pier if 0 < i < bays else pier/2
            x += pier/4 if i == 0 else -pier/4 if i == bays else 0
            box((x, .24, z+(floor_height+.60)/2), (w, .48, floor_height-1.32), wall)
        for i in range(bays):
            x = -length/2 + (i+.5)*pitch
            z0, z1 = z+1.06, z+floor_height-.39
            # Dark frame behind the wall reveal and an inset glass pane.
            for width, yy, low, high, mat in [(window_width,.40,z0,z1,FRAME),
                                            (window_width-.14,.345,z0+.06,z1-.06,GLASS)]:
                vertices=[(x-width/2,yy,low),(x+width/2,yy,low),
                          (x+width/2,yy,high),(x-width/2,yy,high)]
                b.add([origin+rotation@Vector(p) for p in vertices],[(0,1,2,3)],mat)
            box((x, .30, (z0+z1)/2), (.09, .11, z1-z0), FRAME)


def ring_box(b, x, y, width, depth, z, thickness, height, mat):
    for yy in (-depth/2,depth/2):
        b.box((x,y+yy,z+height/2),(width+thickness,thickness,height),mat)
    for xx in (-width/2,width/2):
        b.box((x+xx,y,z+height/2),(thickness,depth,height),mat)


def gable(b, x, y, width, depth, eaves, rise):
    for side in (-1,1):
        vertices = [(x,y-depth/2-.45,eaves+rise),(x+side*(width/2+.45),y-depth/2-.45,eaves),
                    (x+side*(width/2+.45),y+depth/2+.45,eaves),(x,y+depth/2+.45,eaves+rise)]
        # Top and underside have explicit orientation; no double-sided material.
        if side < 0:
            vertices.reverse()
        b.add(vertices,[(0,1,2,3)],ZINC)
    for side in (-1,1):
        yy = y+side*depth/2
        vertices = [(x-width/2,yy,eaves),(x+width/2,yy,eaves),(x,yy,eaves+rise)]
        if side > 0:
            vertices.reverse()
        b.add(vertices,[(0,1,2)],PLASTER)
        for sx in (-1,1):
            b.beam((x,yy+side*.46,eaves+rise),(x+sx*(width/2+.46),yy+side*.46,eaves),.18,ZINC)
    b.beam((x,y-depth/2-.45,eaves+rise),(x,y+depth/2+.45,eaves+rise),.18,ZINC)
    for sx in (-1,1):
        b.box((x+sx*(width/2+.28),y,eaves-.08),(.40,depth+.95,.24),ZINC)


def residence():
    b = Mesh()
    # Offset two differently proportioned gabled volumes rather than a rectangular slab.
    for x,y,w,d,f in [(4,2,27,16,4),(-13,-1,10,23,3)]:
        h=f*3.3
        b.box((x,y,.25),(w+.6,d+.6,.5),STONE)
        facade(b,(x,y-d/2,.5),0,w,f,max(2,round(w/4.8)),PLASTER)
        facade(b,(x,y+d/2,.5),math.pi,w,f,max(2,round(w/4.8)),BRICK)
        facade(b,(x-w/2,y,.5),-math.pi/2,d,f,max(2,round(d/4.8)),PLASTER)
        facade(b,(x+w/2,y,.5),math.pi/2,d,f,max(2,round(d/4.8)),PLASTER)
        b.box((x,y,h+.43),(w,d,.18),STONE)
        gable(b,x,y,w,d,h+.5,3.4 if f==4 else 3.0)
    # Deep, recessed loggias: solid parapets and broad dividing walls, not rail pickets.
    for floor in range(1,4):
        z=.5+floor*3.3
        b.box((4,-7.4,z),(18,3.0,.24),STONE)
        b.box((4,-8.82,z+.65),(18,.20,1.1),WARM)
        for xx in (-5,4,13):
            b.box((xx,-7.4,z+1.65),(.32,3.0,3.3),PLASTER)
    b.box((4,-7.4,13.72),(18.4,3.3,.26),ZINC)
    # Entrance is architectural, with a real sheltered threshold.
    b.box((-4,-6.6,1.65),(2.4,.18,2.9),FRAME)
    b.box((-4,-6.72,1.7),(2.0,.04,2.55),GLASS)
    b.box((-4,-7.15,3.22),(3.6,2.2,.20),ZINC)
    return b


def courtyard():
    b=Mesh()
    # Open central courtyard; two taller rear wings and a low front entrance wing.
    wings=[(0,20,62,12,6),(0,-20,62,12,3),(-25,0,12,28,5),(25,0,12,28,5)]
    for x,y,w,d,f in wings:
        h=f*3.5+.35
        b.box((x,y,.175),(w,d,.35),STONE)
        # Facades on all sides also articulate the actual open courtyard.
        for yy,a,mat in [(y-d/2,0,BRICK if y>0 else PLASTER),(y+d/2,math.pi,PLASTER)]:
            facade(b,(x,yy,.35),a,w,f,max(2,round(w/5.6)),mat,3.5,.72)
        for xx,a in [(x-w/2,-math.pi/2),(x+w/2,math.pi/2)]:
            facade(b,(xx,y,.35),a,d,f,max(2,round(d/5.6)),PLASTER,3.5,.62)
        b.box((x,y,h),(w,d,.30),ZINC)
        ring_box(b,x,y,w,d,h,.28,.90,PLASTER)
        b.box((x,y,h+.12),(w-1.0,d-1.0,.10),GRAVEL)
    # A deep framed entrance emphasizes scale without an explorable interior.
    # No cars, signs, furniture or ornamental trees.
    b.box((0,-26.12,2.75),(11.5,.15,5.4),FRAME)
    b.box((0,-26.24,2.75),(10.4,.03,4.7),GLASS)
    for xx in (-6.0,6.0):
        b.box((xx,-27,3.2),(.65,2.4,6.4),STONE)
    b.box((0,-27,6.4),(12.65,2.4,.55),STONE)
    # Setback rear penthouse and a broad shaded loggia form the skyline.
    b.box((0,20,22.7),(31,8,3.4),WARM)
    facade(b,(0,16,21.3),0,31,1,7,FRAME,3.4,.84)
    b.box((0,20,24.5),(32,9,.35),ZINC)
    for floor in range(1,6):
        z=.35+floor*3.5
        b.box((0,12.6,z),(38,3.2,.25),STONE)
        b.box((0,11.08,z+.67),(38,.20,1.12),WARM)
    for xx in (-19,-9.5,0,9.5,19):
        b.box((xx,12.6,10.8),(.38,3.2,21),PLASTER)
    return b


def shed():
    b=Mesh()
    w,d=42,60
    b.box((0,0,.30),(w+.8,d+.8,.60),STONE)
    # Long elevation: masonry plinth, broad structural bays, clerestory strip.
    for side in (-1,1):
        x=side*w/2
        b.box((x,0,3.8),(.45,d,7),BRICK)
        b.box((x,0,9.9),(.50,d,1.2),WARM)
        b.box((x-side*.12,0,8.55),(.10,d,1.6),GLASS)
        for yy in range(-30,31,10):
            b.box((x+side*.12,yy,5.35),(.68,.55,10.1),STONE)
        for yy in range(-30,31,5):
            b.box((x,yy,8.55),(.50,.12,1.7),FRAME)
    # Four loading doors contained in the architecture, no loading-bay props.
    for y in (-30,30):
        b.box((0,y,9.05),(w,.6,2.9),WARM)
        for x in (-21,-10.5,0,10.5,21):
            b.box((x,y,4.1),(.7,.75,7.6),STONE)
        for x in (-15.75,-5.25,5.25,15.75):
            b.box((x,y,3.55),(8.9,.18,6.5),ZINC)
            b.box((x,y+(-.12 if y<0 else .12),5.4),(7.9,.10,1.0),GLASS)
            for z in (1.1,2.3,3.5,4.7,6.2):
                b.box((x,y+(-.11 if y<0 else .11),z),(8.85,.04,.045),STEEL)
    # Six genuine sawtooth roofs: roof and vertical northlight are separate surfaces.
    for i in range(6):
        y=-30+i*10
        b.add([(-21.45,y-.15,10.55),(21.45,y-.15,10.55),(21.45,y+9.8,14),(-21.45,y+9.8,14)],[(0,1,2,3)],ZINC)
        b.box((0,y+9.8,12.27),(42.8,.12,3.45),GLASS)
        for side in (-1,1):
            x=side*21
            v=[(x,y,10.5),(x,y+10,10.5),(x,y+10,14)]
            if side<0:v.reverse()
            b.add(v,[(0,1,2)],WARM)
        b.box((0,y+9.82,14),(43,.3,.22),STEEL)
        for x in range(-21,22,7):
            b.box((x,y+9.87,12.25),(.14,.2,3.5),STEEL)
    return b


def tower():
    b=Mesh()
    # Low operations base and split-height annex.
    b.box((0,2,.25),(37,26,.5),STONE)
    for x,y,w,d,h in [(0,2,34,23,7.5),(-16,5,12,17,4.0)]:
        b.box((x,y,h/2),(w,d,h),PLASTER)
        for side in (-1,1):
            b.box((x,y+side*(d/2+.03),h*.60),(w-.9,.12,h*.45),GLASS)
            for xx in range(-int(w/2)+2,int(w/2),4):
                b.box((x+xx,y+side*(d/2+.12),h*.60),(.16,.18,h*.46),FRAME)
        b.box((x,y,h),(w+1.0,d+1.0,.45),ZINC)
    b.box((0,-12.7,5.15),(18,5,.50),ZINC)
    for x in (-8.5,8.5):b.box((x,-14,2.5),(.45,.45,5),STONE)
    # A tapered shaft with twelve deliberate planes; flat normals preserve silhouette.
    def frustum(z0,z1,r0,r1,mat,n=12):
        v=[(r*math.cos((i+.5)*math.tau/n),r*math.sin((i+.5)*math.tau/n),z)
           for z,r in ((z0,r0),(z1,r1)) for i in range(n)]
        b.add(v,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]+
                 [tuple(reversed(range(n))),tuple(range(n,2*n))],mat)
    frustum(7.5,55.5,6.3,4.3,PLASTER)
    # Three broad vertical dark reveals, not rows of punched square windows.
    for a in (-math.pi/2,math.pi/6,5*math.pi/6):
        r0,r1=6.0,4.15
        b.beam((r0*math.cos(a),r0*math.sin(a),9),
               (r1*math.cos(a),r1*math.sin(a),54),.72,FRAME,.16)
    frustum(54.5,60,4.3,10.8,STONE)
    frustum(60,61.2,11.6,11.6,ZINC)
    frustum(61.2,67.6,10.35,12.0,GLASS)
    for i in range(12):
        a=(i+.5)*math.tau/12
        b.beam((10.36*math.cos(a),10.36*math.sin(a),61.15),
               (12.01*math.cos(a),12.01*math.sin(a),67.7),.23,FRAME,.28)
    frustum(67.6,68.1,12.65,12.65,FRAME)
    frustum(68.1,69.3,12.9,11.5,ZINC)
    frustum(69.3,70.0,11.5,10.2,PLASTER)
    # Recessed rooftop, no antenna forest or tiny service equipment.
    frustum(70,70.05,9.9,9.9,GRAVEL)
    return b


def dish(tilt_degrees=35):
    b=Mesh()
    # Heavy civil foundation, rotating pedestal and open structural yoke.
    b.cylinder((0,0,0),(0,0,1.4),12,STONE,48)
    b.cylinder((0,0,1.4),(0,0,16),7.5,PLASTER,24,5.2)
    b.cylinder((0,0,16),(0,0,18),6.4,ZINC,48)
    for side in (-1,1):
        for yy in (-4,4):
            b.beam((side*4,yy,17),(side*11,4,30),1.25,STEEL,1.55)
        b.box((side*11,4,28),(2.6,5.0,7),WARM)
        b.cylinder((side*9.5,4,30),(side*13,4,30),2.5,ZINC,32)
    b.beam((-11,4,25),(11,4,25),1.5,STEEL,2.1)
    rotation=Matrix.Rotation(math.radians(tilt_degrees),3,'X')
    center=Vector((0,0,36))
    def p(x,y,z):return center+rotation@Vector((x,y,z))
    radius,focal,segments,rings=35,28,96,14
    def sag(r):return r*r/(4*focal)
    for side in (-1,1):
        b.beam((side*11,4,30),p(side*12,0,sag(12)-1.35),1.1,STEEL,1.3)
    # One center fan, then concentric quads: no missing central disk or zero-area ring.
    for back in (False,True):
        offset=-.42 if back else 0
        v=[p(0,0,offset)]
        for j in range(1,rings+1):
            r=radius*j/rings
            v += [p(r*math.cos(i*math.tau/segments),r*math.sin(i*math.tau/segments),sag(r)+offset) for i in range(segments)]
        faces=[(0,1+i,1+(i+1)%segments) for i in range(segments)]
        for j in range(rings-1):
            a=1+j*segments;c=a+segments
            faces += [(a+i,c+i,c+(i+1)%segments,a+(i+1)%segments) for i in range(segments)]
        if back:faces=[tuple(reversed(f)) for f in faces]
        b.add(v,faces,WARM if back else REFLECTOR,True)
    # Explicit rim thickness and major underside rings/ribs; no tiny wirework.
    def torus(r,z,tube,mat,steps=96):
        v=[]
        for i in range(steps):
            a=i*math.tau/steps
            for j in range(6):
                c=j*math.tau/6
                v.append(p((r+tube*math.cos(c))*math.cos(a),(r+tube*math.cos(c))*math.sin(a),z+tube*math.sin(c)))
        b.add(v,[(i*6+j,((i+1)%steps)*6+j,((i+1)%steps)*6+(j+1)%6,i*6+(j+1)%6)
                 for i in range(steps) for j in range(6)],mat,True)
    torus(35,sag(35)-.21,.34,REFLECTOR)
    for r in (12,24,33):torus(r,sag(r)-1.3,.35,STEEL,48)
    for i in range(16):
        a=i*math.tau/16
        for r0,r1 in ((3,12),(12,24),(24,34.8)):
            b.beam(p(r0*math.cos(a),r0*math.sin(a),sag(r0)-1.35),
                   p(r1*math.cos(a),r1*math.sin(a),sag(r1)-1.35),.52,STEEL,.7)
    # Three substantial feed supports converge at the actual focal point.
    for i in range(3):
        a=i*math.tau/3+math.pi/2
        b.beam(p(30*math.cos(a),30*math.sin(a),sag(30)),p(0,0,focal),.6,STEEL,.85)
    b.cylinder(p(0,0,focal-1.5),p(0,0,focal+1.4),1.15,ZINC,24,.75)
    return b


def apartment_block(b, x, y, width, depth, z, floors, wall):
    height = floors * 3.5
    for yy, angle in ((y-depth/2, 0), (y+depth/2, math.pi)):
        facade(b, (x, yy, z), angle, width, floors, max(2, round(width/5.5)), wall, 3.5)
    for xx, angle in ((x-width/2, -math.pi/2), (x+width/2, math.pi/2)):
        facade(b, (xx, y, z), angle, depth, floors, max(2, round(depth/5.5)), wall, 3.5)
    b.box((x,y,z+height), (width,depth,.3), ZINC)
    ring_box(b,x,y,width,depth,z+height,.3,.85,wall)


def residence_l():
    b=Mesh()
    for x,y,w,d,f in [(-16,0,17,48,8),(10,-15.5,35,17,5)]:
        b.box((x,y,.25),(w+.7,d+.7,.5),STONE)
        apartment_block(b,x,y,w,d,.5,f,BRICK if f==8 else PLASTER)
    # The inside of the L is a deep gallery, not another solid rectangular block.
    for floor in range(1,6):
        z=.5+floor*3.5
        b.box((9,-5.4,z),(34,3.2,.25),STONE)
        b.box((9,-3.85,z+.65),(34,.22,1.1),WARM)
    for x in (-7,1,9,17,25):
        b.box((x,-5.4,9.25),(.45,3.2,17.5),PLASTER)
    b.box((-16,0,30.1),(10,18,3.2),WARM)
    b.box((-16,0,31.85),(11,19,.3),ZINC)
    b.box((-5,-25.5,3.8),(15,6,.4),ZINC)
    return b


def curtain_block(b,x,y,w,d,z,height,floor_height=3.6):
    b.box((x,y,z+height/2),(w,d,height),GLASS)
    for level in range(int(height/floor_height)+1):
        ring_box(b,x,y,w+.15,d+.15,z+level*floor_height,.24,.24,FRAME)
    for xx in (-w/2,w/2):
        for yy in (-d/2,d/2):
            b.box((x+xx,y+yy,z+height/2),(.65,.65,height),STONE)
    b.box((x,y,z+height),(w+.8,d+.8,.45),ZINC)


def residence_terraced():
    b=Mesh()
    b.box((0,0,.3),(57,44,.6),STONE)
    z=.6
    # Four unequal setbacks climb to 106 m, with genuinely usable roof terraces.
    for tier,(w,d,floors) in enumerate([(54,40,9),(42,34,8),(30,28,7),(18,22,6)]):
        x,y=tier*6,tier*3
        h=floors*3.5
        curtain_block(b,x,y,w-1,d-1,z,h,3.5)
        for level in range(floors+1):
            zz=z+level*3.5
            b.box((x,y,zz),(w+1,d+1,.26),PLASTER)
            b.box((x,y-d/2,zz+.63),(w,.22,1.0),WARM)
            for xx in (x-w/2,x+w/2):
                b.box((xx,y,zz+.63),(.22,d,1.0),PLASTER)
        # Deep vertical fins split the balconies into broad recessed bays.
        for xx in range(-int(w/2),int(w/2)+1,6):
            b.box((x+xx,y-d/2+.6,z+h/2),(.28,1.5,h),PLASTER)
        ring_box(b,x,y,w,d,z+h,.3,1.05,PLASTER)
        z+=h
    b.box((18,9,z+.25),(19,23,.5),ZINC)
    return b


def offices_twins():
    b=Mesh()
    b.box((0,0,.3),(68,48,.6),STONE)
    curtain_block(b,0,0,64,42,.6,8,4)
    # Unequal towers separated by an open slot, bridged well above the podium.
    for x,y,h,w in [(-21,3,103,23),(20,-3,78,24)]:
        curtain_block(b,x,y,w,28,8.6,h)
        for xx in (x-w/2,x+w/2):
            b.box((xx,y,8.6+h/2),(1.3,29,h),PLASTER)
        for yy in (-11,11):
            b.box((x,y+yy,8.6+h/2),(w+1,.65,h),WARM)
        # Blade crowns extend beyond the flat curtain wall roof.
        b.box((x-w/2,y,8.6+h+2),(1.3,29,4),PLASTER)
        b.box((x+w/2,y,8.6+h+2),(1.3,29,4),PLASTER)
    curtain_block(b,0,0,30,12,65,8,4)
    b.box((0,0,64.6),(31,13,.8),STONE)
    for yy in (-6.1,6.1):
        b.beam((-14,yy,65),(14,yy,73),.65,STEEL)
        b.beam((-14,yy,73),(14,yy,65),.65,STEEL)
    return b


def loft(b, lower, upper, mat):
    n=len(lower)
    b.add(lower+upper,[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]+
          [tuple(reversed(range(n))),tuple(range(n,2*n))],mat)


def office_spire():
    b=Mesh()
    b.box((0,0,.3),(61,48,.6),STONE)
    curtain_block(b,0,0,56,42,.6,8,4)
    outline=[(-16,-16),(13,-16),(22,-7),(22,8),(13,17),(-16,17),(-22,11),(-22,-10)]
    def p(i,z,push=0):
        x,y=outline[i]
        scale=1-.17*(z-8.6)/110+push
        return (x*scale+7*(z-8.6)/110,y*scale,z)
    top=[p(i,119+outline[i][0]*.5+outline[i][1]*.12) for i in range(8)]
    loft(b,[p(i,8.6) for i in range(8)],top,GLASS)
    # Chamfered, leaning envelope with a diagonal crown, not a box plus antenna.
    for z in range(12,107,4):
        loft(b,[p(i,z,.005) for i in range(8)],[p(i,z+.24,.005) for i in range(8)],FRAME)
    for i in range(8):
        b.beam(p(i,8.6,.008),top[i],.65,STONE)
        b.beam(top[i],top[(i+1)%8],.95,WARM)
    for a,c in [(0,1),(3,4),(5,6)]:
        for z in (9,33,57,81):
            b.beam(p(a,z,.018),p(c,z+24,.018),.85,WARM)
            b.beam(p(c,z,.018),p(a,z+24,.018),.85,WARM)
    loft(b,[(x,y,z+.1) for x,y,z in top],[(x,y,z+.7) for x,y,z in top],ZINC)
    # Lower offset blade gives the silhouette an asymmetric shoulder.
    curtain_block(b,-23,8,13,24,8.6,48)
    return b


def research():
    b=Mesh()
    b.box((0,0,.3),(73,54,.6),STONE)
    for x,y,w,d,z,f in [(0,0,66,46,.6,3),(-6,5,54,34,11.1,3),(-12,10,42,22,21.6,3)]:
        apartment_block(b,x,y,w,d,z,f,PLASTER)
        # Cantilever floor plates and thick end-wall cheeks establish each step.
        b.box((x,y,z),(w+2,d+2,.7),STONE)
        for xx in (x-w/2,x+w/2):
            b.box((xx,y,z+5.25),(1.1,d,10.5),WARM)
    curtain_block(b,-12,10,24,12,32.1,5,5)
    b.box((0,-26,5.5),(37,12,.6),ZINC)
    for x in (-17,17):b.box((x,-30,2.75),(.8,.8,5.5),STONE)
    return b


def civic():
    b=Mesh()
    b.box((0,0,.4),(76,58,.8),STONE)
    curtain_block(b,0,1,54,36,.8,13,4.3)
    # A civic hall's folded copper canopy projects 9 m beyond its glazed lobby.
    # Two sloping solid roof plates meet at an off-centre ridge.
    for xa,xb,za,zb in [(-36,4,18,29),(4,36,29,21)]:
        upper=[(xa,-27,za),(xb,-27,zb),(xb,27,zb),(xa,27,za)]
        loft(b,[(x,y,z-.75) for x,y,z in upper],upper,WARM)
    for y in (-17.1,19.1):
        v=[(-27,y,13.8),(27,y,13.8),(27,y,22.5),(4,y,28.25),(-27,y,19.73)]
        if y>0:v.reverse()
        b.add(v,[tuple(range(5))],GLASS)
    for x,top in [(-27,19.725),(27,22.5)]:
        v=[(x,-17.1,13.8),(x,19.1,13.8),(x,19.1,top),(x,-17.1,top)]
        if x<0:v.reverse()
        b.add(v,[(0,1,2,3)],GLASS)
    for x,y,top in [(-29,-21,19.2),(-29,21,19.2),(29,-21,22),(29,21,22)]:
        b.box((x,y,top/2),(1.4,1.4,top),STONE)
    # Broad load-bearing masonry wall and a clearly recessed public entrance.
    b.box((-21,3,8.4),(11,33,15.2),PLASTER)
    b.box((9,-17.4,4),(19,.4,6.4),FRAME)
    b.box((9,-20,7.3),(24,8,.5),ZINC)
    return b


def depot():
    b=Mesh()
    b.box((0,0,.3),(76,56,.6),STONE)
    profile=[(-36+72*i/16,9+12*math.sin(math.pi*i/16)) for i in range(17)]
    for i in range(16):
        x0,z0=profile[i];x1,z1=profile[i+1]
        b.add([(x0,-27,z0),(x1,-27,z1),(x1,27,z1),(x0,27,z0)],[(0,1,2,3)],ZINC)
    for y in (-26,26):
        vertices=[(x,y,z) for x,z in profile]
        if y<0:vertices.reverse()
        b.add(vertices,[tuple(range(len(vertices)))],GLASS)
        for x in (-36,-18,0,18,36):
            b.box((x,y,4.8),(.9,1,8.4),STONE)
        for x in (-27,-9,9,27):
            b.box((x,y,4.65),(16,.22,8.1),WARM)
            b.box((x,y+(-.15 if y<0 else .15),6.4),(14,.10,1.5),GLASS)
        b.box((0,y,8.8),(73,1,.6),STONE)
    for x in (-36,36):
        b.box((x,0,4.8),(.6,52,8.4),BRICK)
    for y in (-26,-17.33,-8.67,0,8.67,17.33,26):
        for i in range(16):
            x0,z0=profile[i];x1,z1=profile[i+1]
            b.beam((x0,y,z0+.12),(x1,y,z1+.12),.35,STEEL,.42)
        for x in (-36,36):b.box((x,y,4.8),(.9,.65,8.4),STONE)
    return b


def build(export_names=None):
    global PLASTER,STONE,BRICK,ZINC,GLASS,FRAME,WARM,STEEL,GRAVEL,REFLECTOR
    previous=bpy.context.window.scene
    if bpy.data.scenes.get(SCENE_NAME):
        old=bpy.data.scenes[SCENE_NAME]
        if previous == old:
            previous = None
        for obj in list(old.objects):bpy.data.objects.remove(obj,do_unlink=True)
        bpy.data.scenes.remove(old)
    scene=bpy.data.scenes.new(SCENE_NAME)
    bpy.context.window.scene=scene
    scene.unit_settings.system='METRIC'
    MATERIALS.clear()
    PLASTER=material('limestone_plaster','d3cec0',.83)
    STONE=material('cut_concrete','a8a89f',.83)
    BRICK=material('warm_brick','b5a195',.84)
    ZINC=material('zinc_roof','424d51',.43,.55)
    GLASS=material('blue_green_glazing','637e86',.16,.5)
    FRAME=material('graphite_frames','252e30',.43,.5)
    WARM=material('bronze_cladding','9b8770',.55,.3)
    STEEL=material('structural_steel','647175',.42,.65)
    GRAVEL=material('roof_gravel','69675e',.95)
    REFLECTOR=material('reflector_enamel','e1e1d7',.38,.18)
    image=bpy.data.images.load(str(BASE/'assets/environment/airport/textures/polyhaven/brick_wall_006_Diffuse.jpg'),check_existing=False)
    image.name='library_brick_1k'
    image.scale(1024,1024)
    image.pack()
    node=MATERIALS[BRICK].node_tree.nodes.new('ShaderNodeTexImage');node.image=image
    MATERIALS[BRICK].node_tree.links.new(node.outputs['Color'],MATERIALS[BRICK].node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    metrics={}
    placements={'residence_gabled':(-180,-110,0),'residence_courtyard':(0,-110,0),
                'industrial_shed':(180,-110,0),'control_tower':(-180,120,0),
                'satellite_dish_70m':(0,120,0),
                'residence_l':(-400,-110,0),'residence_terraced':(-400,120,0),
                'offices_twins':(-240,360,0),'office_spire':(0,360,0),
                'research_center':(400,120,0),'civic_canopy':(400,-110,0),
                'warehouse_vault':(240,360,0)}
    try:
        for name,constructor in [('residence_gabled',residence),('residence_courtyard',courtyard),
                                 ('industrial_shed',shed),('control_tower',tower),('satellite_dish_70m',dish),
                                 ('residence_l',residence_l),('residence_terraced',residence_terraced),
                                 ('offices_twins',offices_twins),('office_spire',office_spire),
                                 ('research_center',research),('civic_canopy',civic),('warehouse_vault',depot)]:
            obj=constructor().object(name,scene.collection)
            obj.data.calc_loop_triangles()
            # Reject degenerate topology and non-finite vertices before exporting.
            assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co)
            assert all(t.area>1e-7 for t in obj.data.loop_triangles),name+' has degenerate triangles'
            minimum=[min(v.co[i] for v in obj.data.vertices) for i in range(3)]
            maximum=[max(v.co[i] for v in obj.data.vertices) for i in range(3)]
            metrics[name]={'triangles':len(obj.data.loop_triangles),'dimensions_blender':[maximum[i]-minimum[i] for i in range(3)],'min_z':minimum[2]}
            assert len(obj.data.loop_triangles)<22000,name+' exceeds sample budget'
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True);bpy.context.view_layer.objects.active=obj
            if export_names is None or name in export_names:
                bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,
                                          export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
            # GLBs stay origin-local; the editable Blender source is laid out separately.
            obj.location=placements[name]
        bpy.data.libraries.write(str(SOURCE/'airport_asset_library.blend'),{scene},path_remap='RELATIVE',compress=True)
        (OUT/'metrics.json').write_text(json.dumps(metrics,indent=2)+'\n',encoding='utf-8')
        print('PASS: LIBRARY AUTHORING',json.dumps(metrics))
    finally:
        bpy.context.window.scene=previous if previous is not None else scene
    return metrics


if __name__=='__main__':
    build()
