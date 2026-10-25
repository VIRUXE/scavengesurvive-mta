"""Rebuild a bare head for a GTA:SA ped whose mesh carries a hat: run inside Blender with the DragonFF add-on.

    blender --python tools/blender/remodel_head.py -- <ped dir> <out dir> [--only heads|hats|both] [--blocks c,r;c,r] [--above c,r,h] [skin ...]

<ped dir> holds <name>.dff and <name>.txd (tools/extract_ped_models.py puts them in models/work when run with
--keep). For each skin in HEADS the script imports the ped with its texture, deletes the headgear, flattens the cut,
welds the rim and raises a skull over the opening: a thin band that continues the face skin, then rings of hair
textured from the darkest patch of the ped's own atlas, all weighted to the Head bone, and exports
<out dir>/<name>_nohat.dff. The twin keeps the base skin's TXD. Blender's viewport (or the dev studio) is the judge:
GTA models no skull under a hat, so every parameter below was set by eye.

Rules per skin (HEADS): which faces are headgear.
- cap_floor: everything whose centre is this far above the Head bone goes (the crown). The bone sits at the brow on
  most peds, at the chin on some (wmygol1, smokev), hence the per-skin value.
- dark_floor / dark_lum: faces above dark_floor whose texel is darker than dark_lum go (black cap bands); None off.
- bright_floor / bright_lum: the same for light helmets.
- cap_blocks: 8x8 texture blocks (col,row; row 0 at the top) that are headgear below the crown.
- profile: (angle, radial scale) rings of the skull from the rim to the apex; the first is the skin band.
- apex: metres above the rim top for the crown.
"""
import math
import os
import sys

import addon_utils
import bmesh
import bpy

P = ((0.2, 1.0), (0.5, 1.12), (0.85, 1.05), (1.15, 0.8), (1.4, 0.45))
FIRE_BLOCKS = {(4, 6), (4, 7), (5, 6), (5, 7), (6, 6), (6, 7), (7, 6), (7, 7)}
SWAT_BLOCKS = {(3, 5), (3, 6), (3, 7), (4, 5), (4, 6), (4, 7), (5, 5), (5, 6), (6, 5), (6, 6), (7, 5), (7, 6)}
PIZZA_BLOCKS = {(3, 7), (4, 7), (5, 7), (6, 7), (7, 7)}
MACCER_BLOCKS = {(0, 3), (1, 3), (2, 3), (3, 3), (1, 4), (2, 4), (3, 4), (2, 7), (3, 7)}
MACCER_P = ((0.05, 1.0), (0.4, 1.1), (0.8, 1.05), (1.15, 0.8), (1.4, 0.45))
MACCER_UV = (0.2773, 0.2812)
HEADS = {
    # Police & Sheriffs
    4: dict(name="sfpdm1", tex="SFPDM1"),
    119: dict(name="lvpdm1", tex="LVPDM1", dark_floor=-0.005),
    284: dict(name="lapdm1", tex="LAPDM1", dark_floor=None, bright_floor=-0.03, bright_lum=0.6),
    283: dict(name="csher", tex="csher", dark_floor=None),
    288: dict(name="dsher", tex="dsher", dark_floor=None),
    # Military & SWAT
    287: dict(name="army", tex="army", dark_floor=None),
    285: dict(name="swat", tex="swat", dark_floor=None, cap_blocks=SWAT_BLOCKS, apex=0.075),
    # Firefighters
    277: dict(name="lafd1", tex="lafd1", dark_floor=None, cap_floor=0.10, cap_blocks=FIRE_BLOCKS, apex=0.075),
    278: dict(name="lvfd1", tex="lvfd1", dark_floor=None, cap_floor=0.10, cap_blocks=FIRE_BLOCKS, apex=0.075),
    279: dict(name="sffd1", tex="sffd1", dark_floor=None, cap_floor=0.10, cap_blocks=FIRE_BLOCKS, apex=0.075),
    # Civilian & Services
    61: dict(name="wmyplt", tex="wmyplt", dark_floor=-0.005, cap_blocks={(6, 6)}),
    35: dict(name="hmogar", tex="hmogar", dark_floor=None, cap_blocks={(6, 4), (7, 4)}, apex=0.07),
    155: dict(name="wmypizz", tex="wmypizz", dark_floor=None, cap_blocks=PIZZA_BLOCKS),
    205: dict(name="wfyburg", tex="wfyburg", dark_floor=None),
    161: dict(name="cwmyfr", tex="cwmyfr", dark_floor=None),
    36: dict(name="wmygol1", tex="wmygol1", dark_floor=None, apex=0.065),
    37: dict(name="wmygol2", tex="wmygol2", apex=0.065),
    2: dict(name="maccer", tex="maccer", dark_floor=None, cap_floor=0.09, cap_blocks=MACCER_BLOCKS, profile=MACCER_P, apex=0.065, hair_uv=MACCER_UV),
    311: dict(name="smokev", tex="smokev", cap_floor=0.11, dark_floor=None),
    # Bikers
    247: dict(name="bikera", tex="bikera", cap_floor=0.08, dark_floor=None, apex=0.075),
    248: dict(name="bikerb", tex="bikerb", cap_floor=0.07, dark_floor=None, apex=0.075),
    254: dict(name="bikdrug", tex="bikera", cap_floor=0.08, dark_floor=None, apex=0.075),
}


