from __future__ import annotations

import re
from pathlib import Path

from .common import HEADER, NUM, lua_index, lua_value, write_text

HEADER_RE = re.compile(r"^\s*([A-Za-z0-9_]+)\s*,\s*(" + NUM + r")?\s*$")
LINE_RE = re.compile(r"^\s*(" + NUM + r")\s*,\s*([A-Za-z0-9_]+)(?:\s*,\s*(\d+))?(?:\s*,\s*(\d+))?\s*$")


def parse_ltb(raw: bytes) -> tuple[str, dict]:
    lines = raw.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n").split("\n")
    m = HEADER_RE.match(lines[0])
    if not m:
        raise ValueError("bad ltb header: " + lines[0])
    entries = []
    for line in lines[1:]:
        lm = LINE_RE.match(line)
        if not lm:
            continue  # comments and blank lines; upstream sscanf skips them too
        entries.append({"weight": float(lm.group(1)), "uname": lm.group(2),
                        "perLimit": int(lm.group(3) or 3), "serverLimit": int(lm.group(4) or 0)})
    return m.group(1), {"mult": float(m.group(2) or 1.0), "entries": entries}


def canonicalise(tables: dict[str, dict], unames) -> list[tuple[str, str]]:
    """Resolve entry unames case-insensitively (upstream: GetItemTypeFromUniqueName(uname, true)) and drop the
    unknown ones, as upstream does after logging an error. Returns the dropped (table, uname) pairs."""
    by_lower = {u.lower(): u for u in unames}
    unknown = []
    for name in sorted(tables):
        kept = []
        for e in tables[name]["entries"]:
            canon = by_lower.get(e["uname"].lower())
            if canon is None:
                unknown.append((name, e["uname"]))
            else:
                kept.append({**e, "uname": canon})
        tables[name]["entries"] = kept
    return unknown


def render_lua(tables: dict[str, dict]) -> str:
    body = ["local M = {}"] + [f"M{lua_index(name)} = {lua_value(tables[name])}" for name in sorted(tables)]
    return HEADER + "\n".join(body) + "\nreturn M\n"


def convert(src_root, out_data, unames) -> dict:
    tables = {}
    for p in sorted((Path(src_root) / "scriptfiles/loot").glob("*.ltb")):
        name, table = parse_ltb(p.read_bytes())
        tables[name] = table
    for table, uname in canonicalise(tables, unames):
        print(f"loot: dropped unknown uname {uname!r} in {table} (upstream skips it too)")
    write_text(Path(out_data) / "loot_tables.lua", render_lua(tables))
    return tables
