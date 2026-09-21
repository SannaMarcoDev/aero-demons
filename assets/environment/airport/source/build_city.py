"""Authored Garda airport city. Execute stages through Blender MCP in this namespace.
Uses the existing airport.blend, Poly Haven maps, and the read-only site survey.
Blender Z up; site coordinates are (east, Godot-Z) relative to the airport.
Never modifies Terrain3D files. Re-running replaces only our city_* collection.
"""
import bpy, bmesh, math, json, os, random, hashlib
import numpy as np
from mathutils import Vector, Matrix
from pathlib import Path
BASE = Path(bpy.data.filepath).resolve().parents[4]
OUT = BASE / 'assets/environment/airport'
SITE = json.loads((BASE/'subagent-artifacts/city-revision/survey/site.json').read_text())
TEX = OUT/'textures/polyhaven'
HEIGHT = np.array(SITE['heights']).reshape(SITE['size'][1], SITE['size'][0])
ORIGIN = SITE['origin']
scene = bpy.data.scenes['airport_authoring']
bpy.context.window.scene = scene
rng = random.Random(7319)
# Generated collection only; the original airport remains independently editable.
if bpy.data.collections.get('city_authored'):
    for obj in list(bpy.data.collections['city_authored'].all_objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.collections.remove(bpy.data.collections['city_authored'])
collection = bpy.data.collections.new('city_authored')
scene.collection.children.link(collection)
root = bpy.data.objects.new('city_root', None)
collection.objects.link(root)
manifest = {'origin': ORIGIN, 'water': SITE['water'], 'blocks': [], 'roads': [], 'landmarks': [], 'exclusions': [], 'trees': []}


def height(x, z):
    u = (x-SITE['first'][0])/SITE['spacing']; v = (z-SITE['first'][1])/SITE['spacing']
    i, j = math.floor(u), math.floor(v)
    assert 0 <= i < HEIGHT.shape[1]-1 and 0 <= j < HEIGHT.shape[0]-1, (x,z)
    a, b = u-i, v-j
    # Match Terrain3D's two planar triangles, not bilinear interpolation across a saddle.
    if a >= b: value=(1-a)*HEIGHT[j,i]+(a-b)*HEIGHT[j,i+1]+b*HEIGHT[j+1,i+1]
    else: value=(1-b)*HEIGHT[j,i]+(b-a)*HEIGHT[j+1,i]+a*HEIGHT[j+1,i+1]
    return float(value)-ORIGIN[1]


def material(name, source, tint=(1,1,1), roughness=None, metallic=None):
    old = bpy.data.materials.get(name)
    if old: bpy.data.materials.remove(old)
    m = bpy.data.materials[source].copy(); m.name = name
    p = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    for key, value in [('Roughness',roughness),('Metallic',metallic)]:
        if value is not None:
            for link in list(p.inputs[key].links): m.node_tree.links.remove(link)
            p.inputs[key].default_value = value
    for link in p.inputs['Base Color'].links:
        if link.from_node.type == 'TEX_IMAGE':
            src = link.from_node.image
            data = np.empty(len(src.pixels),np.float32); src.pixels.foreach_get(data)
            data = data.reshape(-1,4); data[:,:3] *= np.array(tint)
            im = bpy.data.images.new(name+'_albedo',width=src.size[0],height=src.size[1])
            im.pixels.foreach_set(np.clip(data,0,1).ravel()); im.file_format = 'JPEG'
            im.filepath_raw = str(TEX/(name+'_albedo.jpg')); im.save(quality=93)
            link.from_node.image = im
    return m


def brick_material():
    for old in list(bpy.data.materials):
        if old.name.startswith('city_warm_brick'):bpy.data.materials.remove(old)
    m = bpy.data.materials.new('city_warm_brick'); m.use_nodes=True; m['tile_metres']=3.0
    p=m.node_tree.nodes.get('Principled BSDF')
    for suffix, socket in [('Diffuse','Base Color'),('Rough','Roughness')]:
        n=m.node_tree.nodes.new('ShaderNodeTexImage'); n.image=bpy.data.images.load(str(TEX/('brick_wall_006_'+suffix+'.jpg')),check_existing=True)
        if suffix=='Rough': n.image.colorspace_settings.name='Non-Color'
        m.node_tree.links.new(n.outputs['Color'],p.inputs[socket])
    n=m.node_tree.nodes.new('ShaderNodeTexImage'); n.image=bpy.data.images.load(str(TEX/'brick_wall_006_nor_gl.jpg'),check_existing=True); n.image.colorspace_settings.name='Non-Color'
    norm=m.node_tree.nodes.new('ShaderNodeNormalMap'); norm.inputs['Strength'].default_value=.35
    m.node_tree.links.new(n.outputs['Color'],norm.inputs['Color']);m.node_tree.links.new(norm.outputs['Normal'],p.inputs['Normal'])
    return m


wall = material('city_limestone','ph_cast_concrete',(.84,.78,.65))
white = material('city_chalk','ph_cast_concrete',(1.04,1.01,.92))
brick = brick_material()
roof = material('city_zinc','ph_corrugated_roof',(.38,.42,.44),.68,.28)
steel = bpy.data.materials['ph_structural_steel']
concrete = material('city_paving','ph_airfield_concrete',(.85,.84,.80))
asphalt_source=bpy.data.materials['ph_airfield_asphalt']
asphalt_shader=next(n for n in asphalt_source.node_tree.nodes if n.type=='BSDF_PRINCIPLED')
asphalt_image=asphalt_shader.inputs['Base Color'].links[0].from_node
asphalt_image.image=bpy.data.images.load(str(TEX/'asphalt_floor_Diffuse.jpg'),check_existing=True)
asphalt = material('city_road_asphalt','ph_airfield_asphalt',(.29,.33,.38))
asphalt_image.image=next(n for n in asphalt.node_tree.nodes if n.type=='BSDF_PRINCIPLED').inputs['Base Color'].links[0].from_node.image
glass = material('city_blue_glass','ph_industrial_glass',(.55,.65,.72),.25,.36)
glass2 = material('city_warm_glass','ph_industrial_glass',(1.05,.88,.68),.32,.28)
trim = material('city_terracotta','ph_cast_concrete',(.72,.35,.20))
paint = bpy.data.materials['ph_offwhite_coating']
yellow = bpy.data.materials['ph_safety_yellow']
black = bpy.data.materials['ph_rubber_gasket']
# A darker actual asphalt runway, not a gray concrete strip. Geometry and all markers unchanged.
bpy.data.objects['runway_surface'].data.materials[0] = bpy.data.materials['ph_airfield_asphalt']


class Batch:
    def __init__(self): self.v=[];self.f=[];self.mi=[];self.materials=[];self.uv=[]
    def add(self, verts, faces, mat):
        k=len(self.v);self.v.extend([tuple(v) for v in verts])
        if mat not in self.materials:self.materials.append(mat)
        self.f.extend([tuple(k+i for i in face) for face in faces]);self.mi.extend([self.materials.index(mat)]*len(faces))
    def box(self,c,s,mat,rotation=None):
        a,b,h=[v/2 for v in s]
        verts=[(-a,-b,-h),(a,-b,-h),(a,b,-h),(-a,b,-h),(-a,-b,h),(a,-b,h),(a,b,h),(-a,b,h)]
        self.add([(rotation@Vector(v) if rotation else Vector(v))+Vector(c) for v in verts],[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],mat)
    def beam(self,a,b,w,mat,depth=None):
        delta=Vector(b)-Vector(a)
        if delta.length<.001:return
        self.box((Vector(a)+Vector(b))/2,(w,depth or w,delta.length),mat,delta.to_track_quat('Z','Y').to_matrix())
    def cylinder(self,a,b,r,mat,n=12,r2=None):
        delta=Vector(b)-Vector(a);rot=delta.to_track_quat('Z','Y').to_matrix()
        verts=[Vector(end)+rot@Vector((rr*math.cos(i*math.tau/n),rr*math.sin(i*math.tau/n),0)) for end,rr in [(a,r),(b,r if r2 is None else r2)] for i in range(n)]
        self.add(verts,[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],mat)
    def merge(self,other,offset=(0,0,0),angle=0):
        rot=Matrix.Rotation(angle,3,'Z'); verts=[rot@Vector(v)+Vector(offset) for v in other.v]
        k=len(self.v);self.v.extend([tuple(v) for v in verts])
        for f,mi in zip(other.f,other.mi):
            mat=other.materials[mi]
            if mat not in self.materials:self.materials.append(mat)
            self.f.append(tuple(k+i for i in f));self.mi.append(self.materials.index(mat))
    def mesh(self,name,collision=False):
        if not self.v:return None
        me=bpy.data.meshes.new(name);me.from_pydata(self.v,[],self.f);me.update()
        for mat in self.materials:me.materials.append(mat)
        for p,mi in zip(me.polygons,self.mi):p.material_index=mi
        # Winding is authored below. Recalculating isolated road/window sheets flips
        # them unpredictably against the origin and breaks lighting/backface culling.
        bm=bmesh.new();bm.from_mesh(me)
        bmesh.ops.triangulate(bm,faces=[f for f in bm.faces if len(f.verts)>4]);bm.to_mesh(me);bm.free();me.update()
        uv=me.uv_layers.new(name='metric_uv')
        for p in me.polygons:
            axis=max(range(3),key=lambda i:abs(p.normal[i]));axes=[i for i in range(3) if i!=axis]
            tile=me.materials[p.material_index].get('tile_metres',3)
            for li in p.loop_indices:
                co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]/tile,co[axes[1]]/tile)
        o=bpy.data.objects.new(name+('-colonly' if collision else ''),me);collection.objects.link(o);o.parent=root
        if collision:o.hide_render=True;o.display_type='WIRE'
        return o


