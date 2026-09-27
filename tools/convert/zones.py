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
    rows = []
    for zone in ZONES:
        rows += parse_zone(read_text(Path(src_root) / f"gamemodes/sss/world/zones/{zone}.pwn"), zone)
    write_text(Path(out_seed) / "0002_loot_spawns.sql", render_sql(rows))
    return rows
