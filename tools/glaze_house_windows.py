"""Glazes the window openings of the SA-MP house shells (lshouse1-4, lvhouse1-4, sfhouse1-4), which ship as bare
holes. Run inside Blender with the DragonFF addon enabled, after tools/extract_samp_models.py wrote the originals:

    blender -b --python tools/glaze_house_windows.py -- SRC_DIR OUT_DIR TEXTURE_DIR lshouse1 lshouse2 ...

SRC_DIR holds the extracted DFFs, TEXTURE_DIR the house_window.PNG written by tools/make_house_window.py. Each opening is
a planar rectangular boundary loop in the wall, under 1.85 m tall (taller ones are doors, which the maps place as
door objects); it gets a two-sided translucent pane textured house_window. The shells' triangles all say material 0 and the real
split lives in the BinMesh chunk, which DragonFF ignores, so it is copied into the triangle records first.
models/client/main.lua imports files/house_window.txd into the shells' vanilla dictionaries.
"""
import os
import struct
import sys

import bmesh
import bpy
from mathutils import Vector

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
    bm=bmesh.new(); bm.from_mesh(me)
    uv=bm.loops.layers.uv.active; col=bm.loops.layers.color.active if bm.loops.layers.color else None
    for P,outn in wins:
        h_axis=Vector((-outn.y,outn.x,0)).normalized()
        us=[p.dot(h_axis) for p in P]; zs=[p.z for p in P]
        u0,u1,z0,z1=min(us),max(us),min(zs),max(zs)
        for flip in (False,True):
            vv=[bm.verts.new(p+outn*(0.005 if not flip else -0.005)) for p in P]
            try: f=bm.faces.new(vv)
            except ValueError: continue
            f.material_index=mi
            if f.normal.dot(outn)<0 != flip: f.normal_flip()
            if (f.normal.dot(outn)>0)==flip: f.normal_flip()
            for l in f.loops:
                p=l.vert.co; u=(p.dot(h_axis)-u0)/(u1-u0); v=(p.z-z0)/(z1-z0)
                if flip: u=1-u
                l[uv].uv=(u,v)
                if col: l[col]=(1,1,1,1)
    bm.to_mesh(me); bm.free()
    os.makedirs(dst,exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    r=bpy.ops.export_dff.scene(filepath=f"{dst}/{n}.dff",export_coll=False,only_selected=False,export_version='0x36003')
    print("EXPORT",n,r)
