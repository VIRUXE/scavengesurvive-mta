# exec'd in a live Blender (through the MCP's execute_blender_code) before transplant.py, tp_strip.py, tp3.py and
# tp_tex.py: paths, the skin loader, the hat cut (cut3), ICP alignment, previews, reference sampling and the twin
# exporter, all published in bpy.app.driver_namespace (`ns`), which the other scripts call through.
# Set SS_HATLESS_WORK to the folder fetch_peds.py filled (peds/ and list.txt); exports land in <work>/export and
# review renders in <work>/renders. See README.md.
import json
import math
import os
import sys

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

REPO = os.environ.get("SS_REPO", r"C:\dev\gta\sa\samp\scavengesurvive-mta")
WORK = os.environ.get("SS_HATLESS_WORK", os.path.join(os.environ.get("TEMP", "."), "hatless-work"))
if REPO not in sys.path:
    sys.path.insert(0, REPO)

import tools.extract_ped_models as EP  # noqa: E402
import tools.hatless_rebuild as HR  # noqa: E402
from tools import hatless_proj as hp  # noqa: E402

ns = bpy.app.driver_namespace
PEDS = os.path.join(WORK, "peds")
DON = WORK
OUTDIR = os.path.join(WORK, "export")
OUTR = os.path.join(WORK, "renders")
for d in (OUTDIR, OUTR):
    os.makedirs(d, exist_ok=True)
calib = json.load(open(os.path.join(REPO, "tools", "data", "hatless_calib.json")))
VIEWS = [("f", 0, 8), ("fl", 45, 8), ("l", 90, 8), ("bl", 135, 12), ("b", 180, 12), ("br", 225, 12), ("r", 270, 8), ("fr", 315, 8), ("top", 0, 78), ("low", 20, -30)]
if bpy.data.scenes.get("hatless") is None:
    bpy.data.scenes.new("hatless")

def head_groups(obj, arm):
    head = next(b for b in arm.data.bones if b.name.strip() == "Head")
    names = {b.name.strip() for b in [head] + list(head.children_recursive)}
    return {v.index for v in obj.vertex_groups if v.name.strip() in names}


def head_weight(v, groups):
    return sum(x.weight for x in v.groups if x.group in groups)


def target_G():
    src = bpy.data.objects["mesh"]; arm = bpy.data.objects[ns["arm_name"]]
    return ns["head_groups"](src, arm)


def load_skin(skin):
    name, tex = EP.HEADGEAR[skin][0], EP.HEADGEAR[skin][1]
    sc = bpy.data.scenes.get("hatless"); bpy.context.window.scene = sc
    for o in list(sc.objects):
        if not o.name.startswith(("cmp_", "keep_")): bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0: bpy.data.meshes.remove(m)
    if tex != name and not os.path.exists(os.path.join(PEDS, name + ".txd")):
        import shutil; shutil.copy(os.path.join(PEDS, tex + ".txd"), os.path.join(PEDS, name + ".txd"))
    before = set(sc.objects)
    bpy.ops.import_scene.dff(filepath=os.path.join(PEDS, name + ".dff"), directory=PEDS, files=[{"name": name + ".dff"}, {"name": tex + ".txd"}], load_images=True, remove_doubles=False, txd_pack=True, txd_apply_to_objects=True)
    new = [o for o in sc.objects if o not in before]
    src = max((o for o in new if o.type == "MESH"), key=lambda o: len(o.vertex_groups))
    src.name = "mesh"
    arm = next(o for o in new if o.type == "ARMATURE")
    head = next(b for b in arm.data.bones if b.name.strip() == "Head")
    tbm = (arm.matrix_world @ head.matrix_local).inverted() @ src.matrix_world
    ns.update(tb=np.array(tbm), tbm=tbm, g=next(v for v in src.vertex_groups if v.name.strip() == "Head").index, skin=skin, name=name, tex=tex, arm_name=arm.name)
    atlas = max((i for i in bpy.data.images if i.name.upper().startswith(tex.upper() + ".TXD")), key=lambda i: i.size[0] * i.size[1])
    ns["atlas"] = atlas.name
    for o in new: o.hide_set(True)
    return name, tex, atlas.size[:]


