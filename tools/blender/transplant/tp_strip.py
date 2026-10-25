# exec'd after transplant.py: the seam as a strip. The target is cut on the seam planes (vertices close to a plane are
# snapped onto it first, so the cut leaves no slivers), the donor on the same planes pushed `gap` further into the
# cranium, and the band between the two loops is zipped with fresh triangles whose uvs come from the donor's own
# surface there. The donor's displacement then fades out biharmonically from the target's loop.
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import tools.hatless_rebuild as HR

UP, FWD = np.array([1.0, 0, 0]), np.array([0, 1.0, 0])
SIDE = np.cross(UP, FWD)
Cut, azim, bone_of = ns["Cut"], ns["tp_azim"], ns["tp_bone_of"]


def plane_list(cut):
    """the seam's planes as (point, unit normal, applies(p)) in bone space"""
    fa = cut.face_az
    out = [(np.array([cut.front, 0, 0]), UP, lambda p: abs(float(azim(p, cut.C)[0])) <= fa + 1.0)]
    for sgn in (1, -1):
        n, dvec = cut.normals[sgn]
        out.append((cut.C, n / np.linalg.norm(n), lambda p, dv=dvec: (p - cut.C) @ dv > 0 and cut.nape - 0.004 <= p[0] <= cut.front + 0.004))
    out.append((np.array([cut.nape, 0, 0]), UP, lambda p: abs(float(azim(p, cut.C)[0])) >= fa - 1.0))
    return out


def snap(bm, tb, cut, eps, verts=None):
    """move vertices lying within eps of a seam plane onto it"""
    inv = np.linalg.inv(tb)
    bone = bone_of(tb)
    planes = plane_list(cut)
    moved = 0
    for v in verts if verts is not None else bm.verts:
        p = bone(v.co)
        q = p.copy()
        for pt, n, ok in planes:
            dist = (q - pt) @ n
            if abs(dist) < eps and ok(q):
                q = q - dist * n
        if np.any(q != p):
            v.co = Vector((q @ inv[:3, :3].T + inv[:3, 3]).tolist())
            moved += 1
    return moved


def boundary_loops(faces):
    fs = set(faces)
    nxt = {}
    for f in faces:
        for l in f.loops:
            e = l.edge
            if sum(1 for g in e.link_faces if g in fs) == 1:
                # walk the boundary in the faces' winding: from l.vert to the next vert
                nxt.setdefault(l.vert, []).append(l.link_loop_next.vert)
    loops, seen = [], set()
    for start in list(nxt):
        if start in seen:
            continue
        loop, v = [], start
        while v not in seen and v in nxt:
            seen.add(v)
            loop.append(v)
            v = nxt[v][0]
        if len(loop) > 2:
            loops.append(loop)
    return loops


def frame_of(points, C):
    P = np.asarray(points) - np.asarray(points).mean(0)
    _, _, Vt = np.linalg.svd(P)
    a = Vt[2] if Vt[2] @ UP > 0 else -Vt[2]
    f = FWD - a * (FWD @ a)
    f /= np.linalg.norm(f)
    return a, f, np.cross(a, f)


def phi_of(points, C, fr):
    a, f, s = fr
    d = np.asarray(points) - C
    return np.arctan2(d @ s, d @ f)


def donor_uv_map(d, Vt):
    """triangles of the donor's faces with their uvs, and a BVH over them (target bone space)"""
    tris, uvs = [], []
    for vs, uv in zip(d["faces"], d["uvs"]):
        for k in range(1, len(vs) - 1):
            tris.append((vs[0], vs[k], vs[k + 1]))
            uvs.append((uv[0], uv[k], uv[k + 1]))
    bvh = BVHTree.FromPolygons([Vector(p) for p in Vt], [list(t) for t in tris])
    return bvh, np.array(tris), np.array(uvs)


def affine_uv(Vt, tri, uv, P):
    """uvs of points P from one donor triangle's affine map (extrapolated off the triangle)"""
    A, B, Cc = Vt[tri[0]], Vt[tri[1]], Vt[tri[2]]
    e1, e2 = B - A, Cc - A
    G = np.array([[e1 @ e1, e1 @ e2], [e1 @ e2, e2 @ e2]])
    out = []
    for p in P:
        r = p - A
        b = np.linalg.solve(G, [r @ e1, r @ e2])
        w = np.clip(np.array([1 - b[0] - b[1], b[0], b[1]]), 0, None)
        w /= w.sum() if w.sum() > 1e-9 else 1.0
        if w.sum() < 1e-9:
            w = np.full(3, 1 / 3)
        # clamped onto the triangle: points off it take the colour at its nearest part, never a far-away texel
        out.append(uv[0] * w[0] + uv[1] * w[1] + uv[2] * w[2])
    return out


