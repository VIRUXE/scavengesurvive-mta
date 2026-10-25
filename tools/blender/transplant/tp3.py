# exec'd in the live Blender session after transplant.py (driver namespace `ns`).
# Cranium transplant, third take: the seam is a brow plane across the face, two vertical temple planes through the
# cranium centre and a nape plane tilted down towards the back of the neck (where both necks are plain cylinders).
# The target is cut on it (vertices near a plane snapped onto it first, so no slivers), the donor (subdivided once)
# on the same seam pushed `gap` into the cranium, the band between is zipped with fresh triangles textured from the
# donor's own surface, and the donor's displacement towards the target fades out biharmonically from the seam.
import math

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.kdtree import KDTree

import tools.hatless_rebuild as HR

UP, FWD = np.array([1.0, 0, 0]), np.array([0, 1.0, 0])
SIDE = np.cross(UP, FWD)
R0 = 0.07  # head radius the nape tilt is set up for


def azim(P, C):
    d = np.atleast_2d(P) - C
    return np.degrees(np.arctan2(d @ SIDE, d @ FWD))


def bone_of(tb):
    return lambda co: np.array(co) @ tb[:3, :3].T + tb[:3, 3]


class Seam:
    def __init__(self, C, front, nape_side, nape_back, face_az):
        self.C, self.front, self.nape_side, self.nape_back, self.face_az = np.asarray(C, float), front, nape_side, nape_back, face_az
        self.temple = {}
        for sgn in (1, -1):
            a = math.radians(face_az) * sgn
            dvec = FWD * math.cos(a) + SIDE * math.sin(a)
            n = np.cross(UP, dvec)
            self.temple[sgn] = (n / np.linalg.norm(n), dvec)
        y_side, y_back = R0 * math.cos(math.radians(face_az)), -R0
        self.b = (nape_side - nape_back) / (y_side - y_back)
        self.a = nape_side - self.b * y_side

    def shifted(self, gap, gap_az):
        return Seam(self.C, self.front + gap, self.nape_side + gap, self.nape_back + gap, self.face_az + gap_az)

    def nape_h(self, P):
        P = np.atleast_2d(P)
        return self.a + self.b * (P[:, 1] - self.C[1])

    def nape_plane(self):
        n = np.array([1.0, -self.b, 0.0])
        return np.array([self.a, self.C[1], 0.0]), n / np.linalg.norm(n)

    def replaced(self, P):
        P = np.atleast_2d(P)
        # the tilted nape plane keeps dropping behind the head: nothing below the back of the nape is cranium
        low = np.maximum(self.nape_h(P), min(self.nape_back, self.nape_side) - 0.004)
        return (P[:, 0] > self.front) | ((np.abs(azim(P, self.C)) > self.face_az) & (P[:, 0] > low))

    def planes(self):
        """(point, normal, applies(p)) of each piece"""
        fa = self.face_az
        out = [("brow", np.array([self.front, 0, 0]), UP, lambda p: abs(float(azim(p, self.C)[0])) <= fa + 1.0)]
        for sgn in (1, -1):
            n, dvec = self.temple[sgn]
            out.append(("temple", self.C, n, lambda p, dv=dvec: (p - self.C) @ dv > 0 and float(self.nape_h(p)[0]) - 0.004 <= p[0] <= self.front + 0.004))
        p0, n = self.nape_plane()
        out.append(("nape", p0, n, lambda p: abs(float(azim(p, self.C)[0])) >= fa - 1.0))
        return out

    def piece(self, p):
        """(distance, u): u 0..1 brow (+az to -az), 1..2 temple -az (down), 2..3 nape (round the back), 3..4 temple +az"""
        x = p[0]
        az = float(azim(p, self.C)[0])
        fa = self.face_az
        best = (1e9, None)
        if abs(az) <= fa + 1.0:
            best = min(best, (abs(x - self.front), (fa - az) / (2 * fa)))
        if abs(az) >= fa - 1.0:
            p0, n = self.nape_plane()
            s = (-fa - az) % 360.0
            if s > 360.0 - fa:  # just inside the face sector at -fa: the corner
                s = 0.0
            elif s > 360.0 - 2 * fa:
                s = 360.0 - 2 * fa
            best = min(best, (abs((p - p0) @ n), 2 + s / (360 - 2 * fa)))
        span = self.front - self.nape_side
        for sgn in (1, -1):
            n, dvec = self.temple[sgn]
            lo = float(self.nape_h(p)[0])
            if (p - self.C) @ dvec > 0 and lo - 0.004 <= x <= self.front + 0.004:
                t = min(1.0, max(0.0, (self.front - x) / max(self.front - lo, 1e-6)))
                best = min(best, (abs((p - self.C) @ n), 1 + t if sgn < 0 else 4 - t))
        return best