def remodel(src_dir, out_dir, name, tex, cap_floor=0.045, dark_floor=-0.03, dark_lum=0.12, bright_floor=None, bright_lum=0.7, profile=P, apex=0.09, hair_uv=None, cap_blocks=None, only="both", hat_blocks=None, hat_above=None):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for i in list(bpy.data.images):
        bpy.data.images.remove(i)
    files = [{"name": name + ".dff"}, {"name": name + ".txd"}]
    bpy.ops.import_scene.dff(filepath=os.path.join(src_dir, name + ".dff"), directory=src_dir, files=files, load_images=True, remove_doubles=False, txd_pack=True, txd_apply_to_objects=True)
    ped_objects = list(bpy.data.objects)
    ob = next(o for o in ped_objects if o.type == "MESH")
    arm = next(o for o in ped_objects if o.type == "ARMATURE")
    head = next(b for b in arm.data.bones if b.name.strip() == "Head")
    hx = head.head_local.x
    img = next(i for i in bpy.data.images if tex.upper() in i.name.upper())
    W, H = img.size
    px = img.pixels[:]

    def lum(u, v):
        u %= 1.0
        v %= 1.0
        x = min(W - 1, int(u * W))
        y = min(H - 1, int(v * H))
        i = (y * W + x) * 4
        return 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]

    if hair_uv is None:
        best = None
        for y in range(0, H - 6, 2):
            for x in range(0, W - 6, 2):
                s = sum(px[((yy * W + xx) * 4) + c] for yy in range(y, y + 6) for xx in range(x, x + 6) for c in range(3))
                if best is None or s < best[0]:
                    best = (s, x, y)
        hair_uv = ((best[1] + 3) / W, (best[2] + 3) / H)
    me = ob.data
    bm = bmesh.new()
    bm.from_mesh(me)
    uvl = bm.loops.layers.uv.active
    deform = bm.verts.layers.deform.verify()
    headg = ob.vertex_groups[" Head"].index

    def cen(f):
        return sum(v.co.x for v in f.verts) / len(f.verts)

    def cuv(f):
        return (sum(l[uvl].uv.x for l in f.loops) / len(f.loops), sum(l[uvl].uv.y for l in f.loops) / len(f.loops))

    def blk(f):
        u, v = cuv(f)
        return (int((u % 1.0) * 8), int(((1 - v) % 1.0) * 8))

    doomed = []
    for f in bm.faces:
        h = cen(f) - hx
        if h >= cap_floor:
            doomed.append(f)
        elif dark_floor is not None and h >= dark_floor and lum(*cuv(f)) < dark_lum:
            doomed.append(f)
        elif bright_floor is not None and h >= bright_floor and lum(*cuv(f)) > bright_lum:
            doomed.append(f)
        elif cap_blocks and h >= -0.05 and blk(f) in cap_blocks:
            doomed.append(f)
    notes = []
    if only in ("both", "hats"):
        to_bone = (arm.matrix_world @ head.matrix_local).inverted() @ ob.matrix_world
        notes.append(export_hat(doomed, uvl, to_bone, name, tex, img, out_dir, hat_blocks, hat_above))
    if only == "hats":
        bm.free()
        return f"{name}: " + "; ".join(notes)
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    floor = hx - 0.05 if cap_blocks else hx - 0.03
    bmesh.ops.remove_doubles(bm, verts=[v for v in bm.verts if v.is_boundary and v.co.x >= floor], dist=0.001)
    edges = [e for e in bm.edges if e.is_boundary and min(v.co.x for v in e.verts) >= floor]
    adj = {}
    for e in edges:
        a, b = e.verts
        adj.setdefault(a, []).append(b)
        adj.setdefault(b, []).append(a)
    loops, seen = [], set()
    for start in adj:
        if start in seen:
            continue
        loop, cur, prev = [start], start, None
        seen.add(start)
        while True:
            nxt = next((v for v in adj[cur] if v is not prev and v not in seen), None)
            if nxt is None:
                break
            loop.append(nxt)
            seen.add(nxt)
            prev, cur = cur, nxt
        if len(loop) > 2 and loop[0] in adj.get(loop[-1], []):
            loops.append(loop)
    loops.sort(key=len, reverse=True)
    if not loops:
        raise RuntimeError(f"{name}: the cut left no closed rim")
    loop = loops[0]
    for extra_loop in loops[1:]:
        extra_edges = [bm.edges.get((extra_loop[i], extra_loop[(i + 1) % len(extra_loop)])) for i in range(len(extra_loop))]
        extra_edges = [e for e in extra_edges if e]
        if extra_edges:
            filled = bmesh.ops.holes_fill(bm, edges=extra_edges, sides=0)["faces"]
            bmesh.ops.triangulate(bm, faces=filled)
    n = len(loop)
    rim_uv = [next(l[uvl].uv.copy() for l in v.link_loops) for v in loop]
    cy = sum(v.co.y for v in loop) / n
    cz = sum(v.co.z for v in loop) / n
    apex_x = max(v.co.x for v in loop) + apex

    def ring_at(phi, scale):
        ring = []
        for v in loop:
            x = v.co.x + (apex_x - v.co.x) * math.sin(phi)
            nv = bm.verts.new((x, cy + (v.co.y - cy) * math.cos(phi) * scale, cz + (v.co.z - cz) * math.cos(phi) * scale))
            nv[deform][headg] = 1.0
            ring.append(nv)
        return ring

    # a DFF keeps one UV per vertex: the hairline ring exists twice, a skin copy under the band and a hair copy above
    f_phi, f_scale = profile[0]
    skin_ring = ring_at(f_phi, f_scale)
    hair_rings = [ring_at(f_phi, f_scale)] + [ring_at(p, s) for p, s in profile[1:]]
    apexv = bm.verts.new((apex_x, cy, cz))
    apexv[deform][headg] = 1.0
    old = len(bm.faces)

    def add(verts, uvs):
        try:
            f = bm.faces.new(verts)
        except ValueError:
            return
        f.smooth = True
        for l, u in zip(f.loops, uvs):
            l[uvl].uv = u

    for i in range(n):
        j = (i + 1) % n
        add((loop[i], loop[j], skin_ring[j], skin_ring[i]), (rim_uv[i], rim_uv[j], rim_uv[j], rim_uv[i]))
    for k in range(len(hair_rings) - 1):
        lo, hi = hair_rings[k], hair_rings[k + 1]
        for i in range(n):
            j = (i + 1) % n
            add((lo[i], lo[j], hi[j], hi[i]), (hair_uv,) * 4)
    for i in range(n):
        j = (i + 1) % n
        add((hair_rings[-1][i], hair_rings[-1][j], apexv), (hair_uv,) * 3)
    bm.faces.ensure_lookup_table()
    bmesh.ops.triangulate(bm, faces=[bm.faces[i] for i in range(old, len(bm.faces)) if len(bm.faces[i].verts) == 4])
    bm.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(bm, faces=[bm.faces[i] for i in range(old, len(bm.faces))])
    bm.to_mesh(me)
    bm.free()
    me.update()
    img.name = tex
    for mat in me.materials:
        mat.dff.tex_name = tex
    out = os.path.join(out_dir, name + "_nohat.dff")
    bpy.ops.object.select_all(action="DESELECT")
    for o in ped_objects:
        o.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_dff.scene(filepath=out, export_coll=False, only_selected=True, export_version="0x36003")
    notes.append(f"removed {len(doomed)} faces, rim of {n}, {len(me.polygons)} faces -> {out}")
    return f"{name}: " + "; ".join(notes)