def exclude_rect(x,z,w,d):manifest['exclusions'].append([x-w/2,z-d/2,x+w/2,z+d/2])


def facade(b,w,d,h,mat,style=0):
    """Readable wall bays, recessed-looking glass, sills, floor bands and ground-floor shops."""
    b.box((0,0,h/2),(w,d,h),mat)
    b.box((0,0,.55),(w+.35,d+.35,1.1),concrete)
    for y in [-d/2,d/2]:
        side=-1 if y<0 else 1
        for floor in range(max(1,int(h/3.5))):
            z=2.1+floor*3.5
            if z+1>h:continue
            for x in np.arange(-w/2+2.2,w/2-1,3.9):
                ww=2.35 if floor else 2.8;hh=1.75 if floor else 2.6
                yy=y+side*.06
                b.add([(x-ww/2,yy,z-hh/2),(x+ww/2,yy,z-hh/2),(x+ww/2,yy,z+hh/2),(x-ww/2,yy,z+hh/2)],[(0,1,2,3) if side<0 else (3,2,1,0)],glass2 if (floor+int(x))%7==0 else glass)
                b.box((x,yy+side*.10,z-hh/2-.10),(ww+.30,.35,.17),white)
                if style==1 and floor>0 and int(x)%3==0:
                    b.box((x,yy+side*.75,z-hh/2-.18),(3,1.7,.18),concrete)
                    b.box((x,yy+side*1.48,z-hh/2+.42),(3,.10,.9),glass)
            if floor>0:b.box((0,y+side*.10,floor*3.5+.3),(w+.12,.24,.20),white if style!=2 else steel)
    for x in [-w/2,w/2]:
        side=-1 if x<0 else 1
        for floor in range(max(1,int(h/3.5))):
            z=2.1+floor*3.5
            if z+1>h:continue
            for y in np.arange(-d/2+2.3,d/2-1,4.2):
                xx=x+side*.06
                b.add([(xx,y-1.1,z-.9),(xx,y+1.1,z-.9),(xx,y+1.1,z+.9),(xx,y-1.1,z+.9)],[(0,1,2,3) if side>0 else (3,2,1,0)],glass)
                b.box((xx+side*.10,y,z-1.02),(.35,2.5,.18),white)
    b.box((0,0,h+.06),(w,d,.18),roof)
    for x in [-w/2,w/2]:b.box((x,0,h+.5),(.28,d,.85),mat)
    for y in [-d/2,d/2]:b.box((0,y,h+.5),(w,.28,.85),mat)
    b.box((0,0,h+1.5),(w*.22,d*.26,2.6),roof)
    for x in [-w*.26,w*.25]:
        b.box((x,d*.12,h+.70),(3.6,2.4,1.25),steel)
        for dx in [-.95,.95]:b.cylinder((x+dx,d*.12,h+1.3),(x+dx,d*.12,h+1.4),.74,black,12)
    # Front awning and readable doorway, not luminous billboards.
    b.box((0,-d/2-.75,3.25),(min(w-2,12),1.8,.25),roof)
    b.box((0,-d/2-.12,1.4),(2.1,.15,2.8),glass)


