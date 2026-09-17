"""Close-range revision, executed in stages through Blender MCP, not a runtime generator.
Load into an explicit namespace; call detail_hangar(), detail_shelters(),
detail_technical(), detail_services(), detail_towers(), detail_radome().
The existing authoring scene and supplied reference library must already be loaded.
"""
import bpy, bmesh, math, os, json, shutil
import numpy as np
from mathutils import Vector, Matrix
BASE=r'C:/Users/sanna/Workspace/Godot/Progetti/aero-demons'
OUT=BASE+'/assets/environment/airport'
scene=bpy.data.scenes['airport_authoring'];bpy.context.window.scene=scene
collection=bpy.data.collections['airport_asset']
root=bpy.data.objects['airport_root']
groups={n:bpy.data.objects[n] for n in ['runway','taxiways','aprons','service_roads','buildings','markings','details']}
TEX=OUT+'/textures/polyhaven'
PREVIEW=OUT+'/source/previews/closeup'
os.makedirs(PREVIEW,exist_ok=True)

def pbr(name,asset,tile,metallic=0.0,normal_strength=.5,tint=None,contrast=1.0,level=0.0):
    """Plain glTF PBR graph. Any tint and ORM packing are baked to actual images."""
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True;m.node_tree.nodes.clear();m['tile_metres']=tile;m['polyhaven_asset']=asset
    nt=m.node_tree;p=nt.nodes.new('ShaderNodeBsdfPrincipled');out=nt.nodes.new('ShaderNodeOutputMaterial');nt.links.new(p.outputs['BSDF'],out.inputs['Surface'])
    p.inputs['Metallic'].default_value=metallic
    def image(suffix):
        path=TEX+'/'+asset+'_'+suffix+'.jpg'
        im=bpy.data.images.load(path,check_existing=True)
        return im
    im=image('Diffuse')
    if tint is not None:
        a=np.empty(len(im.pixels),np.float32);im.pixels.foreach_get(a);a=a.reshape((-1,4));gray=a[:,:3].mean(axis=1)
        a[:,:3]=np.clip((gray[:,None]*contrast+level)*np.array(tint)[None,:],0,1)
        colored=bpy.data.images.new(name+'_albedo',width=im.size[0],height=im.size[1]);colored.pixels.foreach_set(a.ravel());colored.filepath_raw=TEX+'/'+name+'_albedo.png';colored.file_format='PNG';colored.save();im=colored
    t=nt.nodes.new('ShaderNodeTexImage');t.image=im;nt.links.new(t.outputs['Color'],p.inputs['Base Color'])
    normal=image('nor_gl');normal.colorspace_settings.name='Non-Color'
    t=nt.nodes.new('ShaderNodeTexImage');t.image=normal
    n=nt.nodes.new('ShaderNodeNormalMap');n.inputs['Strength'].default_value=normal_strength
    nt.links.new(t.outputs['Color'],n.inputs['Color']);nt.links.new(n.outputs['Normal'],p.inputs['Normal'])
    rough=image('Rough');rough.colorspace_settings.name='Non-Color'
    t=nt.nodes.new('ShaderNodeTexImage');t.image=rough;nt.links.new(t.outputs['Color'],p.inputs['Roughness'])
    if metallic > .5 and os.path.exists(TEX+'/'+asset+'_Metal.jpg'):
        met=image('Metal');met.colorspace_settings.name='Non-Color';t=nt.nodes.new('ShaderNodeTexImage');t.image=met;nt.links.new(t.outputs['Color'],p.inputs['Metallic'])
    return m