def snap(bm, tb, seam, eps, verts):
    inv = np.linalg.inv(tb)
    bone = bone_of(tb)
    pl = seam.planes()
    moved = 0
    for v in verts:
        p = bone(v.co)
        q = p.copy()
        for _, pt, n, ok in pl:
            dist = (q - pt) @ n
            if abs(dist) < eps and ok(q):
                q = q - dist * n
        if np.any(q != p):
            v.co = Vector((q @ inv[:3, :3].T + inv[:3, 3]).tolist())
            moved += 1
    return moved


def bisect(bm, tb, seam, which=None, margin=0.03, amargin=25.0):
    """cut the faces (all, or those passing `which`) that straddle one of the seam's planes near its piece"""
    inv = np.linalg.inv(tb)
    R = tb[:3, :3]
    bone = bone_of(tb)
    fa = seam.face_az

    def run(p_b, n_b, near):
        p_b, n_b = np.asarray(p_b, float), np.asarray(n_b, float)
        fs = []
        for f in bm.faces:
            if which is not None and not which(f):
                continue
            P = np.array([bone(v.co) for v in f.verts])
            sd = (P - p_b) @ n_b
            if sd.min() < -1e-6 and sd.max() > 1e-6 and any(near(p, float(azim(p, seam.C)[0])) for p in P):
                fs.append(f)
        if not fs:
            return
        geom = fs + list({e for f in fs for e in f.edges}) + list({v for f in fs for v in f.verts})
        p_m = Vector((p_b @ inv[:3, :3].T + inv[:3, 3]).tolist())
        n_m = Vector((R.T @ n_b).tolist())
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p_m, plane_no=n_m, dist=1e-5)

    run([seam.front, 0, 0], UP, lambda c, a: abs(a) < fa + amargin)
    for sgn in (1, -1):
        dv = seam.temple[sgn][1]
        run(seam.C, seam.temple[sgn][0], lambda c, a, s=sgn, dv=dv: (c - seam.C) @ dv > 0 and float(seam.nape_h(c)[0]) - margin < c[0] < seam.front + margin and abs(a - s * fa) < amargin)
    p0, n = seam.nape_plane()
    run(p0, n, lambda c, a: abs(a) > fa - amargin)


def loop_u(loop, seam, bone):
    n = len(loop)
    u = np.full(n, np.nan)
    for i, v in enumerate(loop):
        dist, uu = seam.piece(bone(v.co))
        if uu is not None and dist < 1.5e-3:
            u[i] = uu % 4.0
    good = np.flatnonzero(~np.isnan(u))
    if 0 < len(good) < n:
        ug = np.unwrap(u[good], period=4.0)
        turn = 4.0 if np.median(np.diff(ug)) > 0 else -4.0
        xs = np.concatenate([good - n, good, good + n])
        ys = np.concatenate([ug - turn, ug, ug + turn])
        u = np.interp(np.arange(n), xs, ys) % 4.0
    return u


