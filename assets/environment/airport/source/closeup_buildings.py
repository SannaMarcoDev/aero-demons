"""Building-by-building stages, execute in closeup_authoring.py's namespace."""
def arch(b,rout,rin,y0,y1,mat,steps=64):
    v=[]
    for y in [y0,y1]:
        for r in [rout,rin]:
            for j in range(steps+1):
                a=j*math.pi/steps;v.append((r*math.cos(a),y,2+.70*r*math.sin(a)))
    n=steps+1;f=[]
    for j in range(steps):
        f.extend([(j,j+1,2*n+j+1,2*n+j),(n+j,3*n+j,3*n+j+1,n+j+1),(j,n+j,n+j+1,j+1),(2*n+j,2*n+j+1,3*n+j+1,3*n+j)])
    f.extend([(0,2*n,3*n,n),(n-1,2*n-1,4*n-1,3*n-1)])
    b.add(v,f,mat,True)

def detail_shelters():
    parents=[bpy.data.objects['arched_shelter_%02d'%i] for i in range(1,5)]
    for p in parents:
        for o in list(p.children):erase(o)
    master=parents[0];b=Batch();arch(b,19,18.45,-23,23,roof)
    b.mesh('shelter_skin_01',master)
    b=Batch();arch(b,19.5,18.25,-24,-22.2,wall);arch(b,19.18,18.6,22.1,23.3,steel)
    for side in [-1,1]:
        b.box((side*18.9,0,1),(.95,46,2),wall)
        b.box((side*18.85,-23.1,1),(1.4,1.8,2),wall)
    # Rear enclosure follows the arch; concrete shell does not cap the front.
    v=[(-18.45,22.95,0),(18.45,22.95,0)]+[(18.45*math.cos(j*math.pi/64),22.95,2+.7*18.45*math.sin(j*math.pi/64)) for j in range(65)]
    b.add(v,[tuple(range(len(v)))],wall)
    b.mesh('shelter_portal_and_back_01',master,.025)
    b=Batch()
    for y in np.arange(-21,23,5.5):arch(b,18.45,18.25,float(y)-.08,float(y)+.08,steel,32)
    # Standing seams are thin geometry over the outer skin, not fake thick ribs.
    for y in np.arange(-22,23,3.7):arch(b,19.035,19.0,float(y)-.028,float(y)+.028,steel,64)
    for side in [-1,1]:
        b.cylinder((side*17.9,-20,2.8),(side*17.9,20,2.8),.045,steel)
        b.box((side*17.95,-18,1.9),(.28,1,1.2),door)
        for yy in [-25.4,-27]:
            b.cylinder((side*18,yy,0),(side*18,yy,1.25),.10,paint,16)
            b.cylinder((side*18,yy,.25),(side*18,yy,.48),.105,joint,16)
    for y in [-15,0,15]:
        b.box((0,y,14.25),(1.6,.32,.18),steel);b.box((0,y,14.13),(1.45,.26,.06),lamp)
    personnel_door(b,12,22.80)
    louver(b,(-10,22.76,3.5),2.2,1.7)
    # Flush drainage grate in front of the shelter.
    b.box((0,-25,.016),(35,.5,.022),joint)
    for x in np.arange(-17.3,17.4,.30):b.box((float(x),-25,.035),(.055,.48,.025),steel)
    for x in [-17,17]:b.box((x,-7,.025),(.10,36,.01),paint)
    b.mesh('shelter_fittings_01',master,.008)
    # Linked geometry, separate shelter roots and independent future replaceability.
    prototypes=list(master.children)
    for idx,p in enumerate(parents[1:],2):
        for source in prototypes:
            o=bpy.data.objects.new(source.name[:-2]+'%02d'%idx,source.data);collection.objects.link(o);o.parent=p
    for idx,p in enumerate(parents,1):sign('shelter_service_label_%02d'%idx,'CLEAR',p,(0,-24.04,14.9),.32)
    print('FOUR_SHELTERS_CLOSEUP_READY')

def hvac(b,x,y,z,w=4,d=6):
    b.box((x,y,z+1),(w,d,2),door)
    b.box((x,y,z+.1),(w+.4,d+.4,.2),steel)
    louver(b,(x,y-d/2-.1,z+1),w-.4,1.5)
    for dx in [-w/4,w/4]:
        b.cylinder((x+dx,y,z+2),(x+dx,y,z+2.25),w*.18,steel,20)
        b.cylinder((x+dx,y,z+2.26),(x+dx,y,z+2.28),w*.14,joint,20)
        for a in np.arange(0,math.pi,.45):b.beam((x+dx-w*.13*math.cos(a),y-w*.13*math.sin(a),z+2.30),(x+dx+w*.13*math.cos(a),y+w*.13*math.sin(a),z+2.30),.04,steel)

