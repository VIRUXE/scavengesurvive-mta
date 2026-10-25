# exec'd in the live Blender session after tp3.py: textures for a transplanted cranium. The donor's atlas becomes the
# twin's `<name>_hair` texture, recoloured: texels the donor painted as skin take the target's skin tone, texels painted
# as hair take the hair colour of the hatless reference (both keep the donor's shading detail), and a smooth colour
# correction fades in from the seam so the two textures meet without a line. The target's atlas is `<name>_bare`.
import math

import bpy
import numpy as np

LUM = np.array([0.299, 0.587, 0.114])


def raster_tri(P, UV, W, H):
    """texels (x, y) inside a uv triangle and the matching 3D points"""
    U = np.asarray(UV, float) * [W, H]
    x0, y0 = np.floor(U.min(0)).astype(int)
    x1, y1 = np.ceil(U.max(0)).astype(int)
    xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
    q = np.stack([xs.ravel() + 0.5, ys.ravel() + 0.5], 1)
    T = np.array([U[1] - U[0], U[2] - U[0]]).T
    if abs(np.linalg.det(T)) < 1e-9:
        return np.floor(U.mean(0))[None] + 0.5, np.asarray(P, float).mean(0)[None]
    b = np.linalg.solve(T, (q - U[0]).T).T
    w0 = 1 - b.sum(1)
    ins = (b[:, 0] >= -0.02) & (b[:, 1] >= -0.02) & (w0 >= -0.02)
    if not ins.any():
        # a triangle smaller than a texel still owns the texel under its centre
        c = U.mean(0)
        return np.floor(c)[None] + 0.5, np.asarray(P, float).mean(0)[None]
    bary = np.stack([w0, b[:, 0], b[:, 1]], 1)[ins]
    return q[ins], bary @ np.asarray(P, float)


def mesh_texels(work, tb, want):
    """texels of the work mesh's loop triangles passing want(material_index): (q, bone point, mesh point, normal)"""
    me = work.data
    me.calc_loop_triangles()
    uv = me.uv_layers.active.data
    out = {}
    for t in me.loop_triangles:
        key = want(t.material_index)
        if key is None:
            continue
        W, H = key
        X = np.array([me.vertices[v].co[:] for v in t.vertices])
        UV = np.array([uv[l].uv[:] for l in t.loops])
        q, Pm = raster_tri(X, UV, W, H)
        if not len(q):
            continue
        n = np.cross(X[1] - X[0], X[2] - X[0])
        n /= np.linalg.norm(n) + 1e-12
        out.setdefault(t.material_index, []).append((q, Pm, np.repeat(n[None], len(q), 0)))
    res = {}
    for k, lst in out.items():
        q = np.concatenate([a[0] for a in lst])
        Pm = np.concatenate([a[1] for a in lst])
        Nm = np.concatenate([a[2] for a in lst])
        res[k] = (q, Pm @ tb[:3, :3].T + tb[:3, 3], Pm, Nm)
    return res


def robust_mean(c, iters=4, k=2.5):
    keep = np.ones(len(c), bool)
    mu = np.median(c, 0)
    for _ in range(iters):
        mu = c[keep].mean(0)
        sd = c[keep].std(0) + 1e-3
        keep = (np.abs(c - mu) / sd < k).all(1)
    return mu, keep


