# exec'd in the live Blender session (driver namespace `ns`): transplant a donor ped's whole cranium (mesh, ears and
# uvs) onto a target ped whose hat was cut away. Both heads are cut along the same surfaces (a brow plane across the
# face, two temple planes through the cranium centre, a nape plane behind), the two cut loops are split to the same
# vertices and welded, and the donor's displacement towards the target fades out biharmonically from the seam, so
# the join is smooth and the rest of the cranium keeps the donor's real shape.
import math
import os

import bmesh
import bpy
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

import tools.hatless_rebuild as HR

DON = ns["DON"]
UP, FWD = np.array([1.0, 0, 0]), np.array([0, 1.0, 0])
SIDE = np.cross(UP, FWD)


def load_donor_full(name):
    """donor head and neck faces in the donor's Head bone space, with per-corner uvs and the texture pixels"""
    cache = ns.setdefault("donors_full", {})
    if name in cache:
        return cache[name]
    sc = bpy.data.scenes.get("donors") or bpy.data.scenes.new("donors")
    win = bpy.context.window.scene
    bpy.context.window.scene = sc
    for o in list(sc.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    pdir = DON + r"\peds"
    files = [{"name": name + ".dff"}, {"name": name + ".txd"}]
    bpy.ops.import_scene.dff(filepath=os.path.join(pdir, name + ".dff"), directory=pdir, files=files, load_images=True, remove_doubles=False, txd_pack=True, txd_apply_to_objects=True)
    mesh = max((o for o in sc.objects if o.type == "MESH"), key=lambda o: len(o.vertex_groups))
    arm = next(o for o in sc.objects if o.type == "ARMATURE")
    head = next(b for b in arm.data.bones if b.name.strip() == "Head")
    tb = np.array((arm.matrix_world @ head.matrix_local).inverted() @ mesh.matrix_world)
    G = ns["head_groups"](mesh, arm)
    neck = {v.index for v in mesh.vertex_groups if v.name.strip() == "Neck"}
    me = mesh.data
    hw = np.array([ns["head_weight"](v, G) for v in me.vertices])
    nw = np.array([ns["head_weight"](v, neck) for v in me.vertices])
    V = np.array([v.co[:] for v in me.vertices]) @ tb[:3, :3].T + tb[:3, 3]
    uvd = me.uv_layers.active.data
    pix = {}
    for i, m in enumerate(me.materials):
        node = next((n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"), None) if m and m.node_tree else None
        if node and node.image:
            w, h = node.image.size
            pix[i] = (node.image.name, np.array(node.image.pixels[:], dtype=np.float32).reshape(h, w, 4))
    faces, uvs, fmat = [], [], []
    for p in me.polygons:
        vs = list(p.vertices)
        # head and neck by weight, plus everything at head height (necks are often weighted to the spine)
        if (hw[vs] + nw[vs]).min() < 0.5 and not (V[vs, 0].min() > -0.11 and np.hypot(V[vs, 1], V[vs, 2]).max() < 0.12):
            continue
        faces.append(vs)
        uvs.append([tuple(uvd[li].uv) for li in p.loop_indices])
        fmat.append(p.material_index)
    me.calc_loop_triangles()
    T = np.array([t.vertices[:] for t in me.loop_triangles if all(hw[i] > 0.5 for i in t.vertices)])
    TN = np.array([t.vertices[:] for t in me.loop_triangles if all(hw[i] + nw[i] > 0.5 for i in t.vertices)])
    for o in list(sc.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for m in list(bpy.data.meshes):
        if m.users == 0:
            bpy.data.meshes.remove(m)
    bpy.context.window.scene = win
    d = dict(name=name, V=V, T=T, TN=TN, faces=faces, uvs=uvs, fmat=fmat, pix=pix, hw=hw, used=np.unique(T))
    cache[name] = d
    return d


def azim(P, C):
    d = np.atleast_2d(P) - C
    return np.degrees(np.arctan2(d @ SIDE, d @ FWD))


class Cut:
    """the seam: brow plane x = front (|az| < face_az), temple planes |az| = face_az through C, nape plane x = nape"""

    def __init__(self, C, front, nape, face_az):
        self.C, self.front, self.nape, self.face_az = np.asarray(C, float), front, nape, face_az
        self.normals = {}
        for sgn in (1, -1):
            a = math.radians(face_az) * sgn
            self.normals[sgn] = (np.cross(UP, FWD * math.cos(a) + SIDE * math.sin(a)), FWD * math.cos(a) + SIDE * math.sin(a))

    def replaced(self, P):
        P = np.atleast_2d(P)
        return (P[:, 0] > self.front) | ((np.abs(azim(P, self.C)) > self.face_az) & (P[:, 0] > self.nape))

    def piece(self, p, tol=4e-4):
        """(distance, u) of a point to the seam: u 0..1 brow (+az to -az), 1..2 temple -az (down), 2..3 nape (round
        the back), 3..4 temple +az (up)"""
        x = p[0]
        az = float(azim(p, self.C)[0])
        fa = self.face_az
        best = (1e9, None)
        if abs(az) <= fa + 1.0:
            best = min(best, (abs(x - self.front), (fa - az) / (2 * fa)))
        if abs(az) >= fa - 1.0:
            b = (-fa - az) % 360.0
            best = min(best, (abs(x - self.nape), 2 + b / (360 - 2 * fa)))
        span = self.front - self.nape
        for sgn in (1, -1):
            n, dvec = self.normals[sgn]
            if (p - self.C) @ dvec > 0 and self.nape - tol <= x <= self.front + tol:
                dist = abs((p - self.C) @ n)
                t = (self.front - x) / span
                best = min(best, (dist, 1 + t if sgn < 0 else 4 - t))
        return best


def bone_of(tb):
    return lambda co: np.array(co) @ tb[:3, :3].T + tb[:3, 3]


def bisect_cut(bm, tb, cut, margin=0.03, amargin=25.0):
    inv = np.linalg.inv(tb)
    R = tb[:3, :3]
    bone = bone_of(tb)

    def run(p_b, n_b, sel):
        fs = []
        for f in bm.faces:
            c = bone(f.calc_center_median())
            if sel(c, float(azim(c, cut.C)[0])):
                fs.append(f)
        if not fs:
            return
        geom = fs + list({e for f in fs for e in f.edges}) + list({v for f in fs for v in f.verts})
        p_m = Vector((np.array(p_b) @ inv[:3, :3].T + inv[:3, 3]).tolist())
        n_m = Vector((R.T @ np.array(n_b)).tolist())
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p_m, plane_no=n_m, dist=1e-5)

    fa = cut.face_az
    run([cut.front, 0, 0], UP, lambda c, a: abs(c[0] - cut.front) < margin and abs(a) < fa + amargin)
    for sgn in (1, -1):
        run(cut.C, cut.normals[sgn][0], lambda c, a, s=sgn: cut.nape - margin < c[0] < cut.front + margin and abs(a - s * fa) < amargin)
    run([cut.nape, 0, 0], UP, lambda c, a: abs(c[0] - cut.nape) < margin and abs(a) > fa - amargin)


def seam_verts(bm, faces, tb, cut, tol=6e-4):
    """boundary vertices of `faces` lying on the seam: {vert: u}"""
    bone = bone_of(tb)
    fs = set(faces)
    out = {}
    for f in faces:
        for e in f.edges:
            if sum(1 for g in e.link_faces if g in fs) != 1:
                continue
            for v in e.verts:
                if v in out:
                    continue
                dist, u = cut.piece(bone(v.co))
                if dist < tol:
                    out[v] = u % 4.0
    return out


def seam_edges(faces, sv):
    fs = set(faces)
    es = []
    for f in faces:
        for e in f.edges:
            if sum(1 for g in e.link_faces if g in fs) == 1 and e.verts[0] in sv and e.verts[1] in sv:
                es.append(e)
    return list(set(es))


def udiff(a, b):
    d = (b - a) % 4.0
    return d if d <= 2.0 else d - 4.0


def split_at(bm, edges, sv, targets, uvl, dl, tol=2e-4):
    """split the seam `edges` at every u of `targets` that is not already a vertex; returns the new {vert: u}"""
    have = np.array(sorted(sv.values()))
    new = {}
    for u in targets:
        if len(have) and np.min(np.abs((have - u + 2.0) % 4.0 - 2.0)) < tol:
            continue
        for e in edges:
            a, b = e.verts
            ua, ub = sv[a], sv[b]
            span = udiff(ua, ub)
            if abs(span) < 1e-9:
                continue
            t = udiff(ua, u) / span
            if 0.0 < t < 1.0:
                # loops of the faces round the edge, to interpolate their uvs after the split
                info = []
                for l in e.link_loops:
                    la, lb = (l, l.link_loop_next) if l.vert is a else (l.link_loop_next, l)
                    info.append((l.face, la[uvl].uv.copy(), lb[uvl].uv.copy()))
                wa = dict(a[dl].items()) if dl else {}
                wb = dict(b[dl].items()) if dl else {}
                ne, nv = bmesh.utils.edge_split(e, a, t)
                nv.co = a.co.lerp(b.co, t)
                if dl:
                    for k in set(wa) | set(wb):
                        nv[dl][k] = wa.get(k, 0.0) * (1 - t) + wb.get(k, 0.0) * t
                for face, uva, uvb in info:
                    for l in face.loops:
                        if l.vert is nv:
                            l[uvl].uv = uva.lerp(uvb, t)
                sv[nv] = u
                new[nv] = u
                edges.remove(e)
                edges.extend([ed for ed in nv.link_edges if ed.verts[0] in sv and ed.verts[1] in sv])
                have = np.append(have, u)
                break
    return new


def laplacian(verts):
    idx = {v: i for i, v in enumerate(verts)}
    n = len(verts)
    L = np.eye(n)
    for v, i in idx.items():
        nb = [idx[e.other_vert(v)] for e in v.link_edges if e.other_vert(v) in idx]
        if nb:
            L[i, nb] -= 1.0 / len(nb)
    return L, idx


def hat_rule(skin, extra_blocks=(), keep_blocks=()):
    """cut3's hat test as a predicate on (bone-space centroid, atlas block), measured on the untouched mesh"""
    work = ns["make_work"]()
    tb = ns["tb"]
    plane = dict(HR.PLANES[skin])
    listed = set(map(tuple, HR.listed_blocks(skin))) | set(map(tuple, extra_blocks))
    keep = set(map(tuple, keep_blocks))
    bm = bmesh.new()
    bm.from_mesh(work.data)
    uvl = bm.loops.layers.uv.active
    bone = bone_of(tb)
    above, below = set(), set()
    for f in bm.faces:
        pb = bone(f.calc_center_median())
        b = face_block(f, uvl)
        if pb[0] > tilted(plane, pb):
            above.add(b)
        elif pb[0] < 0.02 or (pb[1] > 0.03 and pb[0] < plane["front"] - 0.015):
            below.add(b)
    bm.free()
    blocks = ((above - below) | {tuple(b) for b in plane.get("blocks", ())}) - keep

    def is_hat(pb, b):
        if b in keep:
            return False
        if pb[0] > tilted(plane, pb):
            return True
        if pb[1] > -0.01 and pb[0] < plane["front"] - 0.045:
            return False
        return (pb[0] > -0.01 and b in blocks) or (pb[0] > 0.03 and b in listed)

    is_hat.above = above - keep
    return is_hat


def tilted(plane, pb):
    t = min(1.0, max(0.0, (pb[1] + 0.05) / 0.07))
    return plane["back"] + (plane["front"] - plane["back"]) * t


def face_block(f, uvl):
    u = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
    v = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
    return (int((u % 1.0) * 8), int(((1 - v) % 1.0) * 8))


def coverage(edges, sv):
    """share of the seam (u in 0..4) covered by the given seam edges"""
    tot = 0.0
    for e in edges:
        tot += abs(udiff(sv[e.verts[0]], sv[e.verts[1]]))
    return round(tot / 4.0, 3)


def transplant(skin, donor=None, face_az=62.0, nape=0.0, front=None, blend=0.05, near=0.012, front_drop=0.025, nape_min=-0.03, extra_blocks=(), keep_blocks=()):
    donor = donor or ns["donor_choice"][skin]
    name, tex, size = ns["load_skin"](skin)
    tb, g = ns["tb"], ns["g"]
    inv = np.linalg.inv(tb)
    plane = HR.PLANES[skin]
    # align the donor to the face that stays (cut3 strips the hat for the samples only)
    ns["cut3"](skin, extra_blocks=extra_blocks, keep_blocks=keep_blocks)
    P = ns["sample_kept"](bpy.data.objects["work"], tb, g, plane)
    d = load_donor_full(donor)
    A = ns["align"](dict(V=d["V"], T=d["T"]), P)
    Vt = (d["V"] * A["s"]) @ A["R"].T + A["t"]
    used = Vt[d["used"]]
    C = (used.min(0) + used.max(0)) / 2
    C[0] = max(C[0], 0.07)
    don_bvh = BVHTree.FromPolygons([Vector(p) for p in Vt], [list(t) for t in d["TN"]])
    is_hat = hat_rule(skin, extra_blocks, keep_blocks)
    work = ns["make_work"]()
    bone = bone_of(tb)
    mesh_pt = lambda p: Vector((np.array(p) @ inv[:3, :3].T + inv[:3, 3]).tolist())
    rep = {}

    # --- seam placement: dip under every piece of hat that lies on the skin ---
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
    rep["front"], rep["nape"] = round(cut.front, 4), round(cut.nape, 4)

    # --- target: cut along the seam, drop the cranium and any hat left below it ---
    bisect_cut(bm, tb, cut)
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

    # --- donor piece, in the target's mesh space ---
    mat = "hair_" + name
    hm = bpy.data.materials.get(mat) or bpy.data.materials.new(mat)
    hm.use_nodes = True
    names = [m.name for m in work.data.materials]
    if hm.name not in names:
        work.data.materials.append(hm)
        names.append(hm.name)
    mi = names.index(hm.name)
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
    bisect_donor(bm, tb, cut, mi)
    dfaces = [f for f in bm.faces if f.material_index == mi]
    kill = [f for f in dfaces if not cut.replaced(bone(f.calc_center_median()))[0]]
    bmesh.ops.delete(bm, geom=kill, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    dfaces = [f for f in bm.faces if f.material_index == mi]
    tfaces = [f for f in bm.faces if f.material_index != mi]

    # --- seam: split both loops to the same u, weld donor onto target ---
    tsv = seam_verts(bm, tfaces, tb, cut)
    dsv = seam_verts(bm, dfaces, tb, cut)
    tes, des = seam_edges(tfaces, tsv), seam_edges(dfaces, dsv)
    rep.update(t_seam=len(tsv), d_seam=len(dsv), t_cover=coverage(tes, tsv), d_cover=coverage(des, dsv))
    split_at(bm, tes, tsv, sorted(dsv.values()), uvl, dl)
    split_at(bm, des, dsv, sorted(tsv.values()), uvl, None)
    tu = np.array(list(tsv.values()))
    tv = list(tsv.keys())
    weld = {}
    worst = 0.0
    for v, u in dsv.items():
        k = int(np.argmin(np.abs((tu - u + 2.0) % 4.0 - 2.0)))
        worst = max(worst, abs(udiff(tu[k], u)))
        weld[v] = tv[k]
    rep["weld_worst_u"] = round(float(worst), 5)
    gaps = [np.linalg.norm(bone(v.co) - bone(t.co)) for v, t in weld.items()]
    rep["gap_mm"] = [round(float(np.median(gaps)) * 1000, 2), round(float(np.max(gaps)) * 1000, 2)]
    bmesh.ops.weld_verts(bm, targetmap=weld)
    seam = {v for v in tv if v.is_valid}

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
    L, idx = laplacian(verts)
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
    opn = [e for e in bm.edges if len(e.link_faces) == 1 and bone(e.verts[0].co)[0] > -0.03 and bone(e.verts[1].co)[0] > -0.03]
    rep["open_edges"] = len(opn)
    bm.normal_update()
    bm.to_mesh(work.data)
    bm.free()
    ns["cur_tp"] = dict(skin=skin, donor=donor, A=A, Vt=Vt, C=C, cut=cut, mi=mi, rep=rep, bvh=don_bvh, d=d)
    rep.update(donor=donor, rms_mm=round(A["rms"] * 1000, 2), scale=np.round(A["s"], 3).tolist(), C=np.round(C, 3).tolist())
    return rep


def bisect_donor(bm, tb, cut, mi):
    """bisect_cut restricted to the donor's faces (material mi)"""
    inv = np.linalg.inv(tb)
    R = tb[:3, :3]
    bone = bone_of(tb)
    fa = cut.face_az

    def run(p_b, n_b, sel):
        fs = [f for f in bm.faces if f.material_index == mi and sel(bone(f.calc_center_median()))]
        if not fs:
            return
        geom = fs + list({e for f in fs for e in f.edges}) + list({v for f in fs for v in f.verts})
        p_m = Vector((np.array(p_b) @ inv[:3, :3].T + inv[:3, 3]).tolist())
        n_m = Vector((R.T @ np.array(n_b)).tolist())
        bmesh.ops.bisect_plane(bm, geom=geom, plane_co=p_m, plane_no=n_m, dist=1e-5)

    a_of = lambda c: float(azim(c, cut.C)[0])
    run([cut.front, 0, 0], UP, lambda c: abs(c[0] - cut.front) < 0.03 and abs(a_of(c)) < fa + 25)
    for sgn in (1, -1):
        run(cut.C, cut.normals[sgn][0], lambda c, s=sgn: cut.nape - 0.03 < c[0] < cut.front + 0.03 and abs(a_of(c) - s * fa) < 25)
    run([cut.nape, 0, 0], UP, lambda c: abs(c[0] - cut.nape) < 0.03 and abs(a_of(c)) > fa - 25)


ns.update(load_donor_full=load_donor_full, Cut=Cut, transplant=transplant, hat_rule=hat_rule, tp_azim=azim, tp_bone_of=bone_of, tp_face_block=face_block, tp_bisect_cut=bisect_cut, tp_bisect_donor=bisect_donor, tp_laplacian=laplacian, seam_verts=seam_verts, split_at=split_at)