def zipper(bm, A, B, phA, phB, mi, uvl, Pfun, uvfun, period=2 * math.pi):
    """triangles between closed loops A (target) and B (donor), both ordered by increasing parameter"""
    n, m = len(A), len(B)
    ia = int(np.argmin(phA))
    ib = int(np.argmin(phB))
    A = A[ia:] + A[:ia]
    phA = np.concatenate([phA[ia:], phA[:ia]])
    B = B[ib:] + B[:ib]
    phB = np.concatenate([phB[ib:], phB[:ib]])
    ua = np.unwrap(phA, period=period)
    ub = np.unwrap(phB, period=period)
    ua = np.append(ua, ua[0] + period)
    ub = np.append(ub, ub[0] + period)
    faces = []
    i = j = 0
    while i < n or j < m:
        adv_a = j >= m or (i < n and ua[i + 1] <= ub[j + 1])
        if adv_a:
            vs = [A[i % n], A[(i + 1) % n], B[j % m]]
            i += 1
        else:
            vs = [A[i % n], B[(j + 1) % m], B[j % m]]
            j += 1
        try:
            f = bm.faces.new(vs)
        except ValueError:
            continue
        f.material_index = mi
        f.smooth = True
        P = [Pfun(v) for v in vs]
        for l, uv in zip(f.loops, uvfun(P)):
            l[uvl].uv = Vector((float(uv[0]), float(uv[1])))
        faces.append(f)
    return faces


def loop_u(loop, cut, bone):
    """seam parameter of each loop vertex; vertices off the planes take their neighbours' interpolated value"""
    n = len(loop)
    u = np.full(n, np.nan)
    for i, v in enumerate(loop):
        dist, uu = cut.piece(bone(v.co))
        if uu is not None and dist < 1.5e-3:
            u[i] = uu % 4.0
    good = np.flatnonzero(~np.isnan(u))
    if len(good) < n:
        ug = np.unwrap(u[good], period=4.0)
        turn = 4.0 if np.median(np.diff(ug)) > 0 else -4.0
        xs = np.concatenate([good - n, good, good + n])
        ys = np.concatenate([ug - turn, ug, ug + turn])
        u = np.interp(np.arange(n), xs, ys) % 4.0
    return u