floor=pbr('ph_airfield_concrete','concrete_floor_01',2,.0,.20,tint=(1,1.01,1.02),contrast=.55,level=.25)
wall=pbr('ph_cast_concrete','concrete',3,.0,.22,tint=(1.05,1.075,1.08),contrast=.45,level=.32)
roof=pbr('ph_corrugated_roof','corrugated_iron_02',3,.25,.7,tint=(1.65,1.73,1.76))
cladding=pbr('ph_wall_cladding','corrugated_iron_02',3,.12,.6,tint=(1.9,1.98,1.98))
roof.use_backface_culling=False
steel=pbr('ph_structural_steel','metal_plate',2,.7,.25,tint=(.55,.62,.66))
door=pbr('ph_painted_shutter','painted_metal_shutter',3,.15,.45,tint=(.75,.84,.83))
asphalt=pbr('ph_airfield_asphalt','asphalt_floor',4,.0,.4)
paint=pbr('ph_safety_yellow','metal_plate',2,.15,.15,tint=(3.4,2.2,.3))
lightpaint=pbr('ph_offwhite_coating','concrete_floor_01',3,.0,.10,tint=(1.1,1.1,1.08),contrast=.25,level=.6)
# Paint and glass have intentionally smooth optical normals, with photographed roughness.
glass=pbr('ph_industrial_glass','metal_plate',2,.25,.025,tint=(.20,.36,.43))
glass.node_tree.nodes.get('Principled BSDF').inputs['Coat Weight'].default_value=.7
roofglass=glass.copy();roofglass.name='ph_roof_glass'
roofglass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.45
roofglass.surface_render_method='DITHERED'
lamp=pbr('ph_luminaire_diffuser','concrete_floor_02',2,.0,.03,tint=(1.7,1.7,1.6))
p=lamp.node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(.85,.91,1,1);p.inputs['Emission Strength'].default_value=2.0
joint=pbr('ph_rubber_gasket','asphalt_floor',2,.0,.12,tint=(.32,.34,.35))

# Replace all provisional material slots; no Blender-only procedural effect remains.
replace={'weathered_concrete':floor,'service_asphalt':asphalt,'industrial_wall':wall,'galvanized_roof':roof,'dark_structural_steel':steel,'roof_glazing':glass,'runway_white':lightpaint,'taxiway_yellow':paint,'rubber_traces':joint}
for o in collection.objects:
    if o.type=='MESH':
        for slot in o.material_slots:
            if slot.material and slot.material.name in replace:slot.material=replace[slot.material.name]

def unwrap(o):
    me=o.data;me.update();uv=me.uv_layers.active or me.uv_layers.new(name='metric_uv')
    for p in me.polygons:
        axis=max(range(3),key=lambda i:abs(p.normal[i]));axes=[i for i in range(3) if i!=axis]
        scale=me.materials[p.material_index].get('tile_metres',3.0)
        for li in p.loop_indices:
            co=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(co[axes[0]]/scale,co[axes[1]]/scale)
for o in collection.objects:
    if o.type=='MESH':unwrap(o)

def erase(o):
    for c in list(o.children):erase(c)
    bpy.data.objects.remove(o,do_unlink=True)
def empty(name,parent,loc=(0,0,0)):
    o=bpy.data.objects.new(name,None);collection.objects.link(o);o.parent=parent;o.location=loc;return o

class Batch:
    """One static mesh per building component, not thousands of scene objects."""
    def __init__(self): self.v=[];self.f=[];self.m=[];self.materials=[];self.smooth=[]
    def add(self,v,f,mat,smooth=False):
        k=len(self.v);self.v.extend(v)
        if mat not in self.materials:self.materials.append(mat)
        mi=self.materials.index(mat)
        self.f.extend([tuple(k+i for i in face) for face in f]);self.m.extend([mi]*len(f));self.smooth.extend([smooth]*len(f))
    def box(self,c,size,mat,rot=None):
        x,y,z=[s/2 for s in size]
        v=[(-x,-y,-z),(x,-y,-z),(x,y,-z),(-x,y,-z),(-x,-y,z),(x,-y,z),(x,y,z),(-x,y,z)]
        v=[tuple((rot@Vector(p) if rot else Vector(p))+Vector(c)) for p in v]
        self.add(v,[(3,2,1,0),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7),(4,5,6,7)],mat)
    def beam(self,a,b,w,mat,depth=None):
        delta=Vector(b)-Vector(a);self.box((Vector(a)+Vector(b))/2,(w,depth or w,delta.length),mat,delta.to_track_quat('Z','Y').to_matrix())
    def cylinder(self,a,b,r,mat,n=12,r2=None):
        delta=Vector(b)-Vector(a);R=delta.to_track_quat('Z','Y').to_matrix();v=[]
        for end,rr in [(a,r),(b,r if r2 is None else r2)]:
            v.extend([tuple(Vector(end)+R@Vector((rr*math.cos(i*math.tau/n),rr*math.sin(i*math.tau/n),0))) for i in range(n)])
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
        self.add(v,faces,mat,True)
    def mesh(self,name,parent,bevel=0):
        me=bpy.data.meshes.new(name);me.from_pydata(self.v,[],self.f);me.update()
        for m in self.materials:me.materials.append(m)
        for p,mi,smooth in zip(me.polygons,self.m,self.smooth):p.material_index=mi;p.use_smooth=smooth
        bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(me);bm.free()
        o=bpy.data.objects.new(name,me);collection.objects.link(o);o.parent=parent;unwrap(o)
        # Chamfer large simple components, not thousands of sub-pixel mullions/rungs.
        if bevel and len(me.polygons) <= 400:
            bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o
            mod=o.modifiers.new('edge_chamfers','BEVEL');mod.width=bevel;mod.segments=2
            bpy.ops.object.modifier_apply(modifier=mod.name)
        return o

