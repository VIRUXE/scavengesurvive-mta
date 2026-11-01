"""Fixed attachment slots for welded defence panels ("carmour") on the towable Airstream (model 610).

Players weld a defence panel (MetPanel, CrateDoor, ShipDoor, CorPanel, SmallPanel, WoodPanel, InsulPanel, MetalGate)
over a window or the door of the trailer. Every panel type has its own size, so each slot is a fixed rectangle on the
shell and each panel type gets one precomputed placement in it (centred, flat against the surface 2 cm proud, long
side along the slot's long side, scaled down uniformly only when it is bigger than the rectangle). The rectangles
never overlap, so any mix of panel types in the slots can never overlap either.

    python -m tools.carmour_slots [--gta DIR] [--blender EXE] [--sheets DIR]

Runs itself in Blender (DragonFF): reads airstream_tow.dff, casts rays onto the skin to fit each slot's plane, loads the
panel meshes (vanilla ones from gta3.img, the rest from samp_models/files), writes
resources/[scavengesurvive]/vehicles/shared/data/carmour_slots.lua and fails loudly when any two placed panels (every
slot pair x every pair of panel types), a panel and the shell, or a panel and the swinging door leaf touch. The door
slot is tested at every door angle from closed to DOOR_CHECK_DEG. Then it renders contact sheets (one per view: each
panel type filling every slot, plus a mixed set with the door open) into --sheets, stitched by this script.

Coordinates are the vehicle's frame (+Y forward); the door slot is given with the door CLOSED and the client swings
it about M.DOOR.hinge. Rotations are GTA's ZXY (R = Rz * Rx * Ry), the numbers go straight into attachElements.
"""
from __future__ import annotations

import math
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "resources" / "[scavengesurvive]"
SAMP_FILES = RES / "samp_models" / "files"
SHELL_DFF = RES / "airstream_trailer" / "files" / "airstream_tow.dff"
OUT_LUA = RES / "vehicles" / "shared" / "data" / "carmour_slots.lua"
MODEL = 610
PROUD = 0.02  # metres between the skin and the panel's inner face
HINGE = (-1.149, 1.460, -0.445)  # airstream_trailer/towable.lua door
DOOR_OPEN_DEG = 70  # what the client swings the panel to (the door's open limit is the game's; it is checked well past it)
DOOR_CHECK_DEG = 100
CLEAR_REQUIRED_DEG = 95
# name, port model id, source ("samp": samp_models/files, "gta3": gta3.img), dff
PANELS = [
    ("MetPanel", 20301, "samp", "imcmptrkdrl_las_def"),
    ("CrateDoor", 20302, "samp", "container_door_def"),
    ("ShipDoor", 20303, "samp", "freight_sfw_door_def"),
    ("CorPanel", 2904, "gta3", "warehouse_door1"),
    ("SmallPanel", 19843, "samp", "metalpanel1"),
    ("WoodPanel", 5153, "gta3", "stuntramp7_las2"),
    ("InsulPanel", 19371, "samp", "wall019"),
    ("MetalGate", 19303, "samp", "pd_jail_door02"),
]
COLOURS = [(0.85, 0.2, 0.2), (0.9, 0.55, 0.1), (0.9, 0.85, 0.2), (0.2, 0.7, 0.3), (0.2, 0.7, 0.8), (0.35, 0.4, 0.95), (0.7, 0.3, 0.9), (0.95, 0.4, 0.7)]
# the door runs from the hinge (u = 0) back along -Y; the window slots are centred on their measured frames
DOOR_U = (0.14, 0.90)
DOOR_Z = (-0.40, 1.28)
# name, door, normal, u axis (width), v axis (height), centre, w, h
SLOTS = [
    ("door", True, (-1, 0, 0), (0, -1, 0), (0, 0, 1), (-1.216, HINGE[1] - sum(DOOR_U) / 2, sum(DOOR_Z) / 2), DOOR_U[1] - DOOR_U[0], DOOR_Z[1] - DOOR_Z[0]),
    ("frontLeft", False, (0, 1, 0), (1, 0, 0), (0, 0, 1), (-0.455, 4.0, 0.97), 0.22, 0.62),
    ("frontRight", False, (0, 1, 0), (1, 0, 0), (0, 0, 1), (0.445, 4.0, 0.97), 0.22, 0.62),
    ("leftFront", False, (-1, 0, 0), (0, 1, 0), (0, 0, 1), (-1.2, 2.22, 1.05), 1.12, 0.60),
    ("leftRear", False, (-1, 0, 0), (0, 1, 0), (0, 0, 1), (-1.2, -0.915, 1.05), 1.25, 0.60),
    ("rightFront", False, (1, 0, 0), (0, 1, 0), (0, 0, 1), (1.2, 2.32, 1.03), 1.20, 0.60),
    ("rightMid", False, (1, 0, 0), (0, 1, 0), (0, 0, 1), (1.2, 0.96, 1.03), 1.20, 0.60),
    ("rightRear", False, (1, 0, 0), (0, 1, 0), (0, 0, 1), (1.2, -1.01, 1.05), 1.20, 0.60),
    ("rearWindow", False, (0, -1, 0), (1, 0, 0), (0, 0, 1), (0.02, -2.6, 1.055), 1.30, 0.64),
    ("roofFront", False, (0, 0, 1), (1, 0, 0), (0, 1, 0), (0.0, 0.835, 2.2), 0.90, 0.90),
    ("roofRear", False, (0, 0, 1), (1, 0, 0), (0, 1, 0), (0.0, -0.965, 2.2), 0.90, 0.90),
]
VIEWS = ["left", "right", "front34", "rear34", "top"]
TILE = (700, 400)