def transplant2(skin, donor=None, face_az=62.0, nape=0.0, front=None, gap=0.012, gap_az=9.0, snap_eps=0.003, blend=0.05, near=0.012, front_drop=0.025, nape_min=-0.03, extra_blocks=(), keep_blocks=()):
    donor = donor or ns["donor_choice"][skin]
    name, tex, size = ns["load_skin"](skin)
    tb, g = ns["tb"], ns["g"]
    inv = np.linalg.inv(tb)
    plane = HR.PLANES[skin]
    ns["cut3"](skin, extra_blocks=extra_blocks, keep_blocks=keep_blocks)
    P = ns["sample_kept"](bpy.data.objects["work"], tb, g, plane)
    d = ns["load_donor_full"](donor)
    A = ns["align"](dict(V=d["V"], T=d["T"]), P)
    Vt = (d["V"] * A["s"]) @ A["R"].T + A["t"]
    used = Vt[d["used"]]
    C = (used.min(0) + used.max(0)) / 2
    C[0] = max(C[0], 0.07)
    don_bvh = BVHTree.FromPolygons([Vector(p) for p in Vt], [list(t) for t in d["TN"]])
    uv_bvh, uv_tris, uv_uvs = donor_uv_map(d, Vt)
    is_hat = ns["hat_rule"](skin, extra_blocks, keep_blocks)
    work = ns["make_work"]()
    bone = bone_of(tb)
    mesh_pt = lambda p: Vector((np.array(p) @ inv[:3, :3].T + inv[:3, 3]).tolist())
    face_block = ns["tp_face_block"]
    rep = {}

    bm = bmesh.new()
    bm.from_mesh(work.data)
    uvl = bm.loops.layers.uv.active
    dl = bm.verts.layers.deform.verify()
    front0 = plane["front"] if front is None else front
    cut = Cut(C, front0, nape, face_az)
    hat_near = []
    for f in bm.faces:
        pb = bone(f.calc_center_median())
        if not is_hat(pb, face_block(f, uvl)):
            continue
        hit = don_bvh.find_nearest(Vector(pb.tolist()))
        if hit[0] is not None and hit[3] < near:
            hat_near.extend(bone(v.co) for v in f.verts)
    hat_near = np.array(hat_near).reshape(-1, 3)
    if len(hat_near):
        az = np.abs(azim(hat_near, C))
        fr = hat_near[(az < face_az) & ~cut.replaced(hat_near)]
        if len(fr):
            cut.front = max(front0 - front_drop, min(front0, fr[:, 0].min() - 0.002))
        bk = hat_near[(az >= face_az) & ~cut.replaced(hat_near)]
        if len(bk):
            cut.nape = max(nape_min, min(nape, bk[:, 0].min() - 0.002))
    rep["front"], rep["nape"] = round(float(cut.front), 4), round(float(cut.nape), 4)

    # --- target: snap, cut, drop the cranium and any hat left below the seam ---
    rep["snapped"] = snap(bm, tb, cut, snap_eps, [v for v in bm.verts if bone(v.co)[0] > cut.nape - 0.01])
    ns["tp_bisect_cut"](bm, tb, cut)
    doomed, hat_left = [], 0
    for f in bm.faces:
        pb = bone(f.calc_center_median())
        if cut.replaced(pb)[0]:
            doomed.append(f)
        elif is_hat(pb, face_block(f, uvl)):
            doomed.append(f)
            hat_left += 1
    rep["hat_below_seam"] = hat_left
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if bone(v.co)[0] > -0.08], dist=0.0005)
    tfaces = [f for f in bm.faces]

    # --- donor piece, cut on the seam planes pushed `gap` into the cranium ---
    mat = "hair_" + name
    hm = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
    hm.use_nodes = True
    names = [m.name for m in work.data.materials]
    if hm.name not in names:
        work.data.materials.append(hm)
        names.append(hm.name)
    mi = names.index(hm.name)
    dcut = Cut(C, cut.front + gap, cut.nape + gap, face_az + gap_az)
    vmap = {}
    for vs, uvs, fm in zip(d["faces"], d["uvs"], d["fmat"]):
        for i in vs:
            if i not in vmap:
                vmap[i] = bm.verts.new(mesh_pt(Vt[i]))
        try:
            f = bm.faces.new([vmap[i] for i in vs])
        except ValueError:
            continue
        f.material_index = mi
        f.smooth = True
        for l, uv in zip(f.loops, uvs):
            l[uvl].uv = uv
    bmesh.ops.remove_doubles(bm, verts=list(vmap.values()), dist=1e-6)
    dverts0 = [v for v in bm.verts if v.is_valid and any(f.material_index == mi for f in v.link_faces)]
    snap(bm, tb, dcut, snap_eps, dverts0)
    ns["tp_bisect_donor"](bm, tb, dcut, mi)
    dfaces = [f for f in bm.faces if f.material_index == mi]
    kill = [f for f in dfaces if not dcut.replaced(bone(f.calc_center_median()))[0]]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    dfaces = [f for f in bm.faces if f.material_index == mi]
    tfaces = [f for f in bm.faces if f.material_index != mi]

    # --- the two loops ---
    tl = [lp for lp in boundary_loops(tfaces) if np.mean([bone(v.co)[0] for v in lp]) > cut.nape - 0.02]
    dlp = boundary_loops(dfaces)
    on_seam = lambda lp, c: sum(1 for v in lp if c.piece(bone(v.co))[0] < 1e-3)
    tl.sort(key=lambda lp: -on_seam(lp, cut))
    dlp.sort(key=lambda lp: -on_seam(lp, dcut))
    rep["t_loops"] = [(len(lp), on_seam(lp, cut)) for lp in tl[:3]]
    rep["d_loops"] = [(len(lp), on_seam(lp, dcut)) for lp in dlp[:3]]
    LA, LB = tl[0], dlp[0]
    phA, phB = loop_u(LA, cut, bone), loop_u(LB, dcut, bone)
    # both loops in increasing u
    if np.median(np.diff(np.unwrap(phA, period=4.0))) < 0:
        LA, phA = LA[::-1], phA[::-1]
    if np.median(np.diff(np.unwrap(phB, period=4.0))) < 0:
        LB, phB = LB[::-1], phB[::-1]
    mono = lambda u: bool(np.all(np.diff(np.unwrap(np.append(u, u[0]), period=4.0)) > -1e-6))
    rep["monotone"] = [mono(phA), mono(phB)]

    def uvfun(P):
        c = np.mean(P, 0)
        hit = uv_bvh.find_nearest(Vector(c.tolist()))
        k = hit[2]
        return affine_uv(Vt, uv_tris[k], uv_uvs[k], P)

    strip = zipper(bm, list(LA), list(LB), np.asarray(phA), np.asarray(phB), mi, uvl, lambda v: bone(v.co), uvfun, period=4.0)
    rep["strip"] = len(strip)
    seam = set(LA)

    # --- donor weights: nearest original target vertex ---
    src = bpy.data.objects["mesh"]
    Sb = np.array([v.co[:] for v in src.data.vertices]) @ tb[:3, :3].T + tb[:3, 3]
    from mathutils.kdtree import KDTree
    sidx = np.flatnonzero(Sb[:, 0] > -0.15)
    kd = KDTree(len(sidx))
    for j, i in enumerate(sidx):
        kd.insert(Vector(Sb[i].tolist()), j)
    kd.balance()
    dverts = {v for f in bm.faces if f.material_index == mi for v in f.verts} - seam
    for v in dverts:
        _, j, _ = kd.find(Vector(bone(v.co).tolist()))
        sv = src.data.vertices[int(sidx[j])]
        for gi in list(v[dl].keys()):
            del v[dl][gi]
        for ge in sv.groups:
            if ge.weight > 0:
                v[dl][ge.group] = ge.weight

    # --- biharmonic fade of the donor's displacement towards the target ---
    verts = [v for v in bm.verts if bone(v.co)[0] > -0.09]
    L, idx = ns["tp_laplacian"](verts)
    n = len(verts)
    X = np.array([bone(v.co) for v in verts])
    delta = np.zeros((n, 3))
    known = np.ones(n, bool)
    sp = np.array([bone(v.co) for v in seam])
    for v, i in idx.items():
        if v in dverts:
            if np.min(np.linalg.norm(sp - X[i], axis=1)) < blend:
                known[i] = False
            continue
        hit = don_bvh.find_nearest(Vector(X[i].tolist()))
        if hit[0] is not None:
            delta[i] = X[i] - np.array(hit[0])
    L2 = L @ L
    F = np.flatnonzero(~known)
    K = np.flatnonzero(known)
    if len(F):
        delta[F] = np.linalg.solve(L2[np.ix_(F, F)], -L2[np.ix_(F, K)] @ delta[K])
        for i in F:
            verts[i].co = mesh_pt(X[i] + delta[i])
    rep["free"] = int(len(F))
    rep["delta_seam_mm"] = round(float(np.median(np.linalg.norm(delta[[idx[v] for v in seam if v in idx]], axis=1))) * 1000, 2)

    ngons = [f for f in bm.faces if len(f.verts) > 3]
    bmesh.ops.triangulate(bm, faces=ngons, quad_method="BEAUTY", ngon_method="BEAUTY")
    head = [f for f in bm.faces if bone(f.calc_center_median())[0] > -0.06]
    bmesh.ops.recalc_face_normals(bm, faces=head)
    opn = [e for e in bm.edges if len(e.link_faces) == 1 and bone(e.verts[0].co)[0] > -0.03 and bone(e.verts[1].co)[0] > -0.03]
    rep["open_edges"] = len(opn)
    bm.normal_update()
    bm.to_mesh(work.data)
    bm.free()
    ns["cur_tp"] = dict(skin=skin, donor=donor, A=A, Vt=Vt, C=C, cut=cut, dcut=dcut, mi=mi, rep=rep, bvh=don_bvh, d=d, uv=(uv_bvh, uv_tris, uv_uvs))
    rep.update(donor=donor, rms_mm=round(A["rms"] * 1000, 2), scale=np.round(A["s"], 3).tolist())
    return rep


ns.update(transplant2=transplant2, tp_snap=snap, tp_boundary_loops=boundary_loops, tp_zipper=zipper, tp_affine_uv=affine_uv, tp_donor_uv_map=donor_uv_map)
