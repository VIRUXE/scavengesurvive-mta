"""Glazes the window openings of the SA-MP house shells (lshouse1-4, lvhouse1-4, sfhouse1-4), which ship as bare
holes. Run inside Blender with the DragonFF addon enabled, after tools/extract_samp_models.py wrote the originals:

    blender -b --python tools/glaze_house_windows.py -- SRC_DIR OUT_DIR TEXTURE_DIR lshouse1 lshouse2 ...

SRC_DIR holds the extracted DFFs, TEXTURE_DIR the house_window.PNG written by tools/make_house_window.py plus the four curtain PNGs named in
CURTAINS, decoded from the game's TXDs (gta-scout's TXDReader). Each opening is
a planar rectangular boundary loop in the wall, under 1.85 m tall (taller ones are doors, which the maps place as
door objects); it gets a recessed translucent pane textured house_window in a modelled frame, and a pair of curtains. The shells' triangles all say material 0 and the real
split lives in the BinMesh chunk, which DragonFF ignores, so it is copied into the triangle records first.
models/client/main.lua imports files/house_window.txd into the shells' vanilla dictionaries.
"""
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

bpy.ops.preferences.addon_enable(module="DragonFF")
from DragonFF.gtaLib.dff import dff  # noqa: E402


def apply_binmesh_materials(src, dst):
    b=bytearray(open(src,'rb').read())
    d=dff(); d.load_file(src)
    g=d.clumps[0].geometry_list[0] if getattr(d,'clumps',None) else d.geometry_list[0]
    i=bytes(b).find(struct.pack('<I',0x50E)); 
    # verify chunk header
    while i>=0 and struct.unpack_from('<I',b,i+4)[0]>len(b): i=bytes(b).find(struct.pack('<I',0x50E),i+1)
    flag,nmesh,tot=struct.unpack_from('<III',b,i+12); o=i+24
    mp={}
    if flag!=0: return None
    for k in range(nmesh):
        cnt,mat=struct.unpack_from('<II',b,o); o+=8
        idx=struct.unpack_from('<%dI'%cnt,b,o); o+=cnt*4
        for t in range(0,cnt,3): mp[frozenset(idx[t:t+3])]=mat
    t0=g.triangles[0]; key=struct.pack('<4H',t0.b,t0.a,t0.material,t0.c)
    p=bytes(b).find(key)
    n=len(g.triangles); bad=0
    for t in range(n):
        b_,a_,m_,c_=struct.unpack_from('<4H',b,p+t*8)
        mat=mp.get(frozenset((a_,b_,c_)))
        if mat is None: bad+=1;continue
        struct.pack_into('<4H',b,p+t*8,b_,a_,mat,c_)
    open(dst,'wb').write(b); return n,bad


a = sys.argv[sys.argv.index("--") + 1:]
src, dst, texdir, names = a[0], a[1], a[2], a[3:]
GLASS = 'house_window'
CURTAINS = ('ah_curtains1', 'AH_greencurtain', 'CJ_H_CURTAIN1', 'curtain_sink2')  # vanilla, in house_window.txd
def loops_of(bm):
    seen=set(); out=[]
    for e in bm.edges:
        if not e.is_boundary or e in seen: continue
        st=[e]; comp=[]
        while st:
            x=st.pop()
            if x in seen: continue
            seen.add(x); comp.append(x)
            for v in x.verts:
                for y in v.link_edges:
                    if y.is_boundary and y not in seen: st.append(y)
        out.append(comp)
    return out
def ordered(comp):
    es=list(comp); v0=es[0].verts[0]; order=[v0]; cur=v0; used=set()
    while len(order)<len(es):
        for e in cur.link_edges:
            if e in comp and e not in used:
                used.add(e); cur=e.other_vert(cur); order.append(cur); break
        else: return None
    return order