def blender_main(gta: Path, sheets: Path) -> None:
    import bpy
    import numpy as np
    from mathutils import Quaternion, Vector
    from mathutils.bvhtree import BVHTree

    sys.path.insert(0, str(ROOT))
    from tools.extract_samp_models import read_img_entry, read_img_index

    def log(msg):
        print("CARM " + msg, flush=True)

    def rx(a):
        c, s = math.cos(a), math.sin(a)
        return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])

    def ry(a):
        c, s = math.cos(a), math.sin(a)
        return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])

    def rz(a):
        c, s = math.cos(a), math.sin(a)
        return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])

    def zxy(ax, ay, az):
        return rz(math.radians(az)) @ rx(math.radians(ax)) @ ry(math.radians(ay))

    def to_zxy(m):
        sa = max(-1.0, min(1.0, m[2][1]))
        if abs(sa) > 1 - 1e-9:
            return math.degrees(math.asin(sa)), 0.0, math.degrees(math.atan2(m[1][0], m[0][0]))
        return math.degrees(math.asin(sa)), math.degrees(math.atan2(-m[2][0], m[2][2])), math.degrees(math.atan2(-m[0][1], m[1][1]))

    def norm(v):
        return v / np.linalg.norm(v)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    img = gta / "models" / "gta3.img"
    img_index = read_img_index(img)
    tmp = sheets / "_src.dff"

    def grab(path: Path):
        """name -> (verts Nx3, tris) of every non-breakable mesh in the DFF, world transform applied."""
        before = set(bpy.data.objects)
        bpy.ops.import_scene.dff(filepath=str(path))
        out = {}
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.type == "MESH" and not o.name.endswith("_breakable"):
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

    shell = grab(SHELL_DFF)
    body = merge([shell[n] for n in ("chassis", "step", "misc_a")])
    leaf = shell["door_lf_ok"]

    def bvh(geo, eps=0.001):
        return BVHTree.FromPolygons([Vector(p) for p in geo[0]], geo[1], epsilon=eps)

    body_bvh = bvh(body)
    leaf_bvh = bvh(leaf)

    def panel_geo(spec):
        _name, model, src, dff = spec
        if src == "samp":
            path = SAMP_FILES / (dff + ".dff")
        else:
            tmp.write_bytes(read_img_entry(img, img_index[dff + ".dff"]))
            path = tmp
        parts = grab(path)
        if tmp.exists():
            tmp.unlink()
        if not parts:
            raise SystemExit(f"carmour_slots: no mesh in {dff}")
        return merge(list(parts.values()))

    def frame_of(verts):
        """Thin axis c, in-plane axes a (long) and b (short) of the minimum-area rectangle, extents and the centre."""
        p = verts - verts.mean(0)
        _w, vec = np.linalg.eigh(np.cov(p.T))
        c0, e2, e1 = vec[:, 0], vec[:, 1], vec[:, 2]
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
        c = np.cross(a, b)
        if c @ c0 < 0:
            pass  # c = a x b either way: a right-handed frame is all that matters for a slab
        ext = [float(np.ptp(verts @ ax)) for ax in (a, b, c)]
        mid = [float((verts @ ax).min() + (verts @ ax).max()) / 2 for ax in (a, b, c)]
        centre = a * mid[0] + b * mid[1] + c * mid[2]
        return a, b, c, ext, centre

    panels = {}
    for spec in PANELS:
        geo = panel_geo(spec)
        panels[spec[0]] = (geo, frame_of(geo[0]))
        a, b, c, ext, centre = panels[spec[0]][1]
        log(f"panel {spec[0]} ({spec[3]}): {ext[0]:.3f} x {ext[1]:.3f} x {ext[2]:.3f} m")

    def fit_surface(slot):
        _name, door, n, u, v, c, w, h = slot
        n, u, v, c = (np.array(x, dtype=float) for x in (n, u, v, c))
        target = leaf_bvh if door else body_bvh
        pts = []
        for i in range(11):
            for j in range(11):
                o = c + u * (i / 10 - 0.5) * w + v * (j / 10 - 0.5) * h + n * 3
                hit = target.ray_cast(Vector(o), Vector(-n), 6)
                if hit[0] is not None:
                    pts.append(np.array(hit[0]))
        if len(pts) < 0.6 * 121:
            raise SystemExit(f"carmour_slots: slot {_name} hits the shell in only {len(pts)} of 121 rays")
        pts = np.array(pts)
        use = pts
        nf = n
        for _ in range(3):
            _u, _s, vt = np.linalg.svd(use - use.mean(0))
            nf = vt[2] if vt[2] @ n > 0 else -vt[2]
            d = use @ nf
            use = pts[(pts @ nf) >= (pts @ nf).max() - 0.06]
            if len(use) < 6:
                nf = n
                break
        tilt = math.degrees(math.acos(max(-1, min(1, nf @ n))))
        if tilt > 12:
            raise SystemExit(f"carmour_slots: slot {_name} plane tilts {tilt:.1f} deg")
        dmax = float((pts @ nf).max())
        gap = dmax - float((pts @ nf).min())
        centre = c + nf * ((dmax + PROUD) - c @ nf)
        up = norm(u - nf * (u @ nf))
        vp = np.cross(nf, up)
        if vp @ v < 0:
            vp = -vp
        return dict(name=_name, door=door, centre=centre, u=up, v=vp, n=nf, w=w, h=h, tilt=tilt, gap=gap + PROUD)

    def place(fit, key):
        geo, (a, b, c, ext, centre_m) = panels[key]
        long_is_u = fit["w"] >= fit["h"]
        L, S = (fit["u"], fit["v"]) if long_is_u else (fit["v"], fit["u"])
        ld, sd = (fit["w"], fit["h"]) if long_is_u else (fit["h"], fit["w"])
        scale = min(1.0, ld / ext[0], sd / ext[1])
        best = None
        mt = np.array([a, b, c])
        for sa in (1, -1):
            for sb in (1, -1):
                qa, qb = sa * L, sb * S
                q = np.array([qa, qb, np.cross(qa, qb)]).T
                r = q @ mt
                score = float((r @ np.array([0, 0, 1.0])) @ fit["v"])
                if best is None or score > best[0] + 1e-9:
                    best = (score, r)
        r = best[1]
        target = fit["centre"] + fit["n"] * (ext[2] * scale / 2)
        pos = target - r @ (scale * centre_m)
        ax, ay, az = to_zxy(r)
        e = dict(x=round(float(pos[0]), 4), y=round(float(pos[1]), 4), z=round(float(pos[2]), 4), rx=round(ax, 3), ry=round(ay, 3), rz=round(az, 3), scale=round(scale, 4))
        back = zxy(e["rx"], e["ry"], e["rz"])
        if np.abs(back - r).max() > 2e-3:
            raise SystemExit(f"carmour_slots: ZXY decomposition off for {fit['name']}/{key}")
        return e

    fits = [fit_surface(s) for s in SLOTS]
    placed = {f["name"]: {key: place(f, key) for key, *_ in PANELS} for f in fits}
    for f in fits:
        log(f"slot {f['name']}: {f['w']:.2f} x {f['h']:.2f} m, tilt {f['tilt']:.1f} deg, surface relief {f['gap'] * 100:.1f} cm, scales " + " ".join(f"{k}={placed[f['name']][k]['scale']}" for k, *_ in PANELS))

    hinge = np.array(HINGE)

    def world(entry, key, angle=0.0):
        """The placed panel's world vertices (verts, tris); angle: door open degrees (outward = -rz about the hinge)."""
        geo = panels[key][0]
        r = zxy(entry["rx"], entry["ry"], entry["rz"])
        verts = (r @ (entry["scale"] * geo[0]).T).T + np.array([entry["x"], entry["y"], entry["z"]])
        if angle:
            verts = (rz(math.radians(-angle)) @ (verts - hinge).T).T + hinge
        return verts, geo[1]

    def leaf_at(angle):
        verts = leaf[0]
        if angle:
            verts = (rz(math.radians(-angle)) @ (verts - hinge).T).T + hinge
        return verts, leaf[1]

    angles = [0, 15, 30, 45, 60, 70, 80, 90, 95, DOOR_CHECK_DEG]
    keys = [p[0] for p in PANELS]
    names = [s[0] for s in SLOTS]
    tests = 0

    def touches(g1, g2):
        return len(bvh(g1).overlap(bvh(g2))) > 0

    def fail(msg):
        raise SystemExit("carmour_slots: OVERLAP " + msg)

    # every panel clear of the shell (the door panel at every angle)
    for name in names:
        for key in keys:
            for ang in angles if name == "door" else [0]:
                tests += 1
                if touches(world(placed[name][key], key, ang if name == "door" else 0), body):
                    fail(f"{name}/{key} clips the shell at door angle {ang}")
    # every pair of slots x every pair of panel types
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            for k1 in keys:
                for k2 in keys:
                    for ang in angles if "door" in (names[i], names[j]) else [0]:
                        a1 = ang if names[i] == "door" else 0
                        a2 = ang if names[j] == "door" else 0
                        tests += 1
                        if touches(world(placed[names[i]][k1], k1, a1), world(placed[names[j]][k2], k2, a2)):
                            fail(f"{names[i]}/{k1} x {names[j]}/{k2} at door angle {ang}")
    # the swinging leaf against every other slot's panels
    for name in names[1:]:
        for key in keys:
            for ang in angles:
                tests += 1
                if touches(leaf_at(ang), world(placed[name][key], key)):
                    fail(f"door leaf x {name}/{key} at door angle {ang}")
    # the door panels against everything, one degree at a time: the largest angle that stays clear
    clear = DOOR_CHECK_DEG
    for ang in range(0, DOOR_CHECK_DEG + 1):
        bad = False
        for key in keys:
            dp = world(placed["door"][key], key, ang)
            tests += 1
            if touches(dp, body):
                bad = True
            for name in names[1:]:
                for k2 in keys:
                    tests += 1
                    if touches(dp, world(placed[name][k2], k2)):
                        bad = True
        if bad:
            clear = ang - 1
            break
    log(f"{tests} placement tests passed; door panels clear of shell and neighbours up to {clear} deg")
    if clear < CLEAR_REQUIRED_DEG:
        raise SystemExit(f"carmour_slots: door panels clear only to {clear} deg (< {CLEAR_REQUIRED_DEG}); widen the hinge margin")

    def num(v):
        s = f"{v:.4f}".rstrip("0").rstrip(".")
        return "0" if s in ("-0", "") else s

    lines = [
        "-- Generated by tools/carmour_slots.py; do not edit. Fixed slots on the towable Airstream (model 610) for welded defence",
        "-- panels (carmour) go, in the vehicle's frame (+Y forward). A slot is a rectangle (w x h metres) on the shell; the",
        "-- rectangles never overlap, so any mix of panel types in the slots never overlaps either. byPanel: per accepted panel",
        "-- item type, the object's offset (x, y, z), GTA ZXY rotation (rx, ry, rz) and uniform scale that centre it in the slot,",
        "-- flat and 2 cm off the skin, long side along the slot's long side, scaled down only when bigger than the rectangle.",
        "-- The door slot is given with the door CLOSED; swing it with the door by rotating it about DOOR.hinge (a vehicle door",
        "-- cannot carry an attached object): rz about the hinge changes by dir * angle (outward = -rz), up to openDeg.",
        "local M = {}",
        "",
        f"M.DOOR = {{ hinge = {{ x = {num(HINGE[0])}, y = {num(HINGE[1])}, z = {num(HINGE[2])} }}, openDeg = {DOOR_OPEN_DEG}, dir = -1 }}",
        "",
        "M.SLOTS = {",
        f"    [{MODEL}] = {{",
    ]
    for f in fits:
        lines += ["        {", f'            name = "{f["name"]}",', f"            door = {'true' if f['door'] else 'false'},", f"            w = {num(f['w'])},", f"            h = {num(f['h'])},", "            byPanel = {"]
        for key in keys:
            e = placed[f["name"]][key]
            lines.append(f"                {key} = {{")
            lines += [f"                    {k} = {num(e[k])}," for k in ("x", "y", "z", "rx", "ry", "rz", "scale")]
            lines.append("                },")
        lines += ["            },", "        },"]
    lines += ["    },", "}", "", "return M", ""]
    OUT_LUA.parent.mkdir(parents=True, exist_ok=True)
    OUT_LUA.write_text("\n".join(lines), encoding="ascii", newline="\n")
    log(f"wrote {OUT_LUA.relative_to(ROOT)}")

    # ---- contact sheets
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "OBJECT"
    sc.display.shading.show_cavity = False
    sc.world = bpy.data.worlds.new("w")
    sc.render.resolution_x, sc.render.resolution_y = TILE
    cam = bpy.data.cameras.new("c")
    cam_obj = bpy.data.objects.new("c", cam)
    sc.collection.objects.link(cam_obj)
    sc.camera = cam_obj

    def mesh_obj(name, geo, colour):
        me = bpy.data.meshes.new(name)
        me.from_pydata([tuple(p) for p in geo[0]], [], geo[1])
        o = bpy.data.objects.new(name, me)
        o.color = colour + (1.0,)
        sc.collection.objects.link(o)
        return o

    mesh_obj("body", body, (0.62, 0.62, 0.64))
    door_obj = mesh_obj("leaf", leaf, (0.4, 0.35, 0.3))

    def aim(loc, tgt, ortho=None, spin=False):
        cam.type = "ORTHO" if ortho else "PERSP"
        if ortho:
            cam.ortho_scale = ortho
        cam_obj.location = loc
        q = (Vector(tgt) - Vector(loc)).to_track_quat("-Z", "Y")
        if spin:
            q = q @ Quaternion((0, 0, 1), math.radians(90))
        cam_obj.rotation_euler = q.to_euler()

    views = {
        "left": lambda: aim((-20, 0.8, 0.9), (0, 0.8, 0.9), 8.2),
        "right": lambda: aim((20, 0.8, 0.9), (0, 0.8, 0.9), 8.2),
        "front34": lambda: aim((-6.5, 9.0, 3.6), (0, 1.0, 0.8)),
        "rear34": lambda: aim((6.5, -8.0, 3.6), (0, 0.8, 0.9)),
        "top": lambda: aim((0, 0.8, 20), (0, 0.8, 0), 8.2, True),
    }

    def build(assign, angle):
        for o in [o for o in bpy.data.objects if o.name.startswith("P_")]:
            bpy.data.objects.remove(o, do_unlink=True)
        lv = leaf_at(angle)
        door_obj.data.clear_geometry()
        door_obj.data.from_pydata([tuple(p) for p in lv[0]], [], lv[1])
        door_obj.data.update()
        for name in names:
            key = assign[name]
            mesh_obj("P_" + name, world(placed[name][key], key, angle if name == "door" else 0), COLOURS[keys.index(key)])

    def shoot(view, path):
        views[view]()
        sc.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)

    tiles = sheets / "tiles"
    tiles.mkdir(parents=True, exist_ok=True)
    for key in keys:
        build({n: key for n in names}, 0)
        for view in VIEWS:
            shoot(view, tiles / f"{view}_{key}.png")
    mixed = {n: keys[(i * 3 + 1) % len(keys)] for i, n in enumerate(names)}
    log("mixed set: " + ", ".join(f"{n}={mixed[n]}" for n in names))
    for ang in (0, 45, 90):
        build(mixed, ang)
        for view in ("left", "front34", "top"):
            shoot(view, tiles / f"mixed_{view}_{ang}.png")