def detail_technical():
    t=bpy.data.objects['technical_complex']
    for o in list(t.children):erase(o)
    dims=[(-40,0,42,72,64),(15,0,54,82,73),(50,12,20,52,58),(-20,50,100,30,13)]
    for idx,(x,y,w,d,hgt) in enumerate(dims):
        b=Batch();b.box((x,y,hgt/2),(w,d,hgt),wall)
        b.mesh('technical_volume_%02d'%idx,t,.08)
        b=Batch()
        # Concrete precast piers, recessed windows and narrow spandrel bands.
        if idx<3:
            for z in np.arange(6,hgt-3,5.5):
                for xx in np.arange(x-w/2+4,x+w/2-2,5):
                    window(b,float(xx),y-d/2-.08,float(z),3.1,2.2)
                for yy in np.arange(y-d/2+4,y+d/2-2,6):
                    window(b,x+w/2+.08,float(yy),float(z),3.6,2.2,'side')
                b.box((x,y-d/2-.12,float(z)-1.45),(w+.2,.28,.20),steel)
            for xx in np.arange(x-w/2+1,x+w/2,5):b.box((float(xx),y-d/2-.20,hgt/2),(.3,.35,hgt),lightpaint)
        for side in [-1,1]:
            b.box((x+side*(w/2-.2),y,hgt+.65),(.4,d,1.3),wall)
            b.box((x,y+side*(d/2-.2),hgt+.65),(w,.4,1.3),wall)
            b.box((x+side*(w/2-.2),y,hgt+1.34),(.6,d+.2,.12),steel)
            b.box((x,y+side*(d/2-.2),hgt+1.34),(w+.2,.6,.12),steel)
        b.box((x,y,hgt+.05),(w-.8,d-.8,.10),roof)
        if idx<3:
            for xx in [-w/4,w/4]:hvac(b,x+xx,y,hgt+.12)
            for yy in [-d/4,d/4]:
                b.cylinder((x,y+yy,hgt),(x,y+yy,hgt+3.5),.45,steel,16)
                b.cylinder((x,y+yy,hgt+3.5),(x,y+yy,hgt+3.7),.7,steel,16)
            louver(b,(x,y-d/2-.1,2.8),w*.35,2.7)
        else:
            for xx in np.arange(x-w/2+8,x+w/2,12):window(b,float(xx),y+d/2+.1,6,7,2.6)
        personnel_door(b,x-w/2+2,y-d/2-.3)
        for side in [-1,1]:b.cylinder((x+side*(w/2-.6),y-d/2-.5,.2),(x+side*(w/2-.6),y-d/2-.5,hgt),.10,steel)
        b.mesh('technical_facade_%02d'%idx,t,.018)
    b=Batch();ladder(b,-58,-37,0,65.4,True)
    for z in [16,32,48,64]:
        b.box((-58,-38.1,z),(3,2,.18),steel)
        railing(b,(-59.5,-39,z+.1),(-56.5,-39,z+.1))
    b.mesh('technical_access_ladder',t,.008)
    sign('technical_identification','TECHNICAL',t,(-40,-36.4,3.8),.48)
    print('TECHNICAL_COMPLEX_CLOSEUP_READY')

