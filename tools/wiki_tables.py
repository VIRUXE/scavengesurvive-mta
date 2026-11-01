"""Generates the Markdown data tables of the GitHub wiki from the port's own data.

    python -m tools.wiki_tables --wiki ../scavengesurvive-mta.wiki [--images images/items/all]

Every table is written to <wiki>/_tables/<name>.md and, in every wiki page, the text between
`<!-- table:<name> -->` and `<!-- /table:<name> -->` is replaced by it, so the pages can be rewritten by hand around
them and the numbers follow the data (data/generated/item_types.lua, vehicle_types.lua, explosives.lua, machines.lua).
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "resources" / "[scavengesurvive]"
ITEM_TYPES = RES / "data" / "generated" / "item_types.lua"
VEHICLE_TYPES = RES / "data" / "generated" / "vehicle_types.lua"
EXPLOSIVES = RES / "explosives" / "shared" / "logic" / "explosives.lua"
MACHINES = RES / "items" / "shared" / "logic" / "machines.lua"

TOKEN = re.compile(r'\s*(?:(--[^\n]*)|("(?:[^"\\]|\\.)*")|(-?\d+(?:\.\d+)?(?:e[+-]?\d+)?)|(\[)|(\])|([{}=,])|([A-Za-z_][\w.]*))')


def tokens(text: str):
    pos = 0
    while pos < len(text):
        m = TOKEN.match(text, pos)
        if not m or m.end() == pos:
            if text[pos:].strip():
                raise ValueError("lua parse error near " + repr(text[pos : pos + 30]))
            return
        pos = m.end()
        if m.group(1):
            continue
        yield m.lastindex, m.group(m.lastindex)


def parse_table(toks, first=None):
    """Parses a Lua table constructor whose `{` was already consumed; returns a dict (keyed rows) or a list."""
    out = {}
    arr = []
    while True:
        kind, tok = next(toks)
        if tok == "}":
            break
        if tok == ",":
            continue
        key = None
        if kind == 4:
            _, key = next(toks)
            key = key.strip('"')
            next(toks)
            next(toks)
            kind, tok = next(toks)
        elif kind == 7:
            peek = next(toks)
            if peek[1] == "=":
                key = tok
                kind, tok = next(toks)
            else:
                value = convert(kind, tok, toks)
                arr.append(value)
                if peek[1] == "}":
                    break
                continue
        value = convert(kind, tok, toks)
        if key is None:
            arr.append(value)
        else:
            out[key] = value
    return out if out or not arr else arr


def convert(kind, tok, toks):
    if tok == "{":
        return parse_table(toks)
    if kind == 2:
        return tok[1:-1].replace('\\"', '"')
    if kind == 3:
        return float(tok) if re.search(r"[.e]", tok) else int(tok)
    if tok == "true":
        return True
    if tok == "false":
        return False
    if tok == "nil":
        return None
    return tok


def lua_rows(path: Path, prefix: str) -> dict[str, dict]:
    rows = {}
    for line in path.read_text(encoding="utf8").splitlines():
        m = re.match(re.escape(prefix) + r"(\w+) = \{", line)
        if m:
            toks = tokens(line[m.end() :])
            rows[m.group(1)] = parse_table(toks)
    return rows


def md(headers: list[str], rows: list[list], align: str = "") -> str:
    out = ["| " + " | ".join(headers) + " |", "|" + "|".join(":--" if a == "l" else "--:" for a in (align or "l" * len(headers))) + "|"]
    for r in rows:
        out.append("| " + " | ".join(str(c) for c in r) + " |")
    return "\n".join(out) + "\n"


def num(v) -> str:
    if isinstance(v, float) and v == int(v):
        return str(int(v))
    return str(v)


def real(items: dict) -> dict:
    out = {}
    for u, t in items.items():
        if not u.startswith("NULL") and u not in ("VEHICLE_WEAPON", "Unknown"):
            t["name"] = t["name"] or u
            out[u] = t
    return out


def table_weapons(items, cal_names, img):
    rows = []
    for u, t in real(items).items():
        d = t.get("categoryData")
        if t["category"] != "weapon" or not d or not d.get("calibre"):
            continue
        rows.append([t["name"], cal_names.get(d["calibre"], d["calibre"]), d["magSize"], d["maxReserveMags"], t["size"], num(d["muzzleVelocity"]) + " m/s"])
    return md(["Weapon", "Calibre", "Magazine", "Spare magazines", "Size", "Muzzle velocity"], rows, "llrrrr")


def table_melee(items, cal_names, img):
    rows = []
    for u, t in real(items).items():
        d = t.get("categoryData")
        if t["category"] == "weapon" and d and not d.get("calibre"):
            rows.append([t["name"], t["size"]])
    return md(["Weapon", "Size"], rows, "lr")


def table_ammo(items, cal_names, img):
    rows = []
    for u, t in real(items).items():
        d = t.get("categoryData")
        if t["category"] == "ammo" and d:
            rows.append([t["name"], d["name"], cal_names.get(d["calibre"], d["calibre"]), d["rounds"], num(d["bleedMult"]), num(d["koMult"]), num(d["penetration"])])
    return md(["Item", "Type", "Calibre", "Rounds", "Bleed x", "Knockout x", "Penetration"], rows, "lllrrrr")


def table_calibres(items, cal_names, img):
    src = ITEM_TYPES.read_text(encoding="utf8")
    cal = parse_table(tokens(re.search(r"M\.calibres = \{(.*)", src).group(1)))
    rows = [[cal_names.get(k, k), num(v)] for k, v in sorted(cal.items(), key=lambda kv: -kv[1]) if v]
    return md(["Calibre", "Base bleed rate"], rows, "lr")


def table_defences(items, cal_names, img):
    rows = []
    for u, t in real(items).items():
        if t.get("defence"):
            rows.append([t["name"], t["maxHitpoints"], t["size"], "yes" if t["defence"].get("movable") else "no"])
    rows.sort(key=lambda r: (-r[1], r[0]))
    return md(["Defence", "Hit points", "Size", "Can be moved after placing"], rows, "lrrl")


def explosive_presets():
    src = EXPLOSIVES.read_text(encoding="utf8")
    return {m.group(1): float(m.group(2)) for m in re.finditer(r"^    (\w+) = \{ anim = \d+, size = ([\d.]+)", src, re.M)}


def table_explosives(items, cal_names, img):
    sizes = explosive_presets()
    rows = []
    for u, t in real(items).items():
        e = t.get("explosive")
        if e:
            rows.append([t["name"], e["preset"].title(), e["trigger"].replace("_", " ").title(), num(sizes.get(e["preset"], 0)) + " m", t["size"]])
    return md(["Item", "Charge", "Trigger", "Blast radius", "Size"], rows, "lllrr")


def table_containers(items, cal_names, img):
    rows = []
    for u, t in real(items).items():
        d = t.get("categoryData")
        if t["category"] == "bag" and d:
            rows.append([t["name"], "bag worn on the back", d["bag_size"], t["size"]])
        elif t["category"] == "safebox" and d:
            rows.append([t["name"], "container placed in the world", d["size"], t["size"]])
    rows.sort(key=lambda r: (r[1], -r[2], r[0]))
    return md(["Item", "Kind", "Slots", "Item size"], rows, "llrr")


def table_food(items, cal_names, img):
    rows = []
    for u, t in real(items).items():
        d = t.get("categoryData")
        if t["category"] == "food" and d:
            rows.append([t["name"], d["maxBites"], num(d["biteValue"]), "yes" if d["canCook"] else "no", "yes" if d["canRawInfect"] else "no"])
    rows.sort(key=lambda r: (-float(r[2]) * r[1], r[0]))
    return md(["Food", "Bites", "Food per bite", "Can be cooked", "Infects when raw"], rows, "lrrll")


def table_sizes(items, cal_names, img):
    by = {}
    for u, t in real(items).items():
        by.setdefault(t["size"], []).append(t["name"])
    rows = [[s, len(n), ", ".join(sorted(set(n)))] for s, n in sorted(by.items())]
    return md(["Size", "Items", "Which"], rows, "rrl")


def table_scrap(items, cal_names, img):
    src = MACHINES.read_text(encoding="utf8")
    blk = src[src.index("M.SCRAP = {") :]
    blk = blk[: blk.index("\n}")]
    rows = []
    for u, v in re.findall(r"(\w+) = (\d+),", blk):
        rows.append([items[u]["name"] if u in items else u, v])
    rows.sort(key=lambda r: (-int(r[1]), r[0]))
    return md(["Item", "Scrap"], rows, "lr")


WIKI = Path(".")


def picture_index(folder: str) -> dict:
    import json

    idx = WIKI / folder / "index.json"
    return json.loads(idx.read_text(encoding="utf8")) if idx.exists() else {}


def table_catalogue(items, cal_names, img):
    index = picture_index(img)
    out = []
    groups = {"weapon": "Weapons", "ammo": "Ammunition", "food": "Food", "liquid": "Drink", "bag": "Bags", "safebox": "Containers", "generic": "Other items"}
    for cat, title in groups.items():
        rows = []
        for u, t in sorted(real(items).items(), key=lambda kv: kv[1]["name"]):
            if t["category"] != cat:
                continue
            pic = "![](" + img + "/" + index[u] + ")" if u in index else ""
            rows.append([pic, t["name"], t["size"]])
        out.append("### " + title + "\n\n" + md(["", "Item", "Size"], rows, "llr"))
    return "\n".join(out)


def table_vehicles(items, cal_names, img):
    veh = real(lua_rows(VEHICLE_TYPES, "M.byUname."))
    index = picture_index("images/vehicles")
    rows = []
    for u, v in veh.items():
        pic = "![](images/vehicles/" + index[u] + ")" if u in index else ""
        rows.append([pic, v["name"], v["category"], v["group"], num(v["maxFuel"]) + " L", v["trunkSize"], num(v["spawnChance"])])
    rows.sort(key=lambda r: (r[2], r[1]))
    return md(["", "Vehicle", "Type", "Group", "Fuel tank", "Trunk slots", "Spawn chance"], rows, "llllrrr")


TABLES = {
    "weapons": table_weapons,
    "melee": table_melee,
    "ammo": table_ammo,
    "calibres": table_calibres,
    "defences": table_defences,
    "explosives": table_explosives,
    "containers": table_containers,
    "food": table_food,
    "sizes": table_sizes,
    "scrap": table_scrap,
    "catalogue": table_catalogue,
    "vehicles": table_vehicles,
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--wiki", required=True)
    ap.add_argument("--images", default="images/items")
    a = ap.parse_args()
    global WIKI
    wiki = WIKI = Path(a.wiki)
    items = lua_rows(ITEM_TYPES, "M.byUname.")
    src = ITEM_TYPES.read_text(encoding="utf8")
    cal_names = parse_table(tokens(re.search(r"M\.calibreNames = \{(.*)", src).group(1)))
    out = wiki / "_tables"
    out.mkdir(parents=True, exist_ok=True)
    made = {}
    for name, fn in TABLES.items():
        made[name] = fn(items, cal_names, a.images)
        (out / (name + ".md")).write_text(made[name], encoding="utf8", newline="\n")
    for page in wiki.glob("*.md"):
        text = page.read_text(encoding="utf8")
        new = text
        for name, body in made.items():
            pat = re.compile(r"(<!-- table:" + name + r" -->\n).*?(<!-- /table:" + name + r" -->)", re.S)
            new = pat.sub(lambda m: m.group(1) + body + m.group(2), new)
        if new != text:
            page.write_text(new, encoding="utf8", newline="\n")
            print("updated", page.name)
    print(len(items), "item types,", len(made), "tables ->", out)


if __name__ == "__main__":
    main()
