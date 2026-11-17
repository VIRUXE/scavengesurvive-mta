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
        out[pid] = {"z": round(gz, 3), "s": slots[pid]}
        if abs(gz - stored_z[pid]) > 0.25:
            report.append(f"loot\t{pid}\t{x:.2f}\t{y:.2f}\t{stored_z[pid]:.2f}\tmoved\tground at {gz:.2f}")
        tilt = math.degrees(math.acos(max(-1.0, min(1.0, g["nz"]))))
        if tilt > 30:
            report.append(f"loot\t{pid}\t{x:.2f}\t{y:.2f}\t{gz:.2f}\tsteep\t{tilt:.0f} degrees")
    print(f"loot: {len(pts)} points, {len(ground)} on the ground, {len(pts) - len(ground)} without", file=sys.stderr)
    return out


def item_rest(cli: Path, ov: Path, report: list[str]) -> dict[str, float]:
    types = item_types()
    rest: dict[str, float] = {}
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
                rest[t["uname"]] = round(m["base"], 4)
            elif t["model"] > 0:
                report.append(f"item\t{t['uname']}\tmodel {t['model']}\t\t\tno_shape\tplaced as before")
    print(f"items: {len(types)} types, {len(rest)} with a rest height", file=sys.stderr)
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
    # every heading of every (point, model): ok, or why not
    status: dict[tuple[int, int], dict[int, tuple]] = defaultdict(dict)
    info = {}
    for (sid, model, flip, x, y, z, uname), r in zip(keys, batch(cli, ov, queries, VEHICLE_ABOVE)):
        info[(sid, model)] = (x, y, z, uname)
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
            removed.append((sid, model, uname, reason, detail[:250], x, y, z))
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
        "-- when it lies in its rest rotation (rotx, roty, rotz), from the mesh the client draws (sa-geom shapes).",
        "return {",
    ]
    lines += [f"    {u} = {v}," if re.fullmatch(r"[A-Za-z_]\w*", u) else f'    ["{u}"] = {v},' for u, v in sorted(rest.items())]
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
        rows = ",\n".join("({},{},'{}','{}','{}')".format(sid, m, u, reason, detail.replace("\\", "").replace("'", "''")) for sid, m, u, reason, detail, *_ in part)
        pose.append(f"INSERT INTO vehicle_spawn_removed (spawn_id, model, type_uname, reason, detail) VALUES\n{rows};\n")
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
            for sid, m, u, reason, detail, x, y, z in removed:
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