def detail_services():
    for name in ['south_operations','north_workshop','radar_equipment']:
        old=bpy.data.objects[name];loc=old.location.copy();loc.z=0
        w,d,hgt={'south_operations':(85,45,12),'north_workshop':(75,40,11),'radar_equipment':(22,24,10)}[name]
        # Original neutral volumes become roots with coherent base pivots.
        for extra in list(groups['details'].children):
            if extra.name.startswith(name):erase(extra)
        erase(old);parent=empty(name,groups['buildings'],loc)
        b=Batch();b.box((0,0,hgt/2),(w,d,hgt),wall);b.mesh(name+'_envelope',parent,.06)
        b=Batch()
        for sy in [-1,1]:
            b.box((0,sy*(d/2-.2),hgt+.5),(w,.4,1),wall)
            b.box((0,sy*(d/2-.2),hgt+1.05),(w+.2,.65,.12),steel)
        for sx in [-1,1]:
            b.box((sx*(w/2-.2),0,hgt+.5),(.4,d,1),wall)
            b.box((sx*(w/2-.2),0,hgt+1.05),(.65,d+.2,.12),steel)
            b.cylinder((sx*(w/2-.4),-d/2-.35,.2),(sx*(w/2-.4),-d/2-.35,hgt+.4),.09,steel)
        b.box((0,0,hgt+.04),(w-.8,d-.8,.08),roof)
        if name=='south_operations':
            for z in [3.9,8.4]:
                for x in np.arange(-w/2+4,w/2-2,5):
                    if abs(x)>6:window(b,float(x),-d/2-.10,z,3,2)
                for y in np.arange(-d/2+4,d/2-2,5):window(b,w/2+.1,float(y),z,3,2,'side')
            for x in [-1,1]:personnel_door(b,x*.65,-d/2-.15)
            b.box((0,-d/2-1.4,3.3),(7,3,.25),steel)
            for x in [-3,3]:b.cylinder((x,-d/2-2.4,0),(x,-d/2-2.4,3.3),.07,steel)
            b.box((0,-d/2-.8,.08),(7,2,.16),floor)
            for x in [-w/4,w/4]:hvac(b,x,0,hgt+.1)
            sign(name+'_sign','OPERATIONS',parent,(0,-d/2-.2,5.2),.55)
        elif name=='north_workshop':
            for x in [-23,0,23]:
                b.box((x,-d/2-.12,3.6),(12,.20,7.2),door)
                for xx in [x-6.1,x+6.1]:b.box((xx,-d/2-.24,3.7),(.22,.35,7.4),steel)
                b.box((x,-d/2-.23,7.45),(12.5,.4,.25),steel)
                for z in np.arange(.1,7.3,.45):b.box((x,-d/2-.25,float(z)),(12,.06,.055),steel)
                window(b,x,-d/2-.16,9.3,12,1.4)
            personnel_door(b,34,-d/2-.15)
            for y in [-12,0,12]:window(b,w/2+.1,y,6,6,2.2,'side')
            for x in [-20,20]:hvac(b,x,0,hgt+.1,3,4)
            sign(name+'_sign','WORKSHOP',parent,(0,-d/2-.3,10.3),.40)
        else:
            personnel_door(b,-5,-d/2-.16)
            for x in [0,6]:louver(b,(x,-d/2-.15,3),3.7,4)
            for y in [-6,3]:louver(b,(w/2+.1,y,3.6),5,3,'side')
            b.box((0,0,hgt+.12),(12,12,.24),floor)
            sign(name+'_sign','EQUIPMENT',parent,(-5,-d/2-.3,3.2),.26)
        ladder(b,-w/2+2,-d/2-.6,0,hgt+1.1,True)
        b.mesh(name+'_facade_and_services',parent,.02)
    print('OPERATIONS_WORKSHOP_EQUIPMENT_CLOSEUP_READY')

def detail_towers():
    for idx,height in enumerate([40,32]):
        t=bpy.data.objects['antenna_tower_%02d'%idx]
        for o in list(t.children):erase(o)
        # First mast is roof-mounted on the equipment block, not buried in it.
        t.location.z=10.24 if idx==0 else 0
        b=Batch()
        for dx,dy in [(-3,-3),(3,-3),(3,3),(-3,3)]:
            b.box((dx,dy,.2),(1.2,1.2,.4),wall)
            b.box((dx,dy,.45),(.8,.8,.10),steel)
            b.cylinder((dx,dy,.45),(dx*.7,dy*.7,height),.16,steel,12)
            for bx,by in [(-.27,-.27),(-.27,.27),(.27,-.27),(.27,.27)]:b.cylinder((dx+bx,dy+by,.5),(dx+bx,dy+by,.65),.035,steel,6)
        for z in np.arange(1,height-3,4):
            z2=min(float(z)+4,height);factor=1-.3*float(z)/height;factor2=1-.3*z2/height
            for a,c in [((-3,-3),(3,-3)),((3,-3),(3,3)),((3,3),(-3,3)),((-3,3),(-3,-3))]:
                for start,end in [(a,c),(c,a)]:b.cylinder((start[0]*factor,start[1]*factor,float(z)),(end[0]*factor2,end[1]*factor2,z2),.06,steel,8)
        b.box((0,0,height),(9,9,.22),steel)
        for xy in np.arange(-4.4,4.5,.3):
            b.box((float(xy),0,height+.14),(.04,8.8,.035),lightpaint)
            b.box((0,float(xy),height+.15),(8.8,.04,.035),lightpaint)
        for a,c in [((-4.4,-4.4),(4.4,-4.4)),((4.4,-4.4),(4.4,4.4)),((4.4,4.4),(-4.4,4.4)),((-4.4,4.4),(-4.4,-4.4))]:railing(b,(*a,height+.15),(*c,height+.15))
        ladder(b,0,-3.1,.5,height+.15,True)
        b.box((0,0,height+1.1),(1.8,1.8,2),door)
        b.cylinder((0,0,height+2),(0,0,height+4.4),.18,steel,16)
        b.box((0,0,height+4.4),(5,.45,2),door)
        for x in np.arange(-2.3,2.4,.35):b.box((float(x),-.26,height+4.4),(.05,.1,1.9),steel)
        b.cylinder((2.5,2.5,height),(2.5,2.5,height+5.5),.035,steel,8)
        b.mesh('antenna_structure_%02d'%idx,t,.008)
    print('TWO_TOWERS_CLOSEUP_READY')

