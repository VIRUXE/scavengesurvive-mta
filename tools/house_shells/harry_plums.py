"""Harry Plums' fruit warehouse in Doherty, San Fierro (model 11092, burgalrystore_SFS, its roller door burgalrydoor_SFS
11102): a brick hall, 32 x 17 m, four arched windows on its east front, one on each end and the back, a glazed roof
lantern, the loading bay at the north end of the front. Vanilla it is one solid box of collision under a hollow skin, and
its glass paints the broken panes' holes at alpha 50-80 instead of 0, so they show as dark blotches on pale glass.

    python -m tools.house_shells.harry_plums [--gta DIR] [--blender EXE]

Writes into house_shell/files:
- burgalrystore_sfs.txd: the vanilla burgalrystore_sfse.txd with both window textures redrawn at four times their size.
  ws_warehswin1 (the arched heads): the holes see-through and a little larger, the glass left cracked. ws_warehswin2 (the
  lower sashes and the lantern): smashed, most panes gone, jagged shards left in the rest, some glazing bars broken out.
- burgalrystore_sfs.col: the hall hollow. Walls (each window's lower sash open from the sill up, so a player climbs in;
  the arched heads stay solid), the partition and its doorway between the loading bay and the hall, the two walls in from the east end and
  the brick pilasters, the roof slab, the
  vanilla parapets and lantern curb, and the lantern's glass as a mesh, so nobody falls through the roof. The floor is
  the lot under the hall (mission_17_SFS, 11005), flush with its base.
The DFF stays vanilla. Previews of the textures go to tools/trailer_shells/build/harry_plums/.
"""
from __future__ import annotations

import argparse
import os
import random
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FILES = ROOT / "resources" / "[scavengesurvive]" / "house_shell" / "files"
BUILD = ROOT / "tools" / "trailer_shells" / "build" / "harry_plums"
NAME = "burgalrystore_sfs"
TXD = "burgalrystore_sfse.txd"
COL_ARCHIVE = "sfse_12.col"
SCALE = 4
FRAME, HOLE = 200, 80  # vanilla alpha: frame at or over FRAME, glass between, a hole under HOLE
GLASS_A = 112
# (chance a pane is gone, chance it keeps shards; the rest stays whole but cracked), and the share of glazing bars broken
SMASH = {"ws_warehswin1": (0.18, 0.42, 0.0), "ws_warehswin2": (0.5, 0.42, 0.3)}

# model space, metres (x along the front, +y the front, z up; the base at -2.66)
BASE, SLAB, ROOF = -2.66, 2.41, 2.67
SILL, HEAD = -1.83, 0.45  # a window's lower sash, the opening a player climbs through
FRONT_WINDOWS = ((-6.25, -4.35), (0.22, 2.12), (6.69, 8.59), (13.16, 15.06))
BAY = (-14.25, -8.37, 1.68)  # the loading bay in the front wall: x from, x to, its lintel's underside
DOORWAY = (-1.57, 1.66, 1.52)  # in the partition between the bay and the hall: y from, y to, head
EAST_WALLS = ((-2.05, -1.57), (1.19, 1.66))  # from x 10.46 to the east end, either side of the painted door
PILASTERS_X = ((-3.92, -3.45), (-0.68, -0.21), (2.55, 3.02), (5.78, 6.26), (9.02, 9.49), (12.25, 12.73))  # front and back
PILASTERS_Y = ((-5.28, -4.81), (4.42, 4.89))  # on both end walls (the others are the east walls and the window jambs)


# ---- textures -----------------------------------------------------------------------------------------------------
def _cells(alpha, w, h):
    """The panes of a vanilla window texture: 4-connected regions of glass and holes between the frame's bars."""
    seen, cells = set(), []
    for y in range(h):
        for x in range(w):
            if (x, y) in seen or alpha[y][x] >= FRAME:
                continue
            todo, cell = [(x, y)], []
            seen.add((x, y))
            while todo:
                cx, cy = todo.pop()
                cell.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and (nx, ny) not in seen and alpha[ny][nx] < FRAME:
                        seen.add((nx, ny))
                        todo.append((nx, ny))
            cells.append(cell)
    return cells


