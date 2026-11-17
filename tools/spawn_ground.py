"""Lays the loot and vehicle spawn points on the real ground with sa-geom (https://github.com/VIRUXE/sa-geom), offline.

    python -m tools.spawn_ground [--cli PATH] [--gta DIR] [--apply] [--report FILE]

Nothing here runs in the server: the results are data the server reads.

- Loot (loot_spawns.ground): a loot point lays item i of a roll of n at angle i*360/n, 0.6 m out (loot/server/main.lua
  rollSpawn). For every point and every one of those slots (n = 1..roll.MAX_PER_SPAWN) the ground under the slot is
  measured from just above the point's own ground; a slot that lands more than SLOT_STEP off the point's ground (off a
  table, down a step, into a wall) is pulled in to SLOT_PULL metres, and to the point itself if that fails too. The
  column holds {"z": point ground, "s": [[[dx, dy, z, nx, ny], ...one per item...], ...one per n...]}; NULL when there
  is no ground under the point (the roll then places as before).
- Item rest heights (loot/shared/item_rest.lua): how far each item type's origin sits above its lowest point when it
  lies in its rest rotation (rotx, roty, rotz), from the render mesh of the model the client draws (vanilla, SA-MP
  from SAMP.img/samp_models, or the port's prop_models). With the slot's ground and normal the roll puts the item
  flush on the ground and tilted to it, whatever the type: no more per-type modelz guesses.
- Vehicles (vehicle_spawn_poses): every vehicle point x every vehicle type it can roll x both headings it can face
  (spawn.roll turns half of them 180 degrees) laid by the vehicle's mesh (wheels on the ground, tilted to the slope):
  x, y, z and the rotation in MTA "ZXY" order. Boats are left out (they float where they are put). A heading is
  refused when the body runs into collision (a wall, pole, fence, trunk: sa-geom `blocked`), rests propped on
  something higher than the ground under it (`gap` > VEHICLE_GAP) or stands steeper than VEHICLE_STEEP. A model that
  fits one way always faces that way; one that fits neither way goes in vehicle_spawn_removed and that point never
  rolls it. A point with no ground at all (it stands on something the world lacks) spawns as before.

The world is the vanilla map plus the port's own map objects and removals (maps/data/*.lua, world/data/puzzles.lua)
and the SA-MP client's SAMP.ide/SAMP.img/SAMPCOL.img. Points are read from the live DB through the lib credentials in
mods/deathmatch/settings.xml. Without --apply it only writes the report and the files (item_rest.lua, the seeds);
--apply also loads the results into the live DB.

Rerun it after loot points, vehicle points or item models change.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.render_places import MAPS, PUZZLES, REMOVAL, ROW  # noqa: E402

RES = ROOT / "resources" / "[scavengesurvive]"
GTA = Path("/gta/sa/gamefiles/GTA San Andreas")
CLI = Path("/gta/sa/sa-geom/target/release/sa-geom")
SETTINGS = ROOT.parent / "mods" / "deathmatch" / "settings.xml"
ITEM_TYPES = RES / "data" / "generated" / "item_types.lua"
VEHICLE_TYPES = RES / "data" / "generated" / "vehicle_types.lua"
REST_OUT = RES / "loot" / "shared" / "item_rest.lua"
LOOT_SEED = ROOT / "sql" / "seed" / "0009_loot_spawn_ground.sql"
POSE_SEED = ROOT / "sql" / "seed" / "0010_vehicle_spawn_poses.sql"

# the model resources lib/modules/models.lua resolves item models through, with their manifests
MODEL_PACKS = [("samp_models", "manifest.lua"), ("hat_models", "hats.lua"), ("door_models", "doors.lua"), ("prop_models", "props.lua"), ("box_models", "boxes.lua")]
SCATTER = 0.6  # loot/server/main.lua rollSpawn
MAX_PER_SPAWN = 6  # loot/shared/logic/roll.lua roll.MAX_PER_SPAWN
# item size classes for the slot clearance check: box (length, width, height) an item of the class fits in, lying
# with its footprint centred on the slot; types bigger than the last class are not checked (any heading)
ITEM_CLASSES = [(0.5, 0.5, 0.4), (1.0, 0.5, 0.5), (1.8, 0.7, 0.7), (2.6, 1.4, 1.4)]
FOOTPRINT_MAX = 3.0  # a mesh wider than this is clamped (and reported): e.g. a laser pointer's beam
OUTER_RING = (12, 1.3)  # extra slots around the point for crowded rolls: count, radius; s[MAX_PER_SPAWN + 1]
HEADINGS = 16  # clearance is tested at k * 360 / HEADINGS
ITEM_LIFT = 0.08  # the boxes start this far over the ground: bumps under a lying item are not walls
NUDGE = [(r * math.cos(math.radians(a)), r * math.sin(math.radians(a))) for r in (0.15, 0.3, 0.45) for a in range(0, 360, 45)]
SLOT_STEP = 0.3  # a slot this far above/below the point's ground is off its surface
SLOT_PULL = 0.3  # ...and is tried again this far out
POINT_ABOVE, POINT_DEPTH = 0.5, 2.5  # the point's ground: from 0.5 m over the stored z, 2.5 m down
VEHICLE_ABOVE = 0.3  # rays start this far over the stored z (the car's centre, 0.5-1 m up: never under a carport roof)
VEHICLE_BELOW = 3.0  # ...and give up this far under it: deeper ground means the point stands on something missing
VEHICLE_GAP = 0.4  # wheels this far over the ground under the centre: propped on a wall top or kerb, keeps its old spawn
VEHICLE_STEEP = 35.0  # steeper than this the point keeps its old spawn (a car tilted onto a cliff face is no fix)
CATEGORY = {"C": "car", "T": "truck", "M": "motorbike", "B": "pushbike", "H": "helicopter", "P": "plane", "S": "boat", "L": "train"}
SIZE = {"S": "small", "M": "medium", "L": "large"}


# --- inputs -------------------------------------------------------------------------------------------------------


def db(sql: str) -> list[list[str]]:
    text = SETTINGS.read_text(encoding="utf8")
    user = re.search(r'lib\.db_user" value="([^"]*)"', text).group(1)
    pw = re.search(r'lib\.db_pass" value="([^"]*)"', text).group(1)
    # the SQL goes on stdin: the seeds are megabytes, far over the kernel's limit for one argument
    res = subprocess.run(["mariadb", "-h127.0.0.1", f"-u{user}", f"-p{pw}", "scavengesurvive", "-N", "-B"], input=sql, capture_output=True, text=True)
    if res.returncode != 0:  # never echo the command line: it holds the password
        sys.exit(f"mariadb: {res.stderr.strip()[:2000]}")
    return [line.split("\t") for line in res.stdout.splitlines()]


def lua_models(path: Path) -> dict[int, str]:
    """`[id] = { dff = "name", ... }` rows of a model pack's manifest."""
    return {int(i): n for i, n in re.findall(r'\[(\d+)\] = \{ dff = "([^"]+)"', path.read_text(encoding="utf8"))}


