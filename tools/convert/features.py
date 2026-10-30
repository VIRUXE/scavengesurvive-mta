"""Ladders, ziplines and fixed items (upstream gamemodes/sss/world/zones/*.pwn: CreateLadder(x, y, z, height, angle),
the multi-line CreateZipline(x1, y1, z1, x2, y2, z2) and CreateItem(item_X, x, y, z[, rx, ry, rz])) ->
resources/[scavengesurvive]/world/data/features.lua. Ladder and zipline mechanics come from Southclaws/samp-ladders and
samp-zipline (sampctl dependencies, not in the checkout); the fixed items are the workbenches, the scrapyard's machines
and a barbecue, which upstream creates on every start."""
from __future__ import annotations

import re
from pathlib import Path

from .common import HEADER, NUM, UnparsedLine, read_text, write_text

ZONES = ["ls", "sf", "lv", "rc", "fc", "bc", "tr"]
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//[^\n]*")
LADDER_RE = re.compile(r"CreateLadder\s*\(\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM
                       + r")\s*,\s*(" + NUM + r")\s*\)")
ZIPLINE_RE = re.compile(r"CreateZipline\s*\(\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM
                        + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*\)")
ANY_RE = re.compile(r"Create(Ladder|Zipline)\s*\(")
ITEM_RE = re.compile(r"CreateItem\s*\(\s*(?:item_(\w+)|ItemType:(\d+))\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM
                     + r")((?:\s*,\s*" + NUM + r")*)\s*\)")
ANY_ITEM_RE = re.compile(r"CreateItem\s*\(")


def parse_features(src: str, zone: str) -> tuple[list[dict], list[dict]]:
    """Every CreateLadder / CreateZipline call in one zone file (calls may span lines)."""
    text = LINE_COMMENT_RE.sub("", BLOCK_COMMENT_RE.sub("", src))
    ladders = [{"x": float(m[0]), "y": float(m[1]), "base": float(m[2]), "top": float(m[3]), "angle": float(m[4]),
                "zone": zone} for m in LADDER_RE.findall(text)]
    ziplines = [{"x1": float(m[0]), "y1": float(m[1]), "z1": float(m[2]), "x2": float(m[3]), "y2": float(m[4]),
                 "z2": float(m[5]), "zone": zone} for m in ZIPLINE_RE.findall(text)]
    if len(ANY_RE.findall(text)) != len(ladders) + len(ziplines):
        raise UnparsedLine(f"{zone}: a CreateLadder/CreateZipline call did not match the expected arguments")
    return ladders, ziplines


def parse_fixtures(src: str, zone: str, unames: list[str] = ()) -> list[dict]:
    """Every CreateItem(item_X, x, y, z[, rx, ry, rz]) in one zone file; only the heading is kept (the port's items
    carry rz alone). A bare ItemType:N (one in LV) is upstream's Nth DefineItemType, looked up in `unames`. The SF barbecue passes a single 171.0 after z, which lands in rx upstream and tips it over: it is
    taken as the heading it was meant to be."""
    text = LINE_COMMENT_RE.sub("", BLOCK_COMMENT_RE.sub("", src))
    rows = []
    for m in ITEM_RE.finditer(text):
        rot = [float(v) for v in re.findall(NUM, m.group(6))]
        rz = rot[2] if len(rot) >= 3 else (rot[0] if len(rot) == 1 else 0.0)
        uname = m.group(1) or (unames[int(m.group(2))] if int(m.group(2)) < len(unames) else None)
        if not uname:
            raise UnparsedLine(f"{zone}: CreateItem(ItemType:{m.group(2)}) is past the {len(unames)} item types")
        rows.append({"uname": uname, "x": float(m.group(3)), "y": float(m.group(4)), "z": float(m.group(5)),
                     "rz": rz, "zone": zone})
    if len(ANY_ITEM_RE.findall(text)) != len(rows):
        raise UnparsedLine(f"{zone}: a CreateItem call did not match the expected arguments")
    return rows


def render_lua(ladders: list[dict], ziplines: list[dict], fixtures: list[dict] = ()) -> str:
    ladders = sorted(ladders, key=lambda r: (r["zone"], r["x"], r["y"]))
    ziplines = sorted(ziplines, key=lambda r: (r["zone"], r["x1"], r["y1"]))
    out = [HEADER, "-- Upstream: CreateLadder(x, y, base z, top z, facing angle) and CreateZipline(start xyz, end xyz).",
           "return {", "    -- { x, y, base, top, angle, zone }", "    ladders = {"]
    out += [f"        {{ {r['x']!r}, {r['y']!r}, {r['base']!r}, {r['top']!r}, {r['angle']!r}, \"{r['zone']}\" }},"
            for r in ladders]
    out += ["    },", "    -- { x1, y1, z1, x2, y2, z2, zone }", "    ziplines = {"]
    out += [f"        {{ {r['x1']!r}, {r['y1']!r}, {r['z1']!r}, {r['x2']!r}, {r['y2']!r}, {r['z2']!r}, \"{r['zone']}\" }},"
            for r in ziplines]
    out += ["    },", "    -- { uname, x, y, z, rz, zone }: put back in the world by the world resource when missing",
            "    fixtures = {"]
    out += [f"        {{ \"{r['uname']}\", {r['x']!r}, {r['y']!r}, {r['z']!r}, {r['rz']!r}, \"{r['zone']}\" }},"
            for r in sorted(fixtures, key=lambda r: (r["zone"], r["uname"], r["x"], r["y"]))]
    out += ["    },", "}", ""]
    return "\n".join(out)


def convert(src_root, out_resource, unames: list[str] = ()) -> tuple[int, int, int]:
    ladders, ziplines, fixtures = [], [], []
    for zone in ZONES:
        src = read_text(Path(src_root) / f"gamemodes/sss/world/zones/{zone}.pwn")
        l, z = parse_features(src, zone)
        ladders += l
        ziplines += z
        fixtures += parse_fixtures(src, zone, unames)
    write_text(Path(out_resource) / "data" / "features.lua", render_lua(ladders, ziplines, fixtures))
    return len(ladders), len(ziplines), len(fixtures)
