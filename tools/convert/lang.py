from __future__ import annotations

import re
from pathlib import Path

from .common import HEADER, lua_key, lua_value, write_text

ENCODINGS = {"English": "ascii", "Indonesian": "ascii", "Romanian": "ascii", "Bosanski-Hrvatski-Srpski": "cp1250",
             "Cestina-Srpski": "iso8859_2", "Español": "cp1252", "Français": "cp1252", "Português": "cp1252",
             "Português do Brasil": "cp1252", "Russian": "cp1251"}
CODES = {"English": "en", "Indonesian": "id", "Romanian": "ro", "Bosanski-Hrvatski-Srpski": "bhs",
         "Cestina-Srpski": "cs", "Español": "es", "Français": "fr", "Português": "pt", "Português do Brasil": "ptbr",
         "Russian": "ru"}
# gamemodes/ScavengeSurvive.pwn "Embedding Colours"
COLOURS = {"C_YELLOW": "#FFFF00", "C_RED": "#E85454", "C_GREEN": "#33AA33", "C_BLUE": "#33CCFF", "C_ORANGE": "#FFAA00",
           "C_GREY": "#AFAFAF", "C_PINK": "#FFC0CB", "C_NAVY": "#000080", "C_GOLD": "#B8860B", "C_LGREEN": "#00FD4D",
           "C_TEAL": "#008080", "C_BROWN": "#A52A2A", "C_AQUA": "#F0F8FF", "C_BLACK": "#000000", "C_WHITE": "#FFFFFF",
           "C_SPECIAL": "#0025AA"}
# gamemodes/ScavengeSurvive.pwn KEYTEXT_* -> GTA control names (rendered by SA-MP GameText as the bound key)
KEYTEXT = {"KEYTEXT_INTERACT": "VEHICLE_ENTER_EXIT", "KEYTEXT_RELOAD": "PED_ANSWER_PHONE",
           "KEYTEXT_PUT_AWAY": "CONVERSATION_YES", "KEYTEXT_DROP_ITEM": "CONVERSATION_NO",
           "KEYTEXT_INVENTORY": "GROUP_CONTROL_BWD", "KEYTEXT_ENGINE": "CONVERSATION_YES",
           "KEYTEXT_LIGHTS": "CONVERSATION_NO", "KEYTEXT_DOORS": "TOGGLE_SUBMISSIONS"}
# MTA has no ~k~ tokens: show the port's default key for each control (hud/client/keys.lua defaults: interact f,
# dropitem n, putaway y, inventory h; reload is MTA's native r).
CONTROL_LABELS = {"VEHICLE_ENTER_EXIT": "[F]", "PED_ANSWER_PHONE": "[R]", "CONVERSATION_YES": "[Y]",
                  "CONVERSATION_NO": "[N]", "GROUP_CONTROL_BWD": "[H]", "SNEAK_ABOUT": "[LALT]",
                  "TOGGLE_SUBMISSIONS": "[2]"}
TAG_RE = re.compile(r"\{([A-Z_0-9]+)\}")
KEYTEXT_RE = re.compile(r"~k~~([A-Z_]+)~")
GT_RE = re.compile(r"~([a-z])~")
GT = {"n": "\n", "r": "#FF3333", "g": "#33FF33", "b": "#3333FF", "y": "#FFFF33", "w": "#FFFFFF", "p": "#FF33FF",
      "l": "#000000", "h": "#DDDDDD", "d": ""}
KEY_RE = re.compile(r"[A-Z][A-Za-z0-9_]{3,11}")

# Help tips (`<first 9 letters of the uname>_T`) for the port's own item types and for upstream types its language
# files never covered; shown for every language, upstream's English wording.
_WEAR = "Wear this by pressing [F]"
_STORE = "Store items inside this to save them over restarts, read more: /restartinfo"
_BUILD = "Use screwdriver with this to construct a permanent wall, or a hammer to construct a permanent floor, hold [F] to build"
PORT_TIPS = {
    **{u: _WEAR for u in ("BandanaBl", "BandanaGr", "BandanaPat", "BandanaWh", "BucketHat", "BurgerHat", "FireHelmet", "GardenerHat", "GolfCap", "MotoHelmet", "PilotCap", "RanchHat", "SheriffHat")},
    **{u: _STORE for u in ("BigCrate", "BinBag", "CardboardBox", "Carton", "FruitCrate", "LargeCarton", "LongCrate", "OpenCardboardBox", "OpenCarton", "PackingBox", "RubbishBag", "ShippingBox", "SmallCrate", "TrashBag", "WeaponCrate", "WoodenCrate")},
    **{u: _BUILD for u in ("GarageDoor", "InsulDoor", "InsulPanel", "LargeFrame", "SmallPanel")},
}