def item_types() -> list[dict]:
    out = []
    for line in ITEM_TYPES.read_text(encoding="utf8").splitlines():
        if not line.startswith("M.byUname."):
            continue
        g = lambda k: re.search(rf"\b{k} = (-?[\d.]+)", line)  # noqa: E731
        u = re.search(r'\buname = "([^"]+)"', line)
        if u and g("model"):
            out.append({"uname": u.group(1), "model": int(g("model").group(1)), "rest": [float(g(k).group(1)) if g(k) else 0.0 for k in ("rotx", "roty", "rotz")]})
    return out


def vehicle_types() -> list[dict]:
    out = []
    for line in VEHICLE_TYPES.read_text(encoding="utf8").splitlines():
        if not line.startswith("M.byUname."):
            continue
        s = lambda k: re.search(rf'\b{k} = "([^"]*)"', line)  # noqa: E731
        m = re.search(r"\bmodel = (\d+)", line)
        if m and s("uname"):
            out.append({"uname": s("uname").group(1), "model": int(m.group(1)), "group": s("group").group(1) if s("group") else None, "category": s("category").group(1), "size": s("size").group(1)})
    return out


def overlay(work: Path, gta: Path) -> Path:
    """The port's world on top of vanilla: its map objects and removals, the SA-MP models, and mesh shapes for the
    SA-MP and prop models items use."""
    rows = ["<map>"]
    for path in sorted(MAPS.glob("*.lua")) + [PUZZLES]:
        text = path.read_text(encoding="utf8")
        for m, x, y, z, rx, ry, rz, world, interior in ROW.findall(text):
            if int(world) in (-1, 0) and int(interior) in (-1, 0):
                rows.append(f'<object model="{m}" posX="{x}" posY="{y}" posZ="{z}" rotX="{rx}" rotY="{ry}" rotZ="{rz}" interior="0"/>')
        if "removals = {" in text:
            for m, x, y, z, r in REMOVAL.findall(text[text.index("removals = {") :]):
                rows.append(f'<removeWorldObject model="{m}" radius="{r}" posX="{x}" posY="{y}" posZ="{z}" interior="0"/>')
    rows.append("</map>")
    (work / "port.map").write_text("\n".join(rows), encoding="utf8")
    samp = gta / "SAMP"
    toml = [f'ide = [{{ path = "{samp / "SAMP.ide"}" }}]', f'img = [{{ path = "{samp / "SAMPCOL.img"}" }}, {{ path = "{samp / "SAMP.img"}" }}]', 'map = [{ path = "port.map" }]']
    for res, manifest in MODEL_PACKS:
        files = RES / res / "files"
        for mid, name in sorted(lua_models(RES / res / manifest).items()):
            f = files / f"{name}.dff"
            if f.exists():
                toml.append(f'[[dff]]\npath = "{f}"\nid = {mid}')
    p = work / "overlay.toml"
    p.write_text("\n".join(toml) + "\n", encoding="utf8")
    return p