def _inside(px, py, poly):
    hit = False
    for i in range(len(poly)):
        (ax, ay), (bx, by) = poly[i], poly[i - 1]
        if (ay > py) != (by > py) and px < (bx - ax) * (py - ay) / (by - ay) + ax:
            hit = not hit
    return hit


def _shards(rng, x0, y0, x1, y1):
    """Jagged triangles of glass still standing in a pane's corners and along its edges (big-texture pixels)."""
    w, h = x1 - x0, y1 - y0
    out = []
    corners = [(x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)]
    for cx, cy, sx, sy in rng.sample(corners, rng.randint(1, 3)):
        a, b = rng.uniform(0.3, 0.85) * w, rng.uniform(0.3, 0.85) * h
        mid = (cx + sx * a * rng.uniform(0.25, 0.6), cy + sy * b * rng.uniform(0.25, 0.6))
        out.append([(cx, cy), (cx + sx * a, cy), mid, (cx, cy + sy * b)])
    if rng.random() < 0.5:  # a long sliver hanging from the top bar
        u = x0 + rng.uniform(0.2, 0.8) * w
        out.append([(u - w * 0.18, y0), (u + w * 0.14, y0), (u + rng.uniform(-0.1, 0.1) * w, y0 + rng.uniform(0.4, 0.8) * h)])
    return out


