"""Vehicle types (`DefineVehicleType` / `SetVehicleTypeTrailerHitch` in core/server/init.pwn) -> data/generated/
vehicle_types.lua, and vehicle spawn lists (`scriptfiles/vspawn/*.vpl`, CRLF) -> sql/seed/0004_vehicle_spawns.sql.

.vpl grammar (upstream core/vehicle/spawn.pwn): `Defaults(Group, CategoryLetters, SizeLetters)` sets the file
defaults; `Vehicle(x, y, z, rz[, Group|TypeName[, Categories|_[, Sizes|_]]])` is one spawn point. When the 5th
argument is not a group name it is an explicit vehicle type (then categories/sizes are ignored); an unknown type
is dropped, as upstream does after logging. Letters: categories C car, T truck, M motorbike, B pushbike,
H helicopter, P plane, S boat, L train; sizes S/M/L. rz may exceed 360 and upstream adds 180 at random when it
spawns; both stay runtime concerns. The 4 % per-spawn chance is the setting `vehicles.spawn_chance`.
"""
from __future__ import annotations

import re
from pathlib import Path

from .common import HEADER, SEED_HEADER, UnparsedLine, lua_index, lua_value, read_text, sql_str, write_text
from .item_types import coerce, split_args

GROUPS = ["Civilian", "Industrial", "Medical", "Police", "Military", "Unique"]
CATEGORY_LETTERS = {"C": "car", "T": "truck", "M": "motorbike", "B": "pushbike", "H": "helicopter", "P": "plane",
                    "S": "boat", "L": "train"}
SIZE_LETTERS = {"S": "small", "M": "medium", "L": "large"}
CATEGORY_CONST = {f"VEHICLE_CATEGORY_{k.upper()}": k for k in CATEGORY_LETTERS.values()}
SIZE_CONST = {f"VEHICLE_SIZE_{k.upper()}": k for k in SIZE_LETTERS.values()}
# vehicle-type.pwn enum (<<= 1)
FLAGS = {"VEHICLE_FLAG_NOT_LOCKABLE": 1, "VEHICLE_FLAG_NO_ENGINE": 2, "VEHICLE_FLAG_TRAILER": 4,
         "VEHICLE_FLAG_CAN_SURF": 8}
FLAG_KEYS = {1: "notLockable", 2: "noEngine", 4: "trailer", 8: "canSurf"}

# Port-only vehicle types, after upstream's. The towable Airstream (house_shell, tools/trailer_shells/towable.py) is
# the medium Airstream shell on model 610: a small trailer any small hitch takes, rolled rarely at civilian truck
# points, with no trunk (it is lived in); `handling` is what the vehicles resource sets on the model, `door` marks
# a walk-in door (its front-left vehicle door) the interact key opens and shuts.
PORT_TYPES = [
    {"uname": "Airstream", "model": 610, "name": "Airstream", "group": "Civilian", "category": "truck",
     "size": "small", "maxFuel": 0.0, "fuelConsumption": 0.0, "lootTable": "", "trunkSize": 0, "spawnChance": 3.0,
     "flags": FLAGS["VEHICLE_FLAG_TRAILER"], "door": True,
     "handling": {"mass": 1600.0, "turnMass": 4000.0, "centerOfMass": [0.0, 0.4, -0.3], "suspensionLowerLimit": -0.04,
                  "suspensionUpperLimit": 0.12, "suspensionForceLevel": 2.4, "suspensionDamping": 0.15}},
]

TYPE_RE = re.compile(r"(veht_\w+)\s*=\s*DefineVehicleType\((.*?)\);", re.S)
HITCH_RE = re.compile(r"SetVehicleTypeTrailerHitch\((veht_\w+)\s*,\s*(VEHICLE_SIZE_\w+)\s*\);")
CALL_RE = re.compile(r"^([A-Za-z_]\w*)\s*\((.*)\)\s*;?\s*$")


def parse_flags(text: str) -> int:
    flags = 0
    for part in text.split("|"):
        part = part.strip()
        if part:
            flags |= FLAGS[part]
    return flags


def parse_vehicle_types(init_text: str) -> list[dict]:
    """DefineVehicleType rows in file order; uname = the Pawn variable without `veht_` (names repeat: 3 Police Cars)."""
    types = []
    for var, args in TYPE_RE.findall(init_text):
        a = split_args(args)
        if len(a) < 10:
            raise UnparsedLine(f"{var}: {args.strip()}")
        t = {
            "uname": var[len("veht_"):],
            "model": int(coerce(a[0])),
            "name": coerce(a[1]),
            "group": a[2].strip()[len("vgroup_"):],
            "category": CATEGORY_CONST[a[3].strip()],
            "size": SIZE_CONST[a[4].strip()],
            "maxFuel": float(coerce(a[5])),
            "fuelConsumption": float(coerce(a[6])),
            "lootTable": coerce(a[7]),
            "trunkSize": int(coerce(a[8])),
            "spawnChance": float(coerce(a[9])),
            "flags": parse_flags(a[10]) if len(a) > 10 else 0,
        }
        if t["group"] not in GROUPS:
            raise UnparsedLine(f"{var}: unknown group {t['group']}")
        for bit, key in FLAG_KEYS.items():
            t[key] = bool(t["flags"] & bit)
        types.append(t)
    by_var = {"veht_" + t["uname"]: t for t in types}
    for var, size in HITCH_RE.findall(init_text):
        by_var[var]["trailerHitch"] = SIZE_CONST[size]
    return types