# Upstream left these as "##ITEM TIP NOT SET##"; the port gives them a text.
_EAT = "Eat this for food value"
_COOK = "Cook and eat this for food value"
_DRINK = "Drink this to quench your thirst"
_BOOZE = "Drink this to quench your thirst, but alcohol will make you drunk"
_SCRAP = "Used for crafting, scrap and refine it at a machine"
_STASH = "Store items inside this, hold [F] to open it"
_WEARIT = "Wear this by pressing [F]"
_FURN = "Furniture: decoration for your base, hold a Crowbar and press [F] to take it apart"
_JUNK = "This item has no use except as decoration or crafting"
UNSET_TIPS = {
    **{u: _EAT for u in ("Banana", "BreadLoaf", "Bread", "CakeSlice", "FishyFingers", "GrnApple", "IceCream", "IceCreamBars", "Lemon", "Orange", "PizzaOnly", "RedApple", "WeddingCake", "Cereal1", "Cereal2")},
    **{u: _COOK for u in ("Ham", "Steak", "WrappedMeat")},
    **{u: _DRINK for u in ("AppleJuice", "OrangeJuice", "MilkBottle", "MilkCarton")},
    **{u: _BOOZE for u in ("Champagne", "Whisky", "Wine1", "Wine2", "Wine3")},
    **{u: _WEARIT for u in ("Beanie", "CaptainsCap", "DevilMask", "PizzaHat", "PoliceHelm", "PussyMask", "StrawHat", "SwatHelmet", "WitchesHat")},
    **{u: _STASH for u in ("Cupboard", "GearBox", "GunCase", "Holdall", "Locker", "ToolBox", "Workbench")},
    **{u: _FURN for u in ("Barstool", "Desk", "SmallTable", "Table", "Doormat")},
    **{u: _BUILD for u in ("MetalFrame", "RedPanel", "TallFrame")},
    **{u: _SCRAP for u in ("ScrapMetal", "RefinedMetal")},
    **{u: _JUNK for u in ("Boot", "BoxingGloves", "Cross", "Fork", "Knife3", "Broom", "Computer", "Microphone", "Radio", "RadioBox", "PisschBox", "ControlBox", "Ketchup", "Mustard", "PizzaBox")},
    **{u: "Used for crafting" for u in ("Briquettes", "BurntLog", "Canister", "OilDrum", "OilCan")},
    "Spanner": "Used for crafting and repairs",
    "Keycard": "Used to open locked doors that are set up for a keycard",
    "Padlock": "Used for crafting, combine it with a defence to lock it",
    "WheelLock": "Hold [F] at a vehicle with this to lock its wheel, or craft it into a locksmith kit",
    "LockBreaker": "Hold [F] at a locked vehicle with this to break its lock",
    "RemoteControl": "Used for crafting and some puzzles",
    "Locator": "Press [F] at a phone to sync it, then use it to show the distance to the phone",
    "PlotPole": "Place this to claim an area, the people you add can build inside it",
    "RefineMachine": "Put Scrap Metal inside and press [F] to refine it",
    "ScrapMachine": "Put items inside and press [F] to break them down to scrap",
    "WaterMachine": "Put a Water Bottle of sea water inside and press [F] to purify it",
}


def _replace(v: str) -> str:
    v = TAG_RE.sub(lambda m: "~k~~" + KEYTEXT[m.group(1)] + "~" if m.group(1) in KEYTEXT
                   else "R" if m.group(1) == "KEYTEXT_RADIO" else COLOURS.get(m.group(1), ""), v)
    v = KEYTEXT_RE.sub(lambda m: CONTROL_LABELS.get(m.group(1), "[" + m.group(1) + "]"), v)
    v = GT_RE.sub(lambda m: GT.get(m.group(1), ""), v)
    return v.replace("\\n", "\n").replace("\\t", "\t").replace("%P", "%s")


def parse(raw: bytes, encoding: str) -> dict[str, str]:
    text = raw.decode(encoding, errors="replace").replace("\r\n", "\n").replace("\r", "\n")
    out = {}
    for line in text.split("\n"):
        if len(line) < 4 or "=" not in line:
            continue
        key, val = line.split("=", 1)
        key = key.strip()
        if KEY_RE.fullmatch(key):
            out[key] = _replace(val)
    return out


def render_lua(entries: dict[str, str]) -> str:
    body = "\n".join(f"    {lua_key(k)} = {lua_value(entries[k])}," for k in sorted(entries))
    return HEADER + "return {\n" + body + "\n}\n"


def convert(src_root, out_data) -> dict[str, int]:
    counts = {}
    for name, enc in ENCODINGS.items():
        entries = parse((Path(src_root) / "scriptfiles/languages" / name).read_bytes(), enc)
        for uname, tip in PORT_TIPS.items():
            entries.setdefault(uname[:9] + "_T", tip)
        for uname, tip in UNSET_TIPS.items():
            key = uname[:9] + "_T"
            if key not in entries or "NOT SET" in entries[key]:
                entries[key] = tip
        write_text(Path(out_data) / f"lang_{CODES[name]}.lua", render_lua(entries))
        counts[CODES[name]] = len(entries)
    return counts