def building(b,c,x,z,w,d,h,mat,style=0,angle=0):
    levels=[height(x+dx,z+dz) for dx in np.linspace(-w/2,w/2,max(3,math.ceil(w/12))) for dz in np.linspace(-d/2,d/2,max(3,math.ceil(d/12)))]
    ground=max(levels)+.30;depth=ground-min(levels)+1.0
    model=Batch();facade(model,w,d,h,mat,style)
    # Individual terraced foundations reach the downhill terrain, without changing the DEM.
    model.box((0,0,-depth/2),(w+.6,d+.6,depth),concrete)
    b.merge(model,(x,-z,ground),angle)
    proxy=Batch();proxy.box((0,0,(h-depth)/2),(w,d,h+depth),concrete);c.merge(proxy,(x,-z,ground),angle)
    return ground


def clip(poly,axis,limit):
    """Convex half-plane clip in site coordinates; preserves the surface winding."""
    result=[]
    for a,b in zip(poly,poly[1:]+poly[:1]):
        da=a[0]*axis[0]+a[1]*axis[1]-limit;db=b[0]*axis[0]+b[1]*axis[1]-limit
        if da>=-1e-8:result.append(a)
        if (da>0 and db<0) or (da<0 and db>0):
            t=da/(da-db);result.append((a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t))
    return result


def drape(b,poly,mat,offset):
    # Same approach as RoadTerrainConformer: clip to the native terrain triangles.
    # Sampling only road endpoints causes metre-wide buried gaps on this 15 m DEM.
    spacing=SITE['spacing'];ox,oz=SITE['first']
    for j in range(math.floor((min(p[1] for p in poly)-oz)/spacing),math.floor((max(p[1] for p in poly)-oz)/spacing)+1):
        for i in range(math.floor((min(p[0] for p in poly)-ox)/spacing),math.floor((max(p[0] for p in poly)-ox)/spacing)+1):
            x=ox+i*spacing;z=oz+j*spacing;q=poly
            for axis,limit in [((1,0),x),((-1,0),-x-spacing),((0,1),z),((0,-1),-z-spacing)]:q=clip(q,axis,limit)
            for axis,limit in [((1,-1),x-z),((-1,1),z-x)]:
                triangle=clip(q,axis,limit)
                if len(triangle)<3:continue
                area=sum(a[0]*bb[1]-bb[0]*a[1] for a,bb in zip(triangle,triangle[1:]+triangle[:1]))
                if abs(area)<1e-6:continue
                if area>0:triangle.reverse()
                verts=[(xx,-zz,height(xx,zz)+offset) for xx,zz in triangle]
                b.add(verts,[(0,k,k+1) for k in range(1,len(verts)-1)],mat)


def draped_rect(b,x,z,w,d,mat,offset=.10):
    drape(b,[(x-w/2,z-d/2),(x-w/2,z+d/2),(x+w/2,z+d/2),(x+w/2,z-d/2)],mat,offset)


def car(b,x,z,angle=0,color=None):
    h=height(x,z)+.12;v=Batch()
    v.box((0,0,.72),(1.85,4.3,1.0),color or [white,steel,trim][rng.randrange(3)])
    v.box((0,-.15,1.42),(1.66,2.1,.62),glass)
    v.box((0,-.12,1.79),(1.65,1.9,.12),color or white)
    for xx in [-.91,.91]:
        for yy in [-1.35,1.35]:v.cylinder((xx-.12,yy,.43),(xx+.12,yy,.43),.34,black,8)
    for xx in [-.60,.60]:v.box((xx,-2.16,.84),(.38,.03,.20),paint)
    b.merge(v,(x,-z,h),angle)