def _break(rng, out, run, line, vertical, chance, tint):
    """Cuts part of one glazing bar's run (vanilla pixels `run` along `line`) out of the big texture; returns []."""
    if len(run) < 3 or rng.random() >= chance:
        return []
    lo, hi = run[0] * SCALE, (run[-1] + 1) * SCALE
    a = rng.randint(lo, lo + (hi - lo) // 3)
    b = rng.randint(a + (hi - lo) // 4, hi)
    for k in range(a, b):
        jag = rng.randint(0, SCALE - 1) if k - a < SCALE or b - k < SCALE else SCALE
        for d in range(jag):
            x, y = (line * SCALE + d, k) if vertical else (k, line * SCALE + d)
            out[y][x] = tint + (0,)
    return []


def redraw(png_in: Path, name: str, seed: int):
    """The window texture `name` redrawn SCALE times larger: rows of (r, g, b, a)."""
    from PIL import Image

    im = Image.open(png_in).convert("RGBA")
    w, h = im.size
    src = [[im.getpixel((x, y)) for x in range(w)] for y in range(h)]
    alpha = [[p[3] for p in row] for row in src]
    glass = [p for row in src for p in row if p[3] < FRAME]
    tint = tuple(sum(p[i] for p in glass) // len(glass) for i in range(3))
    rng = random.Random(seed)
    gone_p, shard_p, bar_p = SMASH[name]
    W, H = w * SCALE, h * SCALE
    out = [[None] * W for _ in range(H)]
    # the frame, and which bars of it break: a bar is a run of frame pixels between two panes, thin enough to be glazing
    for y in range(h):
        for x in range(w):
            p = src[y][x]
            for dy in range(SCALE):
                for dx in range(SCALE):
                    out[y * SCALE + dy][x * SCALE + dx] = p if p[3] >= FRAME else None
    for cell in _cells(alpha, w, h):
        xs, ys = [c[0] for c in cell], [c[1] for c in cell]
        x0, y0, x1, y1 = min(xs) * SCALE, min(ys) * SCALE, (max(xs) + 1) * SCALE, (max(ys) + 1) * SCALE
        holes = {(x, y) for x, y in cell if alpha[y][x] < HOLE}
        roll = rng.random()
        kind = "gone" if roll < gone_p else "shards" if roll < gone_p + shard_p else "whole"
        polys = _shards(rng, x0, y0, x1, y1) if kind == "shards" else []
        cracks = []
        if kind == "whole":  # a star of cracks from a point in the pane
            cx, cy = rng.uniform(x0, x1), rng.uniform(y0, y1)
            for _ in range(rng.randint(3, 6)):
                ex, ey = rng.uniform(x0, x1), rng.uniform(y0, y1)
                cracks.append((cx, cy, ex, ey))
        for x, y in cell:
            for dy in range(SCALE):
                for dx in range(SCALE):
                    X, Y = x * SCALE + dx, y * SCALE + dy
                    px, py = X + 0.5, Y + 0.5
                    if kind == "gone":
                        keep = False
                    elif kind == "shards":
                        keep = any(_inside(px, py, poly) for poly in polys)
                    else:  # whole: the vanilla holes, grown by a pixel
                        keep = not any((x + ox, y + oy) in holes for ox in (-1, 0, 1) for oy in (-1, 0, 1) if (ox == 0 or oy == 0))
                    if not keep:
                        out[Y][X] = tint + (0,)
                        continue
                    r, g, b, _ = src[y][x]
                    a = GLASS_A
                    for cx, cy, ex, ey in cracks:
                        vx, vy = ex - cx, ey - cy
                        t = max(0.0, min(1.0, ((px - cx) * vx + (py - cy) * vy) / (vx * vx + vy * vy)))
                        if (px - cx - t * vx) ** 2 + (py - cy - t * vy) ** 2 < 0.8:
                            r, g, b, a = min(255, r + 70), min(255, g + 70), min(255, b + 70), 190
                    out[Y][X] = (r, g, b, a)
    # light the broken edges: glass next to a gap catches the light
    for Y in range(H):
        for X in range(W):
            p = out[Y][X]
            if p and 0 < p[3] < FRAME:
                near = any(0 <= X + ox < W and 0 <= Y + oy < H and out[Y + oy][X + ox][3] == 0 for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                if near:
                    out[Y][X] = (min(255, p[0] + 55), min(255, p[1] + 55), min(255, p[2] + 55), 170)
    # broken glazing bars: a bar is frame one vanilla pixel thick with glass either side; a run of one breaks out in a
    # ragged length, a stub or two left standing
    if bar_p:
        for vertical in (True, False):
            for line in range(1, (w if vertical else h) - 1):
                run = []
                for k in range(h if vertical else w):
                    x, y = (line, k) if vertical else (k, line)
                    a, b = (alpha[y][x - 1], alpha[y][x + 1]) if vertical else (alpha[y - 1][x], alpha[y + 1][x])
                    if alpha[y][x] >= FRAME and a < FRAME and b < FRAME:
                        run.append(k)
                    elif run:
                        run = _break(rng, out, run, line, vertical, bar_p, tint)
                if run:
                    _break(rng, out, run, line, vertical, bar_p, tint)
    return out


def native(name: str, mask: str, rows, filt: int) -> bytes:
    """A D3D9 A8R8G8B8 texture native, one mip level."""
    h, w = len(rows), len(rows[0])
    data = b"".join(struct.pack("<4B", b, g, r, a) for row in rows for r, g, b, a in row)
    head = struct.pack("<II", 9, filt) + name.encode().ljust(32, b"\0") + mask.encode().ljust(32, b"\0")
    head += struct.pack("<II", 0x0500, 21) + struct.pack("<HHBBBB", w, h, 32, 1, 4, 0x01) + struct.pack("<I", len(data)) + data
    version = 0x1803FFFF

    def chunk(kind, body):
        return struct.pack("<III", kind, len(body), version) + body

    return chunk(0x15, chunk(1, head) + chunk(3, b""))


def write_png(rows, path: Path):
    from PIL import Image

    im = Image.new("RGBA", (len(rows[0]), len(rows)))
    im.putdata([p for row in rows for p in row])
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path)


# ---- collision (inside Blender) -------------------------------------------------------------------------------------
def walls():
    """The hall's collision boxes (x0, y0, z0, x1, y1, z1)."""
    boxes = []

    def wall_x(x0, x1, y0, y1, gaps):
        """A wall along x from x0 to x1, y0..y1 thick, base to the slab, with gaps (u0, u1, z0, z1) cut out."""
        u = x0
        for g0, g1, z0, z1 in sorted(gaps):
            boxes.append((u, y0, BASE, g0, y1, SLAB))
            if z0 > BASE:
                boxes.append((g0, y0, BASE, g1, y1, z0))
            if z1 < SLAB:
                boxes.append((g0, y0, z1, g1, y1, SLAB))
            u = g1
        boxes.append((u, y0, BASE, x1, y1, SLAB))

    def wall_y(y0, y1, x0, x1, gaps):
        for b in _swap(lambda: wall_x(y0, y1, x0, x1, gaps)):
            boxes.append(b)

    def _swap(fn):
        start = len(boxes)
        fn()
        moved = [(b[1], b[0], b[2], b[4], b[3], b[5]) for b in boxes[start:]]
        del boxes[start:]
        return moved

    wall_x(-16.17, 16.18, 7.84, 8.35, [(a, b, SILL, HEAD) for a, b in FRONT_WINDOWS] + [(BAY[0], BAY[1], BASE, BAY[2])])
    wall_x(-16.14, 16.18, -8.75, -8.05, [(-6.25, -4.35, SILL, HEAD)])
    wall_y(-8.05, 7.84, -16.17, -15.45, [(-1.14, 0.75, SILL, HEAD)])
    wall_y(-8.05, 7.84, 15.45, 16.18, [])
    wall_y(-8.05, 7.84, -7.15, -6.68, [(DOORWAY[0], DOORWAY[1], BASE, DOORWAY[2])])
    # the two walls running in from the east end either side of the painted door
    for y0, y1 in EAST_WALLS:
        boxes.append((10.46, y0, BASE, 15.66, y1, SLAB))
    # the brick pilasters standing proud of the walls inside
    for x0, x1 in PILASTERS_X:
        boxes.append((x0, 7.66, BASE, x1, 7.84, SLAB))
        boxes.append((x0, -8.23, BASE, x1, -8.05, SLAB))
    boxes.append((-11.75, -8.23, BASE, -11.28, -8.05, SLAB))
    for y0, y1 in PILASTERS_Y:
        boxes.append((-15.66, y0, BASE, -15.45, y1, SLAB))
        boxes.append((15.45, y0, BASE, 15.66, y1, SLAB))
    for y0, y1 in EAST_WALLS:  # the west end has pilasters where the east walls meet the east end
        boxes.append((-15.66, y0, BASE, -15.45, y1, SLAB))
    boxes.append((-16.18, -8.84, SLAB, 16.21, 8.45, ROOF))
    return boxes


def build_col(vanilla_dir: Path, out: Path):
    import bmesh
    import bpy

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    before = set(bpy.data.objects)
    bpy.ops.import_scene.dff(filepath=str(vanilla_dir / f"{NAME}.col"))
    kept = []
    for o in [o for o in bpy.data.objects if o not in before]:
        if o.type == "EMPTY" and o.empty_display_type == "CUBE":
            c, s = o.matrix_world.translation, o.matrix_world.to_scale()
            if c.z - s.z >= ROOF - 0.01:  # the parapets and the lantern's curb; the solid hall goes
                kept.append((c.x - s.x, c.y - s.y, c.z - s.z, c.x + s.x, c.y + s.y, c.z + s.z))
        bpy.data.objects.remove(o)
    # the lantern's glass, as a mesh of collision, out of the vanilla model
    bpy.ops.import_scene.dff(filepath=str(vanilla_dir / f"{NAME}.dff"), read_mat_split=True, remove_doubles=False, load_images=False)
    src = next(o for o in bpy.data.objects if o.type == "MESH" and not o.name.startswith("2dfx"))
    mw = src.matrix_world.copy()
    bm = bmesh.new()
    for p in src.data.polygons:
        mat = src.data.materials[p.material_index]
        nodes = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"] if mat and mat.node_tree else []
        tex = ((nodes[0].image.name if nodes[0].image else nodes[0].label or nodes[0].name) if nodes else "").split(".")[0].lower()
        vs = [mw @ src.data.vertices[i].co for i in p.vertices]
        if tex == "ws_warehswin2" and min(v.z for v in vs) >= 3.19:
            bm.faces.new([bm.verts.new(v) for v in vs])
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    mesh = bpy.data.meshes.new(f"{NAME}_lantern")
    bm.to_mesh(mesh)
    bm.free()
    coll = bpy.data.collections.new(NAME)
    bpy.context.scene.collection.children.link(coll)
    lantern = bpy.data.objects.new(f"{NAME}_lantern", mesh)
    lantern.dff.type = "COL"
    coll.objects.link(lantern)
    objs = [lantern]
    for i, (x0, y0, z0, x1, y1, z1) in enumerate(walls() + kept):
        e = bpy.data.objects.new(f"{NAME}_col{i}", None)
        e.empty_display_type = "CUBE"
        e.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        e.scale = ((x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2)
        e.dff.type = "COL"
        coll.objects.link(e)
        objs.append(e)
    bpy.context.view_layer.update()
    for o in bpy.context.view_layer.objects:
        o.select_set(o in objs)
    bpy.ops.export_col.scene(filepath=str(out / f"{NAME}.col"), export_version="3", only_selected=True)
    print(f"harry_plums: {NAME}.col, {len(objs) - 1} boxes and the lantern ({len(mesh.polygons)} faces)")


# ---- main -----------------------------------------------------------------------------------------------------------
def main(argv=None) -> int:
    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta, parse_col_library, read_img_entry, read_img_index, txd_natives

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender.exe (default: BLENDER or the newest install)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    img = gta / "models" / "gta3.img" if gta else None
    blender = find_blender(args.blender)
    if not img or not img.is_file() or not blender:
        print("harry_plums: needs GTA:SA (--gta) and Blender (--blender)", file=sys.stderr)
        return 2
    index = read_img_index(img)
    vanilla = BUILD / "vanilla"
    vanilla.mkdir(parents=True, exist_ok=True)
    (vanilla / f"{NAME}.dff").write_bytes(read_img_entry(img, index[f"{NAME}.dff"]))
    for col, data in parse_col_library(read_img_entry(img, index[COL_ARCHIVE])).items():
        if col.lower() == NAME:
            (vanilla / f"{NAME}.col").write_bytes(data)
    txd = read_img_entry(img, index[TXD])
    (vanilla / TXD).write_bytes(txd)
    tex = BUILD / "tex"
    subprocess.run(["node", str(ROOT / "tools" / "trailer_shells" / "txd_png.mjs"), str(vanilla / TXD), str(tex)], check=True)
    version, device, natives = txd_natives(txd)
    out_natives = []
    for n in natives:
        name = n[32:64].split(b"\0")[0].decode("latin1")
        mask = n[64:96].split(b"\0")[0].decode("latin1")
        if name.lower() in SMASH:
            rows = redraw(tex / f"{name.lower()}.png", name.lower(), seed=sum(map(ord, name)))
            write_png(rows, BUILD / f"{name.lower()}.png")
            n = native(name, mask, rows, struct.unpack_from("<I", n, 28)[0])
        out_natives.append(n)
    body = struct.pack("<IIIHH", 0x01, 4, version, len(out_natives), device) + b"".join(out_natives)
    body += struct.pack("<III", 0x03, 0, version)
    FILES.mkdir(parents=True, exist_ok=True)
    (FILES / f"{NAME}.txd").write_bytes(struct.pack("<III", 0x16, len(body), version) + body)
    print(f"harry_plums: {NAME}.txd ({len(out_natives)} textures)")
    res = subprocess.run([str(blender), "-b", "--python", __file__, "--", str(vanilla), str(FILES)], capture_output=True, text=True)
    print("\n".join(line for line in (res.stdout + res.stderr).splitlines() if "harry_plums" in line or "Error" in line))
    return 0 if res.returncode == 0 and (FILES / f"{NAME}.col").is_file() else 1


if __name__ == "__main__":
    if "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        build_col(Path(rest[0]), Path(rest[1]))
    else:
        sys.exit(main())