def radial_offset(bvh, C, p, reach=0.04):
    """offset of p from the donor's surface, measured along the horizontal ray from the head's vertical axis"""
    o = np.array([p[0], C[1], C[2]])
    d = p - o
    r = np.linalg.norm(d)
    if r < 1e-6:
        return np.zeros(3)
    d /= r
    hit = bvh.ray_cast(Vector(o.tolist()), Vector(d.tolist()), r + reach)
    if hit[0] is None:
        return np.zeros(3)
    return p - np.array(hit[0])


def components(faces):
    """connected face islands (through shared edges)"""
    fs = set(faces)
    seen, out = set(), []
    for f in faces:
        if f in seen:
            continue
        comp, stack = [], [f]
        seen.add(f)
        while stack:
            g = stack.pop()
            comp.append(g)
            for e in g.edges:
                for h in e.link_faces:
                    if h in fs and h not in seen:
                        seen.add(h)
                        stack.append(h)
        out.append(comp)
    return out


def place_seam(skin, bm, tb, uvl, is_hat, don_bvh, C, front, nape_side, nape_back, face_az, near, front_drop, nape_min):
    """the seam, lowered under every piece of hat that lies on the skin (within `near` of the donor's surface)"""
    bone = bone_of(tb)
    face_block = ns["tp_face_block"]
    seam = Seam(C, front, nape_side, nape_back, face_az)
    pts = []
    for f in bm.faces:
        pb = bone(f.calc_center_median())
        if not is_hat(pb, face_block(f, uvl)):
            continue
        hit = don_bvh.find_nearest(Vector(pb.tolist()))
        if hit[0] is not None and hit[3] < near:
            pts.extend(bone(v.co) for v in f.verts)
    pts = np.array(pts).reshape(-1, 3)
    if len(pts):
        left = pts[~seam.replaced(pts)]
        az = np.abs(azim(left, C)) if len(left) else np.zeros(0)
        fr = left[az < face_az]
        if len(fr):
            seam.front = max(front - front_drop, min(front, fr[:, 0].min() - 0.002))
        bk = left[az >= face_az]
        if len(bk):
            drop = float(np.max(seam.nape_h(bk) - bk[:, 0])) + 0.002
            drop = min(drop, nape_side - nape_min)
            seam = Seam(C, seam.front, nape_side - drop, nape_back - drop, face_az)
    return seam


