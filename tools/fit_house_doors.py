"""Fits a door to every entrance of the SA-MP house shells (lshouse1-4, lvhouse1-4, sfhouse1-4). Upstream hangs the
vanilla Gen_doorINT swing doors in them, 1.5 m by 2.5 m, where the openings are 1.04 to 1.85 m wide and 2.0 to 2.4 m
tall, hinged up to 0.65 m beside the opening and sunk up to 0.45 m into the floor. Run inside Blender with the DragonFF
addon enabled, after tools/extract_samp_models.py wrote the originals:

    blender -b --python tools/fit_house_doors.py -- SRC_DIR GTA_DIR

SRC_DIR holds the extracted shells and their baked <name>int.dff interiors (as for tools/glaze_house_windows.py). For
each door upstream places at the same spot in most copies of a shell, the opening around it is measured with rays
through the shell's and the interior's walls (both sides clear = the opening), and the house's vanilla door is
rescaled to it: the leaf stretched, the handles moved with the free edge but not resized, the collision (one box, two
spheres) scaled the same way. Two leaves in one opening are a double door and get half of it each. Writes:

- door_models/files/<house>_door<k>.dff/.col and door_models/doors.lua: port model ids 20101+, each given its vanilla door's
  object.dat physical properties group (a requested id has none, and would not swing), textured from that door's TXD;
- maps/shared/shell_doors.lua: per shell, which upstream door (in the shell's frame) each fitted door replaces and
  where it hangs instead (shared/logic/placement.lua swaps them when the maps are built).
"""
import math
import os
import re
import struct
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
sys.path.insert(0, ROOT)
from tools.extract_samp_models import parse_col_library, read_img_entry, read_img_index  # noqa: E402

bpy.ops.preferences.addon_enable(module="DragonFF")

RES = os.path.join(ROOT, "resources", "[scavengesurvive]")
DOOR_MODELS = os.path.join(RES, "door_models")
DOORS_LUA = os.path.join(DOOR_MODELS, "doors.lua")
SHELL_DOORS_LUA = os.path.join(RES, "maps", "shared", "shell_doors.lua")
FIRST_ID = 20101  # port model ids (tools/port_hats.py uses 20001+)
UPSTREAM_DOORS = (1491, 1492, 1494, 1499, 1502)  # Gen_doorINT01..05: what upstream hangs in the shells
VANILLA = {1491: "gen_doorint01", 1492: "gen_doorint02", 1494: "gen_doorint03", 1502: "gen_doorint04"}
# one vanilla door per house, so a street of the same shell is not a lottery of doors; the wooden four (Gen_doorINT05
# is rusted sheet metal)
DOOR_STYLE = {
    "sfhouse1": 1502,
    "sfhouse2": 1494,
    "sfhouse3": 1492,
    "sfhouse4": 1491,
    "lshouse1": 1492,
    "lshouse2": 1502,
    "lshouse3": 1494,
    "lshouse4": 1491,
    "lvhouse1": 1494,
    "lvhouse2": 1492,
    "lvhouse3": 1502,
    "lvhouse4": 1491,
}
GAP = 0.005  # clearance at the jambs and under the head, so the leaf swings free
MAX_SINGLE = 2.0  # wider than this, the cluster is not a door opening (a neighbour's door caught in the radius)

a = sys.argv[sys.argv.index("--") + 1 :]
src, gta = a[0], a[1]


def shell_names():
    man = open(os.path.join(MODELS, "manifest.lua")).read()
    return {int(i): n for i, n in re.findall(r'\[(\d+)\] = \{ dff = "(\w\whouse\d)",', man)}


def map_rows(models):
    rows = []
    datadir = os.path.join(RES, "maps", "data")
    pat = r"\{ *(\d+), *([-\d.e]+), *([-\d.e]+), *([-\d.e]+), *[-\d.e]+, *[-\d.e]+, *([-\d.e]+)"
    for f in os.listdir(datadir):
        for m in re.finditer(pat, open(os.path.join(datadir, f)).read()):
            if int(m[1]) in models:
                rows.append((int(m[1]), *map(float, m.groups()[1:])))
    return rows