def make_work():
    sc = bpy.context.scene
    src = bpy.data.objects["mesh"]
    old = bpy.data.objects.get("work")
    if old: bpy.data.objects.remove(old, do_unlink=True)
    work = src.copy(); work.data = src.data.copy(); work.name = "work"; work.data.name = "work"
    sc.collection.objects.link(work)
    for m in list(work.modifiers): work.modifiers.remove(m)
    work.parent = None
    work.matrix_world = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Rotation(-math.pi / 2, 4, "Y") @ src.matrix_world
    # own copies of the materials, so the twin's texture names never touch the original ped
    for i, m in enumerate(work.data.materials):
        work.data.materials[i] = m.copy()
    return work


def cut3(skin, extra_blocks=(), keep_blocks=()):
    """cut2 plus protection of the face under the brow (mouth, lips, chin) from the atlas-block rule"""
    work = ns["make_work"](); tb = ns["tb"]
    plane = dict(HR.PLANES[skin]); listed = set(map(tuple, HR.listed_blocks(skin))) | set(map(tuple, extra_blocks))
    bm = bmesh.new(); bm.from_mesh(work.data); uvl = bm.loops.layers.uv.active
    bone = lambda co: np.array(co) @ tb[:3, :3].T + tb[:3, 3]
    def blk(f):
        u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops); v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
        return (int((u % 1.0) * 8), int(((1 - v) % 1.0) * 8))
    above, below, doomed, rest = set(), set(), [], []
    for f in bm.faces:
        pb = bone(sum((v.co for v in f.verts), Vector()) / len(f.verts))
        t = min(1.0, max(0.0, (pb[1] + 0.05) / 0.07))
        if pb[0] > plane["back"] + (plane["front"] - plane["back"]) * t and blk(f) not in keep_blocks:
            doomed.append(f); above.add(blk(f)); continue
        rest.append((f, pb))
        if pb[0] < 0.02 or (pb[1] > 0.03 and pb[0] < plane["front"] - 0.015):
            below.add(blk(f))
    blocks = ((above - below) | {tuple(b) for b in plane.get("blocks", ())}) - set(keep_blocks)
    for f, pb in rest:
        b = blk(f)
        if b in keep_blocks: continue
        protected = pb[1] > -0.01 and pb[0] < plane["front"] - 0.045      # mouth, lips, chin, lower face
        if protected: continue
        if (pb[0] > -0.01 and b in blocks) or (pb[0] > 0.03 and b in listed):
            doomed.append(f)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if bone(v.co)[0] > -0.08], dist=0.0005)
    bm.to_mesh(work.data); bm.free()
    return len(doomed), sorted(blocks)


def sample_kept(work, tb, g, plane, n=1500, below=0.005, seed=1):
    G = target_G(); hwf = ns["head_weight"]
    me = work.data; me.calc_loop_triangles()
    rng = np.random.default_rng(seed)
    tris = []
    for t in me.loop_triangles:
        vs = [me.vertices[i] for i in t.vertices]
        if not all(hwf(v, G) > 0.5 for v in vs): continue
        X = np.array([v.co[:] for v in vs]) @ tb[:3, :3].T + tb[:3, 3]
        c = X.mean(0); tt = min(1.0, max(0.0, (c[1] + 0.05) / 0.07))
        h = plane["back"] + (plane["front"] - plane["back"]) * tt
        if 0.0 < c[0] < h - below: tris.append(X)
    tris = np.array(tris)
    area = np.linalg.norm(np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]), axis=1) / 2
    idx = rng.choice(len(tris), size=n, p=area / area.sum())
    u, v = rng.random(n), rng.random(n)
    flip = u + v > 1; u[flip], v[flip] = 1 - u[flip], 1 - v[flip]
    X = tris[idx]
    return X[:, 0] + (X[:, 1] - X[:, 0]) * u[:, None] + (X[:, 2] - X[:, 0]) * v[:, None]