def window(b,x,y,z,w,h,axis='front'):
    """Recessed glazing, gasket, four-sided frame and sub-mullions; metres."""
    tmp=Batch();tmp.box((0,0,0),(w,.10,h),glass)
    for xx in [-w/2,w/2]:tmp.box((xx,-.075,0),(.10,.18,h+.16),steel)
    for zz in [-h/2,h/2]:tmp.box((0,-.075,zz),(w+.16,.20,.12),steel)
    for xx in np.arange(-w/2+1.2,w/2,.0+1.2):tmp.box((float(xx),-.09,0),(.055,.13,h),steel)
    tmp.box((0,-.22,-h/2-.08),(w+.3,.6,.12),lightpaint)
    R=Matrix.Rotation(math.pi/2 if axis=='side' else -math.pi/2 if axis=='left' else 0,3,'Z')
    for mi,mat in enumerate(tmp.materials):
        faces=[f for f,m in zip(tmp.f,tmp.m) if m==mi];b.add([tuple(R@Vector(v)+Vector((x,y,z))) for v in tmp.v],faces,mat)

def personnel_door(b,x,y,z=0,axis='front'):
    temp=Batch();temp.box((0,0,1.18),(1.12,.12,2.36),door)
    for xx in [-.62,.62]:temp.box((xx,-.09,1.23),(.12,.20,2.46),steel)
    temp.box((0,-.09,2.43),(1.36,.20,.12),steel)
    temp.box((0,-.10,.04),(1.4,.35,.08),steel)
    temp.cylinder((.40,-.2,1.03),(.40,-.2,1.22),.026,steel)
    for zz in [.4,1.95]:temp.box((-.5,-.1,zz),(.11,.13,.13),steel)
    temp.box((0,-.09,1.83),(.42,.05,.3),glass)
    R=Matrix.Rotation(math.pi/2 if axis=='side' else 0,3,'Z')
    for mi,mat in enumerate(temp.materials):b.add([tuple(R@Vector(v)+Vector((x,y,z))) for v in temp.v],[f for f,m in zip(temp.f,temp.m) if mi==m],mat)

def louver(b,c,w,h,axis='front'):
    temp=Batch();temp.box((0,0,0),(w,.18,h),joint)
    for x in [-w/2,w/2]:temp.box((x,-.10,0),(.1,.25,h),steel)
    for z in np.arange(-h/2,h/2,.24):temp.box((0,-.13,float(z)),(w,.35,.08),steel,Matrix.Rotation(-.5,3,'X'))
    R=Matrix.Rotation(math.pi/2 if axis=='side' else 0,3,'Z')
    for mi,mat in enumerate(temp.materials):b.add([tuple(R@Vector(v)+Vector(c)) for v in temp.v],[f for f,m in zip(temp.f,temp.m) if mi==m],mat)

