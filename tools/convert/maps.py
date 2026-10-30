"""Upstream `scriptfiles/maps/**/*.map` -> `resources/[scavengesurvive]/maps/data/<ZONE>.lua` + a census report.

Grammar (upstream world/objects.pwn): a line whose first character is below 'A' is skipped (digits, blanks,
`;`/`//` comments, the legacy `world, interior, range` headers). Otherwise the line is split as `name(args)` and
only the FIRST call on the line counts - a second statement glued on the same line was never created upstream, so
it is dropped here too and counted. `Create*` = `model,x,y,z,rx,ry,rz[,world=-1][,interior=-1][,playerid][,range]`;
`options(world,interior,range)` changes the file defaults for the lines after it; `RemoveBuildingForPlayer(_,
model,x,y,z,radius)` is a world-model removal; `SetObjectMaterial`/`SetObjectMaterialText` apply to the previous
object. The 8-argument `CreateDynamicObject(..., 7.0)` form was mis-read upstream (the draw distance became the
virtual world, hiding the object); here it is the draw distance the author meant. Materials are kept as data but
MTA has no per-object material replacement, so the loader ignores them.
"""
from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path

from .common import NUM, UnparsedLine, lua_value, read_text, write_text
from .. import gen_vanilla_objects

MAPS_HEADER = ("-- Derived from Southclaws/ScavengeSurvive scriptfiles/maps (CC BY-SA 4.0). See THIRD_PARTY_NOTICES.md\n"
               "-- GENERATED FILE - do not edit; run: python -m tools.convert maps\n")
ZONES_HEADER = ("-- Derived from Southclaws/ScavengeSurvive pyss/data/regions.json (MPL-2.0). See THIRD_PARTY_NOTICES.md\n"
                "-- GENERATED FILE - do not edit; run: python -m tools.convert maps\n")
ZONE_NAMES = ("ls", "sf", "lv", "rc", "fc", "bc", "tr")
CALL_RE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)(.*)$", re.S)
NUM_RE = re.compile(r"^" + NUM + r"$")
SAMP_IDE = Path(__file__).resolve().parents[1] / "data" / "samp.ide"
DEFAULT_RANGE = 350.0
BUILDING_LIMIT = 3000.0  # MTA createBuilding rejects |x| or |y| beyond this


def is_samp_model(model: int) -> bool:
    return model >= 18631 or 11682 <= model <= 11753


def load_samp_ids(path: Path = SAMP_IDE) -> set[int]:
    ids = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        head = line.split(",", 1)[0].strip()
        if head.isdigit():
            ids.add(int(head))
    return ids


def num(token: str):
    token = token.strip()
    if not NUM_RE.match(token):
        raise ValueError(token)
    return float(token) if "." in token else int(token)


def split_args(args: str) -> list[str]:
    return [a.strip() for a in args.split(",")]


def parse_map(text: str, name: str) -> dict:
    """One .map file -> {objects, removals, materials, counts}. Objects are 10-field lists
    [model, x, y, z, rx, ry, rz, world, interior, range]; removals [model, x, y, z, radius]."""
    world, interior, rng = -1, -1, DEFAULT_RANGE
    objects, removals, materials = [], [], []
    counts = Counter()
    for raw in text.split("\n"):
        line = raw.strip()
        if not raw or raw[0] < "A":
            if line and not line.startswith("//") and not line.startswith(";"):
                counts["legacy_header"] += 1
            continue
        m = CALL_RE.match(line)
        if not m:
            counts["unparsed"] += 1
            continue
        fn, args, tail = m.group(1), m.group(2), m.group(3).strip()
        if tail.startswith(";"):
            tail = tail[1:].strip()
        if tail and not tail.startswith("//"):
            counts["dropped_tail"] += 1  # a second statement on the line: upstream never saw it either
        if fn == "options":
            a = split_args(args)
            world, interior, rng = int(a[0]), int(a[1]), float(a[2])
            counts["options"] += 1
        elif fn.startswith("Create"):
            a = split_args(args)
            if len(a) < 7:
                raise UnparsedLine(f"{name}: {line}")
            model = int(num(a[0]))
            vals = [num(v) for v in a[1:7]]
            w, i, r = world, interior, rng
            if len(a) == 8:
                r = float(num(a[7]))  # author's draw distance (upstream mis-read it as the world)
                counts["eight_arg"] += 1
            elif len(a) >= 9:
                w, i = int(num(a[7])), int(num(a[8]))
                if len(a) >= 11:
                    r = float(num(a[10]))
                if w == -1:
                    w = world
                if i == -1:
                    i = interior
            objects.append([model, *vals, w, i, r])
            counts["objects"] += 1
        elif fn == "RemoveBuildingForPlayer":
            a = split_args(args)
            if len(a) < 6:
                raise UnparsedLine(f"{name}: {line}")
            removals.append([int(num(a[1])), *(num(v) for v in a[2:6])])
            counts["removals"] += 1
        elif fn in ("SetObjectMaterial", "SetObjectMaterialText"):
            if objects:
                materials.append({"object": len(objects), "call": fn, "args": args.strip()})
            counts["materials"] += 1
        elif fn in ("SetDynamicObjectMaterial", "objmat", "objtxt", "SetDynamicObjectMaterialText"):
            counts["ignored_calls"] += 1  # upstream ignores these too (no object id / unknown name)
        else:
            raise UnparsedLine(f"{name}: {line}")
    return {"objects": objects, "removals": removals, "materials": materials, "counts": counts}


