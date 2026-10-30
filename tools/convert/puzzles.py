"""The puzzles' static objects (upstream gamemodes/sss/world/puzzles/{ranch,mtchill,codehunt}.pwn CreateDynamicObject,
with RANCH_STUFF_VIRTUALW as world 1) -> resources/[scavengesurvive]/world/data/puzzles.lua.

Most of Mt Chiliad's radio station and the SF lockup also stand in scriptfiles/maps (ChilRadio.map, SfLockup.map),
which the maps resource already builds: an object found there (same model and position) is left out. The objects the
puzzles move or write on (the cave lift, the ranch PC's screen, the radio station's keypad and its spark) are left to
world/shared/logic/puzzles.lua. The puzzle items created into a variable from plain numbers (`ch_battery =
CreateItem(item_Battery, x, y, z, rx, ry, rz)`) become fixtures tagged "<file>.<variable>", which the puzzle logic
asks for by tag; the code hunt's parts are placed from its own random spots and are left to the logic."""
from __future__ import annotations

import re
from pathlib import Path

from .common import HEADER, NUM, UnparsedLine, read_text, write_text
from .maps import DEFAULT_RANGE, map_files, parse_map

PUZZLES = ["ranch", "mtchill", "codehunt"]
WORLDS = {"RANCH_STUFF_VIRTUALW": 1}
STATEFUL = {"CaveLift", "RanchPcObj", "ch_keypad", "ch_keypadprt"}
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.S)
LINE_COMMENT_RE = re.compile(r"//[^\n]*")
OBJECT_RE = re.compile(r"(?:(\w+)\s*=\s*)?CreateDynamicObject\s*\(([^()]*)\)")
ANY_RE = re.compile(r"CreateDynamicObject\s*\(")
NUM_RE = re.compile(r"^\s*" + NUM + r"\s*$")
ITEM_RE = re.compile(r"(\w+)\s*=\s*CreateItem\s*\(\s*item_(\w+)\s*,([^()]*)\)")


def parse_objects(src: str, name: str) -> list[list]:
    """[model, x, y, z, rx, ry, rz, world, interior, range] for every CreateDynamicObject but the stateful ones."""
    text = LINE_COMMENT_RE.sub("", BLOCK_COMMENT_RE.sub("", src))
    rows, seen = [], 0
    for m in OBJECT_RE.finditer(text):
        seen += 1
        args = [a.strip() for a in m.group(2).split(",")]
        if len(args) < 7 or not all(NUM_RE.match(a) for a in args[:7]):
            raise UnparsedLine(f"{name}: CreateDynamicObject({m.group(2).strip()})")
        world = -1
        if len(args) >= 8:
            world = WORLDS.get(args[7], None) if not NUM_RE.match(args[7]) else int(float(args[7]))
            if world is None:
                raise UnparsedLine(f"{name}: unknown world {args[7]}")
        if m.group(1) in STATEFUL:
            continue
        vals = [float(a) for a in args[1:7]]
        rows.append([int(args[0]), *vals, world, -1, DEFAULT_RANGE])
    if seen != len(ANY_RE.findall(text)):
        raise UnparsedLine(f"{name}: a CreateDynamicObject call did not match")
    return rows


def parse_items(src: str, name: str) -> list[dict]:
    """Tagged fixtures: every `var = CreateItem(item_X, x, y, z[, rx, ry, rz])` whose arguments are all numbers."""
    text = LINE_COMMENT_RE.sub("", BLOCK_COMMENT_RE.sub("", src))
    rows = []
    for m in ITEM_RE.finditer(text):
        args = [a.strip() for a in m.group(3).split(",") if a.strip()]
        if not all(NUM_RE.match(a) for a in args):
            continue
        vals = [float(a) for a in args]
        rz = vals[5] if len(vals) >= 6 else 0.0
        rows.append({"uname": m.group(2), "x": vals[0], "y": vals[1], "z": vals[2], "rz": rz, "zone": name,
                     "tag": f"{name}.{m.group(1)}"})
    return rows


def map_keys(src_root) -> set[tuple]:
    """(model, x, y, z) of every object the maps resource already builds from scriptfiles/maps."""
    keys = set()
    for p in map_files(src_root):
        for o in parse_map(read_text(p), p.name)["objects"]:
            keys.add((o[0], round(o[1], 2), round(o[2], 2), round(o[3], 2)))
    return keys


def render_lua(objects: list[list], fixtures: list[dict] = ()) -> str:
    out = [HEADER, "-- Upstream world/puzzles/*.pwn objects not in scriptfiles/maps (the ranch's quarry, caves, metro)",
           "return {", "    -- { model, x, y, z, rx, ry, rz, world, interior, range }  (world/interior -1 = any)",
           "    objects = {"]
    out += ["        { " + ", ".join(repr(v) for v in o) + " }," for o in objects]
    out += ["    },", "    -- { uname, x, y, z, rz, puzzle, tag }: the puzzle items, put back by the world resource",
            "    fixtures = {"]
    for r in sorted(fixtures, key=lambda r: r["tag"]):
        vals = ", ".join(repr(r[k]) for k in ("x", "y", "z", "rz"))
        out.append(f"        {{ \"{r['uname']}\", {vals}, \"{r['zone']}\", \"{r['tag']}\" }},")
    out += ["    },", "}", ""]
    return "\n".join(out)


def convert(src_root, out_resource) -> tuple[int, int]:
    known = map_keys(src_root)
    objects, fixtures = [], []
    for name in PUZZLES:
        src = read_text(Path(src_root) / f"gamemodes/sss/world/puzzles/{name}.pwn")
        for o in parse_objects(src, name):
            if (o[0], round(o[1], 2), round(o[2], 2), round(o[3], 2)) not in known:
                objects.append(o)
        fixtures += parse_items(src, name)
    write_text(Path(out_resource) / "data" / "puzzles.lua", render_lua(objects, fixtures))
    return len(objects), len(fixtures)
