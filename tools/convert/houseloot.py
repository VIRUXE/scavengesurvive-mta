"""House loot (upstream gamemodes/sss/world/houseloot.pwn): every hollow-house object (models 19490, 19492, 19494,
19496, wherever a map placed one) gets up to four world_civilian loot points at fixed offsets rotated by the house's
rotation. Upstream rolled a 50 % coin per house at every start; the port keeps a deterministic half (a hash of the
house position) so the seed is stable and the world keeps the same density."""
from __future__ import annotations

import math
from pathlib import Path

from . import maps
from .common import SEED_HEADER, write_text

HOUSE_OFFSETS = {
    19490: [(-3.73, -3.33, -0.42), (4.25, 3.30, -0.42), (3.11, 0.16, -3.29), (-1.49, -1.67, -3.29)],
    19492: [(-2.99, -0.84, -1.93), (2.49, -1.77, -4.81), (-2.60, -0.16, -4.81), (2.66, 1.97, -1.93)],
    19494: [(-2.52, 1.84, -1.75), (3.52, 2.26, -4.70), (2.78, 1.91, -1.75)],
    19496: [(-2.29, -0.57, -1.75), (3.46, 2.53, -1.75), (3.65, 2.23, -4.39)],
}
TABLE, WEIGHT, SIZE = "world_civilian", 20.0, 3


def attached_pos(px, py, pz, rx, ry, rz, ox, oy, oz):
    """GetAttachedObjectPos from houseloot.pwn: the offset in the object's rotated frame, degrees in SA-MP order."""
    cx, cy, cz = math.cos(math.radians(rx)), math.cos(math.radians(ry)), math.cos(math.radians(rz))
    sx, sy, sz = math.sin(math.radians(rx)), math.sin(math.radians(ry)), math.sin(math.radians(rz))
    x = px + ox * cy * cz - ox * sx * sy * sz - oy * cx * sz + oz * sy * cz + oz * sx * cy * sz
    y = py + ox * cy * sz + ox * sx * sy * cz + oy * cx * cz + oz * sy * sz - oz * sx * cy * cz
    z = pz - ox * cx * sy + oy * sx + oz * cx * cy
    return x, y, z


def selected(px, py) -> bool:
    """Deterministic stand-in for upstream's random(100) < 50 per house: half the houses, fixed per position."""
    return (int(round(px * 100)) + int(round(py * 100))) % 2 == 0


def house_spawns(objects_by_zone: dict[str, list]) -> list[dict]:
    rows = []
    for zone, objects in objects_by_zone.items():
        for obj in objects:
            model, px, py, pz, rx, ry, rz = obj[0], *obj[1:7]
            if model not in HOUSE_OFFSETS or not selected(px, py):
                continue
            for ox, oy, oz in HOUSE_OFFSETS[model]:
                x, y, z = attached_pos(px, py, pz, rx, ry, rz, ox, oy, oz)
                rows.append({"x": round(x, 4), "y": round(y, 4), "z": round(z, 4), "zone": zone.lower(), "house": model})
    return rows


def render_sql(rows: list[dict]) -> str:
    rows = sorted(rows, key=lambda r: (r["zone"], r["x"], r["y"], r["z"]))
    out = [SEED_HEADER, "-- Runs after 0002_loot_spawns.sql (which clears loot_spawns); house points are added back here."]
    if rows:
        vals = [f"({r['x']!r},{r['y']!r},{r['z']!r},'{TABLE}',{WEIGHT!r},{SIZE},0,0,'{r['zone']}',POINT({r['x']!r}, {r['y']!r}))"
                for r in rows]
        out.append("INSERT INTO loot_spawns (x,y,z,table_name,weight,size,interior,dimension,zone,pos) VALUES\n"
                   + ",\n".join(vals) + ";\n")
    out.append("INSERT IGNORE INTO loot_spawn_state (spawn_id, next_roll_at) SELECT id, NOW() FROM loot_spawns;\n")
    return "\n".join(out)


def convert(src_root, out_seed) -> list[dict]:
    root = Path(src_root) / "scriptfiles" / "maps"
    by_zone: dict[str, list] = {}
    for path in maps.map_files(src_root):
        zone = maps.zone_of(path, root)
        parsed = maps.parse_map(path.read_text(encoding="utf-8", errors="replace"), str(path))
        by_zone.setdefault(zone, []).extend(parsed["objects"])
    rows = house_spawns(by_zone)
    write_text(Path(out_seed) / "0006_house_loot.sql", render_sql(rows))
    return rows