def ladder(b,x,y,bottom,top,cage=False):
    for xx in [x-.35,x+.35]:b.cylinder((xx,y,bottom),(xx,y,top+1.1),.035,steel)
    for z in np.arange(bottom+.25,top,.28):b.cylinder((x-.35,y,float(z)),(x+.35,y,float(z)),.02,steel,n=8)
    if cage:
        for z in np.arange(bottom+2,top,1.3):
            for i in range(12):
                a=i*math.pi/12;aa=(i+1)*math.pi/12;b.beam((x+.7*math.cos(a),y-.7*math.sin(a),float(z)),(x+.7*math.cos(aa),y-.7*math.sin(aa),float(z)),.035,steel)
        for a in [0,math.pi/4,math.pi/2,3*math.pi/4,math.pi]:b.beam((x+.7*math.cos(a),y-.7*math.sin(a),bottom+2),(x+.7*math.cos(a),y-.7*math.sin(a),top),.025,steel)

def railing(b,a,c):
    a,c=Vector(a),Vector(c);length=(c-a).length
    for z in [.55,1.1]:b.cylinder(a+Vector((0,0,z)),c+Vector((0,0,z)),.035,steel)
    for t in np.linspace(0,1,max(2,int(length/1.8)+1)):
        p=a.lerp(c,float(t));b.cylinder(p,p+Vector((0,0,1.1)),.04,steel)

def sign(name,text,parent,loc,size=1):
    curve=bpy.data.curves.new(name,'FONT');curve.body=text;curve.size=size;curve.extrude=.01;curve.align_x='CENTER'
    o=bpy.data.objects.new(name,curve);collection.objects.link(o);o.parent=parent;o.location=loc;o.rotation_euler=(math.pi/2,0,0);curve.materials.append(lightpaint)
    bpy.ops.object.select_all(action='DESELECT');o.select_set(True);bpy.context.view_layer.objects.active=o;bpy.ops.object.convert(target='MESH');unwrap(o)
    return o

