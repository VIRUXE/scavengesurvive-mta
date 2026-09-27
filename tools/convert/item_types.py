from __future__ import annotations

import json
import re

from .common import HEADER, NUM, SEED_HEADER, lua_index, lua_value, sql_str

POSITIONAL = ["name", "uname", "model", "size", "rotx", "roty", "rotz", "modelz", "attx", "atty", "attz",
              "attrx", "attry", "attrz", "usecarryanim", "colour", "boneid", "longpickup", "buttonz",
              "maxhitpoints", "price"]
DEFAULTS = dict(rotx=0.0, roty=0.0, rotz=0.0, modelz=0.0, attx=0.0, atty=0.0, attz=0.0, attrx=0.0, attry=0.0,
                attrz=0.0, usecarryanim=False, colour=-1, boneid=6, longpickup=False, buttonz=0.96,
                maxhitpoints=5, price=1)
LUA_KEY = {"usecarryanim": "useCarryAnim", "longpickup": "longPickup", "maxhitpoints": "maxHitpoints"}

DEFINE_RE = re.compile(r"(item_\w+)\s*=\s*DefineItemType\((.*?)\);", re.S)
WEAPON_RE = re.compile(r"DefineItemTypeWeapon\((.*?)\);", re.S)
CALIBRE_RE = re.compile(r"(calibre_\w+)\s*=\s*DefineAmmoCalibre\(\"([^\"]+)\",\s*(" + NUM + r")\);")
AMMO_RE = re.compile(r"DefineItemTypeAmmo\((.*?)\);", re.S)
FOOD_RE = re.compile(r"DefineFoodItem\((.*?)\);", re.S)
LIQUID_RE = re.compile(r"DefineLiquidContainerItem\((.*?)\);", re.S)
SAFEBOX_RE = re.compile(r"DefineSafeboxType\((.*?)\);", re.S)
BAG_RE = re.compile(r"DefineBagType\((.*?)\);", re.S)

WEAPON_IDS = {
    "WEAPON_BRASSKNUCKLE": 1, "WEAPON_GOLFCLUB": 2, "WEAPON_NITESTICK": 3, "WEAPON_KNIFE": 4, "WEAPON_BAT": 5,
    "WEAPON_SHOVEL": 6, "WEAPON_POOLSTICK": 7, "WEAPON_KATANA": 8, "WEAPON_CHAINSAW": 9, "WEAPON_DILDO": 10,
    "WEAPON_DILDO2": 11, "WEAPON_VIBRATOR": 12, "WEAPON_VIBRATOR2": 13, "WEAPON_FLOWER": 14, "WEAPON_CANE": 15,
    "WEAPON_GRENADE": 16, "WEAPON_TEARGAS": 17, "WEAPON_MOLTOV": 18, "WEAPON_COLT45": 22, "WEAPON_SILENCED": 23,
    "WEAPON_DEAGLE": 24, "WEAPON_SHOTGUN": 25, "WEAPON_SAWEDOFF": 26, "WEAPON_SHOTGSPA": 27, "WEAPON_UZI": 28,
    "WEAPON_MP5": 29, "WEAPON_AK47": 30, "WEAPON_M4": 31, "WEAPON_TEC9": 32, "WEAPON_RIFLE": 33, "WEAPON_SNIPER": 34,
    "WEAPON_ROCKETLAUNCHER": 35, "WEAPON_HEATSEEKER": 36, "WEAPON_FLAMETHROWER": 37, "WEAPON_MINIGUN": 38,
    "WEAPON_SATCHEL": 39, "WEAPON_BOMB": 40, "WEAPON_SPRAYCAN": 41, "WEAPON_FIREEXTINGUISHER": 42,
    "WEAPON_CAMERA": 43, "WEAPON_PARACHUTE": 46,
}
# weapon.pwn: enum (<<= 1) { WEAPON_FLAG_ASSISTED_FIRE_ONCE = 1, _ASSISTED_FIRE, _ONLY_FIRE_AIMED, _LIQUID_AMMO }
WEAPON_FLAGS = {"WEAPON_FLAG_ASSISTED_FIRE_ONCE": 1, "WEAPON_FLAG_ASSISTED_FIRE": 2, "WEAPON_FLAG_ONLY_FIRE_AIMED": 4,
                "WEAPON_FLAG_LIQUID_AMMO": 8}