def letters(text: str, table: dict, what: str, where: str) -> str:
    for ch in text:
        if ch not in table:
            raise UnparsedLine(f"{where}: invalid {what} letter {ch!r} in {text!r}")
    return text


def parse_vpl(text: str, filename: str, type_names: dict[str, str]) -> tuple[list[dict], list[str]]:
    """Spawn rows of one .vpl; type_names maps lower-case display name -> uname. Returns (rows, dropped lines)."""
    rows, dropped = [], []
    default = {"group": None, "categories": "", "sizes": ""}
    for n, raw in enumerate(text.split("\n"), 1):
        line = raw.strip()
        if not line or line.startswith(";") or line.startswith("//"):
            continue  # upstream's sscanf yields a function name like "; Vehicle", which matches nothing
        m = CALL_RE.match(line)
        if not m:
            raise UnparsedLine(f"{filename}:{n}: {line}")
        fn, a = m.group(1), [x.strip() for x in m.group(2).split(",")]
        where = f"{filename}:{n}"
        if fn == "Defaults":
            if len(a) != 3 or a[0] not in GROUPS:
                raise UnparsedLine(f"{where}: {line}")
            default = {"group": a[0], "categories": letters(a[1], CATEGORY_LETTERS, "category", where),
                       "sizes": letters(a[2], SIZE_LETTERS, "size", where)}
        elif fn == "Vehicle":
            if len(a) < 4 or len(a) > 7:
                raise UnparsedLine(f"{where}: {line}")
            row = {"x": float(a[0]), "y": float(a[1]), "z": float(a[2]), "rz": float(a[3]), "group": None,
                   "type": None, "categories": "", "sizes": "", "file": filename}
            who = a[4] if len(a) > 4 and a[4] else None
            if who is None:
                if default["group"] is None:
                    raise UnparsedLine(f"{where}: no group and no Defaults")
                row["group"] = default["group"]
            elif who in GROUPS:
                row["group"] = who
            else:
                uname = type_names.get(who.lower())
                if uname is None:
                    dropped.append(f"{where}: unknown vehicle type {who!r}")
                    continue
                row["type"] = uname
            if row["group"]:
                cats = a[5] if len(a) > 5 and a[5] not in ("", "_") else default["categories"]
                sizes = a[6] if len(a) > 6 and a[6] not in ("", "_") else default["sizes"]
                if not cats or not sizes:
                    raise UnparsedLine(f"{where}: empty categories/sizes and no Defaults")
                row["categories"] = letters(cats, CATEGORY_LETTERS, "category", where)
                row["sizes"] = letters(sizes, SIZE_LETTERS, "size", where)
            rows.append(row)
        else:
            raise UnparsedLine(f"{where}: {line}")
    return rows, dropped


def render_types_lua(types: list[dict]) -> str:
    by_name = {}
    for t in types:
        by_name.setdefault(t["name"].lower(), t["uname"])  # first definition wins (upstream GetVehicleTypeFromName)
    body = ["local M = {}", f"M.order = {lua_value([t['uname'] for t in types])}", "M.byUname = {}"]
    body += [f"M.byUname{lua_index(t['uname'])} = {lua_value(t)}" for t in types]
    body += [f"M.unameByName = {lua_value(by_name)}", f"M.groups = {lua_value(GROUPS)}",
             f"M.categoryLetters = {lua_value(CATEGORY_LETTERS)}", f"M.sizeLetters = {lua_value(SIZE_LETTERS)}"]
    return HEADER + "\n".join(body) + "\nreturn M\n"


def render_sql(rows: list[dict]) -> str:
    rows = sorted(rows, key=lambda r: (r["file"], r["x"], r["y"], r["z"], r["rz"]))
    vals = [f"({r['x']!r},{r['y']!r},{r['z']!r},{r['rz']!r},{sql_str(r['group']) if r['group'] else 'NULL'},"
            f"{sql_str(r['type']) if r['type'] else 'NULL'},{sql_str(r['categories'])},{sql_str(r['sizes'])},"
            f"{sql_str(r['file'])},POINT({r['x']!r}, {r['y']!r}))" for r in rows]
    out = [SEED_HEADER, "DELETE FROM vehicle_spawns;", "ALTER TABLE vehicle_spawns AUTO_INCREMENT = 1;"]
    for i in range(0, len(vals), 500):
        out.append("INSERT INTO vehicle_spawns (x,y,z,rz,group_name,type_name,categories,sizes,file,pos) VALUES\n"
                   + ",\n".join(vals[i:i + 500]) + ";\n")
    return "\n".join(out)


def convert(src_root, out_data, out_seed) -> tuple[list[dict], list[dict], list[str]]:
    src = Path(src_root)
    types = parse_vehicle_types(read_text(src / "gamemodes/sss/core/server/init.pwn"))
    for port in PORT_TYPES:
        t = dict(port)
        for bit, key in FLAG_KEYS.items():
            t[key] = bool(t["flags"] & bit)
        types.append(t)
    type_names = {}
    for t in types:
        type_names.setdefault(t["name"].lower(), t["uname"])
    rows, dropped = [], []
    for p in sorted((src / "scriptfiles/vspawn").glob("*.vpl")):
        r, d = parse_vpl(read_text(p), p.name, type_names)
        rows += r
        dropped += d
    write_text(Path(out_data) / "vehicle_types.lua", render_types_lua(types))
    write_text(Path(out_seed) / "0004_vehicle_spawns.sql", render_sql(rows))
    return types, rows, dropped