def map_files(src_root) -> list[Path]:
    root = Path(src_root) / "scriptfiles" / "maps"
    return sorted(p for p in root.rglob("*.map") if "_" not in {d.name for d in p.relative_to(root).parents})


def zone_of(path: Path, root: Path) -> str:
    return path.relative_to(root).parts[0]


def render_zone_lua(zone: str, files: list[str], objects: list, removals: list, materials: list) -> str:
    out = [MAPS_HEADER, "return {", f"    zone = {lua_value(zone)},", f"    files = {lua_value(files)},",
           "    -- { model, x, y, z, rx, ry, rz, world, interior, range }  (world/interior -1 = any; upstream defaults)",
           "    objects = {"]
    out += [f"        {lua_value(o)}," for o in objects]
    out += ["    },", "    -- { model, x, y, z, radius }", "    removals = {"]
    out += [f"        {lua_value(r)}," for r in removals]
    out += ["    },", "    -- upstream SetObjectMaterial(Text) on objects[object]; MTA has no equivalent, kept for the record",
            "    materials = {"]
    out += [f"        {lua_value(m)}," for m in materials]
    out += ["    },", "}", ""]
    return "\n".join(out)


def signed_area(pts: list[list[float]]) -> float:
    n = len(pts)
    return 0.5 * sum(pts[i][0] * pts[(i + 1) % n][1] - pts[(i + 1) % n][0] * pts[i][1] for i in range(n))


def parse_regions(text: str) -> dict[str, list[list[float]]]:
    """Top-level zone polygons from pyss/data/regions.json -> {zone_lower: [[x, y], ...]}
    with duplicate closing vertex stripped and vertices wound counter-clockwise for createColPolygon."""
    raw = json.loads(text)
    out: dict[str, list[list[float]]] = {}
    for name in ZONE_NAMES:
        pts = raw.get(name.upper()) or raw.get(name)
        if not pts:
            continue
        norm = [[float(p[0]), float(p[1])] for p in pts]
        if len(norm) > 1 and norm[0] == norm[-1]:
            norm = norm[:-1]
        if len(norm) >= 3 and signed_area(norm) < 0:
            norm = list(reversed(norm))
        out[name] = norm
    return out


def render_zones_lua(zone_polys: dict[str, list[list[float]]]) -> str:
    out = [ZONES_HEADER, "return {"]
    for zone in sorted(zone_polys):
        out.append(f"    {zone} = {lua_value(zone_polys[zone])},")
    out += ["}", ""]
    return "\n".join(out)


def render_meta(zones: list[str]) -> str:
    lines = ['<meta>',
             '    <info author="scavengesurvive-mta" type="script" name="maps" description="Upstream static maps built client-side (createBuilding) and server zone colshapes" version="0.1.0"/>',
             '    <min_mta_version server="1.6.0" client="1.6.0-9.22410"/>',  # createBuilding
             '    <download_priority_group>85</download_priority_group>',
             '    <include resource="lib"/>',
             '    <include resource="models"/>',
             '    <script src="shared/events.lua" type="shared"/>',
             '    <script src="server/main.lua" type="server"/>',
             '    <script src="client/main.lua" type="client"/>',
             '    <file src="shared/logic/placement.lua"/>',
             '    <file src="shared/logic/zones.lua"/>',
             '    <file src="shared/glazed_windows.lua"/>',  # tools/glaze_house_windows.py
             '    <file src="shared/shell_doors.lua"/>',  # tools/fit_house_doors.py
             '    <file src="data/zones.lua"/>',
             '    <file src="data/index.lua"/>']
    lines += [f'    <file src="data/{z}.lua"/>' for z in zones]
    lines += ['    <export function="getZoneAt" type="server"/>',
              '    <export function="getPlayerZone" type="server"/>',
              '    <export function="getMapStats" type="client"/>',
              '</meta>', '']
    return "\n".join(lines)


def classify(model: int, vanilla: set[int], samp: set[int]) -> str:
    if model in vanilla:
        return "vanilla"
    if is_samp_model(model):
        return "samp" if model in samp else "samp_unknown"
    return "unknown"


