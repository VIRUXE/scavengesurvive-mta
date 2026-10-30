from __future__ import annotations

import re
from pathlib import Path

from .common import NUM, SEED_HEADER, UnparsedLine, read_text, write_text

CALL_RE = re.compile(r"CreateStaticLootSpawn\s*\(")
ARGS_RE = re.compile(
    r"^\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*GetLootIndexFromName\(\"([A-Za-z0-9_]+)\"\)"
    r"\s*,\s*(" + NUM + r")(?:\s*,\s*(-?\d+))?(?:\s*,\s*(-?\d+))?(?:\s*,\s*(-?\d+))?\s*$")
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
ZONES = ["ls", "sf", "lv", "rc", "fc", "bc", "tr"]
PUZZLE_LOOT = [("codehunt", "sf"), ("mtchill", "fc"), ("ranch", "bc")]
# core/world/supply-crate.pwn DefineSupplyDropPos("Name", x, y, z) and weapons-cache.pwn DefineWeaponsCachePos(x, y, z)
SUPPLY_RE = re.compile(r"^\s*DefineSupplyDropPos\s*\(\s*\"([^\"]+)\"\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*("
                       + NUM + r")\s*\)\s*;")
CACHE_RE = re.compile(r"^\s*DefineWeaponsCachePos\s*\(\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*\)\s*;")


def parse_zone(src: str, zone: str) -> list[dict]:
    rows = []
    src = BLOCK_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), src)
    for line in src.split("\n"):
        if not CALL_RE.search(line) or line.lstrip().startswith("//"):
            continue
        inner = line[line.index("(") + 1:line.rindex(")")]
        m = ARGS_RE.match(inner)
        if not m:
            raise UnparsedLine(line.strip())
        rows.append({"x": float(m.group(1)), "y": float(m.group(2)), "z": float(m.group(3)), "table": m.group(4),
                     "weight": float(m.group(5)), "size": int(m.group(6)) if m.group(6) else -1, "zone": zone,
                     "dimension": int(m.group(7) or 0), "interior": int(m.group(8) or 0)})
    return rows


def parse_drop_points(src: str, zone: str) -> tuple[list[dict], list[dict]]:
    """Supply-drop and weapons-cache positions of one zone file (upstream: 36 and 186 in total, caches all in sf)."""
    supply, caches = [], []
    src = BLOCK_COMMENT_RE.sub(lambda m: "\n" * m.group(0).count("\n"), src)
    for line in src.split("\n"):
        if line.lstrip().startswith("//"):
            continue
        if "DefineSupplyDropPos" in line:
            m = SUPPLY_RE.match(line)
            if not m:
                raise UnparsedLine(line.strip())
            supply.append({"name": m.group(1), "x": float(m.group(2)), "y": float(m.group(3)), "z": float(m.group(4)),
                           "zone": zone})
        elif "DefineWeaponsCachePos" in line:
            m = CACHE_RE.match(line)
            if not m:
                raise UnparsedLine(line.strip())
            caches.append({"x": float(m.group(1)), "y": float(m.group(2)), "z": float(m.group(3)), "zone": zone})
    return supply, caches


def render_drop_points_sql(supply: list[dict], caches: list[dict]) -> str:
    supply = sorted(supply, key=lambda r: (r["zone"], r["x"], r["y"], r["z"]))
    caches = sorted(caches, key=lambda r: (r["zone"], r["x"], r["y"], r["z"]))
    out = [SEED_HEADER, "DELETE FROM supply_drop_points;", "DELETE FROM weapon_cache_points;"]
    if supply:
        vals = [f"('{r['name'].replace(chr(39), chr(39) * 2)}',{r['x']!r},{r['y']!r},{r['z']!r},'{r['zone']}')"
                for r in supply]
        out.append("INSERT INTO supply_drop_points (name,x,y,z,zone) VALUES\n" + ",\n".join(vals) + ";\n")
    if caches:
        vals = [f"({r['x']!r},{r['y']!r},{r['z']!r},'{r['zone']}')" for r in caches]
        out.append("INSERT INTO weapon_cache_points (x,y,z,zone) VALUES\n" + ",\n".join(vals) + ";\n")
    return "\n".join(out)


def render_sql(rows: list[dict]) -> str:
    rows = sorted(rows, key=lambda r: (r["zone"], r["x"], r["y"], r["z"], r["table"], r["weight"], r["size"]))
    vals = [f"({r['x']!r},{r['y']!r},{r['z']!r},'{r['table']}',{r['weight']!r},{r['size']},{r['interior']},"
            f"{r['dimension']},'{r['zone']}',POINT({r['x']!r}, {r['y']!r}))" for r in rows]
    out = [SEED_HEADER, "DELETE FROM loot_spawn_state;", "DELETE FROM loot_spawns;", "ALTER TABLE loot_spawns AUTO_INCREMENT = 1;"]
    for i in range(0, len(vals), 500):
        out.append("INSERT INTO loot_spawns (x,y,z,table_name,weight,size,interior,dimension,zone,pos) VALUES\n"
                   + ",\n".join(vals[i:i + 500]) + ";\n")
    out.append("INSERT INTO loot_spawn_state (spawn_id, next_roll_at) SELECT id, NOW() FROM loot_spawns;\n")
    return "\n".join(out)


def convert(src_root, out_seed) -> list[dict]:
    rows, supply, caches = [], [], []
    for zone in ZONES:
        src = read_text(Path(src_root) / f"gamemodes/sss/world/zones/{zone}.pwn")
        rows += parse_zone(src, zone)
        s, c = parse_drop_points(src, zone)
        supply += s
        caches += c
    # the puzzles' own loot: the code hunt's SF lockup (codehunt.pwn LoadLockup_SF, 4 world_survivor spots)
    for puzzle, zone in PUZZLE_LOOT:
        rows += parse_zone(read_text(Path(src_root) / f"gamemodes/sss/world/puzzles/{puzzle}.pwn"), zone)
    write_text(Path(out_seed) / "0002_loot_spawns.sql", render_sql(rows))
    write_text(Path(out_seed) / "0005_drop_points.sql", render_drop_points_sql(supply, caches))
    return rows