def two_means(c, seed_a, iters=10):
    """split colours into a cluster near seed_a and the rest; returns (labels a=True, centre a, centre b)"""
    lum = c @ LUM
    ca = np.asarray(seed_a, float)
    cb = c[np.argsort(np.abs(lum - ca @ LUM))[-max(1, len(c) // 5):]].mean(0)
    for _ in range(iters):
        a = np.linalg.norm(c - ca, axis=1) < np.linalg.norm(c - cb, axis=1)
        if a.any():
            ca = c[a].mean(0)
        if (~a).any():
            cb = c[~a].mean(0)
    return a, ca, cb


def seam_dist(P, S):
    out = np.empty(len(P))
    for i in range(0, len(P), 2048):
        out[i : i + 2048] = np.min(np.linalg.norm(P[i : i + 2048, None, :] - S[None], axis=2), 1)
    return out


def set_image(mat, img):
    mat.use_nodes = True
    nt = mat.node_tree
    tn = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None) or nt.nodes.new("ShaderNodeTexImage")
    tn.image = img
    tn.label = img.name
    bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
        nt.links.new(bsdf.outputs[0], out.inputs[0])
    nt.links.new(tn.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0


def texture(skin, hair_rgb=None, detail=0.85, seam_lambda=0.012, mask="donor", crown_h=0.035, brow_skin=0.012, fabric=False, hair_back=False, hair_from_atlas=False, nape_hair=0.018, deshadow=False, ref_front=False, debug_s=False):
    tp = ns["cur_tp"]
    work = bpy.data.objects["work"]
    name, tb = ns["name"], ns["tb"]
    mi, d, Vt, seam = tp["mi"], tp["d"], tp["Vt"], tp["seam"]
    PA, uA = ns["tp_loops_dbg"][0], ns["tp_loops_dbg"][1]
    rep = {}

    # --- images ---
    atlas = bpy.data.images[ns["atlas"]]
    AW, AH = atlas.size
    apx = np.array(atlas.pixels[:], dtype=np.float32).reshape(AH, AW, 4)
    from collections import Counter

    dk = Counter(d["fmat"]).most_common(1)[0][0]
    dpx = d["pix"][dk][1].copy()
    DH, DW = dpx.shape[:2]

    # --- texels ---
    tx = mesh_texels(work, tb, lambda m: (DW, DH) if m == mi else (AW, AH))
    hq, hP, hPm, hN = tx[mi]
    body = [k for k in tx if k != mi]
    bq = np.concatenate([tx[k][0] for k in body])
    bP = np.concatenate([tx[k][1] for k in body])
    bPm = np.concatenate([tx[k][2] for k in body])
    bN = np.concatenate([tx[k][3] for k in body])
    front_seam = PA[(uA % 4.0 < 2.0) | (uA % 4.0 > 3.0)]
    # target skin: just under the brow seam and in front of the temple seams
    ds = seam_dist(bP, front_seam)
    band = (ds > 0.004) & (ds < 0.03) & (bP[:, 0] > seam.front - 0.035)
    tcol = apx[bq[band, 1].astype(int) % AH, bq[band, 0].astype(int) % AW, :3]
    t_skin, keep = robust_mean(tcol)
    # donor skin: the donor's own face in the same band (its faces, aligned)
    dq, dP = [], []
    for vs, uvs, fm in zip(d["faces"], d["uvs"], d["fmat"]):
        if fm != dk:
            continue
        for k in range(1, len(vs) - 1):
            tri = (vs[0], vs[k], vs[k + 1])
            q, P = raster_tri(Vt[list(tri)], [uvs[0], uvs[k], uvs[k + 1]], DW, DH)
            if len(q):
                dq.append(q)
                dP.append(P)
    dq, dP = np.concatenate(dq), np.concatenate(dP)
    dds = seam_dist(dP, front_seam)
    dband = (dds > 0.004) & (dds < 0.03) & ~seam.replaced(dP) & (dP[:, 0] > seam.front - 0.035)
    dcol = dpx[dq[dband, 1].astype(int) % DH, dq[dband, 0].astype(int) % DW, :3]
    d_skin, _ = robust_mean(dcol)
    # donor cranium texels: skin or hair
    hcol = dpx[hq[:, 1].astype(int) % DH, hq[:, 0].astype(int) % DW, :3]
    is_skin, c_skin, c_hair = two_means(hcol, d_skin)
    dist_s = np.linalg.norm(hcol - c_skin, axis=1)
    dist_h = np.linalg.norm(hcol - c_hair, axis=1)
    s = np.clip((dist_h / (dist_s + dist_h + 1e-6) - 0.35) / 0.3, 0, 1)
    bald = np.linalg.norm(c_skin - c_hair) < 0.08
    if bald:
        s[:] = 1.0
    d_hair = c_hair
    # the reference, sampled on the cranium's texels and (for its skin tone) on the face under the seam
    rcol, rw = ns["sample_views"](skin, hPm, hN)
    vis = ~np.isnan(rcol[:, 0]) & (rw > 0.05)
    fcol, fw = ns["sample_views"](skin, bPm[band], bN[band])
    fok = ~np.isnan(fcol[:, 0]) & (fw > 0.05)
    r_skin = robust_mean(fcol[fok])[0] if fok.sum() > 20 else None
    s_d = s.copy()
    t_hair = None if hair_rgb is None else np.array(hair_rgb, float)
    haired = True
    c_rs = c_rh = None
    if r_skin is not None and vis.sum() > 50:
        a_, c_rs, c_rh = two_means(rcol[vis], r_skin)
        haired = (~a_).sum() > 0.15 * vis.sum() and np.linalg.norm(c_rh - c_rs) > 0.06
        if t_hair is None and haired:
            t_hair = np.clip(c_rh, 0, 1)
        rep.update(ref_seen=round(float(vis.mean()), 2), r_skin=np.round(r_skin * 255).astype(int).tolist(), r_hair=np.round(c_rh * 255).astype(int).tolist(), haired=bool(haired))
    haz = np.abs(ns["tp_azim"](hP, seam.C))
    if mask == "ref" and haired and vis.sum() > 50:
        ds_ = np.linalg.norm(rcol[vis] - c_rs, axis=1)
        dh_ = np.linalg.norm(rcol[vis] - c_rh, axis=1)
        s_ref = np.clip((dh_ / (ds_ + dh_ + 1e-6) - 0.35) / 0.3, 0, 1)
        from mathutils.kdtree import KDTree
        from mathutils import Vector
        vi = np.flatnonzero(vis)
        kd = KDTree(len(vi))
        for j, i in enumerate(vi):
            kd.insert(Vector(hP[i].tolist()), j)
        kd.balance()
        sm = np.empty(len(s))
        for i in range(len(s)):
            nb = kd.find_n(Vector(hP[i].tolist()), 12)
            ws = np.array([1.0 / (dd + 0.002) for _, _, dd in nb])
            sm[i] = (ws * s_ref[[j for _, j, _ in nb]]).sum() / ws.sum()
        s = sm
        above = hP[:, 0] - seam.front
        brow = (haz < seam.face_az) & (above < brow_skin)
        s[brow] = np.maximum(s[brow], np.clip(1 - above[brow] / brow_skin, 0, 1) ** 0.5)
        ear = (haz > 62) & (haz < 128) & (hP[:, 0] > seam.nape_side - 0.015) & (hP[:, 0] < seam.front - 0.005)
        s[ear] = np.maximum(s[ear], np.clip((s_d[ear] - 0.4) / 0.3, 0, 1))
    elif haired and hair_back:
        back = (haz > seam.face_az + 12) & ~((haz > 62) & (haz < 128) & (hP[:, 0] < seam.front - 0.01) & (s_d > 0.7))
        s[back] = 0.0
        crown = hP[:, 0] > seam.front + crown_h
        s[crown] = np.minimum(s[crown], np.clip((seam.front + crown_h + 0.01 - hP[crown, 0]) / 0.01, 0, 1))
    elif haired:
        # the donor's own hairline, with hair over any bald crown it has, and the reference's back of the head
        crown = hP[:, 0] > seam.front + crown_h
        s[crown] = np.minimum(s[crown], np.clip((seam.front + crown_h + 0.01 - hP[crown, 0]) / 0.01, 0, 1))
        # the front hairline as the reference draws it (the face-on view sees the forehead well), with skin
        # right above the brows where the reference's eyebrows would otherwise read as hair
        if ref_front and c_rs is not None:
            above = hP[:, 0] - seam.front
            fore = (haz < 50) & (above > 0) & (above < 0.05) & vis & (rw > 0.5)
            if fore.sum() > 20:
                ds_ = np.linalg.norm(rcol[fore] - c_rs, axis=1)
                dh_ = np.linalg.norm(rcol[fore] - c_rh, axis=1)
                s[fore] = np.clip((dh_ / (ds_ + dh_ + 1e-6) - 0.35) / 0.3, 0, 1)
                brow = (haz < seam.face_az) & (above > 0) & (above < brow_skin)
                s[brow] = np.maximum(s[brow], np.clip(1 - above[brow] / brow_skin, 0, 1) ** 0.5)
        # hair over the back and the top of the sides, down to a nape hairline a little above the seam
        lo = seam.nape_h(hP) + nape_hair
        ear = (haz > 62) & (haz < 128) & (hP[:, 0] < seam.front - 0.01) & (s_d > 0.7)
        back = (haz > 95) & ~ear
        ramp = np.clip((hP[:, 0] - lo) / 0.012, 0, 1)
        s[back] = np.minimum(s[back], 1 - ramp[back])
    else:
        s[:] = 1.0
    # the donor's eyebrows: a dark run right above the seam with skin over it, in the face sector, is a brow, not
    # a hairline (the target keeps its own brows below the seam)
    above = hP[:, 0] - seam.front
    face = (haz < seam.face_az - 4) & (above >= 0) & (above < 0.035)
    if face.any():
        ab = np.floor(haz[face] / 6.0).astype(int) * np.sign(ns["tp_azim"](hP[face], seam.C)).astype(int)
        hb = np.floor(above[face] / 0.002).astype(int)
        fi = np.flatnonzero(face)
        brow_n = 0
        for a in np.unique(ab):
            col = ab == a
            meds = {h: float(np.median(s_d[fi[col & (hb == h)]])) for h in np.unique(hb[col])}
            hs = sorted(meds)
            run = []
            for h in hs:
                if meds[h] < 0.5:
                    if run and h - run[-1] > 2:
                        break
                    run.append(h)
                elif run:
                    # skin over a short dark run that starts within 12 mm of the seam: the run is a brow
                    if run[0] <= 6 and run[-1] - run[0] <= 6 and h - run[-1] <= 2:
                        sel = fi[col & (hb >= run[0]) & (hb <= run[-1])]
                        s[sel] = 1.0
                        brow_n += len(sel)
                    break
                elif h > 6:
                    break
        rep["brow_texels"] = int(brow_n)
    if hair_from_atlas:
        back = (np.abs(ns["tp_azim"](bP, seam.C)) > 100) & (bP[:, 0] < seam.nape_back + 0.01) & (bP[:, 0] > seam.nape_back - 0.12)
        cc = apx[bq[back, 1].astype(int) % AH, bq[back, 0].astype(int) % AW, :3]
        if len(cc) > 30:
            a_, cs_, ch_ = two_means(cc, t_skin)
            t_hair = ch_
            rep["atlas_hair"] = np.round(ch_ * 255).astype(int).tolist()
    if t_hair is None:
        t_hair = d_hair * (t_skin / np.maximum(d_skin, 1e-3))
    # --- recolour the donor atlas where the cranium uses it, keeping the donor's shading relative to its own class ---
    lum = hcol @ LUM + 1e-4
    cls = (d_skin @ LUM) * s_d + (d_hair @ LUM) * (1 - s_d)
    rel = lum / np.maximum(cls, 1e-3)
    # skin keeps the shading of texels the donor painted as skin, hair the strands of texels it painted as hair
    skin_new = t_skin[None] * np.clip(1 + 0.6 * (rel - 1) * s_d, 0.8, 1.15)[:, None]
    hair_new = t_hair[None] * np.clip(1 + detail * (rel - 1) * (1 - s_d * 0.7), 0.6, 1.35)[:, None]
    if fabric:
        # a knitted hood (the SWAT balaclava): one colour, a little of the donor's shading, no skin anywhere
        s = np.zeros_like(s)
        hair_new = t_hair[None] * np.clip(1 + 0.25 * (rel - 1), 0.85, 1.15)[:, None]
    new = np.clip(skin_new * s[:, None] + hair_new * (1 - s[:, None]), 0, 1)
    if debug_s:
        new = np.repeat(s[:, None], 3, 1)
    # --- seam correction: per seam position, the target's colour minus the new donor colour next to the seam ---
    hds = seam_dist(hP, PA)
    bds = seam_dist(bP, PA)
    # seam position of every texel near the seam: u of the nearest seam vertex
    def near_u(P):
        out = np.empty(len(P))
        for i in range(0, len(P), 2048):
            out[i : i + 2048] = uA[np.argmin(np.linalg.norm(P[i : i + 2048, None, :] - PA[None], axis=2), 1)]
        return out
    hu = near_u(hP)
    bu = near_u(bP)
    bins = 48
    corr = np.full((bins, 3), np.nan)
    bcol_all = apx[bq[:, 1].astype(int) % AH, bq[:, 0].astype(int) % AW, :3]
    t_is_skin = np.linalg.norm(bcol_all - t_skin, axis=1) < 0.12
    for b in range(bins):
        lo, hi = 4.0 * b / bins, 4.0 * (b + 1) / bins
        mh = (hu >= lo) & (hu < hi) & (hds < 0.012) & (s > 0.6)
        mb = (bu >= lo) & (bu < hi) & (bds < 0.012) & t_is_skin
        if mh.sum() >= 4 and mb.sum() >= 4:
            corr[b] = np.median(bcol_all[mb], 0) - np.median(new[mh], 0)
    good = ~np.isnan(corr[:, 0])
    rep["seam_bins"] = int(good.sum())
    if good.any() and not debug_s:
        cen = (np.arange(bins) + 0.5) * 4.0 / bins
        gc = np.concatenate([cen[good] - 4, cen[good], cen[good] + 4])
        for c in range(3):
            corr[~good, c] = np.interp(cen[~good], gc, np.tile(corr[good, c], 3))
        k = np.array([0.25, 0.5, 0.25])
        for _ in range(3):
            corr = np.stack([np.convolve(np.pad(corr[:, c], 1, mode="wrap"), k, mode="valid") for c in range(3)], 1)
        cu = np.stack([np.interp(hu, np.concatenate([cen - 4, cen, cen + 4]), np.tile(corr[:, c], 3)) for c in range(3)], 1)
        w = np.exp(-hds / seam_lambda) * s
        new = np.clip(new + cu * w[:, None], 0, 1)
    # --- write: average texels hit by several faces (mirrored uvs), then dilate into the unused border ---
    out = dpx.copy()
    acc = np.zeros((DH, DW, 3))
    cnt = np.zeros((DH, DW))
    iy, ix = hq[:, 1].astype(int) % DH, hq[:, 0].astype(int) % DW
    np.add.at(acc, (iy, ix), new)
    np.add.at(cnt, (iy, ix), 1)
    m = cnt > 0
    out[m, :3] = acc[m] / cnt[m][:, None]
    used = m.copy()
    for _ in range(3):
        pad = np.pad(out[..., :3], ((1, 1), (1, 1), (0, 0)), mode="edge")
        pu = np.pad(used, 1)
        nb = np.zeros((DH, DW, 3))
        nc = np.zeros((DH, DW))
        for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
            sel = pu[dy : dy + DH, dx : dx + DW]
            nb += pad[dy : dy + DH, dx : dx + DW] * sel[..., None]
            nc += sel
        grow = ~used & (nc > 0) & ~m
        # only grow over texels the cranium does not use and the donor's own skin/hair would otherwise show
        out[grow, :3] = nb[grow] / nc[grow][:, None]
        used = used | grow
    hair_img = bpy.data.images.get(name + "_hair")
    if hair_img is None or tuple(hair_img.size) != (DW, DH):
        if hair_img is not None:
            bpy.data.images.remove(hair_img)
        hair_img = bpy.data.images.new(name + "_hair", DW, DH)
    hair_img.pixels = out.astype(np.float32).ravel().tolist()
    bare = bpy.data.images.get(name + "_bare")
    if bare is None or tuple(bare.size) != (AW, AH):
        if bare is not None:
            bpy.data.images.remove(bare)
        bare = bpy.data.images.new(name + "_bare", AW, AH)
    if deshadow:
        fixed, norm, p90 = ns["deshadow"](skin, work, mi, apx)
        apx = fixed
        rep["deshadow"] = [round(norm, 3), round(p90, 3)]
    bare.pixels = apx.astype(np.float32).ravel().tolist()
    set_image(work.data.materials[0], bare)
    set_image(work.data.materials[mi], hair_img)
    ns["cur_tex"] = dict(t_skin=t_skin, d_skin=d_skin, t_hair=t_hair, d_hair=d_hair, bald=bool(bald))
    rep.update(t_skin=np.round(t_skin * 255).astype(int).tolist(), d_skin=np.round(d_skin * 255).astype(int).tolist(), t_hair=np.round(np.asarray(t_hair) * 255).astype(int).tolist(), d_hair=np.round(d_hair * 255).astype(int).tolist(), skin_share=round(float(s.mean()), 2), bald=bool(bald))
    return rep


ns.update(tp_texture=texture, tp_raster_tri=raster_tri, tp_mesh_texels=mesh_texels)