def streetlight(b,x,z,angle=0):
    h=height(x,z);v=Batch()
    v.cylinder((0,0,0),(0,0,8),.10,steel,6,r2=.065)
    v.beam((0,0,7.9),(2.1,0,8.4),.09,steel)
    v.box((2.0,0,8.35),(1.2,.42,.18),steel)
    b.merge(v,(x,-z,h),angle)


def street(name,points,width=14,bridge=False):
    """Baked road with continuous edge lines. All supplied coordinates are authored."""
    b=Batch();c=Batch();detail=Batch();sampled=[]
    for index,(a,bb) in enumerate(zip(points,points[1:])):
        a=np.array(a,dtype=float);bb=np.array(bb,dtype=float)
        count=max(1,math.ceil(np.linalg.norm(bb[:2]-a[:2])/6))
        for j in range(count):
            p=a+(bb-a)*j/count
            if len(p)==2:p=np.append(p,height(*p)+.22)
            sampled.append(p)
    p=np.array(points[-1],dtype=float)
    if len(p)==2:p=np.append(p,height(*p)+.22)
    sampled.append(p)
    for i,(a,bb) in enumerate(zip(sampled,sampled[1:])):
        delta=bb[:2]-a[:2];unit=delta/np.linalg.norm(delta);normal=np.array([-unit[1],unit[0]])
        def ribbon(lo,hi,mat,lift=0):
            v=[]
            for p,off in [(a,lo),(a,hi),(bb,hi),(bb,lo)]:
                q=p[:2]+normal*off
                y=p[2] if bridge or len(points[0])==3 else height(*q)+.22
                v.append((q[0],-q[1],y+lift))
            if bridge or len(points[0])==3:
                b.add(v,[(0,1,2,3)],mat)
                if mat==asphalt:c.add(v,[(0,1,2,3)],mat)
            else:
                poly=[(vv[0],-vv[1]) for vv in v]
                surface=Batch();drape(surface,poly,mat,.22+lift);b.merge(surface)
                if mat==asphalt:c.merge(surface)
        ribbon(-width/2-2.3,width/2+2.3,concrete,-.055)
        ribbon(-width/2,width/2,asphalt)
        for off in [-width/2+.40,width/2-.40]:ribbon(off-.065,off+.065,paint,.015)
        if i%3==0:ribbon(-.07,.07,paint,.016)
        if bridge:
            for side in [-1,1]:
                pa=a[:2]+normal*side*(width/2+1.9);pb=bb[:2]+normal*side*(width/2+1.9)
                detail.beam((pa[0],-pa[1],a[2]-.85),(pb[0],-pb[1],bb[2]-.85),1.7,concrete,1.0)
                detail.beam((pa[0],-pa[1],a[2]+1.1),(pb[0],-pb[1],bb[2]+1.1),.12,steel)
                if i%2==0:detail.beam((pa[0],-pa[1],a[2]),(pa[0],-pa[1],a[2]+1.12),.10,steel)
            if i%10==0:
                ground=height(a[0],a[1]);deck=a[2]
                for side in [-1,1]:
                    q=a[:2]+normal*side*width*.32
                    detail.cylinder((q[0],-q[1],ground-1),(q[0],-q[1],deck-1),1.35,concrete,10,r2=1.15)
                detail.box((a[0],-a[1],deck-1.7),(width+2,3.3,1.8),concrete,Matrix.Rotation(-math.atan2(unit[1],unit[0])+math.pi/2,3,'Z'))
    b.mesh('city_road_'+name);c.mesh('city_road_'+name+'_collision',True);detail.mesh('city_viaduct_structure_'+name)
    manifest['roads'].append({'name':name,'width':width,'points':[list(map(float,p)) for p in sampled[::3]]+[list(map(float,sampled[-1]))], 'bridge':bridge, 'draped':not bridge and len(points[0])==2})


