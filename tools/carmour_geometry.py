"""Geometry for attaching defences to the towable Airstream (carmour, vehicles/shared/logic/carmour.lua).

A player aims a held defence at the trailer: the panel lies flat against the shell where the camera ray meets it, at
full size, and may not overlap another panel. Door defences go on the door leaf only (scaled to fit it). The game
(client and server alike, from the same shared logic) needs the shell to cast that ray on and the size and axes of
every defence, so this writes them as data:

    python -m tools.carmour_geometry [--gta DIR] [--blender EXE]

Runs itself in Blender (DragonFF): reads airstream_tow.dff (the body without its door, decimated to about SHELL_TRIS
triangles, and the door leaf with the door CLOSED) and every defence's DFF (vanilla ones from gta3.img, SA-MP ones from
samp_models/files), and writes resources/[scavengesurvive]/vehicles/shared/data/carmour_geometry.lua.

Coordinates are the vehicle's frame (+Y forward). A defence's frame is its minimum-area rectangle: a the long side,
b the short side, c = a x b the thin axis, ext the three extents and centre the box's middle, in the model's own space.
"""
from __future__ import annotations

import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "resources" / "[scavengesurvive]"
SAMP_FILES = RES / "samp_models" / "files"
SHELL_DFF = RES / "airstream_trailer" / "files" / "airstream_tow.dff"
OUT_LUA = RES / "vehicles" / "shared" / "data" / "carmour_geometry.lua"
MODEL = 610
SHELL_TRIS = 900
HINGE = (-1.149, 1.460, -0.445)  # airstream_trailer/towable.lua door
DOOR_OPEN_DEG = 70
# The door a door defence covers: the drawn door on the leaf's outer face (its frame runs the leaf's width, 0.52 .. 1.47,
# from z -0.39 up to where the leaf bends inward under the arch at 1.33; measured on screen against projected points),
# 2 cm in from each edge. The arch above it belongs to the body.
DOOR_FACE_Y = (HINGE[1] - 0.92, HINGE[1] - 0.02)
DOOR_FACE_Z = (-0.39, 1.30)
# uname, model, source ("samp": samp_models/files, "gta3": gta3.img), dff, door (goes on the door leaf only)
PANELS = [
    ("Door", 18553, "gta3", "count_ammundoor", True),
    ("CrateDoor", 20302, "samp", "container_door_def", True),
    ("ShipDoor", 20303, "samp", "freight_sfw_door_def", True),
    ("InsulDoor", 19398, "samp", "wall046", True),
    ("MetPanel", 20301, "samp", "imcmptrkdrl_las_def", False),
    ("CorPanel", 2904, "gta3", "warehouse_door1", False),
    ("SmallPanel", 19843, "samp", "metalpanel1", False),
    ("WoodPanel", 5153, "gta3", "stuntramp7_las2", False),
    ("InsulPanel", 19371, "samp", "wall019", False),
    ("MetalGate", 19303, "samp", "pd_jail_door02", False),
]