def align(donor, P, iters=30, smin=0.85, smax=1.2):
    """donor bone space -> target bone space: x = R (s * q) + t, fitted to the target points P"""
    V, T = donor["V"], donor["T"]
    bvh = BVHTree.FromPolygons([Vector(v) for v in V], [list(t) for t in T])
    R, s, t = np.eye(3), np.ones(3), np.zeros(3)
    for it in range(iters):
        Q = (P - t) @ R / s                      # target points in donor space
        near = [bvh.find_nearest(Vector(q)) for q in Q]
        ok = np.array([n[0] is not None for n in near])
        q = np.array([list(n[0]) if n[0] is not None else [0, 0, 0] for n in near])[ok]
        x = P[ok]
        d = np.array([n[3] for n in np.array(near, dtype=object)[ok]])
        keep = d < max(0.012, np.percentile(d, 85))   # trim outliers (ears, collars)
        q, x = q[keep], x[keep]
        sq = q * s
        mq, mx = sq.mean(0), x.mean(0)
        H = (sq - mq).T @ (x - mx)
        U, _, Vt = np.linalg.svd(H)
        D = np.diag([1, 1, np.sign(np.linalg.det(Vt.T @ U.T))])
        R = Vt.T @ D @ U.T
        t = mx - R @ mq
        y = (x - t) @ R                           # = s * q ideally
        s = np.clip((q * y).sum(0) / np.maximum((q * q).sum(0), 1e-9), smin, smax)
        t = (x - (q * s) @ R.T).mean(0)
    Q = (P - t) @ R / s
    dist = np.array([bvh.find_nearest(Vector(qq))[3] or 0 for qq in Q])
    return dict(R=R, s=s, t=t, rms=float(np.sqrt(np.mean(np.minimum(dist, 0.03) ** 2))), med=float(np.median(dist)))


def preview(work_name="work", up_min=-0.06):
    sc = bpy.context.scene; work = bpy.data.objects[work_name]; tb = ns["tb"]
    old = bpy.data.objects.get("preview")
    if old: bpy.data.objects.remove(old, do_unlink=True)
    pv = work.copy(); pv.data = work.data.copy(); pv.name = "preview"; sc.collection.objects.link(pv)
    bm = bmesh.new(); bm.from_mesh(pv.data)
    kill = [f for f in bm.faces if (np.array(sum((v.co for v in f.verts), Vector()) / len(f.verts)) @ tb[:3, :3].T + tb[:3, 3])[0] < up_min]
    bmesh.ops.delete(bm, geom=kill, context="FACES"); bm.to_mesh(pv.data); bm.free()
    for o in sc.objects: o.hide_set(o is not pv)


