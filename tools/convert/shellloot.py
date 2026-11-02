"""Shell loot: loot points inside the enterable trailers (house_shell models 3167-3175: the kept IPL placements in
house_shell/trailers.lua plus the map-placed ones in maps/data) and the log cabin row (house_shell/cabins.lua).
The points per model live in tools/shell_loot.py in the model's frame; here they are carried to each placement.
Roughly one in SURVIVOR_ONE_IN rolls world_survivor, the rest world_civilian, chosen by a hash of the position."""
from __future__ import annotations

import re
from pathlib import Path

from tools import shell_loot

from .common import NUM, SEED_HEADER, write_text
from .houseloot import attached_pos

RESOURCES = Path(__file__).resolve().parents[2] / "resources" / "[scavengesurvive]"
TRAILER_ROW = re.compile(r"^\s*\{\s*(31(?:6[7-9]|7[0-5]))\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*\},?\s*$")
MAP_ROW = re.compile(r"^\s*\{\s*(31(?:6[7-9]|7[0-5]))\s*,((?:\s*" + NUM + r"\s*,){6,}[^}]*)\}")
CABIN_ROW = re.compile(r"^\s*\{\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*\},?\s*$")
MAX_TILT = 10.0


def nearest_zone(x: float, y: float, spawns: list[dict]) -> str:
    best = min(spawns, key=lambda s: (s["x"] - x) ** 2 + (s["y"] - y) ** 2)
    return best["zone"]


def trailer_placements() -> list[tuple[int, float, float, float, float, float, float]]:
    """(model, x, y, z, rx, ry, rz) of every trailer the shells cover, IPL placements then the maps' objects."""
    out = []
    for line in (RESOURCES / "house_shell" / "trailers.lua").read_text(encoding="utf-8").split("\n"):
        m = TRAILER_ROW.match(line)
        if m:
            out.append((int(m.group(1)), float(m.group(2)), float(m.group(3)), float(m.group(4)), 0.0, 0.0, float(m.group(5))))
    for path in sorted((RESOURCES / "maps" / "data").glob("*.lua")):
        for line in path.read_text(encoding="utf-8").split("\n"):
            m = MAP_ROW.match(line)
            if not m:
                continue
            f = [v.strip() for v in m.group(2).split(",") if v.strip()]
            x, y, z, rx, ry, rz = (float(v) for v in f[:6])
            if len(f) >= 8 and (int(float(f[6])) not in (-1, 0) or int(float(f[7])) not in (-1, 0)):
                continue  # inside an interior or another world
            if abs(rx) <= MAX_TILT and abs(ry) <= MAX_TILT:
                out.append((int(m.group(1)), x, y, z, rx, ry, rz))
    return out


def cabin_placements() -> list[tuple[float, float, float, float]]:
    out, inside = [], False
    for line in (RESOURCES / "house_shell" / "cabins.lua").read_text(encoding="utf-8").split("\n"):
        if line.strip().startswith("placements"):
            inside = True
        elif inside:
            m = CABIN_ROW.match(line)
            if m:
                out.append(tuple(float(g) for g in m.groups()))
    return out


def pick_table(x: float, y: float) -> str:
    h = (int(round(x * 100)) * 31 + int(round(y * 100)) * 17) % shell_loot.SURVIVOR_ONE_IN
    return shell_loot.TABLES[1] if h == 0 else shell_loot.TABLES[0]


def shell_spawns(spawns: list[dict]) -> list[dict]:
    rows = []
    for model, px, py, pz, rx, ry, rz in trailer_placements():
        for ox, oy, oz in shell_loot.trailer_points(model):
            rows.append(point(spawns, px, py, pz, rx, ry, rz, ox, oy, oz))
    cabin = shell_loot.cabin_points()
    for px, py, pz, rz in cabin_placements():
        for ox, oy, oz in cabin:
            rows.append(point(spawns, px, py, pz, 0.0, 0.0, rz, ox, oy, oz))
    seen, out = set(), []
    for r in rows:  # a placement listed twice would stack its points
        key = (r["x"], r["y"], r["z"])
        if key not in seen:
            seen.add(key)
            out.append(r)
    return out


def point(spawns, px, py, pz, rx, ry, rz, ox, oy, oz) -> dict:
    x, y, z = attached_pos(px, py, pz, rx, ry, rz, ox, oy, oz)
    x, y, z = round(x, 4), round(y, 4), round(z, 4)
    return {"x": x, "y": y, "z": z, "zone": nearest_zone(x, y, spawns), "table": pick_table(x, y)}


def render_sql(rows: list[dict]) -> str:
    rows = sorted(rows, key=lambda r: (r["zone"], r["x"], r["y"], r["z"]))
    out = [SEED_HEADER, "-- Runs after 0002_loot_spawns.sql (which clears loot_spawns); shell points are added back here."]
    if rows:
        vals = [f"({r['x']!r},{r['y']!r},{r['z']!r},'{r['table']}',{shell_loot.WEIGHT!r},{shell_loot.SIZE},0,0,'{r['zone']}',POINT({r['x']!r}, {r['y']!r}))" for r in rows]
        out.append("INSERT INTO loot_spawns (x,y,z,table_name,weight,size,interior,dimension,zone,pos) VALUES\n" + ",\n".join(vals) + ";\n")
    out.append("INSERT IGNORE INTO loot_spawn_state (spawn_id, next_roll_at) SELECT id, NOW() FROM loot_spawns;\n")
    return "\n".join(out)


def convert(spawns: list[dict], out_seed) -> list[dict]:
    rows = shell_spawns(spawns)
    write_text(Path(out_seed) / "0007_shell_loot.sql", render_sql(rows))
    return rows