def detail_radome():
    old=bpy.data.objects.get('radome') or bpy.data.objects['radome_shell'];loc=old.location.copy();erase(old)
    parent=empty('radome',groups['buildings'],loc)
    b=Batch();v=[];segments=96;rings=24
    # Smooth closed polar fan; avoids zero-area quads at the apex.
    for j in range(rings):
        a=(math.pi/2)*j/rings
        for i in range(segments):
            t=i*math.tau/segments;v.append((51*math.cos(a)*math.cos(t),51*math.cos(a)*math.sin(t),1.2+31*math.sin(a)))
    v.append((0,0,32.2));faces=[]
    for j in range(rings-1):
        for i in range(segments):faces.append((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i))
    for i in range(segments):faces.append(((rings-1)*segments+i,(rings-1)*segments+(i+1)%segments,len(v)-1))
    b.add(v,faces,lightpaint,True);shell=b.mesh('radome_shell',parent)
    uv=shell.data.uv_layers.active
    for p in shell.data.polygons:
        us=[]
        for li in p.loop_indices:
            co=shell.data.vertices[shell.data.loops[li].vertex_index].co;us.append(math.atan2(co.y,co.x)/math.tau)
        seam=max(us)-min(us)>.5
        for li,u in zip(p.loop_indices,us):
            co=shell.data.vertices[shell.data.loops[li].vertex_index].co
            uv.data[li].uv=((u+(1 if seam and u<0 else 0))*math.tau*51/3,math.asin(max(-1,min(1,(co.z-1.2)/31)))*31/3)
    b=Batch()
    # Skirt and broad panel seams, restrained rather than a sci-fi geodesic cage.
    for i in range(96):
        a=i*math.tau/96;c=(i+1)*math.tau/96
        b.add([(52*math.cos(a),52*math.sin(a),0),(52*math.cos(c),52*math.sin(c),0),(52*math.cos(c),52*math.sin(c),1.3),(52*math.cos(a),52*math.sin(a),1.3)],[(0,1,2,3)],wall)
    for j in range(1,12):
        a=j*math.pi/24
        for i in range(96):
            t=i*math.tau/96;tt=(i+1)*math.tau/96
            b.beam((51.025*math.cos(a)*math.cos(t),51.025*math.cos(a)*math.sin(t),1.225+31*math.sin(a)),(51.025*math.cos(a)*math.cos(tt),51.025*math.cos(a)*math.sin(tt),1.225+31*math.sin(a)),.055,steel)
    for i in range(48):
        t=i*math.tau/48
        for j in range(23):
            a=j*math.pi/48;aa=(j+1)*math.pi/48
            b.beam((51.025*math.cos(a)*math.cos(t),51.025*math.cos(a)*math.sin(t),1.225+31*math.sin(a)),(51.025*math.cos(aa)*math.cos(t),51.025*math.cos(aa)*math.sin(t),1.225+31*math.sin(aa)),.055,steel)
    b.box((0,-51.5,2),(8,5,4),wall)
    b.box((0,-51.5,4.12),(8.5,5.5,.24),roof)
    personnel_door(b,0,-54.1)
    for x in [-2.5,2.5]:louver(b,(x,-54.08,2.6),1.4,1.4)
    for x in [-4,4]:b.cylinder((x,-54,0),(x,-54,1.3),.09,paint,12)
    b.mesh('radome_skirt_panels_and_access',parent,.012)
    sign('radome_service_label','RADOME',parent,(0,-54.18,3),.32)
    print('RADOME_CLOSEUP_READY')