def render_obj(obj_name, prefix, modes=("grey", "tex"), views=VIEWS, res=300, dist=0.62):
    sc = bpy.context.scene
    ob = bpy.data.objects[obj_name]
    hidden = {o.name: o.hide_render for o in sc.objects}
    for o in sc.objects: o.hide_render = o is not ob
    ob.hide_set(False)
    mw = ob.matrix_world
    pts = np.array([list(mw @ v.co) for v in ob.data.vertices])
    # the object is upright (Z up) for previews/compare: frame the top 0.3 m
    zmax = pts[:, 2].max()
    sel = pts[pts[:, 2] > zmax - 0.28]
    c = Vector(((sel.min(0) + sel.max(0)) / 2).tolist()); c.z = zmax - 0.13
    cam = bpy.data.objects.get("revcam")
    if cam is None:
        cd = bpy.data.cameras.new("revcam"); cam = bpy.data.objects.new("revcam", cd); sc.collection.objects.link(cam)
    cam.data.lens = 60; cam.data.clip_start = 0.01
    sc.camera = cam
    try: sc.render.engine = "BLENDER_WORKBENCH"
    except TypeError: pass
    sc.render.resolution_x = sc.render.resolution_y = res; sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    sh = sc.display.shading
    UP, FWD = Vector((0, 0, 1)), Vector((0, -1, 0))   # preview objects face -Y
    SIDE = UP.cross(FWD)
    out = []
    for mode in modes:
        if mode == "tex": sh.light = "FLAT"; sh.color_type = "TEXTURE"
        else: sh.light = "STUDIO"; sh.color_type = "SINGLE"; sh.single_color = (0.75, 0.75, 0.75); sh.show_specular_highlight = False
        for name, yaw, el in views:
            a, e = math.radians(yaw), math.radians(el)
            d = (FWD * math.cos(a) + SIDE * math.sin(a)) * math.cos(e) + UP * math.sin(e)
            z = d.normalized(); x = (UP if abs(el) < 70 else FWD).cross(z).normalized()
            cam.matrix_world = Matrix((x, z.cross(x), z)).transposed().to_4x4(); cam.location = c + z * dist
            sc.render.filepath = os.path.join(OUTR, f"{prefix}-{mode}-{name}.png")
            bpy.ops.render.render(write_still=True); out.append(sc.render.filepath)
    for o in sc.objects:
        if o.name in hidden: o.hide_render = hidden[o.name]
    return out


def image_rows(path):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    bpy.data.images.remove(img)
    return a


def game_matrix(skin):
    """mesh space -> game world (studio), through the Head bone's matrix measured in the studio"""
    M = np.array(calib[str(skin)]); tb = ns["tb"]
    G = np.eye(4)
    G[:3, :3] = M[:3, :3].T @ tb[:3, :3]
    G[:3, 3] = M[:3, :3].T @ tb[:3, 3] + M[3, :3]
    return Matrix(G.tolist())


def sample_views(skin, Pm, Nm, power=4, erode=3):
    """reference colour (light-corrected) and total weight for mesh-space points/normals"""
    prep = json.load(open(REPO + r"\tools\data\hatless_prep.json"))[str(skin)]
    G = np.array(ns["game_matrix"](skin))
    Pw = Pm @ G[:3, :3].T + G[:3, 3]
    Nw = Nm @ G[:3, :3].T; Nw /= np.linalg.norm(Nw, axis=1)[:, None] + 1e-9
    key = f"ref{skin}"
    if key not in ns:
        ref = ns["image_rows"](REPO + rf"\docs\images\hatless-refs\{skin}.jpg")
        green = (ref[..., 1] > ref[..., 0] + 0.12) & (ref[..., 1] > ref[..., 2] + 0.12)
        er = ~green
        for _ in range(erode):
            er = er & np.roll(er, 1, 0) & np.roll(er, -1, 0) & np.roll(er, 1, 1) & np.roll(er, -1, 1)
        ns[key] = (ref, er)
    ref, er = ns[key]
    s = ref.shape[0] / 1024.0
    acc = np.zeros((len(Pw), 3)); wsum = np.zeros(len(Pw))
    for view in ("front", "three", "side", "back"):
        to_cam = hp.camera(view)[0] - Pw; to_cam /= np.linalg.norm(to_cam, axis=1)[:, None]
        xy = hp.to_reference("level", view, hp.to_grid("level", view, hp.to_shot(view, Pw), prep["offset"][view]), prep["ref_xform"][view]) * s
        x = np.clip(np.round(xy[:, 0]).astype(int), 0, ref.shape[1] - 1); y = np.clip(np.round(xy[:, 1]).astype(int), 0, ref.shape[0] - 1)
        w = np.clip((Nw * to_cam).sum(1), 0, 1) ** power * er[y, x]
        acc += ref[y, x] * w[:, None]; wsum += w
    col = np.where(wsum[:, None] > 1e-4, acc / np.maximum(wsum, 1e-4)[:, None], np.nan)
    return np.clip(col / np.maximum(np.array(prep["light"]), 0.5), 0, 1), wsum