def upstream_doors(sid, rows):
    """Doors upstream hangs at the same spot (shell frame) in at least half of the copies of shell `sid`."""
    shells = [r for r in rows if r[0] == sid]
    found = []
    for s in shells:
        c, si = math.cos(math.radians(-s[4])), math.sin(math.radians(-s[4]))
        for r in rows:
            if r[0] not in UPSTREAM_DOORS or abs(r[1] - s[1]) > 16 or abs(r[2] - s[2]) > 16 or abs(r[3] - s[3]) > 8:
                continue
            dx, dy = r[1] - s[1], r[2] - s[2]
            x, y, z, rz = dx * c - dy * si, dx * si + dy * c, r[3] - s[3], round(r[4] - s[4]) % 360
            for d in found:
                if abs(d["x"] - x) < 0.3 and abs(d["y"] - y) < 0.3 and abs(d["z"] - z) < 0.3 and d["r"] == rz:
                    d["n"] += 1
                    break
            else:
                found.append(dict(x=x, y=y, z=z, r=rz, n=1))
    return [d for d in found if d["n"] >= len(shells) / 2]


def walls_of(name):
    vs, ps = [], []
    for fn in (name, name + "int"):
        before = set(bpy.data.objects)
        bpy.ops.import_scene.dff(filepath=f"{src}/{fn}.dff")
        for o in [o for o in bpy.data.objects if o not in before and o.type == "MESH"]:
            b = len(vs)
            vs += [o.matrix_world @ v.co for v in o.data.vertices]
            ps += [[b + i for i in p.vertices] for p in o.data.polygons]
    return BVHTree.FromPolygons(vs, ps)


def measure(tree, d):
    """The opening a door leaf from hinge d spans, along the leaf (lo, hi from the hinge), up from d's z (bottom,
    top), and the wall's depth across it; None when the leaf's middle is not in an opening."""
    r = math.radians(d["r"])
    along, across, up = Vector((math.cos(r), math.sin(r), 0)), Vector((-math.sin(r), math.cos(r), 0)), Vector((0, 0, 1))
    hinge = Vector((d["x"], d["y"], d["z"]))

    def clear(p):
        return tree.ray_cast(p, across, 0.7)[0] is None and tree.ray_cast(p, -across, 0.7)[0] is None

    def edge(origin, step, limit):
        """How far from origin along step the opening stays clear: 1 cm steps, then halved down to 0.1 mm."""
        t = 0.0
        while clear(origin + step * (t + 0.01)) and t < limit:
            t += 0.01
        lo_, hi_ = t, t + 0.01
        while hi_ - lo_ > 1e-4:
            m = (lo_ + hi_) / 2
            lo_, hi_ = (m, hi_) if clear(origin + step * m) else (lo_, m)
        return lo_

    mid = hinge + along * 0.7 + up
    if not clear(mid):
        return None
    lo, hi = -edge(mid, -along, 3), edge(mid, along, 4)
    cen = mid + along * ((lo + hi) / 2)
    zl, zh = -edge(cen, -up, 2), edge(cen, up, 3)
    bottom = 1 + zl
    if bottom < -0.9:  # the opening runs down to the floor: stand on the floor, inside or out, whichever is higher
        floors = [f.z - hinge.z for f in (tree.ray_cast(cen + across * s * 0.4, -up, 4)[0] for s in (1, -1)) if f]
        if not floors:
            return None
        bottom = max(floors)
    side = cen + along * ((hi - lo) / 2 + 0.15)
    faces = [tree.ray_cast(side - across * s * 0.7, across * s, 1.4)[0] for s in (1, -1)]
    depth = sum((f - side).dot(across) for f in faces) / 2 if None not in faces else 0.0
    return dict(lo=lo + 0.7, hi=hi + 0.7, bottom=bottom, top=1 + zh, depth=depth, centre=cen)


def fitted(d, m, leaves):
    """Where the fitted leaf hangs (shell frame) and its size; a double door's leaves share the opening."""
    r = math.radians(d["r"])
    along, across = Vector((math.cos(r), math.sin(r), 0)), Vector((-math.sin(r), math.cos(r), 0))
    hinge = Vector((d["x"], d["y"], d["z"])) + along * (m["lo"] + GAP) + across * m["depth"]
    width = (m["hi"] - m["lo"]) / leaves - 2 * GAP
    return dict(x=hinge.x, y=hinge.y, z=d["z"] + m["bottom"], r=d["r"], w=width, h=m["top"] - m["bottom"] - GAP)