def split_args(s: str) -> list[str]:
    out, depth, cur, quoted = [], 0, "", False
    for ch in s:
        if ch == '"':
            quoted = not quoted
        if ch == "," and depth == 0 and not quoted:
            out.append(cur.strip())
            cur = ""
            continue
        if not quoted:
            depth += ch in "([{"
            depth -= ch in ")]}"
        cur += ch
    if cur.strip():
        out.append(cur.strip())
    return out


def coerce(v: str):
    v = v.strip()
    if v.startswith('"'):
        return v.strip('"')
    if v in ("true", "false"):
        return v == "true"
    v = v.replace("_:", "")
    if re.fullmatch(NUM, v):
        return float(v) if "." in v else int(v)
    if v == "ITEM_FLOOR_OFFSET":
        return 0.96
    if v.replace(" ", "") == "ITEM_FLOOR_OFFSET/3":
        return 0.32
    return v  # symbolic: anim_Blunt, WEAPON_COLT45, calibre_9mm, liquid_Water


def parse_flags(v: str) -> int:
    flags = 0
    for part in v.split("|"):
        part = part.strip()
        flags |= WEAPON_FLAGS[part] if part in WEAPON_FLAGS else int(part)
    return flags


def parse_item_types(src: str) -> dict[str, dict]:
    types: dict[str, dict] = {}
    for index, m in enumerate(DEFINE_RE.finditer(src)):
        fields = dict(DEFAULTS)
        pos = 0
        for arg in split_args(m.group(2)):
            if arg.startswith("."):
                k, v = arg[1:].split("=", 1)
                fields[k.strip()] = coerce(v)
            else:
                fields[POSITIONAL[pos]] = coerce(arg)
                pos += 1
        fields.update(_symbol=m.group(1), _index=index, category="generic", categoryData=None)
        types[fields["uname"]] = fields
    return types


def apply_categories(types: dict[str, dict], init_src: str, apparel_src: str) -> None:
    by_symbol = {t["_symbol"]: t for k, t in types.items() if not k.startswith("_")}
    # Calibres are keyed by their Pawn symbol suffix (calibre_9mm -> "9mm"): display names collide upstream
    # (calibre_50cae and calibre_50bmg are both ".50") while the Pawn code compares calibre ids, not names.
    calibres = {sym: {"id": sym[len("calibre_"):], "name": name, "bleed": float(b)}
                for sym, name, b in CALIBRE_RE.findall(init_src)}

    def target(args):
        return by_symbol.get(args[0].strip())

    for argstr in WEAPON_RE.findall(init_src):
        a = split_args(argstr)
        t = target(a)
        if not t:
            continue
        base = coerce(a[1])
        base = WEAPON_IDS.get(base, base) if isinstance(base, str) else base
        anim = a[6].strip().replace("anim_", "") if len(a) > 6 and a[6].strip() != "-1" else None
        if base == 0:
            data = {"melee": True, "baseWeapon": 0, "bleed": float(coerce(a[3])), "knockout": float(coerce(a[4])),
                    "animSet": anim}
        else:
            cal = calibres[a[2].strip()]["id"] if a[2].strip() in calibres else None
            flags = parse_flags(a[7]) if len(a) > 7 else 0
            data = {"melee": False, "baseWeapon": base, "calibre": cal, "muzzleVelocity": float(coerce(a[3])),
                    "magSize": int(coerce(a[4])), "maxReserveMags": int(coerce(a[5])), "animSet": anim,
                    "flags": flags}
            if flags & WEAPON_FLAGS["WEAPON_FLAG_LIQUID_AMMO"]:
                data["liquid"] = a[2].strip().replace("liquid_", "")  # calibre slot holds a liquid type
        t["category"], t["categoryData"] = "weapon", data
    for argstr in AMMO_RE.findall(init_src):
        a = split_args(argstr)
        t = target(a)
        if t:
            t["category"] = "ammo"
            t["categoryData"] = {"name": coerce(a[1]), "calibre": calibres[a[2].strip()]["id"],
                                 "bleedMult": float(coerce(a[3])), "koMult": float(coerce(a[4])),
                                 "penetration": float(coerce(a[5])), "rounds": int(coerce(a[6])),
                                 "noTransfer": bool(coerce(a[7])) if len(a) > 7 else False}
    for argstr in FOOD_RE.findall(init_src):
        a = split_args(argstr)
        t = target(a)
        if t:
            t["category"] = "food"
            t["categoryData"] = {"maxBites": int(coerce(a[1])), "biteValue": float(coerce(a[2])),
                                 "canCook": bool(coerce(a[3])), "canRawInfect": bool(coerce(a[4])),
                                 "destroyOnEnd": bool(coerce(a[5]))}
    for argstr in LIQUID_RE.findall(init_src):
        a = split_args(argstr)
        t = target(a)
        if t:
            pairs = a[3:]
            liquids = [[pairs[i].replace("liquid_", ""), float(coerce(pairs[i + 1]))] for i in range(0, len(pairs) - 1, 2)]
            t["category"] = "liquid"
            t["categoryData"] = {"capacity": float(coerce(a[1])), "reusable": bool(coerce(a[2])), "liquids": liquids}
    for argstr in SAFEBOX_RE.findall(init_src):
        a = split_args(argstr)
        t = target(a)
        if t:
            t["category"], t["categoryData"] = "safebox", {"size": int(coerce(a[1]))}
    for argstr in BAG_RE.findall(apparel_src):
        a = split_args(argstr)
        t = by_symbol.get(a[1].strip())
        if t:
            t["category"], t["categoryData"] = "bag", {"bag_name": coerce(a[0]), "bag_size": int(coerce(a[2]))}
    types["_calibres"] = {v["id"]: v["bleed"] for v in calibres.values()}
    types["_calibre_names"] = {v["id"]: v["name"] for v in calibres.values()}