def batch(cli: Path, ov: Path, queries: list[dict], above: float) -> list[dict]:
    res = subprocess.run([str(cli), "batch", "--above", str(above), "--overlay", str(ov)], input="\n".join(json.dumps(q) for q in queries) + "\n", capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(res.stderr)
    out = [json.loads(line) for line in res.stdout.splitlines() if line.strip()]
    assert len(out) == len(queries), (len(out), len(queries))
    return out


# --- loot ---------------------------------------------------------------------------------------------------------


def ring(n: int, r: float) -> list[tuple[float, float]]:
    return [(math.cos(math.radians(i * 360.0 / n)) * r, math.sin(math.radians(i * 360.0 / n)) * r) for i in range(1, n + 1)]


def loot(cli: Path, ov: Path, report: list[str]) -> dict[int, dict | None]:
    pts = [(int(i), float(x), float(y), float(z), int(it)) for i, x, y, z, it in db("SELECT id, x, y, z, interior FROM loot_spawns ORDER BY id")]
    base = batch(cli, ov, [{"x": x, "y": y, "z": z, "interior": it, "depth": POINT_DEPTH} for _, x, y, z, it in pts], POINT_ABOVE)
    ground = {}
    for (pid, x, y, z, it), g in zip(pts, base):
        if g["hit"]:
            ground[pid] = (x, y, g["z"], it, g)
        else:
            report.append(f"loot\t{pid}\t{x:.2f}\t{y:.2f}\t{z:.2f}\tno_ground\tplaced as before")
    # every slot at full scatter, then the pulled-in and centre fallbacks for the slots that leave their surface
    out: dict[int, dict | None] = {pid: None for pid, *_ in pts}
    slots = {pid: [[None] * n for n in range(1, MAX_PER_SPAWN + 1)] for pid in ground}
    for radius in (SCATTER, SLOT_PULL, 0.0):
        todo = []
        for pid, (x, y, gz, it, _) in ground.items():
            for n in range(1, MAX_PER_SPAWN + 1):
                for i, (dx, dy) in enumerate(ring(n, radius)):
                    if slots[pid][n - 1][i] is None:
                        todo.append((pid, n, i, dx, dy, {"x": x + dx, "y": y + dy, "z": gz, "interior": it, "depth": SLOT_STEP + POINT_ABOVE + 1.0}))
        for (pid, n, i, dx, dy, _), r in zip(todo, batch(cli, ov, [t[5] for t in todo], POINT_ABOVE) if todo else []):
            gz = ground[pid][2]
            if r["hit"] and (abs(r["z"] - gz) <= SLOT_STEP or radius == 0.0):
                slots[pid][n - 1][i] = [round(dx, 3), round(dy, 3), round(r["z"], 3), round(r["nx"], 3), round(r["ny"], 3)]
    stored_z = {p[0]: p[3] for p in pts}
    for pid, (x, y, gz, it, g) in ground.items():
        for n_list in slots[pid]:
            for k, v in enumerate(n_list):
                if v is None:  # not even the centre: lay it on the point's own ground
                    n_list[k] = [0.0, 0.0, round(gz, 3), round(g["nx"], 3), round(g["ny"], 3)]
    # the outer ring: room for crowded rolls; a slot off the point's surface is left out (false)
    count, radius = OUTER_RING
    todo = [(pid, k, dx, dy) for pid in ground for k, (dx, dy) in enumerate(ring(count, radius))]
    outer = batch(cli, ov, [{"x": ground[pid][0] + dx, "y": ground[pid][1] + dy, "z": ground[pid][2], "interior": ground[pid][3], "depth": SLOT_STEP + POINT_ABOVE + 1.0} for pid, k, dx, dy in todo], POINT_ABOVE)
    for pid in ground:
        slots[pid].append([False] * count)
    for (pid, k, dx, dy), r in zip(todo, outer):
        if r["hit"] and abs(r["z"] - ground[pid][2]) <= SLOT_STEP:
            slots[pid][-1][k] = [round(dx, 3), round(dy, 3), round(r["z"], 3), round(r["nx"], 3), round(r["ny"], 3)]
    fit_slots(cli, ov, ground, slots, report)
    for pid, (x, y, gz, it, g) in ground.items():
        out[pid] = {"z": round(gz, 3), "s": slots[pid]}
        if abs(gz - stored_z[pid]) > 0.25:
            report.append(f"loot\t{pid}\t{x:.2f}\t{y:.2f}\t{stored_z[pid]:.2f}\tmoved\tground at {gz:.2f}")
        tilt = math.degrees(math.acos(max(-1.0, min(1.0, g["nz"]))))
        if tilt > 30:
            report.append(f"loot\t{pid}\t{x:.2f}\t{y:.2f}\t{gz:.2f}\tsteep\t{tilt:.0f} degrees")
    print(f"loot: {len(pts)} points, {len(ground)} on the ground, {len(pts) - len(ground)} without", file=sys.stderr)
    return out


def clearance(cli: Path, ov: Path, queries: list[dict]) -> list[dict]:
    """sa-geom clearance: per query the ground and, per item class box, the bitmask of the HEADINGS that are clear."""
    if not queries:
        return []
    res = subprocess.run([str(cli), "clearance", "--above", str(POINT_ABOVE), "--overlay", str(ov)], input="\n".join(json.dumps(q) for q in queries) + "\n", capture_output=True, text=True)
    if res.returncode != 0:
        sys.exit(res.stderr)
    out = [json.loads(line) for line in res.stdout.splitlines() if line.strip()]
    assert len(out) == len(queries), (len(out), len(queries))
    return out


def fit_slots(cli: Path, ov: Path, ground: dict, slots: dict, report: list[str]) -> None:
    """Which headings each item size class fits in at every slot (appended to the slot as three masks). A slot where a
    class fits no heading is nudged (NUDGE offsets, staying on the point's surface) to the spot where the most classes
    fit, then the most headings; the slot keeps its own spot when no nudge does better."""
    boxes = [list(b) for b in ITEM_CLASSES]

    def q(pid, dx, dy, z):
        x, y, _, it, _ = ground[pid]
        return {"x": x + dx, "y": y + dy, "z": z, "interior": it, "depth": SLOT_STEP + POINT_ABOVE + 1.0, "lift": ITEM_LIFT, "headings": HEADINGS, "boxes": boxes}

    def score(masks):
        return (sum(1 for m in masks if m), sum(bin(m).count("1") for m in masks))

    keys = [(pid, n, i) for pid, s in slots.items() for n, lst in enumerate(s) for i in range(len(lst)) if lst[i]]
    first = clearance(cli, ov, [q(pid, *slots[pid][n][i][:2], slots[pid][n][i][2]) for pid, n, i in keys])
    cramped = []
    for (pid, n, i), r in zip(keys, first):
        v = slots[pid][n][i]
        masks = r["masks"] if r["hit"] else [0] * len(boxes)
        v += masks
        if any(m == 0 for m in masks):
            cramped.append((pid, n, i))
    tries, tkeys = [], []
    for pid, n, i in cramped:
        v = slots[pid][n][i]
        for ox, oy in NUDGE:
            tries.append(q(pid, v[0] + ox, v[1] + oy, v[2]))
            tkeys.append((pid, n, i, v[0] + ox, v[1] + oy))
    best: dict[tuple, tuple] = {}
    for (pid, n, i, dx, dy), r in zip(tkeys, clearance(cli, ov, tries)):
        if not r["hit"] or abs(r["z"] - ground[pid][2]) > SLOT_STEP:
            continue
        sc = score(r["masks"])
        # prefer the most classes, then the most headings, then the smallest move
        key = (sc, -math.hypot(dx - slots[pid][n][i][0], dy - slots[pid][n][i][1]))
        if (pid, n, i) not in best or key > best[(pid, n, i)][0]:
            best[(pid, n, i)] = (key, [round(dx, 3), round(dy, 3), r["z"], r["nx"], r["ny"], *r["masks"]])
    moved = still = 0
    for pid, n, i in cramped:
        v = slots[pid][n][i]
        b = best.get((pid, n, i))
        if b and b[0][0] > score(v[5:]):
            slots[pid][n][i] = b[1]
            moved += 1
        if any(m == 0 for m in slots[pid][n][i][5:]):
            still += 1
    stuck = defaultdict(list)
    for pid, s in slots.items():
        for n, lst in enumerate(s[:MAX_PER_SPAWN]):
            for i, v in enumerate(lst):
                for c, m in enumerate(v[5:]):
                    if m == 0:
                        stuck[(pid, c + 1)].append(f"{i + 1}/{n + 1}")
    names = {1: "small", 2: "medium", 3: "long", 4: "large"}
    for (pid, c), where in sorted(stuck.items()):
        x, y, gz, _, _ = ground[pid]
        report.append(f"loot\t{pid}\t{x:.2f}\t{y:.2f}\t{gz:.2f}\tno_room_{names[c]}\t{len(where)} slots ({' '.join(where[:6])}{' ...' if len(where) > 6 else ''}): any heading")
    print(f"loot slots: {len(keys)} checked, {len(cramped)} cramped, {moved} nudged, {still} still with a class that fits nowhere", file=sys.stderr)


def item_rest(cli: Path, ov: Path, report: list[str]) -> dict[str, tuple]:
    types = item_types()
    rest: dict[str, tuple] = {}
    by_rest = defaultdict(list)
    for t in types:
        by_rest[tuple(t["rest"])].append(t)
    for r, group in by_rest.items():
        ids = sorted({t["model"] for t in group})
        res = subprocess.run([str(cli), "model", "--overlay", str(ov), "--rest=" + ",".join(str(v) for v in r), *map(str, ids)], capture_output=True, text=True, check=True)
        info = {m["model"]: m for m in json.loads(res.stdout)}
        for t in group:
            m = info.get(t["model"])
            if m and m.get("shape") and m.get("base") is not None:
                x0, x1, y0, y1 = m["rect"]
                sx, sy, sz = x1 - x0, y1 - y0, m["size"][2]
                if max(sx, sy) > FOOTPRINT_MAX:
                    report.append(f"item\t{t['uname']}\tmodel {t['model']}\t\t\toversized_mesh\t{sx:.2f} x {sy:.2f} m, footprint clamped to {FOOTPRINT_MAX} m")
                    sx, sy = min(sx, FOOTPRINT_MAX), min(sy, FOOTPRINT_MAX)
                    x0, x1, y0, y1 = (x0 + x1 - sx) / 2, (x0 + x1 + sx) / 2, (y0 + y1 - sy) / 2, (y0 + y1 + sy) / 2
                long_x = 1 if sx > sy else 0
                length, width = max(sx, sy), min(sx, sy)
                cls = next((k + 1 for k, (cl, cw, ch) in enumerate(ITEM_CLASSES) if length <= cl and width <= cw and sz <= ch), 0)
                # base, footprint centre (cx, cy) and size (sx, sy) in the item's frame, size class (0: unchecked), long
                # axis is x
                rest[t["uname"]] = (round(m["base"], 4), round((x0 + x1) / 2, 3), round((y0 + y1) / 2, 3), cls, long_x, round(sx, 3), round(sy, 3), round(sz, 3))
            elif t["model"] > 0:
                report.append(f"item\t{t['uname']}\tmodel {t['model']}\t\t\tno_shape\tplaced as before")
    classes = defaultdict(int)
    for v in rest.values():
        classes[v[3]] += 1
    print(f"items: {len(types)} types, {len(rest)} with a rest height; by size class {dict(sorted(classes.items()))}", file=sys.stderr)
    return rest


# --- vehicles -----------------------------------------------------------------------------------------------------


def vehicles(cli: Path, ov: Path, report: list[str]) -> list[tuple]:
    types = vehicle_types()
    rows = db("SELECT id, x, y, z, rz, IFNULL(group_name, ''), IFNULL(type_name, ''), categories, sizes FROM vehicle_spawns ORDER BY id")
    queries, keys = [], []
    for sid, x, y, z, rz, group, tname, cats, sizes in rows:
        x, y, z, rz = float(x), float(y), float(z), float(rz)
        if tname:
            cand = [t for t in types if t["uname"] == tname]
        else:
            cs = {CATEGORY[c] for c in cats if c in CATEGORY}
            ss = {SIZE[c] for c in sizes if c in SIZE}
            cand = [t for t in types if t["group"] == group and t["category"] in cs and t["size"] in ss]
        models = set()
        for t in cand:
            # boats float where they are put; several types can share a model (one pose serves them all)
            if t["category"] in ("boat", "train") or t["model"] in models:
                continue
            models.add(t["model"])
            for flip in (0, 1):
                yaw = (rz + 180.0 * flip) % 360.0
                queries.append({"x": x, "y": y, "z": z, "yaw": yaw, "model": t["model"], "depth": VEHICLE_ABOVE + VEHICLE_BELOW})
                keys.append((int(sid), t["model"], flip, x, y, z, t["uname"]))
    # each model's box (rect in its own frame, height, origin above its lowest point) for the in-game review overlay
    vmodels = sorted({k[1] for k in keys})
    res = subprocess.run([str(cli), "model", *map(str, vmodels)], capture_output=True, text=True, check=True)
    boxes = {m["model"]: m for m in json.loads(res.stdout) if m.get("rect")}
    # every heading of every (point, model): ok, or why not
    status: dict[tuple[int, int], dict[int, tuple]] = defaultdict(dict)
    info, ground_at, block_at = {}, {}, {}
    for (sid, model, flip, x, y, z, uname), r in zip(keys, batch(cli, ov, queries, VEHICLE_ABOVE)):
        info[(sid, model)] = (x, y, z, uname)
        if r["hit"]:
            ground_at[(sid, model)] = r["z"]
        if r.get("blocked") and (sid, model) not in block_at:
            block_at[(sid, model)] = r["blocked"]["at"]
        if not r["hit"]:
            status[(sid, model)][flip] = ("no_ground", "")
            continue
        tilt = math.degrees(math.acos(max(-1.0, min(1.0, r["nz"]))))
        blocked = r.get("blocked")
        if blocked:
            status[(sid, model)][flip] = ("blocked", f"{blocked['name'] or blocked['model']} at {blocked['at'][0]:.1f} {blocked['at'][1]:.1f} {blocked['at'][2]:.1f}")
        elif (r.get("gap") or 0.0) > VEHICLE_GAP:
            status[(sid, model)][flip] = ("propped", f"{r['gap']:.2f} m over the ground under it")
        elif tilt > VEHICLE_STEEP:
            status[(sid, model)][flip] = ("steep", f"{tilt:.0f} degrees")
        else:
            p, rot = r["pos"], r["rot"]
            status[(sid, model)][flip] = ("ok", (p[0], p[1], p[2], rot[0], rot[1], rot[2]), tilt)
    poses, removed, unknown = [], [], set()
    for (sid, model), heads in sorted(status.items()):
        x, y, z, uname = info[(sid, model)]
        ok = {f: h for f, h in heads.items() if h[0] == "ok"}
        if ok:
            for f, h in ok.items():
                poses.append((sid, model, f, *h[1]))
            if max(h[2] for h in ok.values()) > 20:
                report.append(f"vehicle\t{sid}\t{x:.2f}\t{y:.2f}\t{z:.2f}\tslope\t{max(h[2] for h in ok.values()):.0f} degrees under a {uname}")
            if len(ok) == 1:
                f_bad = 1 - next(iter(ok))
                report.append(f"vehicle\t{sid}\t{x:.2f}\t{y:.2f}\t{z:.2f}\tone_way\t{uname} {heads[f_bad][0]} the other way ({heads[f_bad][1]}): always faces the way it fits")
        elif all(h[0] == "no_ground" for h in heads.values()):
            unknown.add(sid)  # nothing to measure: the point spawns as before
        else:
            reasons = [h for h in heads.values() if h[0] != "no_ground"]
            reason, detail = reasons[0][0], "; ".join(f"{h[0]}: {h[1]}" for h in reasons)
            b = boxes.get(model, {})
            rect, size, base = b.get("rect") or [0, 0, 0, 0], b.get("size") or [0, 0, 0], b.get("base") or 0
            at = block_at.get((sid, model)) or [None, None, None]
            geo = (ground_at.get((sid, model)), *rect, size[2], base, *at)
            removed.append((sid, model, uname, reason, detail[:250], x, y, z, geo))
            report.append(f"vehicle\t{sid}\t{x:.2f}\t{y:.2f}\t{z:.2f}\tremoved\t{uname} ({model}) does not fit either way: {detail}")
    for sid in sorted(unknown):
        x, y, z, _ = next(v for k, v in info.items() if k[0] == sid)
        report.append(f"vehicle\t{sid}\t{x:.2f}\t{y:.2f}\t{z:.2f}\tno_ground\tnothing under the point: spawns as before")
    print(f"vehicles: {len(rows)} points, {len(poses)} poses, {len(removed)} point x model pairs removed", file=sys.stderr)
    return poses, removed


# --- outputs ------------------------------------------------------------------------------------------------------


def write_rest(rest: dict[str, float]) -> None:
    lines = [
        "-- Generated by tools/spawn_ground.py; do not edit. Item type -> metres its origin sits above its lowest point",
        "-- when it lies in its rest rotation (rotx, roty, rotz), from the mesh the client draws (sa-geom shapes), then the",
        "-- centre of its footprint in its own frame (cx, cy), its size class for the slot clearance masks (1 small, 2",
        "-- medium, 3 long, 4 large; 0 bigger, not checked), 1 when its long side is its own x axis, the footprint's",
        "-- size and the item's height: { base, cx, cy, class, longX, sx, sy, sz }",
        "return {",
    ]
    def lua(v):
        return "{ " + ", ".join(str(x) for x in v) + " }"

    lines += [f"    {u} = {lua(v)}," if re.fullmatch(r"[A-Za-z_]\w*", u) else f'    ["{u}"] = {lua(v)},' for u, v in sorted(rest.items())]
    lines.append("}")
    REST_OUT.write_text("\n".join(lines) + "\n", encoding="utf8")


def chunks(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i : i + n]


def write_seeds(ground: dict[int, dict | None], poses: list[tuple], removed: list[tuple]) -> tuple[str, str]:
    head = "-- Generated by tools/spawn_ground.py (sa-geom) from the live DB; rerun it, do not edit by hand.\n"
    loot = [head, "CREATE TEMPORARY TABLE spawn_ground_tmp (id INT PRIMARY KEY, ground LONGTEXT NOT NULL);\n"]
    vals = [(pid, g) for pid, g in sorted(ground.items()) if g]
    for part in chunks(vals, 500):
        rows = ",\n".join(f"({pid},'{json.dumps(g, separators=(',', ':'))}')" for pid, g in part)
        loot.append(f"INSERT INTO spawn_ground_tmp (id, ground) VALUES\n{rows};\n")
    loot.append("UPDATE loot_spawns s LEFT JOIN spawn_ground_tmp t ON t.id = s.id SET s.ground = t.ground;\n")
    loot.append("DROP TEMPORARY TABLE spawn_ground_tmp;\n")
    pose = [head, "DELETE FROM vehicle_spawn_poses;\n"]
    for part in chunks(poses, 1000):
        rows = ",\n".join(f"({s},{m},{f},{x:.4f},{y:.4f},{z:.4f},{rx:.3f},{ry:.3f},{rz:.3f})" for s, m, f, x, y, z, rx, ry, rz in part)
        pose.append(f"INSERT INTO vehicle_spawn_poses (spawn_id, model, flip, x, y, z, rx, ry, rz) VALUES\n{rows};\n")
    pose.append("DELETE FROM vehicle_spawn_removed;\n")
    for part in chunks(removed, 1000):
        def num(v):
            return "NULL" if v is None else f"{float(v):.3f}"

        rows = ",\n".join(
            "({},{},'{}','{}','{}',{})".format(sid, m, u, reason, detail.replace("\\", "").replace("'", "''"), ",".join(num(v) for v in geo))
            for sid, m, u, reason, detail, x, y, z, geo in part
        )
        pose.append(
            "INSERT INTO vehicle_spawn_removed (spawn_id, model, type_uname, reason, detail, ground_z, box_x0, box_x1, box_y0, box_y1, "
            f"box_h, box_base, block_x, block_y, block_z) VALUES\n{rows};\n"
        )
    LOOT_SEED.write_text("".join(loot), encoding="utf8")
    POSE_SEED.write_text("".join(pose), encoding="utf8")
    return "".join(loot), "".join(pose)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cli", type=Path, default=CLI)
    ap.add_argument("--gta", type=Path, default=GTA)
    ap.add_argument("--apply", action="store_true", help="load the results into the live DB")
    ap.add_argument("--report", type=Path, help="TSV of the points that need a look")
    ap.add_argument("--removed", type=Path, help="TSV of every (vehicle point, model) that fits neither way")
    a = ap.parse_args(argv)
    report: list[str] = []
    with tempfile.TemporaryDirectory() as tmp:
        ov = overlay(Path(tmp), a.gta)
        rest = item_rest(a.cli, ov, report)
        ground = loot(a.cli, ov, report)
        poses, removed = vehicles(a.cli, ov, report)
    write_rest(rest)
    loot_sql, pose_sql = write_seeds(ground, poses, removed)
    if a.removed:
        with open(a.removed, "w", encoding="utf8") as f:
            f.write("spawn_id\tx\ty\tz\tmodel\ttype\treason\tdetail\n")
            for sid, m, u, reason, detail, x, y, z, _ in removed:
                f.write(f"{sid}\t{x:.3f}\t{y:.3f}\t{z:.3f}\t{m}\t{u}\t{reason}\t{detail}\n")
    if a.report:
        a.report.write_text("kind\tid\tx\ty\tz\tflag\tnote\n" + "\n".join(report) + "\n", encoding="utf8")
    print(f"{len(report)} report lines", file=sys.stderr)
    if a.apply:
        for sql in (loot_sql, pose_sql):
            db(sql)  # one mariadb session per file: the temporary table lives for its statements
        print("applied to the live DB", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
