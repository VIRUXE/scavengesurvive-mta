"""Rebuild a hatless twin's bare head from its reference image (#89): run inside Blender with the DragonFF add-on.

    blender -b --python tools/blender/rebuild_head.py -- build <job.json>
    blender -b --python tools/blender/rebuild_head.py -- dump <ped dir> <name> <tex> <out json> <out atlas png>

`tools/hatless_rebuild.py` writes the job: the ped's DFF and TXD, its cut plane and hat blocks, the Head bone's world
matrix in the studio and the registration of its reference. `build`:

1. Cut. Every face above a plane in Head bone space goes: the brow height over the face and ears, a lower height
   behind them (under the hat's rim). So do faces above the jaw in the headgear's own atlas blocks: blocks used
   above the plane and nowhere on the kept face, neck or body, plus the hand-listed ones (a visor, a brim, a band).
2. Skull. From the largest boundary circuit of the cut, rings of vertices run to an apex over the Head bone's up
   axis; each vertex is pushed out to the reference's visual hull: the farthest point along its ray from the head's
   centre that lands on the bare head (not the green screen) in all four studio views (tools/hatless_proj.py).
   Radii are smoothed and may grow only slowly from the rim, so the forehead continues instead of jutting.
3. Hair. The new faces use their own material and a 256x256 texture with polar UVs (crown in the middle). Each
   texel takes the reference colour from the views that face it best, divided by the studio's lighting factor (the
   game lights the texture again), and fades from the face's own colour at the rim over the first rings.
4. Export `<name>_nohat.dff` and `<name>_nohat.txd`, which holds only the hair: `models` imports it into the base
   skin's shared TXD.
"""
import json
import math
import os
import sys

import addon_utils
import bmesh
import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
from tools import hatless_proj as hp  # noqa: E402

K = 9  # rings between the rim and the apex
TEX = 256
GRID = "level"


def import_ped(ped_dir, name, txds):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for i in list(bpy.data.images):
        bpy.data.images.remove(i)
    files = [{"name": name + ".dff"}] + [{"name": t} for t in txds]
    bpy.ops.import_scene.dff(filepath=os.path.join(ped_dir, name + ".dff"), directory=ped_dir, files=files, load_images=True, remove_doubles=False, txd_pack=True, txd_apply_to_objects=True)
    peds = list(bpy.data.objects)
    ob = max((o for o in peds if o.type == "MESH"), key=lambda o: len(o.vertex_groups))
    arm = next(o for o in peds if o.type == "ARMATURE")
    head = next(b for b in arm.data.bones if b.name.strip() == "Head")
    to_bone = np.array((arm.matrix_world @ head.matrix_local).inverted() @ ob.matrix_world)
    return peds, ob, arm, to_bone


def image_rows(path):
    """An image file as float RGB rows, row 0 at the top."""
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)[::-1, :, :3]
    bpy.data.images.remove(img)
    return a


def dump(ped_dir, name, tex, out_json, out_png):
    _, ob, _, tb = import_ped(ped_dir, name, [name + ".txd"])
    me = ob.data
    g = next(v for v in ob.vertex_groups if v.name.strip() == "Head").index
    verts = [[float(x) for x in np.array(v.co) @ tb[:3, :3].T + tb[:3, 3]] for v in me.vertices]
    headw = [max([x.weight for x in v.groups if x.group == g] or [0]) for v in me.vertices]
    uv = me.uv_layers.active.data
    faces = [[list(p.vertices), [list(uv[li].uv) for li in p.loop_indices]] for p in me.polygons]
    json.dump({"verts": verts, "headw": headw, "faces": faces}, open(out_json, "w"))
    atlas = next(i for i in bpy.data.images if tex.upper() in i.name.upper())
    atlas.filepath_raw = out_png
    atlas.file_format = "PNG"
    atlas.save()


def boundary_circuits(edges):
    """Closed walks over boundary edges (Hierholzer): a rim that pinches against itself visits that vertex twice."""
    by_vert = {}
    for e in edges:
        for v in e.verts:
            by_vert.setdefault(v, []).append(e)
    used, loops = set(), []
    for start in list(by_vert):
        if all(e in used for e in by_vert[start]):
            continue
        stack, circuit = [start], []
        while stack:
            v = stack[-1]
            e = next((e for e in by_vert[v] if e not in used), None)
            if e is None:
                circuit.append(stack.pop())
            else:
                used.add(e)
                stack.append(e.other_vert(v))
        if len(circuit) > 3:
            loops.append(circuit[:-1])
    return sorted(loops, key=len, reverse=True)