def neighborhood(name,xs,zs,w=170,d=190):
    visuals=Batch();props=Batch();coll=Batch()
    for j,z in enumerate(zs):
        for i,x in enumerate(xs):
            block=Batch();proxy=Batch();pad=Batch()
            # Walkable perimeter and courtyard paths, with open planted ground rather than giant empty slabs.
            for dx in [-w/2+5,w/2-5]:draped_rect(pad,x+dx,z,10,d,concrete)
            for dz in [-d/2+6,d/2-6]:draped_rect(pad,x,z+dz,w-20,12,concrete)
            draped_rect(pad,x,z,7,d-24,concrete)
            draped_rect(pad,x,z,w-20,6,concrete)
            pad.mesh('city_pavement_'+name+'_%d_%d'%(i,j));exclude_rect(x,z,w+12,d+12)
            manifest['blocks'].append({'name':name+'_%d_%d'%(i,j),'center':[x,z],'size':[w,d]})
            if name=='centro' and (i,j) in [(1,1),(2,2),(0,2)]:
                tower(block,proxy,x,z,w,d,[(1,1),(2,2),(0,2)].index((i,j)))
            else:
                if (i+j)%3==0:
                    footprints=[(0,-d*.32,w-30,27),(0,d*.30,w-30,27),(-w*.33,0,25,d*.40),(w*.33,0,25,d*.40)]
                else:
                    footprints=[(-w*.26,-d*.28,w*.39,38),(w*.26,-d*.28,w*.39,44),(-w*.26,d*.27,w*.39,46),(w*.26,d*.27,w*.39,38)]
                for k,(dx,dz,ww,dd) in enumerate(footprints):
                    floors=rng.choice([4,5,6,7,8]) if name!='giardini' else rng.choice([3,4,5])
                    building(block,proxy,x+dx,z+dz,ww,dd,floors*3.5,[wall,brick,white][(i+j+k)%3],(k+i)%3)
                    draped_rect(block,x+dx,z+dz,ww+5,dd+5,concrete,.13)
            # Courtyard trees inside the open central gardens; keep tower podiums clear.
            tower_site=name=='centro' and (i,j) in [(1,1),(2,2),(0,2)]
            for dx in ([-w*.39,w*.39] if tower_site else [-w*.15,w*.15]):
                for dz in ([-d*.33,d*.33] if tower_site else [-d*.11,d*.11]):
                    gx,gz=x+dx,z+dz;hh=height(gx,gz)
                    manifest['trees'].append([gx,gz,hh])
            for k in range(7):
                px=x-w*.3+k*7;pz=z+d*.43
                if k%3!=1:car(props,px,pz,color=[white,roof,trim][k%3])
                for dx in [-2.7,2.7]:
                    xx=px+dx;zz=pz;hh=height(xx,zz)+.16
                    props.box((xx,-zz,hh),(.10,5.4,.025),paint)
            for dx in [-w/2+3,w/2-3]:streetlight(props,x+dx,z,math.pi if dx>0 else 0)
            for dx in [-12,12]:
                hh=height(x+dx,z);props.box((x+dx,-z,hh+.5),(3,.6,.18),trim)
                for xx in [-1,1]:props.box((x+dx+xx,-z,hh+.24),(.1,.5,.5),steel)
            block.mesh('city_block_'+name+'_%d_%d'%(i,j));proxy.mesh('city_block_'+name+'_%d_%d_proxy'%(i,j),True)
    props.mesh('city_details_'+name)
    # Shared street lattice: no random disconnected buildings.
    dx=xs[1]-xs[0];dz=zs[1]-zs[0]
    for i,x in enumerate([xs[0]-dx/2]+[v+dx/2 for v in xs]):street(name+'_ns_'+str(i),[(x,zs[0]-dz/2),(x,zs[-1]+dz/2)],16)
    for j,z in enumerate([zs[0]-dz/2]+[v+dz/2 for v in zs]):street(name+'_ew_'+str(j),[(xs[0]-dx/2,z),(xs[-1]+dx/2,z)],16)


def tower(b,c,x,z,w,d,variant):
    h=[126,96,112][variant]
    building(b,c,x,z,104,70,12,wall,2)
    if variant==0:
        building(b,c,x-17,z,40,42,h,white,2)
        building(b,c,x+23,z+6,27,38,83,wall,2)
        gh=max(height(x-17,z),height(x+23,z+6))
        b.box((x-17,-z,gh+h+3.5),(42,44,2.0),steel)
        for dx in [-19,19]:b.box((x-17+dx,-z,gh+h/2),(1.1,43,h),trim)
    elif variant==1:
        for k in range(3):building(b,c,x-28+k*24,z+k*6,27,44,h-k*19,wall if k!=1 else white,2)
    else:
        building(b,c,x,z,46,46,h,brick,2)
        building(b,c,x,z,34,34,h+15,white,2)
    manifest['landmarks'].append({'name':'tower_'+str(variant),'x':x,'z':z,'height':h})


def quarters():
    neighborhood('centro',[-1710,-1520,-1330],[-360,-130,100,330],155,195)
    neighborhood('ponente',[-2430,-2220,-2010],[300,540,780,1020],170,195)
    neighborhood('belvedere',[-2170,-1950,-1730],[-1180,-940,-700],170,195)
    neighborhood('giardini',[-1700,-1480,-1260],[780,1020,1260],170,195)
    # Fourth skyline landmark, a stepped research headquarters well away from the runway.
    b=Batch();c=Batch();tower(b,c,-950,-650,180,190,1)
    b.mesh('city_research_headquarters');c.mesh('city_research_headquarters_proxy',True)
    exclude_rect(-950,-650,160,130)
    print('CITY QUARTERS',len(manifest['blocks']))