def stitch(sheets: Path) -> None:
    from PIL import Image, ImageDraw

    tiles = sheets / "tiles"
    keys = [p[0] for p in PANELS]

    def sheet(files, labels, cols, out):
        ims = [Image.open(tiles / f) for f in files]
        w, h = ims[0].size
        rows = (len(ims) + cols - 1) // cols
        canvas = Image.new("RGB", (w * cols, h * rows), (30, 30, 30))
        draw = ImageDraw.Draw(canvas)
        for i, (im, label) in enumerate(zip(ims, labels)):
            x, y = (i % cols) * w, (i // cols) * h
            canvas.paste(im.convert("RGB"), (x, y))
            draw.text((x + 8, y + 6), label, fill=(255, 255, 255))
        canvas.save(sheets / out)

    for view in VIEWS:
        sheet([f"{view}_{k}.png" for k in keys], keys, 2, f"sheet_{view}.png")
    mixed = [f"mixed_{v}_{a}.png" for v in ("left", "front34", "top") for a in (0, 45, 90)]
    sheet(mixed, [f"{v} door {a} deg" for v in ("left", "front34", "top") for a in (0, 45, 90)], 3, "sheet_mixed.png")


def main(argv=None) -> int:
    import argparse

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender.exe (default: BLENDER or the newest install)")
    ap.add_argument("--sheets", type=Path, default=Path(os.environ.get("TEMP", ".")) / "carmour_sheets", help="where the contact sheets go")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("carmour_slots: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    blender = find_blender(args.blender)
    if not blender:
        print("carmour_slots: no Blender found (pass --blender)", file=sys.stderr)
        return 2
    args.sheets.mkdir(parents=True, exist_ok=True)
    cmd = [str(blender), "-b", "--python", __file__, "--", str(gta), str(args.sheets)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    print("\n".join(line[5:] if line.startswith("CARM ") else line for line in out.splitlines() if line.startswith("CARM") or "Error" in line or "carmour_slots" in line or "Traceback" in line))
    if res.returncode != 0:
        return res.returncode or 1
    stitch(args.sheets)
    print(f"contact sheets in {args.sheets}")
    return 0


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        try:
            blender_main(Path(rest[0]), Path(rest[1]))
        except SystemExit as e:
            print(e, flush=True)
            sys.exit(1)
    else:
        sys.path.insert(0, str(ROOT))
        sys.exit(main())