def _public(t: dict) -> dict:
    return {LUA_KEY.get(k, k): v for k, v in t.items() if not k.startswith("_")}


def _ordered(types):
    return sorted((t for k, t in types.items() if not k.startswith("_")), key=lambda t: t["_index"])


def render_lua(types: dict[str, dict]) -> str:
    lines = [HEADER, "local M = { byUname = {}, order = {}, calibres = {}, calibreNames = {} }"]
    for t in _ordered(types):
        lines.append(f"M.byUname{lua_index(t['uname'])} = {lua_value(_public(t))}")
    lines.append("M.order = " + lua_value([t["uname"] for t in _ordered(types)]))
    lines.append("M.calibres = " + lua_value(types.get("_calibres", {})))
    lines.append("M.calibreNames = " + lua_value(types.get("_calibre_names", {})))
    lines.append("return M\n")
    return "\n".join(lines)


def render_sql(types: dict[str, dict]) -> str:
    rows = []
    for t in sorted((t for k, t in types.items() if not k.startswith("_")), key=lambda t: t["uname"]):
        cd = "NULL" if t["categoryData"] is None else sql_str(json.dumps(t["categoryData"], sort_keys=True))
        rows.append(f"({sql_str(t['uname'])},{sql_str(t['name'])},{int(t['model'])},{int(t['size'])},"
                    f"{int(t['maxhitpoints'])},{sql_str(t['category'])},{cd})")
    out = [SEED_HEADER]
    for i in range(0, len(rows), 500):
        out.append("INSERT INTO item_types (uname,name,model,size,max_hitpoints,category,category_data) VALUES\n"
                   + ",\n".join(rows[i:i + 500])
                   + "\nON DUPLICATE KEY UPDATE name=VALUES(name), model=VALUES(model), size=VALUES(size), "
                     "max_hitpoints=VALUES(max_hitpoints), category=VALUES(category), category_data=VALUES(category_data);\n")
    return "\n".join(out)


def convert(src_root, out_data, out_seed) -> dict:
    from pathlib import Path

    from .common import read_text, write_text
    init = read_text(Path(src_root) / "gamemodes/sss/core/server/init.pwn")
    apparel = "".join(read_text(p) for p in sorted((Path(src_root) / "gamemodes/sss/core/apparel").glob("*.pwn")))
    types = parse_item_types(init)
    apply_categories(types, init, apparel)
    write_text(Path(out_data) / "item_types.lua", render_lua(types))
    write_text(Path(out_seed) / "0001_item_types.sql", render_sql(types))
    return types
