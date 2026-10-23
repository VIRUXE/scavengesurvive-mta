"""Ladders and ziplines (upstream gamemodes/sss/world/zones/*.pwn: CreateLadder(x, y, z, height, angle) and the
multi-line CreateZipline(x1, y1, z1, x2, y2, z2)) -> resources/[scavengesurvive]/world/data/features.lua.
Mechanics come from Southclaws/samp-ladders and samp-zipline (sampctl dependencies, not in the checkout)."""
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


def render_lua(ladders: list[dict], ziplines: list[dict]) -> str:
    ladders = sorted(ladders, key=lambda r: (r["zone"], r["x"], r["y"]))
    ziplines = sorted(ziplines, key=lambda r: (r["zone"], r["x1"], r["y1"]))
    out = [HEADER, "-- Upstream: CreateLadder(x, y, base z, top z, facing angle) and CreateZipline(start xyz, end xyz).",
           "return {", "    -- { x, y, base, top, angle, zone }", "    ladders = {"]
    out += [f"        {{ {r['x']!r}, {r['y']!r}, {r['base']!r}, {r['top']!r}, {r['angle']!r}, \"{r['zone']}\" }},"
            for r in ladders]
    out += ["    },", "    -- { x1, y1, z1, x2, y2, z2, zone }", "    ziplines = {"]
    out += [f"        {{ {r['x1']!r}, {r['y1']!r}, {r['z1']!r}, {r['x2']!r}, {r['y2']!r}, {r['z2']!r}, \"{r['zone']}\" }},"
            for r in ziplines]
    out += ["    },", "}", ""]
    return "\n".join(out)


def convert(src_root, out_resource) -> tuple[int, int]:
    ladders, ziplines = [], []
    for zone in ZONES:
        l, z = parse_features(read_text(Path(src_root) / f"gamemodes/sss/world/zones/{zone}.pwn"), zone)
        ladders += l
        ziplines += z
    write_text(Path(out_resource) / "data" / "features.lua", render_lua(ladders, ziplines))
    return len(ladders), len(ziplines)