def blender_main(gta: Path) -> None:
    import bmesh
    import bpy
    import numpy as np

    sys.path.insert(0, str(ROOT))
    from tools.extract_samp_models import read_img_entry, read_img_index

    def log(msg):
        print("CARM " + msg, flush=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    img = gta / "models" / "gta3.img"
    img_index = read_img_index(img)
    tmp = OUT_LUA.parent / "_src.dff"

    def grab(path: Path, decimate=None):
        """name -> (verts Nx3, tris) of every non-breakable mesh in the DFF, world transform applied; decimate: a
        {name: triangle budget} to collapse those meshes to first."""
        before = set(bpy.data.objects)
        bpy.ops.import_scene.dff(filepath=str(path))
        out = {}
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.type != "MESH" or o.name.endswith("_breakable"):
                continue
            me = o.data
            bm = bmesh.new()
            bm.from_mesh(me)
            bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.002)
            bmesh.ops.triangulate(bm, faces=bm.faces[:])
            bm.to_mesh(me)
            bm.free()
            budget = (decimate or {}).get(o.name)
            if budget and len(me.polygons) > budget:
                mod = o.modifiers.new("dec", "DECIMATE")
                mod.ratio = budget / len(me.polygons)
                bpy.context.view_layer.objects.active = o
                bpy.ops.object.modifier_apply(modifier=mod.name)
                me = o.data
            me.calc_loop_triangles()
            verts = np.array([tuple(o.matrix_world @ v.co) for v in me.vertices])
            out[o.name] = (verts, [tuple(t.vertices) for t in me.loop_triangles])
        for o in [o for o in bpy.data.objects if o not in before]:
            bpy.data.objects.remove(o, do_unlink=True)
        return out

    def merge(parts):
        verts, tris, base = [], [], 0
        for v, t in parts:
            verts.append(v)
            tris += [(a + base, b + base, c + base) for a, b, c in t]
            base += len(v)
        return np.vstack(verts), tris

    body_names = ("chassis", "step", "misc_a")
    raw = grab(SHELL_DFF)
    counts = {n: len(raw[n][1]) for n in body_names}
    total = sum(counts.values())
    budgets = {n: max(40, int(SHELL_TRIS * c / total)) for n, c in counts.items()}
    shell = grab(SHELL_DFF, budgets)
    body = merge([shell[n] for n in body_names])
    leaf = shell["door_lf_ok"]
    log(f"shell {total} tris -> {len(body[1])}; door leaf {len(leaf[1])}")

    # the door's opening on the leaf's outer face (the -X side): DOOR_FACE_Y back from the hinge, DOOR_FACE_Z up
    lv = leaf[0]
    door = dict(x=float(lv[:, 0].min()), y0=DOOR_FACE_Y[0], y1=DOOR_FACE_Y[1], z0=DOOR_FACE_Z[0], z1=DOOR_FACE_Z[1])
    log(f"door leaf face x {door['x']:.3f}, y {door['y0']:.3f}..{door['y1']:.3f}, z {door['z0']:.3f}..{door['z1']:.3f}")

    def panel_geo(spec):
        _name, _model, src, dff, _door = spec
        if src == "samp":
            path = SAMP_FILES / (dff + ".dff")
        else:
            tmp.write_bytes(read_img_entry(img, img_index[dff + ".dff"]))
            path = tmp
        parts = grab(path)
        if tmp.exists():
            tmp.unlink()
        if not parts:
            raise SystemExit(f"carmour_geometry: no mesh in {dff}")
        return merge(list(parts.values()))

    def frame_of(verts):
        """Long axis a, short axis b of the minimum-area rectangle across the two widest principal axes, c = a x b,
        the extents along a, b, c and the box's centre, all in model space."""
        p = verts - verts.mean(0)
        _w, vec = np.linalg.eigh(np.cov(p.T))
        e2, e1 = vec[:, 1], vec[:, 2]
        best = None
        for ang in np.arange(0, 90, 0.25):
            t = math.radians(ang)
            a = math.cos(t) * e1 + math.sin(t) * e2
            b = -math.sin(t) * e1 + math.cos(t) * e2
            area = np.ptp(verts @ a) * np.ptp(verts @ b)
            if best is None or area < best[0] - 1e-9:
                best = (area, a, b)
        _area, a, b = best
        if np.ptp(verts @ b) > np.ptp(verts @ a):
            a, b = b, a
        # snap near-axis directions so the numbers stay clean, and keep a and b pointing the positive way
        def tidy(v):
            v = np.where(np.abs(v) < 1e-4, 0.0, v)
            i = int(np.argmax(np.abs(v)))
            return v / np.linalg.norm(v) * (1 if v[i] > 0 else -1)

        a, b = tidy(a), tidy(b)
        c = np.cross(a, b)
        ext = [float(np.ptp(verts @ ax)) for ax in (a, b, c)]
        mid = [float((verts @ ax).min() + (verts @ ax).max()) / 2 for ax in (a, b, c)]
        centre = a * mid[0] + b * mid[1] + c * mid[2]
        return a, b, c, ext, centre

    def num(v, places=4):
        s = f"{v:.{places}f}".rstrip("0").rstrip(".")
        return "0" if s in ("-0", "") else s

    def vec(v):
        return "{ " + ", ".join(num(float(x)) for x in v) + " }"

    def blob(verts, tris):
        vs = ",".join(f"{num(float(x), 3)},{num(float(y), 3)},{num(float(z), 3)}" for x, y, z in verts)
        ts = ",".join(f"{a + 1},{b + 1},{c + 1}" for a, b, c in tris)
        return vs, ts

    lines = [
        "-- Generated by tools/carmour_geometry.py; do not edit. What attaching a defence to the towable Airstream",
        "-- (model 610) needs, in the vehicle's frame (+Y forward): the body's triangles (no door) and the door leaf's with",
        "-- the door CLOSED (verts: x,y,z per vertex; tris: 1-based vertex indices, three per triangle), the leaf's outer",
        "-- face as a rectangle (x; y0..y1; z0..z1) and its hinge, and per defence its frame in model space: a (long side),",
        "-- b (short side), c = a x b (thin axis), ext (extents along a, b, c), centre (the box's middle); door = goes on the",
        "-- door leaf only. A door panel swings with the door about hinge, rz changing by dir * angle up to openDeg.",
        "local M = {}",
        "",
        f"M.MODEL = {MODEL}",
    ]
    vs, ts = blob(*body)
    lines += [f'M.SHELL = {{ verts = "{vs}", tris = "{ts}" }}']
    vs, ts = blob(*leaf)
    hinge = "{ x = %s, y = %s, z = %s }" % tuple(num(v) for v in HINGE)
    face = "x = %s, y0 = %s, y1 = %s, z0 = %s, z1 = %s" % tuple(num(door[k]) for k in ("x", "y0", "y1", "z0", "z1"))
    lines += [f'M.DOOR = {{ hinge = {hinge}, openDeg = {DOOR_OPEN_DEG}, dir = -1, face = {{ {face} }}, verts = "{vs}", tris = "{ts}" }}']
    lines += ["", "M.PANELS = {"]
    for spec in PANELS:
        a, b, c, ext, centre = frame_of(panel_geo(spec)[0])
        name, model, _src, _dff, is_door = spec
        log(f"panel {name}: {ext[0]:.3f} x {ext[1]:.3f} x {ext[2]:.3f} m{' (door)' if is_door else ''}")
        lines.append(f"    {name} = {{ model = {model}, door = {'true' if is_door else 'false'}, a = {vec(a)}, b = {vec(b)}, c = {vec(c)}, ext = {vec(ext)}, centre = {vec(centre)} }},")
    lines += ["}", "", "return M", ""]
    OUT_LUA.write_text("\n".join(lines), encoding="ascii", newline="\n")
    log(f"wrote {OUT_LUA.relative_to(ROOT)}")


def main(argv=None) -> int:
    import argparse

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender.exe (default: BLENDER or the newest install)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("carmour_geometry: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    blender = find_blender(args.blender)
    if not blender:
        print("carmour_geometry: no Blender found (pass --blender)", file=sys.stderr)
        return 2
    cmd = [str(blender), "-b", "--python", __file__, "--", str(gta)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    print("\n".join(line[5:] if line.startswith("CARM ") else line for line in out.splitlines() if line.startswith("CARM") or "Error" in line or "carmour_geometry" in line or "Traceback" in line))
    return res.returncode


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        try:
            blender_main(Path(rest[0]))
        except SystemExit as e:
            print(e, flush=True)
            sys.exit(1)
    else:
        sys.path.insert(0, str(ROOT))
        sys.exit(main())