def civic_and_airfield():
    for name,x,z,w,d,h in [('research_west',-1080,-900,112,38,17.5),('research_east',-800,-900,100,38,21),('research_library',-930,-410,135,32,14),('hospital',-920,130,105,65,24.5),('school',-910,480,120,36,14),('transport_hall',-1090,700,85,35,10.5)]:
        b=Batch();c=Batch();building(b,c,x,z,w,d,h,white,2)
        b.mesh('city_'+name);c.mesh('city_'+name+'_proxy',True)
        p=Batch();draped_rect(p,x,z,w+32,d+34,concrete);p.mesh('city_'+name+'_plaza');exclude_rect(x,z,w+40,d+42)
    # Campus streets and promenades form a real network.
    for name,points in [
        ('campus_west',[(-1150,-1040),(-1150,1380)]),
        ('campus_east',[(-660,-1040),(-660,700)]),
        ('campus_north',[(-1620,-1060),(-1150,-1040),(-660,-1040)]),
        ('campus_mid',[(-1235,-475),(-660,-475)]),
        ('civic',[(-1235,215),(-660,215)]),
        ('civic_south',[(-1810,660),(-660,660)]),
        ('center_to_west',[(-1905,420),(-1805,445),(-1235,445)]),
        ('north_link',[(-1905,-580),(-1905,420)]),
        ('north_to_center',[(-2280,-580),(-1620,-580),(-1615,-475)]),
        ('south_park',[(-1590,445),(-1590,660)]),
        ('west_south',[(-1905,1140),(-1810,1380),(-1150,1380)]),
    ]:street(name,points,18)
    street('airport_gate',[(-660,215,height(-660,215)+.2),(-620,231,height(-620,231)+.2),(-580,231,.025)],10)
    # Airport operations: tower, parking, maintenance and fuel district; never in taxi corridors.
    b=Batch();c=Batch();props=Batch()
    x,z=-520,660;g=height(x,z)+.3
    b.box((x,-z,g+18),(12,12,36),wall);c.box((x,-z,g+18),(12,12,36),concrete)
    b.box((x,-z,g+37),(27,23,2),white);b.box((x,-z,g+41),(23,20,6),glass)
    b.box((x,-z,g+44.5),(29,25,1.3),steel);b.cylinder((x,-z,g+45),(x,-z,g+52),.16,steel,8)
    c.box((x,-z,g+41),(27,23,8),concrete)
    building(b,c,-500,760,62,35,10.5,wall,2)
    exclude_rect(-500,715,110,200)
    street('operations_access',[(-580,231,.025),(-600,440,height(-600,440)+.2),(-600,840,height(-600,840)+.2),(-470,845,height(-470,845)+.2)],10)
    for x,z,w,d in [(810,880,85,135),(1010,880,110,135),(820,1130,90,90),(1040,1150,125,90)]:
        building(b,c,x,z,w,d,14,white,2);exclude_rect(x,z,w+36,d+35)
        p=Batch();draped_rect(p,x,z,w+26,d+25,concrete);p.mesh('city_logistics_yard_%d_%d'%(x,z))
        for k in range(4):
            px=x-w/2+12+k*17;pz=z-d/2-10;props.box((px,-pz,height(px,pz)+1.3),(6,2.5,2.6),[roof,trim,white][k%3])
    for x,z in [(760,540),(810,540),(860,540),(910,540)]:
        h=height(x,z);b.cylinder((x,-z,h),(x,-z,h+16),16,white,32)
        b.cylinder((x,-z,h+16),(x,-z,h+17),16,roof,32,r2=2)
        c.cylinder((x,-z,h),(x,-z,h+17),16,concrete,16)
        exclude_rect(x,z,42,42)
    for name,points in [('logistics_main',[(660,430),(1130,430),(1130,1300),(680,1300),(660,430)]),('logistics_cross',[(660,1010),(1130,1010)]),('hangar_service',[(540,1180,.025),(580,1230,height(580,1230)+.2),(680,1300,height(680,1300)+.2)])]:street(name,points,12)
    # Independent service apron clear of hangar entry and existing collision openings.
    for k in range(22):car(props,735+k%8*7,710+k//8*9)
    for x,z in [(-570,550),(-570,790),(680,740),(1100,750),(700,1200),(1100,1240)]:streetlight(props,x,z)
    b.mesh('city_airport_support');c.mesh('city_airport_support_proxy',True);props.mesh('city_details_airport')
    # Existing user-authored road remains intact: this continuation meets its west endpoint.
    street('southern_access',[(1130,1300),(1300,1670),(1420,2100),(1318.484,2586.572)],16)
    street('city_bypass',[(-1905,1140),(-2000,1560),(-1560,1830),(-800,2090),(0,2260),(830,2260),(1318.484,2586.572)],18)
    print('CITY CIVIC AND AIRFIELD COMPLETE')


def waterfront():
    # Low viaduct crosses the inland end of the inlet, never the runway axis.
    deck=204.0-ORIGIN[1]
    street('bay_viaduct',[(-1450,-1760,deck),(-1150,-1800,deck),(-830,-1790,deck),(-550,-1730,deck)],16,True)
    street('bay_west',[(-1905,-1300),(-2000,-1570),(-1920,-1860),(-1770,-2030),(-1600,-2010),(-1510,-1880)],14)
    # Last road section is a gentle engineered ramp up to the bridge deck.
    street('bridge_west_ramp',[(-1510,-1880,height(-1510,-1880)+.22),(-1450,-1760,deck)],16,True)
    street('bridge_east_ramp',[(-550,-1730,deck),(-500,-1560,height(-500,-1560)+.22),(-520,-1350,height(-520,-1350)+.22)],16,True)
    street('bay_east',[(-520,-1350),(-590,-1170),(-660,-1040)],14)
    b=Batch();c=Batch();props=Batch()
    # Town on the landward terrace, quays on piles at water level, connected by a sloping service road.
    for x,z,w,d,h in [(-1820,-2180,70,28,17.5),(-1940,-2160,70,32,21),(-1910,-1940,62,28,14),(-1750,-2250,45,26,14)]:
        building(b,c,x,z,w,d,h,wall if x<-1800 else brick,1);exclude_rect(x,z,w+25,d+25)
    street('waterfront_terrace',[(-2000,-1570),(-2090,-1900),(-2040,-2300),(-1840,-2380),(-1690,-2260),(-1770,-2030)],12)
    qh=187.6-ORIGIN[1]
    # The west shore at z=-2000 is low enough for a plausible quay and approach without DEM surgery.
    b.box((-1395,2000,qh-1.0),(45,235,2),concrete);c.box((-1395,2000,qh-1.0),(45,235,2),concrete)
    exclude_rect(-1395,-2000,58,250)
    for z in [-2070,-2010,-1950]:
        b.box((-1305,-z,qh-.25),(145,9,.50),concrete);c.box((-1305,-z,qh-.25),(145,9,.50),concrete)
        for x in [-1380,-1330,-1280,-1240]:b.cylinder((x,-z,height(x,z)-1),(x,-z,qh-.2),.7,steel,8)
        for x in [-1350,-1290]:
            props.box((x,-z-3.4,qh+.2),(1,1,.4),steel)
    for z in range(-2100,-1900,20):
        props.cylinder((-1411,-z,qh),(-1411,-z,qh+1.1),.045,steel,6)
        props.beam((-1411,-z,qh+1.1),(-1411,-z-20,qh+1.1),.06,steel)
    street('quay_ramp',[(-1600,-2010,height(-1600,-2010)+.25),(-1510,-2025,height(-1510,-2025)+.25),(-1410,-2025,qh+.04)],9,True)
    b.mesh('city_waterfront');c.mesh('city_waterfront_proxy',True);props.mesh('city_details_waterfront')
    manifest['landmarks'].append({'name':'quay','x':-1395,'z':-2000,'height':187.6})
    print('CITY WATERFRONT COMPLETE')


def infrastructure():
    b=Batch();c=Batch()
    turbine_sites=[(1430,-1620),(1770,-1440),(1540,-1130),(1880,-880),(1610,-620),(1820,-320)]
    for i,(x,z) in enumerate(turbine_sites):
        h=height(x,z);hub=112;R=Matrix.Rotation(.25,3,'Z');t=Batch()
        t.cylinder((0,0,0),(0,0,hub),3.3,white,20,r2=1.7)
        t.box((0,1,hub),(5,11,5),white)
        t.cylinder((0,-5,hub),(0,-7,hub),2.3,white,16,r2=1.3)
        for blade in range(3):
            a=blade*math.tau/3+.23
            # Swept tapered blade with an aerofoil-like closed section, not a rectangular paddle.
            verts=[]
            for r,chord,sweep in [(2,1.5,0),(10,3.8,1),(27,2.7,2),(47,.3,4)]:
                for yy,edge in [(-6.8,-1),(-6.8,1),(-6.2,1),(-6.2,-1)]:
                    q=Matrix.Rotation(a,3,'Y')@Vector((edge*chord/2+sweep,0,r))
                    verts.append((q.x,yy,hub+q.z))
            t.add(verts,[(0,3,2,1),(12,13,14,15)]+[(j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k) for j in range(3) for k in range(4)],white)
        b.merge(t,(x,-z,h),.25);c.cylinder((x,-z,h),(x,-z,h+hub),3.3,concrete,12,r2=1.7)
        b.cylinder((x,-z,h-1),(x,-z,h+.25),11,concrete,24)
        exclude_rect(x,z,35,35)
        manifest['landmarks'].append({'name':'turbine_%02d'%i,'x':x,'z':z,'height':159})
    street('wind_access',[(1130,430),(1310,100),(1490,-260),(1610,-620),(1540,-1130),(1430,-1620)],8)
    for i,(a,bb) in enumerate([(turbine_sites[0],turbine_sites[1]),(turbine_sites[2],turbine_sites[3]),(turbine_sites[4],turbine_sites[5])]):street('wind_spur_'+str(i),[a,bb],6)
    b.mesh('city_wind_farm');c.mesh('city_wind_farm_proxy',True)
    # Telecommunications site: braced mast and actual parabolic dishes with feed supports.
    b=Batch();c=Batch();x,z=-2740,-790;h=height(x,z)
    building(b,c,x+42,z+30,38,22,7,wall,2)
    for yy in [-1,1]:
        for xx in [-1,1]:b.beam((x+xx*5,-z+yy*5,h),(x+xx*1,-z+yy*1,h+102),.65,steel)
    for level in range(0,96,8):
        low=5-4*level/102;high=5-4*(level+8)/102
        for side in [-1,1]:
            b.beam((x-low,-z+side*low,h+level),(x+high,-z+side*high,h+level+8),.22,steel)
            b.beam((x+low,-z+side*low,h+level),(x-high,-z+side*high,h+level+8),.22,steel)
            b.beam((x+side*low,-z-low,h+level),(x+side*high,-z+high,h+level+8),.22,steel)
    for level in [36,66,96]:b.box((x,-z,h+level),(7,7,.35),steel)
    b.cylinder((x,-z,h+100),(x,-z,h+125),.25,paint,8)
    c.box((x,-z,h+50),(10,10,100),concrete)
    for i in range(3):
        xx=x-30-i*24;zz=z+35;hh=height(xx,zz)
        b.cylinder((xx,-zz,hh),(xx,-zz,hh+7),.55,steel,10)
        verts=[];radius=7.0
        for ring in range(7):
            rr=radius*ring/6
            for k in range(24):
                a=k*math.tau/24;verts.append((xx+rr*math.cos(a),-zz+rr*math.sin(a),hh+7+rr*rr/17))
        b.add(verts,[(j*24+k,j*24+(k+1)%24,(j+1)*24+(k+1)%24,(j+1)*24+k) for j in range(6) for k in range(24) if j>0],white)
        for a in [0,math.tau/3,2*math.tau/3]:b.beam((xx+6*math.cos(a),-zz+6*math.sin(a),hh+9),(xx,-zz,hh+13),.11,steel)
        b.box((xx,-zz,hh+13),(.6,.6,.8),steel)
    exclude_rect(x-15,z,160,130)
    street('telecom_access',[(-2280,-820),(-2440,-900),(-2670,-910),(-2740,-790)],8)
    b.mesh('city_telecommunications');c.mesh('city_telecommunications_proxy',True)
    manifest['landmarks'].append({'name':'telecommunications','x':x,'z':z,'height':125})
    print('CITY INFRASTRUCTURE COMPLETE')


def check():
    # Runnable regression on the baked surfaces: winding and clearance at vertices
    # AND triangle interiors (endpoints alone missed the original buried roads).
    count=0
    for road in manifest['roads']:
        if not road['draped']:continue
        ob=bpy.data.objects['city_road_'+road['name']];me=ob.data
        for face in me.polygons:
            points=[ob.matrix_world @ me.vertices[i].co for i in face.vertices]
            center=sum(points,Vector())/len(points)
            assert face.normal.z>0, (ob.name,'downward surface')
            for p in points+[center]:
                clearance=p.z-height(p.x,-p.y)
                assert .14<clearance<.26,(ob.name,'terrain contact',clearance,tuple(p))
            count+=1
    assert count>10000
    print('PASS: CITY AUTHORING SURFACE CHECK',count,'triangles')


def export():
    bpy.context.view_layer.update()
    check()
    # Offset source vertices to spatial chunk pivots, improving local AABBs and culling.
    for o in collection.objects:
        if o.type!='MESH':continue
        coords=np.array([v.co[:] for v in o.data.vertices]);center=(coords.min(axis=0)+coords.max(axis=0))/2
        for v in o.data.vertices:v.co-=Vector(center)
        o.location+=Vector(center)
    # Inherited masks can have packed 2K data despite a 1K disk file.
    # Remove that packed copy before reloading, then pack the actual 1K image.
    for image in bpy.data.images:
        if image.filepath and '_mask_1k' in image.filepath and os.path.isfile(bpy.path.abspath(image.filepath)):
            if image.packed_file:image.unpack(method='REMOVE')
            image.reload()
            assert tuple(image.size)==(1024,1024),(image.name,tuple(image.size))
            image.pack()
    for target,objects in [('airport_layout',list(bpy.data.collections['airport_asset'].objects)),('airport_city',list(collection.objects))]:
        bpy.ops.object.select_all(action='DESELECT')
        for o in objects:o.select_set(True)
        bpy.context.view_layer.objects.active=objects[0]
        # Source collision proxies are exportable despite being hidden in renders.
        bpy.ops.export_scene.gltf(filepath=str(OUT/(target+'.glb')),export_format='GLB',use_selection=True,use_active_scene=True,export_yup=True,export_apply=True,export_cameras=False,export_lights=False,export_texcoords=True,export_normals=True,export_tangents=True,export_materials='EXPORT')
    (OUT/'source/city_layout.json').write_text(json.dumps(manifest,indent=2))
    # Source preview only: terrain sampled from the real DEM, excluded from both glTF exports.
    prev=bpy.data.collections['preview_only_excluded']
    for ob in list(prev.objects):
        if ob.name.startswith('city_context_'):bpy.data.objects.remove(ob,do_unlink=True)
    bpy.data.objects['closeup_preview_ground'].hide_render=True
    terrain=Batch();verts=[];stride=5
    for j in range(0,HEIGHT.shape[0],stride):
        for i in range(0,HEIGHT.shape[1],stride):
            x=SITE['first'][0]+i*SITE['spacing'];z=SITE['first'][1]+j*SITE['spacing'];verts.append((x,-z,HEIGHT[j,i]-ORIGIN[1]))
    nx=len(range(0,HEIGHT.shape[1],stride));nz=len(range(0,HEIGHT.shape[0],stride))
    terrain.add(verts,[(j*nx+i,j*nx+i+1,(j+1)*nx+i+1,(j+1)*nx+i) for j in range(nz-1) for i in range(nx-1)],bpy.data.materials['closeup_preview_ground_material'])
    ob=terrain.mesh('city_context_terrain');collection.objects.unlink(ob);prev.objects.link(ob);ob.parent=None
    watermat=bpy.data.materials.new('city_context_water');watermat.diffuse_color=(.075,.18,.24,1)
    water=Batch();water.box((-700,200,SITE['water']-ORIGIN[1]-.3),(6900,6900,.3),watermat)
    ob=water.mesh('city_context_water');collection.objects.unlink(ob);prev.objects.link(ob);ob.parent=None
    camera=bpy.data.objects['preview_camera'];camera.location=(2600,-3700,2800)
    camera.rotation_euler=(Vector((-800,150,0))-camera.location).to_track_quat('-Z','Y').to_euler();camera.data.lens=44
    scene.camera=camera
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_distance=5800
                area.spaces.active.region_3d.view_location=(-700,0,0)
    for im in bpy.data.images:
        if im.filepath and os.path.isfile(bpy.path.abspath(im.filepath)):
            im.filepath=bpy.path.relpath(bpy.path.abspath(im.filepath),start=str(OUT/'source'))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source/airport.blend'))
    meshes=[o for o in collection.objects if o.type=='MESH']
    print('CITY_EXPORT_OK',len(meshes),'mesh objects',sum(len(o.data.polygons) for o in meshes),'polygons',len(manifest['blocks']),'blocks',len(manifest['roads']),'roads')