def transplant3(skin, donor=None, face_az=62.0, nape_side=0.0, nape_back=-0.03, front=None, gap=0.008, gap_az=6.0, snap_eps=0.003, blend=0.05, band_t=0.008, band_d=0.012, mu=0.3, near=0.012, front_drop=0.025, nape_min=-0.04, subdiv=1, donor_weld=3e-4, inner_gap=0.015, extra_blocks=(), keep_blocks=()):
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
    uv_bvh, uv_tris, uv_uvs = ns["tp_donor_uv_map"](d, Vt)
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
    seam = place_seam(skin, bm, tb, uvl, is_hat, don_bvh, C, plane["front"] if front is None else front, nape_side, nape_back, face_az, near, front_drop, nape_min)
    rep["seam"] = dict(front=round(float(seam.front), 4), nape_side=round(float(seam.nape_side), 4), nape_back=round(float(seam.nape_back), 4))

    # --- target ---
    rep["snapped"] = snap(bm, tb, seam, snap_eps, [v for v in bm.verts if bone(v.co)[0] > seam.nape_back - 0.02])
    bisect(bm, tb, seam)
    doomed, hat_left = [], 0
    for f in bm.faces:
        pb = bone(f.calc_center_median())
        if seam.replaced(pb)[0]:
            doomed.append(f)
        elif is_hat(pb, face_block(f, uvl)):
            doomed.append(f)
            hat_left += 1
    rep["hat_below_seam"] = hat_left
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if bone(v.co)[0] > -0.08], dist=0.0005)
    loose = []
    for comp in components(list(bm.faces)):
        if len(comp) < 40 and np.mean([bone(f.calc_center_median())[0] for f in comp]) > -0.09:
            c = np.mean([bone(f.calc_center_median()) for f in comp], 0)
            a = abs(float(azim(c, C)[0]))
            stray = len(comp) < 3 or (len(comp) < 10 and 55 < a < 115 and -0.015 < c[0] < seam.front)
            # hat pieces left hanging behind the head (bandana tails); glasses and cigarettes sit in front
            hat_bits = (a > 90 or c[0] > seam.front) and all(face_block(f, uvl) in is_hat.above for f in comp)
            if stray or hat_bits:
                loose.extend(comp)
    rep["hat_islands"] = len(loose)
    bmesh.ops.delete(bm, geom=loose, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")

    # --- donor piece ---
    mat = "hair_" + name
    hm = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
    hm.use_nodes = True
    names = [m.name for m in work.data.materials]
    if hm.name not in names:
        work.data.materials.append(hm)
        names.append(hm.name)
    mi = names.index(hm.name)
    dseam = seam.shifted(gap, gap_az)
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
    bmesh.ops.remove_doubles(bm, verts=list(vmap.values()), dist=donor_weld)
    isd = lambda f: f.material_index == mi
    # a donor whose hair is a shell over the scalp: drop the scalp underneath, so the cut leaves one boundary
    bm.normal_update()
    dfs = [f for f in bm.faces if isd(f)]
    dv = list({v for f in dfs for v in f.verts})
    di = {v: i for i, v in enumerate(dv)}
    dbvh = BVHTree.FromPolygons([v.co.copy() for v in dv], [[di[v] for v in f.verts] for f in dfs])
    inner = []
    for k, f in enumerate(dfs):
        c = f.calc_center_median()
        n = f.normal
        pb = bone(c)
        radial = pb - C
        radial /= np.linalg.norm(radial) + 1e-9
        nb = tb[:3, :3] @ np.array(n)
        if nb @ radial < 0.3:
            continue
        hit = dbvh.ray_cast(c + n * 2e-4, n, inner_gap)
        if hit[0] is not None and hit[2] != k:
            hn = tb[:3, :3] @ np.array(dfs[hit[2]].normal)
            if hn @ radial > 0.3:
                inner.append(f)
    rep["inner_faces"] = len(inner)
    bmesh.ops.delete(bm, geom=inner, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # trim the donor to the cranium (plus a margin) before subdividing, then cut it exactly
    rough = [f for f in bm.faces if isd(f) and not seam.shifted(-0.02, -15.0).replaced(bone(f.calc_center_median()))[0]]
    bmesh.ops.delete(bm, geom=rough, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    for _ in range(subdiv):
        dfs = [f for f in bm.faces if isd(f)]
        edges = list({e for f in dfs for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True, smooth=1.0)
        bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if isd(f) and len(f.verts) > 3])
    dverts0 = list({v for f in bm.faces if isd(f) for v in f.verts})
    snap(bm, tb, dseam, snap_eps * 0.6, dverts0)
    bisect(bm, tb, dseam, which=isd)
    kill = [f for f in bm.faces if isd(f) and not dseam.replaced(bone(f.calc_center_median()))[0]]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    # only the cranium itself: the donor's hair clips, earrings and other loose bits go
    comps = sorted(components([f for f in bm.faces if isd(f)]), key=len)
    extra = [f for comp in comps[:-1] for f in comp]
    rep["donor_islands"] = len(comps) - 1
    bmesh.ops.delete(bm, geom=extra, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    dfaces = [f for f in bm.faces if isd(f)]
    tfaces = [f for f in bm.faces if not isd(f)]

    # --- zip the two loops ---
    loops = ns["tp_boundary_loops"]
    on_seam = lambda lp, s: sum(1 for v in lp if s.piece(bone(v.co))[0] < 1e-3)
    tl = sorted(loops(tfaces), key=lambda lp: -on_seam(lp, seam))
    dlp = sorted(loops(dfaces), key=lambda lp: -on_seam(lp, dseam))
    rep["t_loops"] = [(len(lp), on_seam(lp, seam)) for lp in tl[:3]]
    rep["d_loops"] = [(len(lp), on_seam(lp, dseam)) for lp in dlp[:3]]
    def merged(lps, s):
        # every boundary run lying on the seam, as one sequence ordered round the seam (a cut through a pinch
        # point splits the boundary into several loops)
        runs = [lp for lp in lps if len(lp) >= 3 and on_seam(lp, s) >= 0.8 * len(lp)] or lps[:1]
        vs, us, seen = [], [], set()
        for lp in runs:
            for v, u in zip(lp, loop_u(lp, s, bone)):
                if v not in seen:
                    seen.add(v)
                    vs.append(v)
                    us.append(u)
        order = np.argsort(us)
        return [vs[i] for i in order], np.asarray(us)[order], len(runs)

    LA, uA, nA = merged(tl, seam)
    LB, uB, nB = merged(dlp, dseam)
    rep["runs"] = [nA, nB]
    mono = lambda u: bool(np.all(np.diff(np.unwrap(np.append(u, u[0]), period=4.0)) > -1e-6))
    rep["monotone"] = [mono(uA), mono(uB)]
    affine_uv = ns["tp_affine_uv"]

    def uvfun(P):
        hit = uv_bvh.find_nearest(Vector(np.mean(P, 0).tolist()))
        return affine_uv(Vt, uv_tris[hit[2]], uv_uvs[hit[2]], P)

    ns["tp_loops_dbg"] = (np.array([bone(v.co) for v in LA]), np.array(uA), np.array([bone(v.co) for v in LB]), np.array(uB))
    strip = ns["tp_zipper"](bm, list(LA), list(LB), np.asarray(uA), np.asarray(uB), mi, uvl, lambda v: bone(v.co), uvfun, period=4.0)
    rep["strip"] = len(strip)
    seam_v = set(LA)
    # close every other hole the cut left in or round the cranium (a pinch point in a cut loop, a donor's open
    # hair seam, an earlobe sliced by the nape plane): all open edges near the seam, filled loop by loop
    def near_seam(v):
        p = bone(v.co)
        return p[0] > seam.nape_back - 0.02 and (min(seam.piece(p)[0], dseam.piece(p)[0]) < 0.015 or dseam.replaced(p)[0])
    open_e = [e for e in bm.edges if len(e.link_faces) == 1 and near_seam(e.verts[0]) and near_seam(e.verts[1])]
    filled = 0
    if open_e:
        res = bmesh.ops.holes_fill(bm, edges=open_e, sides=0)
        tri = bmesh.ops.triangulate(bm, faces=res["faces"], quad_method="BEAUTY", ngon_method="BEAUTY")["faces"]
        for f in tri:
            f.material_index = mi
            f.smooth = True
            P = [bone(v.co) for v in f.verts]
            for l, uv in zip(f.loops, uvfun(P)):
                l[uvl].uv = Vector((float(uv[0]), float(uv[1])))
            filled += 1
    rep["holes_filled"] = [len(open_e), filled]

    # --- donor weights from the nearest original vertex ---
    src = bpy.data.objects["mesh"]
    Sb = np.array([v.co[:] for v in src.data.vertices]) @ tb[:3, :3].T + tb[:3, 3]
    sidx = np.flatnonzero(Sb[:, 0] > -0.15)
    kd = KDTree(len(sidx))
    for j, i in enumerate(sidx):
        kd.insert(Vector(Sb[i].tolist()), j)
    kd.balance()
    dverts = {v for f in bm.faces if isd(f) for v in f.verts} - seam_v
    for v in dverts:
        _, j, _ = kd.find(Vector(bone(v.co).tolist()))
        sv = src.data.vertices[int(sidx[j])]
        for gi in list(v[dl].keys()):
            del v[dl][gi]
        for ge in sv.groups:
            if ge.weight > 0:
                v[dl][ge.group] = ge.weight

    # --- donor displacement fades out biharmonically from the seam (the target stays put) ---
    verts = [v for v in bm.verts if bone(v.co)[0] > -0.11]
    L, idx = ns["tp_laplacian"](verts)
    n = len(verts)
    X = np.array([bone(v.co) for v in verts])
    delta = np.zeros((n, 3))
    known = np.ones(n, bool)
    sp = np.array([bone(v.co) for v in seam_v])
    dseam = np.array([np.min(np.linalg.norm(sp - X[i], axis=1)) for i in range(n)])
    for v, i in idx.items():
        if v in dverts:
            known[i] = dseam[i] >= blend
            continue
        delta[i] = radial_offset(don_bvh, C, X[i])
    L2 = L @ L
    F = np.flatnonzero(~known)
    K = np.flatnonzero(known)
    if len(F):
        delta[F] = np.linalg.solve(L2[np.ix_(F, F)], -L2[np.ix_(F, K)] @ delta[K])
        X[F] = X[F] + delta[F]
    rep["free"] = int(len(F))

    # --- damped thin-plate smoothing of a narrow band across the brow and temple seams ---
    if band_t > 0:
        isdon = np.array([v in dverts for v in verts])
        su = {v: seam.piece(bone(v.co))[1] for v in seam_v}
        front_seam = np.array([bone(v.co) for v in seam_v if su[v] is not None and (su[v] % 4.0 < 2.0 - 1e-3 or su[v] % 4.0 > 3.0 + 1e-3)])
        if len(front_seam):
            dfs = np.array([np.min(np.linalg.norm(front_seam - X[i], axis=1)) for i in range(n)])
            F2 = np.flatnonzero((np.where(isdon, dfs < band_d, dfs < band_t)) & (X[:, 0] > seam.nape_side + 0.005))
            K2 = np.setdiff1d(np.arange(n), F2)
            X0 = X.copy()
            M = L2[np.ix_(F2, F2)] + mu * np.eye(len(F2))
            X[F2] = np.linalg.solve(M, mu * X0[F2] - L2[np.ix_(F2, K2)] @ X[K2])
            mv = np.linalg.norm(X[F2] - X0[F2], axis=1)
            rep["fair_mm"] = [int(len(F2)), round(float(np.median(mv)) * 1000, 2), round(float(np.max(mv)) * 1000, 2)]
    for i in range(n):
        verts[i].co = mesh_pt(X[i])

    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 3], quad_method="BEAUTY", ngon_method="BEAUTY")
    head = [f for f in bm.faces if bone(f.calc_center_median())[0] > -0.08]
    bmesh.ops.recalc_face_normals(bm, faces=head)
    rep["open_edges"] = sum(1 for e in bm.edges if len(e.link_faces) == 1 and min(bone(e.verts[0].co)[0], bone(e.verts[1].co)[0]) > -0.05)
    rep["tris_donor"] = sum(1 for f in bm.faces if isd(f))
    bm.normal_update()
    bm.to_mesh(work.data)
    bm.free()
    ns["cur_tp"] = dict(skin=skin, donor=donor, A=A, Vt=Vt, C=C, seam=seam, dseam=dseam, mi=mi, rep=rep, bvh=don_bvh, d=d, uv=(uv_bvh, uv_tris, uv_uvs))
    rep.update(donor=donor, rms_mm=round(A["rms"] * 1000, 2), scale=np.round(A["s"], 3).tolist())
    return rep


ns.update(transplant3=transplant3, Seam=Seam, tp3_bisect=bisect, tp3_snap=snap, tp3_loop_u=loop_u)