def tri_texels(me, tri, W, H, uv):
    X = np.array([me.vertices[v].co[:] for v in tri.vertices])
    U = np.array([uv[l].uv[:] for l in tri.loops]) * [W, H]
    x0, y0 = np.floor(U.min(0)).astype(int); x1, y1 = np.ceil(U.max(0)).astype(int)
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    q = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
    T = np.array([U[1] - U[0], U[2] - U[0]]).T
    if abs(np.linalg.det(T)) < 1e-9: return None
    b = np.linalg.solve(T, (q - U[0]).T).T; w0 = 1 - b.sum(1)
    ins = (b[:, 0] >= -0.05) & (b[:, 1] >= -0.05) & (w0 >= -0.05)
    q, b, w0 = q[ins], b[ins], w0[ins]
    if not len(q): return None
    bary = np.stack([w0, b[:, 0], b[:, 1]], 1)
    n = np.cross(X[1] - X[0], X[2] - X[0]); n /= np.linalg.norm(n) + 1e-12
    return q, bary, bary @ X, n


def head_tris(work, hair_mi):
    G = target_G(); hwf = ns["head_weight"]; tb = ns["tb"]
    me = work.data; me.calc_loop_triangles()
    neck = next((v.index for v in work.vertex_groups if v.name.strip() == "Neck"), None)
    out = []
    for tri in me.loop_triangles:
        if tri.material_index == hair_mi: continue
        vs = [me.vertices[v] for v in tri.vertices]
        if all(hwf(v, G) > 0.5 for v in vs) or (neck is not None and all(hwf(v, G) + max([x.weight for x in v.groups if x.group == neck] or [0]) > 0.8 for v in vs) and (np.mean([np.array(v.co) for v in vs], 0) @ tb[:3, :3].T + tb[:3, 3])[0] > -0.05):
            out.append(tri)
    return out