def build(job):
    name, tex, plane = job["name"], job["tex"], job["plane"]
    peds, ob, arm, tb = import_ped(job["ped_dir"], name, [name + ".txd"])
    atlas = next(i for i in bpy.data.images if tex.upper() in i.name.upper())
    views = hp.GRIDS[GRID]
    bone_m = np.array(job["bone_matrix"])
    offset, xform, light = job["offset"], job["ref_xform"], np.array(job["light"])

    def world(p):  # mesh space -> world
        return hp.to_world(bone_m, np.asarray(p, dtype=np.float64) @ tb[:3, :3].T + tb[:3, 3])

    def ref_xy(view, w):
        return hp.to_reference(GRID, view, hp.to_grid(GRID, view, hp.to_shot(view, w), offset[view]), xform[view])

    ref = image_rows(job["reference"])
    solid = ~((ref[..., 1] > ref[..., 0] + 0.2) & (ref[..., 1] > ref[..., 2] + 0.2))
    tinted = (ref[..., 1] > ref[..., 0] + 0.06) & (ref[..., 1] > ref[..., 2] + 0.06)  # green-screen fringe: never hair

    def sample(view, w):
        xy = np.round(ref_xy(view, w)).astype(int)
        return np.clip(xy[:, 1], 0, ref.shape[0] - 1), np.clip(xy[:, 0], 0, ref.shape[1] - 1)

    def inside(pts):
        w = world(pts)
        ok = np.ones(len(pts), bool)
        for view in views:
            ok &= solid[sample(view, w)]
        return ok

    # 1. cut
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    deform = bm.verts.layers.deform.verify()
    headg = next(g for g in ob.vertex_groups if g.name.strip() == "Head").index

    def bone(p):
        return np.asarray(p) @ tb[:3, :3].T + tb[:3, 3]

    def blk(f):
        u = sum(lp[uvl].uv.x for lp in f.loops) / len(f.loops)
        v = sum(lp[uvl].uv.y for lp in f.loops) / len(f.loops)
        return (int((u % 1.0) * 8), int(((1 - v) % 1.0) * 8))

    above, below, doomed, rest = set(), set(), [], []
    for f in bm.faces:
        pb = bone(sum((v.co for v in f.verts), Vector()) / len(f.verts))
        t = min(1.0, max(0.0, (pb[1] + 0.05) / 0.07))  # the front height over the face and ears, the back one behind
        if pb[0] > plane["back"] + (plane["front"] - plane["back"]) * t:
            doomed.append(f)
            above.add(blk(f))
            continue
        rest.append((f, pb[0]))
        if pb[0] < 0.02 or (pb[1] > 0.03 and pb[0] < plane["front"] - 0.015):  # chin, neck, body; the face below the brow
            below.add(blk(f))
    blocks = (above - below) | {tuple(b) for b in plane.get("blocks", ())}
    listed = {tuple(b) for b in job["listed_blocks"]}  # may share a block with the clothes: only above 0.03 m
    doomed += [f for f, h in rest if (h > -0.01 and blk(f) in blocks) or (h > 0.03 and blk(f) in listed)]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if v.is_boundary and bone(v.co)[0] >= -0.03], dist=0.001)
    loops = boundary_circuits([e for e in bm.edges if e.is_boundary and min(bone(v.co)[0] for v in e.verts) >= -0.03])
    loop = loops[0]
    n = len(loop)

    # 2. skull
    headv = [v.co.copy() for v in bm.verts if v[deform].get(headg, 0) > 0.5]
    cc = np.array(sum(headv, Vector()) / len(headv))
    inv = np.linalg.inv(tb)
    up = inv[:3, :3] @ np.array([1.0, 0, 0])
    up /= np.linalg.norm(up)
    fwd = inv[:3, :3] @ np.array([0, 1.0, 0])
    fwd -= up * (fwd @ up)
    fwd /= np.linalg.norm(fwd)
    side = np.cross(up, fwd)
    rim = np.array([list(v.co) for v in loop])
    d0 = (rim - cc) / np.linalg.norm(rim - cc, axis=1)[:, None]
    rs = np.linspace(0.26, 0.02, 241)
    grid = np.zeros((K + 2, n, 3))  # level 0 = rim, level K+1 = apex
    grid[0] = rim
    for k in range(1, K + 2):
        t = k / (K + 1)
        for i in range(n):
            om = math.acos(max(-1.0, min(1.0, float(d0[i] @ up))))
            d = up if om < 1e-6 or k == K + 1 else (math.sin((1 - t) * om) * d0[i] + math.sin(t * om) * up) / math.sin(om)
            cand = cc + rs[:, None] * d
            ok = inside(cand)
            grid[k, i] = cand[np.argmax(ok)] if ok.any() else cc + 0.08 * d
    rad = np.linalg.norm(grid - cc, axis=2)
    dirs = (grid - cc) / rad[..., None]
    for _ in range(15):
        sm = rad.copy()
        sm[1:-1] = (rad[1:-1] * 2 + np.roll(rad[1:-1], 1, 1) + np.roll(rad[1:-1], -1, 1) + rad[:-2] + rad[2:]) / 6
        sm[-1] = rad[-1].mean()
        rad[1:] = sm[1:]
    for _ in range(3):
        for k in range(1, K + 2):
            rad[k] = np.minimum(rad[k], rad[k - 1] * (1.06 if k == 1 else 1.10))
        sm = rad.copy()
        sm[1:-1] = (rad[1:-1] * 2 + np.roll(rad[1:-1], 1, 1) + np.roll(rad[1:-1], -1, 1)) / 4
        rad[1:-1] = sm[1:-1]
        rad[-1] = rad[-1].mean()
    grid[1:] = cc + dirs[1:] * rad[1:, :, None]
    grid[-1] = grid[-1].mean(0)

    # 3. hair: geometry on its own material, polar UVs, baked from the reference
    hair_name = (name + "_hair")[:31]
    hair_img = bpy.data.images.new(hair_name, TEX, TEX, alpha=True)
    mat = bpy.data.materials.new(hair_name)
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = hair_img
    node.label = hair_name
    bsdf = next(nd for nd in mat.node_tree.nodes if nd.type == "BSDF_PRINCIPLED")
    mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    mat.dff.tex_name = hair_name
    me.materials.append(mat)
    mi = len(me.materials) - 1
    phi = np.arctan2(d0 @ side, d0 @ fwd)
    rows = []
    for k in range(K + 2):
        row = []
        for i in range(n):  # level 0 copies the rim: a DFF keeps one UV per vertex, the rim keeps the atlas's
            nv = bm.verts.new(Vector(grid[k, i]))
            nv[deform][headg] = 1.0
            row.append(nv)
        rows.append(row + [row[0]])
    old = len(bm.faces)

    def uvk(k, i):
        r = 0.47 * (1 - k / (K + 1))
        return Vector((0.5 + r * math.cos(phi[i % n]), 0.5 + r * math.sin(phi[i % n])))

    for k in range(K + 1):
        for i in range(n):
            vs = [rows[k][i], rows[k][i + 1], rows[k + 1][i + 1], rows[k + 1][i]]
            uvs = [uvk(k, i), uvk(k, i + 1), uvk(k + 1, i + 1), uvk(k + 1, i)]
            if k == K:
                vs, uvs = vs[:3], uvs[:3]
            if len(set(vs)) < len(vs):
                continue
            try:
                f = bm.faces.new(vs)
            except ValueError:
                continue
            f.material_index = mi
            f.smooth = True
            for lp, u in zip(f.loops, uvs):
                lp[uvl].uv = u
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=[bm.faces[i] for i in range(old, len(bm.faces))])

    uu, vv = np.meshgrid((np.arange(TEX) + 0.5) / TEX, (np.arange(TEX) + 0.5) / TEX)
    vv = 1 - vv  # image row 0 is UV v = 1
    r = np.minimum(np.hypot(uu - 0.5, vv - 0.5) / 0.47, 1.0)
    ang = np.arctan2(vv - 0.5, uu - 0.5)
    un = np.unwrap(np.append(phi, phi[0]))
    sgn = 1 if un[-1] > un[0] else -1
    fi = np.interp((ang - un[0]) * sgn % (2 * math.pi), (un - un[0]) * sgn, np.arange(n + 1))
    fk = (1 - r) * (K + 1)
    i0 = np.floor(fi).astype(int) % n
    i1 = (i0 + 1) % n
    k0 = np.clip(np.floor(fk).astype(int), 0, K)
    ti, tk = fi - np.floor(fi), fk - k0
    w00, w01, w10, w11 = (1 - ti) * (1 - tk), ti * (1 - tk), (1 - ti) * tk, ti * tk
    P = (grid[k0, i0] * w00[..., None] + grid[k0, i1] * w01[..., None] + grid[k0 + 1, i0] * w10[..., None] + grid[k0 + 1, i1] * w11[..., None]).reshape(-1, 3)
    N = (P - cc) / np.linalg.norm(P - cc, axis=1)[:, None]
    Pw = world(P)
    Nw = (N @ tb[:3, :3].T) @ bone_m[:3, :3]
    acc, wsum = np.zeros((len(P), 3)), np.zeros(len(P))
    for view in views:
        to_cam = hp.camera(view)[0] - Pw
        to_cam /= np.linalg.norm(to_cam, axis=1)[:, None]
        yx = sample(view, Pw)
        wgt = np.clip((Nw * to_cam).sum(1), 0, 1) ** 4 * (solid[yx] & ~tinted[yx])
        acc += ref[yx] * wgt[:, None]
        wsum += wgt
    col = np.where(wsum[:, None] > 1e-4, acc / np.maximum(wsum, 1e-4)[:, None], np.nan).reshape(TEX, TEX, 3)
    for _ in range(64):  # texels no view saw take their neighbours' colour
        holes = np.isnan(col[..., 0])
        if not holes.any():
            break
        pad = np.pad(col, ((1, 1), (1, 1), (0, 0)), mode="wrap")
        fill = np.nanmean(np.stack([pad[:-2, 1:-1], pad[2:, 1:-1], pad[1:-1, :-2], pad[1:-1, 2:]]), 0)
        col[holes] = fill[holes]
    col = np.clip(np.nan_to_num(col, nan=0.1) / np.maximum(light, 0.5), 0, 1)
    apx = np.array(atlas.pixels[:], dtype=np.float32).reshape(atlas.size[1], atlas.size[0], 4)[..., :3]
    rimcol = []
    for v in loop:
        ls = [lp for lp in v.link_loops if lp.face.material_index != mi]
        uv = ls[0][uvl].uv if ls else None
        rimcol.append(None if uv is None else apx[min(atlas.size[1] - 1, int((uv.y % 1.0) * atlas.size[1])), min(atlas.size[0] - 1, int((uv.x % 1.0) * atlas.size[0]))])
    mean_rim = np.mean([c for c in rimcol if c is not None], 0)
    rimcol = np.array([c if c is not None else mean_rim for c in rimcol])
    # at the front the rim can run through the eyebrows: a rim texel much darker than the face's skin takes the skin
    skin = []
    for f in bm.faces:
        if f.material_index == mi:
            continue
        pb = bone(sum((v.co for v in f.verts), Vector()) / len(f.verts))
        if pb[1] > 0.03 and 0.02 < pb[0] < plane["front"] - 0.02:
            u = sum(lp[uvl].uv.x for lp in f.loops) / len(f.loops)
            v = sum(lp[uvl].uv.y for lp in f.loops) / len(f.loops)
            skin.append(apx[min(atlas.size[1] - 1, int((v % 1.0) * atlas.size[1])), min(atlas.size[0] - 1, int((u % 1.0) * atlas.size[0]))])
    if skin:
        skin = np.median(np.array(skin), 0)
        lum = np.array([0.299, 0.587, 0.114])
        front = np.array([bone(np.array(v.co))[1] > 0.0 for v in loop])
        dark = front & (rimcol @ lum < 0.8 * (skin @ lum))
        rimcol[dark] = skin
    rc = (rimcol[i0] * (1 - ti)[..., None] + rimcol[i1] * ti[..., None]).reshape(TEX, TEX, 3)
    # over the face the rim sits just above the brows, so the skin carries further up (4 rings) before the reference's
    # forehead takes over; elsewhere 2.5 rings
    facing = np.clip((np.cos(ang - np.arctan2(0.0, 1.0)) - 0.3) / 0.5, 0, 1)  # 1 towards the face (+fwd = UV +u)
    fade = np.clip(((1 - r) * (K + 1)) / (2.5 + 1.5 * facing), 0, 1)[..., None]
    col = rc * (1 - fade) + col * fade
    hair_img.pixels = np.concatenate([col, np.ones((TEX, TEX, 1))], 2)[::-1].astype(np.float32).ravel().tolist()

    # 4. export
    bm.to_mesh(me)
    bm.free()
    me.update()
    # the texture's own spelling in the TXD ("<txd>/<TEXTURE>/0"): GTA matches names without case, Blender does not
    tex_name = atlas.name.split("/")[1] if atlas.name.count("/") >= 2 else tex
    atlas.name = tex_name
    for m in me.materials[:mi]:
        m.dff.tex_name = tex_name
    out_dir = job["out_dir"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in peds:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_dff.scene(filepath=os.path.join(out_dir, name + "_nohat.dff"), export_coll=False, only_selected=True, export_version="0x36003")
    from DragonFF.gtaLib import txd as rwtxd
    from DragonFF.ops.txd_exporter import txd_exporter

    t = rwtxd.txd()
    t.device_id = rwtxd.DeviceType.DEVICE_D3D9
    t.native_textures = [txd_exporter._create_texture_native_from_image(hair_img, hair_name)]
    t.write_file(os.path.join(out_dir, name + "_nohat.txd"), 0x36003)
    print(f"REBUILT {name}: {len(doomed)} faces cut, rim of {n}, skull radius {rad.min():.3f}..{rad.max():.3f} m, {len(me.polygons)} faces")


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :]
    addon_utils.enable("DragonFF", default_set=False)
    if argv[0] == "dump":
        dump(*argv[1:6])
    else:
        build(json.load(open(argv[1])))