def render_census(zones: dict, vanilla: set[int], samp: set[int]) -> str:
    total = Counter()
    rows = []
    samp_use: Counter = Counter()
    unknown_use: Counter = Counter()
    worlds: Counter = Counter()
    far = 0
    for zone in sorted(zones):
        z = zones[zone]
        c = Counter()
        for o in z["objects"]:
            kind = classify(o[0], vanilla, samp)
            c[kind] += 1
            if kind.startswith("samp"):
                samp_use[o[0]] += 1
            elif kind == "unknown":
                unknown_use[o[0]] += 1
            worlds[(o[7], o[8])] += 1
            if abs(o[1]) > BUILDING_LIMIT or abs(o[2]) > BUILDING_LIMIT:
                far += 1
        c["removals"] = len(z["removals"])
        c["files"] = len(z["files"])
        c["objects"] = len(z["objects"])
        for k, v in z["counts"].items():
            c[k] = v
        total.update(c)
        rows.append((zone, c))
    cols = ["files", "objects", "vanilla", "samp", "samp_unknown", "unknown", "removals", "materials",
            "dropped_tail", "eight_arg", "legacy_header", "ignored_calls"]
    out = ["# Upstream map census", "",
           "Generated by `python -m tools.convert maps` from `scriptfiles/maps/**/*.map` (CC BY-SA 4.0). Do not edit.", "",
           "Columns: `samp` = SA-MP-only model present in `tools/data/samp.ide`; `samp_unknown` = in the SA-MP id range "
           "but not in samp.ide; `unknown` = neither vanilla (`tools/data/vanilla_objects.txt`) nor SA-MP; "
           "`dropped_tail` = a second statement glued on a line (upstream parsed only the first call); `eight_arg` = "
           "`CreateDynamicObject(..., dist)` (upstream mis-read the distance as the world); `legacy_header` = "
           "`world, interior, range` lines upstream skips; `ignored_calls` = material lines upstream ignores.", "",
           "| zone | " + " | ".join(cols) + " |", "| --- | " + " | ".join("---:" for _ in cols) + " |"]
    for zone, c in rows:
        out.append(f"| {zone} | " + " | ".join(str(c.get(k, 0)) for k in cols) + " |")
    out.append("| **all** | " + " | ".join(str(total.get(k, 0)) for k in cols) + " |")
    out += ["", f"Objects beyond MTA's createBuilding limit (|x| or |y| > {BUILDING_LIMIT:g}, must be createObject): {far}", "",
            "## (world, interior) combinations", "", "| world | interior | objects |", "| ---: | ---: | ---: |"]
    for (w, i), n in sorted(worlds.items()):
        out.append(f"| {w} | {i} | {n} |")
    out += ["", f"## SA-MP-only models used by maps ({len(samp_use)} distinct, {sum(samp_use.values())} placements)", "",
            "| model | placements | in samp.ide |", "| ---: | ---: | --- |"]
    for model, n in sorted(samp_use.items()):
        out.append(f"| {model} | {n} | {'yes' if model in samp else 'no'} |")
    if unknown_use:
        out += ["", f"## Unknown models ({len(unknown_use)} distinct)", "", "| model | placements |", "| ---: | ---: |"]
        out += [f"| {m} | {n} |" for m, n in sorted(unknown_use.items())]
    out.append("")
    return "\n".join(out)


def convert(src_root, out_resource, out_report=None) -> dict:
    root = Path(src_root) / "scriptfiles" / "maps"
    zones: dict[str, dict] = {}
    for path in map_files(src_root):
        zone = zone_of(path, root)
        z = zones.setdefault(zone, {"files": [], "objects": [], "removals": [], "materials": [], "counts": Counter()})
        parsed = parse_map(read_text(path), path.relative_to(root).as_posix())
        offset = len(z["objects"])
        z["files"].append(path.relative_to(root).as_posix())
        z["objects"] += parsed["objects"]
        z["removals"] += parsed["removals"]
        z["materials"] += [{**m, "object": m["object"] + offset} for m in parsed["materials"]]
        z["counts"].update(parsed["counts"])
    out_resource = Path(out_resource)
    for zone in sorted(zones):
        z = zones[zone]
        write_text(out_resource / "data" / f"{zone}.lua",
                   render_zone_lua(zone, z["files"], z["objects"], z["removals"], z["materials"]))
    index = {zone: {"objects": len(zones[zone]["objects"]), "removals": len(zones[zone]["removals"])}
             for zone in sorted(zones)}
    regions_path = Path(src_root) / "pyss" / "data" / "regions.json"
    zone_polys = parse_regions(read_text(regions_path)) if regions_path.is_file() else {}
    write_text(out_resource / "data" / "zones.lua", render_zones_lua(zone_polys))
    write_text(out_resource / "data" / "index.lua", MAPS_HEADER + "return " + lua_value(index) + "\n")
    write_text(out_resource / "meta.xml", render_meta(sorted(zones)))
    if out_report:
        write_text(Path(out_report), render_census(zones, gen_vanilla_objects.load(), load_samp_ids()))
    return zones