for n in names:
    bpy.ops.wm.read_factory_settings(use_empty=True); bpy.ops.preferences.addon_enable(module="DragonFF")
    os.makedirs(dst, exist_ok=True)
    tmp = f"{dst}/{n}.materials.dff"
    apply_binmesh_materials(f"{src}/{n}.dff", tmp)
    bpy.ops.import_scene.dff(filepath=tmp)
    os.remove(tmp)
    o=[o for o in bpy.data.objects if o.type=='MESH'][0]; me=o.data
    # detection on a welded copy
    det=bmesh.new(); det.from_mesh(me); bmesh.ops.remove_doubles(det,verts=det.verts,dist=1e-4)
    wins=[]
    allv=[v.co for v in det.verts]; ctr=sum(allv,Vector())/len(allv)
    for comp in loops_of(det):
        if len(comp)!=4: continue
        vs=ordered(comp)
        if not vs or len(vs)!=4: continue
        P=[v.co.copy() for v in vs]
        n_=(P[1]-P[0]).cross(P[2]-P[1]); 
        if n_.length<1e-6: continue
        n_.normalize()
        if abs(n_.z)>0.2: continue
        if max(abs((p-P[0]).dot(n_)) for p in P)>0.02: continue
        e0,e1=(P[1]-P[0]),(P[2]-P[1])
        if abs(e0.dot(e1))>0.05*e0.length*e1.length: continue
        zs=[p.z for p in P]; h=max(zs)-min(zs)
        w=max((e0 if abs(e0.z)<abs(e1.z) else e1).length,0)
        if h<0.4 or w<0.4 or h>=1.85 or w>5.0: continue
        # outward = normal of the single face next to the loop
        out=n_.copy()
        cen=sum(P,Vector())/4
        if (cen-ctr).dot(out)<0: out=-out
        wins.append((P,out))
    print("WINDOWS",n,len(wins),[ (round(max(p.z for p in P)-min(p.z for p in P),2)) for P,_ in wins])
    # material
    base=me.materials[0]; gm=base.copy(); gm.name=GLASS
    gm['dff']=dict(base['dff']) if 'dff' in base.keys() else {}
    try: gm.dff.tex_name=GLASS
    except Exception as ex: print("dffprop",ex)
    img=bpy.data.images.load(f"{texdir}/{GLASS}.PNG"); img.name=GLASS+'.PNG'
    for nd in gm.node_tree.nodes:
        if nd.type=='TEX_IMAGE': nd.image=img; nd.label=GLASS
    me.materials.append(gm); mi=len(me.materials)-1
    cname=CURTAINS[sum(map(ord,n))%len(CURTAINS)]  # one curtain per house
    cm=base.copy(); cm.name=cname
    cm['dff']=dict(base['dff']) if 'dff' in base.keys() else {}
    try: cm.dff.tex_name=cname
    except Exception as ex: print("dffprop",ex)
    cimg=bpy.data.images.load(f"{texdir}/{cname}.PNG"); cimg.name=cname+'.PNG'
    for nd in cm.node_tree.nodes:
        if nd.type=='TEX_IMAGE': nd.image=cimg; nd.label=cname
    me.materials.append(cm); ci=len(me.materials)-1
    bm=bmesh.new(); bm.from_mesh(me)
    uv=bm.loops.layers.uv.active; col=bm.loops.layers.color.active if bm.loops.layers.color else None
    FRAME_UV=(0.03,0.5)  # opaque frame pixels of house_window
    def box(bm,c,h_axis,outn,su,sv,sn):
        """Axis-aligned box centred at c, su wide along the wall, sv tall, sn deep along the outward normal."""
        basis=Matrix((h_axis*su,Vector((0,0,sv)),outn*sn)).transposed()  # columns: along the wall, up, outward
        m=Matrix.Translation(c)@basis.to_4x4()
        r=bmesh.ops.create_cube(bm,size=1.0,matrix=m,calc_uvs=False)
        fs={f for v in r['verts'] for f in v.link_faces}
        bmesh.ops.recalc_face_normals(bm,faces=list(fs))
        for f in fs:
            f.material_index=mi
            for l in f.loops:
                l[uv].uv=FRAME_UV
                if col: l[col]=(1,1,1,1)
    def panel(bm,pts,uvs,outn):
        """A curtain face, visible from both sides."""
        for flip in (False,True):
            vv=[bm.verts.new(p) for p in pts]; f=bm.faces.new(vv); f.material_index=ci
            if (f.normal.dot(outn)>0)==flip: bmesh.ops.reverse_faces(bm,faces=[f])
            for l in f.loops:
                u,v=uvs[vv.index(l.vert)]; l[uv].uv=(1-u if flip else u,v)
                if col: l[col]=(1,1,1,1)
    for P,outn in wins:
        h_axis=Vector((-outn.y,outn.x,0)).normalized()
        us=[p.dot(h_axis) for p in P]; zs=[p.z for p in P]
        u0,u1,z0,z1=min(us),max(us),min(zs),max(zs)
        w,hh=u1-u0,z1-z0
        ref=P[0]; uc=(u0+u1)/2; zc=(z0+z1)/2
        def at(u,z,n=0.0): return h_axis*(u-ref.dot(h_axis))+Vector((ref.x,ref.y,z))+outn*n
        T,D=0.07,0.07  # frame bar width, frame depth (from 0.03 outside the wall to 0.04 inside)
        # frame: four bars, each overlapping the wall edge by a little
        box(bm,at(uc,z1-T/2,-0.005),h_axis,outn,w,T,D)
        box(bm,at(uc,z0+T/2,-0.005),h_axis,outn,w,T,D)
        box(bm,at(u0+T/2,zc,-0.005),h_axis,outn,T,hh-2*T,D)
        box(bm,at(u1-T/2,zc,-0.005),h_axis,outn,T,hh-2*T,D)
        # mullions: thinner, set back with the glass
        if w>1.1: box(bm,at(uc,zc,-0.02),h_axis,outn,0.035,hh-2*T,0.04)
        if hh>1.0: box(bm,at(uc,zc,-0.02),h_axis,outn,w-2*T,0.035,0.04)
        # sill below, head trim above, standing proud of the wall
        box(bm,at(uc,z0-0.03,0.04),h_axis,outn,w+0.18,0.06,0.16)
        box(bm,at(uc,z1+0.025,0.015),h_axis,outn,w+0.12,0.05,0.07)
        # curtains: a gathered panel at each side, hung from the head and ending above the sill
        if hh>0.7:
            top,bot=z1-T-0.01,z0+T+0.1
            pw=0.3*(w-2*T)
            for a,b in ((u0+T,u0+T+pw),(u1-T-pw,u1-T)):
                m_=(a+b)/2
                for ua,ub,na,nb,ta,tb in ((a,m_,-0.08,-0.14,0.0,0.5),(m_,b,-0.14,-0.08,0.5,1.0)):
                    panel(bm,[at(ua,bot,na),at(ub,bot,nb),at(ub,top,nb),at(ua,top,na)],[(ta,0.0),(tb,0.0),(tb,1.0),(ta,1.0)],outn)
        # glass, recessed behind the frame and visible from both sides
        gu0,gu1,gz0,gz1=u0+T,u1-T,z0+T,z1-T
        for flip in (False,True):
            vv=[bm.verts.new(at(gu,gz,-0.03)) for gu,gz in ((gu0,gz0),(gu1,gz0),(gu1,gz1),(gu0,gz1))]
            f=bm.faces.new(vv); f.material_index=mi
            if (f.normal.dot(outn)>0)==flip: bmesh.ops.reverse_faces(bm,faces=[f])
            for l in f.loops:
                i=vv.index(l.vert); u=(0.12,0.88,0.88,0.12)[i]; v=(0.12,0.12,0.88,0.88)[i]
                l[uv].uv=(1-u if flip else u,v)
                if col: l[col]=(1,1,1,1)
    bm.to_mesh(me); bm.free()
    os.makedirs(dst,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    r=bpy.ops.export_dff.scene(filepath=f"{dst}/{n}.dff",export_coll=False,only_selected=False,export_version='0x36003')
    print("EXPORT",n,r)