def detail_hangar():
    h=bpy.data.objects['main_hangar']
    for o in list(h.children):erase(o)
    envelope=Batch();detail=Batch();frames=Batch()
    # Real side-wall openings, not glass painted onto an uninterrupted box.
    for side in [-1,1]:
        x=side*87
        for z,ht in [(2,4),(12.5,11),(24,6)]:envelope.box((x,0,z),(1.4,350,ht),wall if z==2 else cladding)
        for yc in np.arange(-162.5,175,25):
            for z in [5.5,19.5]:
                for offset in [-11.9,11.9]:envelope.box((x,float(yc+offset),z),(1.4,1.2,3),wall)
                window(frames,x+side*.78,float(yc),z,22.6,2.8,'side' if side>0 else 'left')
            detail.box((x+side*.83,float(yc-12.5),13.5),(.3,.4,27),steel)
        for y in [-155,-80,0,80,155]:
            detail.cylinder((x+side*1.1,y,.2),(x+side*1.1,y,27.3),.12,steel)
            detail.box((x+side*.9,y,.45),(.5,.6,.9),wall)
        detail.box((side*87.9,0,27.15),(.55,352,.5),steel)
    envelope.box((0,174.4,13.5),(172,1.2,27),cladding)
    for xc in [-58,0,58]:
        for y in [-176,176]:
            vv=[(xc-29,y,27),(xc+29,y,27),(xc,y,31)]
            envelope.add(vv,[(0,1,2) if y<0 else (2,1,0)],cladding)
    # Front shoulders retain the 72 m central clear opening.
    for x in [-61,61]:
        envelope.box((x,-174.4,13.5),(50,1.2,27),cladding)
        envelope.box((x,-175.1,1.4),(50,.3,2.8),wall)
        for dx in [-16,-8,0,8,16]:window(frames,x+dx,-175.18,24,6.8,2)
        personnel_door(detail,x+(-18 if x<0 else 18),-175.40)
    envelope.box((0,-174.4,24),(72,1.2,6),cladding)
    detail.box((0,-176,21.4),(174,1.5,.65),steel)
    for x in [-36,36]:detail.box((x,-175.65,10.5),(.5,1.1,21),steel)
    envelope.mesh('hangar_envelope',h,.035)
    # Skylights are actual roof apertures, with raised kerbs and subdivided panes.
    for bay,xc in enumerate([-58,0,58]):
        b=Batch();ys=sorted(set([-176,176]+[k+d for k in range(-145,150,35) for d in [-7,7]]));xs=[-29,-20,-4,0,4,20,29]
        for xa,xb in zip(xs,xs[1:]):
            for ya,yb in zip(ys,ys[1:]):
                is_glass=abs((xa+xb)/2) in [12] and any(k-7 < (ya+yb)/2 < k+7 for k in range(-145,150,35))
                vv=[(xc+x,y,31-abs(x)*4/29) for x,y in [(xa,ya),(xb,ya),(xb,yb),(xa,yb)]]
                b.add(vv,[(0,1,2,3)],roofglass if is_glass else roof)
                if is_glass:
                    for ix in [xa,xb]:frames.beam((xc+ix,ya,31-abs(ix)*4/29+.14),(xc+ix,yb,31-abs(ix)*4/29+.14),.22,steel)
                    for y in np.arange(ya,yb+.1,2):frames.beam((xc+xa,float(y),31-abs(xa)*4/29+.16),(xc+xb,float(y),31-abs(xb)*4/29+.16),.09,steel)
                    for x in np.arange(xa,xb+.1,2):frames.beam((xc+float(x),ya,31-abs(x)*4/29+.18),(xc+float(x),yb,31-abs(x)*4/29+.18),.06,steel)
        b.mesh('hangar_roof_bay_%02d'%bay,h)
        detail.box((xc,0,31.1),(.5,352,.22),steel)
        for y in [-158,-88,-18,52,122]:
            detail.box((xc,y,31.65),(1.6,1.6,1.2),steel);detail.box((xc,y,32.35),(2,2,.24),steel)
        # Eave purlins and support columns are visible through the entrance.
        for side in [-1,1]:
            xx=xc+side*28.5;detail.box((xx,0,26.5),(.4,348,.5),steel)
            for y in range(-170,175,34):
                detail.box((xx,y,12.4),(.36,.6,24.8),steel)
                detail.box((xx,y,.12),(.9,1.1,.24),steel)
        # User-supplied trusses retain their metric dimensions, repeated rather than stretched.
        source=bpy.data.objects['Interior_Trusses']
        shared=source.data.copy();shared.name='hangar_shared_truss_module_%02d'%bay;shared.materials.clear();shared.materials.append(steel)
        for p in shared.polygons:p.material_index=0
        for j,y in enumerate([-136,-68,0,68,136]):
            o=bpy.data.objects.new('hangar_truss_%02d_%02d'%(bay,j),shared);collection.objects.link(o);o.parent=h;o.location=(xc,y,10);unwrap(o)
        for y in range(-153,160,34):
            detail.box((xc,y,23.8),(2.8,.5,.2),steel);detail.box((xc,y,23.67),(2.6,.42,.06),lamp)
    frames.mesh('hangar_glazing_frames',h,.012)
    # Parked multi-leaf sliding doors stay autonomous and do not cap the entrance.
    for side in [-1,1]:
        b=Batch()
        for i in range(6):
            x=side*(39.3+i*6.2);b.box((x,-175.8-(i%2)*.14,10.5),(6.12,.28,21),door)
            for dx in [-3,3]:b.box((x+dx,-176.02,10.5),(.18,.22,21),steel)
            for z in [.2,7,14,20.8]:b.box((x,-176.02,z),(6.1,.22,.16),steel)
            b.box((x,-176.12,1.5),(.08,.12,.8),steel)
        b.mesh('hangar_sliding_door_'+('left' if side<0 else 'right'),h,.025)
    # Track rails, ducts, cabinets and a modest crane runway, without unnecessary clutter.
    for x in [-85,85]:
        detail.box((x,-175.6,2.3),(2.4,.8,4.6),door)
        louver(detail,(x,-176.06,3.2),1.8,1.5)
    for y in [-171,171]:
        for x in [-58,0,58]:detail.box((x,y,18),(52,.45,.65),paint)
    ladder(detail,82,-172,0,26,True)
    detail.mesh('hangar_structure_services',h,.025)
    sign('hangar_identification','HANGAR',h,(0,-175.12,24),1.5)
    # Human-readable maintenance lanes on the existing apron/floor; no duplicate floor mesh.
    b=Batch()
    for x in [-80,80]:b.box((x,0,.025),(.12,334,.008),paint)
    b.box((0,-178,.025),(72,.15,.008),paint)
    b.mesh('hangar_floor_safety_lines',h)
    print('HANGAR_CLOSEUP_READY')