def deshadow(skin, work, hair_mi, orig_px):
    """lift the cap's baked shadow: a smooth per-vertex brightness ratio (reference over atlas, normalised on the
    cheeks) applied to the upper face, keeping the atlas's own detail"""
    tb = ns["tb"]; me = work.data; uv = me.uv_layers.active.data
    H, W = orig_px.shape[:2]
    front = HR.PLANES[skin]["front"]
    tris = head_tris(work, hair_mi)
    lum = np.array([0.299, 0.587, 0.114])
    tri_ratio, tri_h, tri_f = {}, {}, {}
    for tri in tris:
        r = tri_texels(me, tri, W, H, uv)
        if r is None: continue
        q, bary, P, n = r
        hb = P @ tb[:3, :3].T + tb[:3, 3]
        col, wt = ns["sample_views"](skin, P, np.repeat(n[None], len(P), 0))
        if np.nansum(wt) < 1e-3: col, wt = ns["sample_views"](skin, P, np.repeat(-n[None], len(P), 0))
        o = orig_px[q[:, 1].astype(int) % H, q[:, 0].astype(int) % W, :3]
        ok = ~np.isnan(col[:, 0]) & (o @ lum > 0.04)
        if ok.sum() < 2: continue
        tri_ratio[tri.index] = float(np.median((col[ok] @ lum) / (o[ok] @ lum)))
        tri_h[tri.index] = float(hb[:, 0].mean()); tri_f[tri.index] = float(hb[:, 1].mean())
    cheeks = [r for i, r in tri_ratio.items() if front - 0.10 < tri_h[i] < front - 0.07 and tri_f[i] > 0.03]
    norm = np.median(cheeks) if cheeks else np.median(list(tri_ratio.values()))
    # per vertex, then smoothed over the mesh
    vsum, vcnt = {}, {}
    tri_by_idx = {t.index: t for t in tris}
    for i, r in tri_ratio.items():
        for v in tri_by_idx[i].vertices:
            vsum[v] = vsum.get(v, 0) + r / norm; vcnt[v] = vcnt.get(v, 0) + 1
    vr = {v: vsum[v] / vcnt[v] for v in vsum}
    adj = {}
    for t in tris:
        a, b, c = t.vertices
        for x, y in ((a, b), (b, c), (c, a)): adj.setdefault(x, set()).add(y); adj.setdefault(y, set()).add(x)
    for _ in range(3):
        vr = {v: (vr[v] * 2 + sum(vr.get(u, vr[v]) for u in adj.get(v, ()))) / (2 + len(adj.get(v, ()))) for v in vr}
    out = orig_px.copy(); acc = np.zeros((H, W)); cnt = np.zeros((H, W))
    for tri in tris:
        r = tri_texels(me, tri, W, H, uv)
        if r is None: continue
        q, bary, P, n = r
        hb = P @ tb[:3, :3].T + tb[:3, 3]
        rv = np.array([min(2.2, max(1.0, vr.get(v, 1.0))) for v in tri.vertices])
        ratio = bary @ rv
        t = np.clip((hb[:, 0] - (front - 0.075)) / 0.025, 0, 1) * (hb[:, 1] > -0.02)
        f = 1 + t * (ratio - 1)
        ix = q[:, 0].astype(int) % W; iy = q[:, 1].astype(int) % H
        np.add.at(acc, (iy, ix), f); np.add.at(cnt, (iy, ix), 1)
    m = cnt > 0
    fac = np.ones((H, W)); fac[m] = acc[m] / cnt[m]
    out[..., :3] = np.clip(orig_px[..., :3] * fac[..., None], 0, 1)
    return out, float(norm), float(np.percentile(list(vr.values()), 90))


def export2(skin):
    sc = bpy.context.scene; work = bpy.data.objects["work"]; name = ns["name"]
    src = bpy.data.objects["mesh"]; arm = next(o for o in sc.objects if o.type == "ARMATURE")
    me = work.data; mi = [m.name for m in me.materials].index("hair_" + name)
    for m, label in ((me.materials[0], name + "_bare"), (me.materials[mi], name + "_hair")):
        m.dff.tex_name = label
    old = src.data; src.data = me
    bpy.ops.object.select_all(action="DESELECT")
    peds = [arm, src] + [o for o in sc.objects if o.type == "EMPTY"]
    for o in peds: o.hide_set(False); o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    out = os.path.join(OUTDIR, f"{name}_nohat.dff")
    bpy.ops.export_dff.scene(filepath=out, export_coll=False, only_selected=True, export_version="0x36003")
    src.data = old
    from DragonFF.gtaLib import txd as rwtxd
    from DragonFF.ops.txd_exporter import txd_exporter
    t = rwtxd.txd(); t.device_id = rwtxd.DeviceType.DEVICE_D3D9
    t.native_textures = [txd_exporter._create_texture_native_from_image(bpy.data.images[name + "_bare"], name + "_bare"),
                         txd_exporter._create_texture_native_from_image(bpy.data.images[name + "_hair"], name + "_hair")]
    t.write_file(os.path.join(OUTDIR, f"{name}_nohat.txd"), 0x36003)
    for o in peds: o.hide_set(True)
    return out


ns.update(head_groups=head_groups, head_weight=head_weight, target_G=target_G, load_skin=load_skin, make_work=make_work, cut3=cut3, sample_kept=sample_kept, align=align, preview=preview, render_obj=render_obj, image_rows=image_rows, game_matrix=game_matrix, sample_views=sample_views, tri_texels=tri_texels, head_tris=head_tris, deshadow=deshadow, export2=export2, DON=DON, PEDS=PEDS, OUTDIR=OUTDIR, OUTR=OUTR, REPO=REPO)