def build_dff(style, w, h, path):
    """The vanilla door rescaled to w x h: the leaf's own bounds (it starts a centimetre or two off the hinge and the
    floor) mapped onto the opening, the handles carried with the free edge, unscaled. Returns the leaf's x and z
    bounds, for the collision."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    tmp = path + ".src.dff"
    open(tmp, "wb").write(read_img_entry(gta3, gta3_index[VANILLA[style] + ".dff"]))
    bpy.ops.import_scene.dff(filepath=tmp)
    os.remove(tmp)
    o = next(o for o in bpy.data.objects if o.type == "MESH")
    bm = bmesh.new()
    bm.from_mesh(o.data)
    parts, seen = [], set()
    for v in bm.verts:
        if v in seen:
            continue
        part, stack = [], [v]
        while stack:
            x = stack.pop()
            if x not in seen:
                seen.add(x)
                part.append(x)
                stack += [e.other_vert(x) for e in x.link_edges]
        parts.append(part)
    leaf = max(parts, key=lambda p: max(x.co.x for x in p) - min(x.co.x for x in p))
    bounds = (min(x.co.x for x in leaf), max(x.co.x for x in leaf), min(x.co.z for x in leaf), max(x.co.z for x in leaf))
    fit_x, fit_z = fitter(bounds, w, h)
    for part in parts:
        if part is leaf:
            for x in part:
                x.co.x, x.co.z = fit_x(x.co.x), fit_z(x.co.z)
        else:  # a handle: same distance from the free edge, same height
            for x in part:
                x.co.x += w - bounds[1]
    bm.to_mesh(o.data)
    bm.free()
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_dff.scene(filepath=path, export_coll=False, only_selected=False, export_version="0x36003")
    return bounds


def fitter(bounds, w, h):
    """Maps the leaf's x bounds onto 0..w and its z bounds onto 0..h."""
    x0, x1, z0, z1 = bounds
    return (lambda x: (x - x0) * w / (x1 - x0)), (lambda z: (z - z0) * h / (z1 - z0))


def build_col(style, name, w, h, bounds):
    """The vanilla door's COL3 (bounds, two spheres, one box) fitted like the leaf, renamed."""
    c = bytearray(dynamic_cols[VANILLA[style]])
    fit_x, fit_z = fitter(bounds, w, h)
    sx, sz = w / (bounds[1] - bounds[0]), h / (bounds[3] - bounds[2])
    c[8:30] = name.encode("ascii").ljust(22, b"\0")[:22]

    def scale(off):
        x, y, z = struct.unpack_from("<3f", c, off)
        struct.pack_into("<3f", c, off, fit_x(x), y, fit_z(z))

    scale(32)  # bounds min
    scale(44)  # bounds max
    lo, hi = struct.unpack_from("<3f", c, 32), struct.unpack_from("<3f", c, 44)
    centre = [(p + q) / 2 for p, q in zip(lo, hi)]
    radius = math.dist(centre, hi)
    struct.pack_into("<4f", c, 56, *centre, radius)
    spheres, boxes = struct.unpack_from("<HH", c, 72)
    sphere_at, box_at = struct.unpack_from("<II", c, 84)
    for i in range(spheres):
        scale(sphere_at + 4 + i * 20)
        r_ = struct.unpack_from("<f", c, sphere_at + 4 + i * 20 + 12)[0]
        struct.pack_into("<f", c, sphere_at + 4 + i * 20 + 12, r_ * min(sx, sz))
    for i in range(boxes):
        scale(box_at + 4 + i * 28)
        scale(box_at + 4 + i * 28 + 12)
    return bytes(c)


def lua_doors(models):
    head = [
        "-- Generated by tools/fit_house_doors.py; do not edit. Port model id -> a vanilla Gen_doorINT rescaled to",
        "-- an entrance of the house shells, in door_models/files/; parent lends its physical properties group (swings).",
        "return {",
    ]
    body = [f'    [{i}] = {{ dff = "{n}", txdModel = {s}, parent = {s}, dist = 100 }},' for i, n, s in models]
    return "\n".join(head + body + ["}", ""])