# The faces the rules above delete are the skin's hat, cap or helmet: exported on their own, de-skinned and expressed
# in the Head bone's bind frame (DragonFF rebuilds the bone from the skin's inverse bind matrix, so the bone's rest
# matrix is that frame), they make a static object that `items` attaches on SA-MP bone 2 at zero offset: the game
# places an attachment in the bone's own axes, which are rotated against the ped's model space (#77).
def export_hat(faces, uvl, to_bone, name, tex, img, out_dir, blocks=None, above=None):
    hb = bmesh.new()
    huv = hb.loops.layers.uv.new()
    verts = {}
    lining = 0
    for f in faces:
        # GTA models a skull patch under its hats, textured with a smear of the face, and the rules cut it with
        # the hat: only faces in the hat's own atlas blocks (tools/port_hats.py) go into the object, and a block
        # listed in `above` only from that height over the bone up
        if blocks is not None:
            cu = sum(l[uvl].uv.x for l in f.loops) / len(f.loops)
            cv = sum(l[uvl].uv.y for l in f.loops) / len(f.loops)
            block = (int((cu % 1.0) * 8), int(((1 - cv) % 1.0) * 8))
            floor = (above or {}).get(block)
            height = (to_bone @ f.calc_center_median()).x
            if block not in blocks and floor is None or floor is not None and height < floor:
                lining += 1
                continue
        vs = []
        for v in f.verts:
            if v not in verts:
                verts[v] = hb.verts.new(to_bone @ v.co)
            vs.append(verts[v])
        try:
            nf = hb.faces.new(vs)
        except ValueError:
            continue
        nf.smooth = f.smooth
        for l, ol in zip(nf.loops, f.loops):
            l[huv].uv = ol[uvl].uv
    # These are isolated atlas scraps rather than part of the hat shell: one under the fire helmet's front brim,
    # and three hair triangles on the bucket hat's rear underside. Keep the filter spatial and skin-specific so
    # small attached details on the other hats remain intact.
    if name in ("lafd1", "maccer"):
        remaining = set(hb.faces)
        scraps = []
        while remaining:
            seed = remaining.pop()
            component = {seed}
            stack = [seed]
            while stack:
                face = stack.pop()
                for edge in face.edges:
                    for linked in edge.link_faces:
                        if linked in remaining:
                            remaining.remove(linked)
                            component.add(linked)
                            stack.append(linked)
            if len(component) != 1:
                continue
            face = next(iter(component))
            center = face.calc_center_median()
            if name == "lafd1" and center.x < 0.01 and center.y > 0.08:
                scraps.extend(component)
            elif name == "maccer" and center.x < 0.09 and center.y < 0:
                scraps.extend(component)
        if scraps:
            bmesh.ops.delete(hb, geom=scraps, context="FACES_ONLY")
            loose = [v for v in hb.verts if not v.link_faces]
            if loose:
                bmesh.ops.delete(hb, geom=loose, context="VERTS")
    # A ped is drawn without back-face culling, an object is not, and a GTA hat's faces are wound every which way;
    # worse, MTA culls an attached object on the opposite side from a free-standing one (studio, 2026-10-25). So the
    # shell is made double-sided: consistent normals, then every face again with its winding reversed, as the
    # SA-MP hats are. A few hundred extra triangles per hat.
    # The golf cap and sheriff hat had open crown-back loops where the original skin's hair used to sit. Close only
    # those small upper loops; the large lower boundary is the opening that lets the hat sit on a head.
    if name in ("wmygol1", "csher"):
        remaining = {e for e in hb.edges if e.is_boundary}
        closed = 0
        while remaining:
            seed = remaining.pop()
            boundary = {seed}
            stack = [seed]
            while stack:
                edge = stack.pop()
                for vert in edge.verts:
                    for linked in vert.link_edges:
                        if linked in remaining:
                            remaining.remove(linked)
                            boundary.add(linked)
                            stack.append(linked)
            verts = {v for edge in boundary for v in edge.verts}
            center = tuple(sum(v.co[i] for v in verts) / len(verts) for i in range(3))
            is_crown_back = (
                name == "wmygol1" and len(boundary) == 10 and center[0] > 0.17 and abs(center[1]) < 0.02
            ) or (
                name == "csher" and len(boundary) == 8 and center[0] > 0.17 and center[1] < 0
            )
            if not is_crown_back:
                continue
            uv_at_vert = {}
            for edge in boundary:
                for face in edge.link_faces:
                    for loop in face.loops:
                        if loop.edge == edge:
                            uv_at_vert[loop.vert] = loop[huv].uv.copy()
                            other = edge.other_vert(loop.vert)
                            other_loop = next(item for item in face.loops if item.vert == other)
                            uv_at_vert[other] = other_loop[huv].uv.copy()
            fill = bmesh.ops.holes_fill(hb, edges=list(boundary), sides=0)
            for face in fill.get("faces", []):
                for loop in face.loops:
                    if loop.vert in uv_at_vert:
                        loop[huv].uv = uv_at_vert[loop.vert]
                closed += 1
        if closed:
            print(f"{name}: closed {closed} crown-back loop(s)")
    hb.faces.ensure_lookup_table()
    bmesh.ops.recalc_face_normals(hb, faces=hb.faces[:])
    dup = bmesh.ops.duplicate(hb, geom=hb.faces[:])
    bmesh.ops.reverse_faces(hb, faces=[g for g in dup["geom"] if isinstance(g, bmesh.types.BMFace)])
    me = bpy.data.meshes.new(name + "_hat")
    hb.to_mesh(me)
    hb.free()
    me.update()
    mat = bpy.data.materials.new(name + "_hat")
    mat.dff.tex_name = tex
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    bsdf = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf:
        mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    ob = bpy.data.objects.new(name + "_hat", me)
    bpy.context.collection.objects.link(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    out = os.path.join(out_dir, name + "_hat.dff")
    bpy.ops.export_dff.scene(filepath=out, export_coll=False, only_selected=True, export_version="0x36003")
    bpy.data.objects.remove(ob, do_unlink=True)
    lo = [min(v.co[i] for v in me.vertices) for i in range(3)]
    hi = [max(v.co[i] for v in me.vertices) for i in range(3)]
    extent = " ".join("%s %.2f..%.2f" % (a, lo[i], hi[i]) for i, a in enumerate("xyz"))
    return f"hat of {len(me.polygons)} faces, {lining} lining faces dropped ({extent}) -> {out}"


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :]
    only = "both"
    if "--only" in argv:
        i = argv.index("--only")
        only = argv[i + 1]
        del argv[i : i + 2]
    hat_blocks = None  # "c,r;c,r": the hat's atlas blocks, for a run over one skin (tools/extract_ped_models.py --hats)
    if "--blocks" in argv:
        i = argv.index("--blocks")
        hat_blocks = {tuple(int(v) for v in b.split(",")) for b in argv[i + 1].split(";")}
        del argv[i : i + 2]
    hat_above = None  # "c,r,h;c,r,h": blocks that are hat only from h metres over the Head bone up
    if "--above" in argv:
        i = argv.index("--above")
        hat_above = {(int(c), int(r)): float(h) for c, r, h in (b.split(",") for b in argv[i + 1].split(";"))}
        del argv[i : i + 2]
    src_dir, out_dir = argv[0], argv[1]
    skins = [int(s) for s in argv[2:]] or list(HEADS)
    addon_utils.enable("DragonFF", default_set=False)
    for skin in skins:
        spec = dict(HEADS[skin])
        print(remodel(src_dir, out_dir, spec.pop("name"), spec.pop("tex"), only=only, hat_blocks=hat_blocks, hat_above=hat_above, **spec))