def render_meta(doors_lua: Path) -> str:
    dffs = (
        sorted(f"{name}.dff" for name in re.findall(r'dff = "([^"]+)"', doors_lua.read_text(encoding="ascii")))
        if doors_lua.is_file()
        else []
    )
    files = sorted(dffs + [name[:-4] + ".col" for name in dffs])
    lines = [
        "<meta>",
        '    <info author="scavengesurvive-mta" type="script" name="door_models" '
        'description="Fitted entrance doors for the house shells" version="0.1.0"/>',
        '    <min_mta_version server="1.6.0" client="1.6.0-9.21695"/>',
        "    <download_priority_group>90</download_priority_group>",
        '    <include resource="lib"/>',
        '    <script src="client/main.lua" type="client"/>',
        '    <file src="doors.lua"/>',
    ]
    lines += [f'    <file src="files/{name}"/>' for name in files]
    lines += [
        '    <export function="resolve" type="client"/>',
        '</meta>',
    ]
    return "\n".join(lines) + "\n"


def write_meta(out_dir: Path) -> None:
    (out_dir / "meta.xml").write_text(render_meta(out_dir / "doors.lua"), encoding="ascii", newline="\n")


def lua_shell_doors(placed):
    head = [
        "-- Generated by tools/fit_house_doors.py: the doors the house shells' entrances get instead of upstream's, in",
        "-- the shell's frame, as { ux, uy, uz, urz, model, x, y, z, rz }: upstream's door (any Gen_doorINT) at u is",
        "-- replaced by the fitted port model hinged at x, y, z (shared/logic/placement.lua).",
        "return {",
    ]
    body = []
    for sid in sorted(placed):
        body.append(f"    [{sid}] = {{")
        for u, model, f in placed[sid]:
            vals = [u["x"], u["y"], u["z"], u["r"]]
            row = ", ".join(f"{v:.3f}" for v in vals) + f", {model}, " + ", ".join(f"{f[k]:.3f}" for k in "xyz")
            body.append(f"        {{ {row}, {f['r']} }},")
        body.append("    },")
    return "\n".join(head + body + ["}", ""])


gta3 = os.path.join(gta, "models", "gta3.img")
gta3_index = read_img_index(gta3)
dynamic_cols = parse_col_library(read_img_entry(gta3, gta3_index["dynamic2.col"]))
names = shell_names()
rows = map_rows(set(UPSTREAM_DOORS) | set(names))
models, placed, next_id = [], {}, FIRST_ID
for sid, name in sorted(names.items(), key=lambda kv: kv[1]):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    tree = walls_of(name)
    doors = [(d, measure(tree, d)) for d in upstream_doors(sid, rows)]
    doors = [(d, m) for d, m in doors if m and m["hi"] - m["lo"] <= 2 * MAX_SINGLE]
    fits = []
    for d, m in doors:
        leaves = sum(1 for _, o in doors if (o["centre"] - m["centre"]).length < 0.1)
        if (m["hi"] - m["lo"]) / leaves > MAX_SINGLE:
            print("SKIP", name, d, "opening", round(m["hi"] - m["lo"], 2))
            continue
        fits.append((d, fitted(d, m, leaves)))
    style = DOOR_STYLE[name]
    for k, (d, f) in enumerate(fits, 1):
        dname = f"{name}_door{k}"
        bounds = build_dff(style, f["w"], f["h"], os.path.join(DOOR_MODELS, "files", dname + ".dff"))
        col = build_col(style, dname, f["w"], f["h"], bounds)
        open(os.path.join(DOOR_MODELS, "files", dname + ".col"), "wb").write(col)
        models.append((next_id, dname, style))
        placed.setdefault(sid, []).append((d, next_id, f))
        print("DOOR", dname, next_id, "w %.2f h %.2f" % (f["w"], f["h"]), "from", d)
        next_id += 1
open(DOORS_LUA, "w", newline="\n").write(lua_doors(models))
open(SHELL_DOORS_LUA, "w", newline="\n").write(lua_shell_doors(placed))
write_meta(Path(DOOR_MODELS))
