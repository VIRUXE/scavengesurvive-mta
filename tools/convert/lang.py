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
        write_text(Path(out_data) / f"lang_{CODES[name]}.lua", render_lua(entries))
        counts[CODES[name]] = len(entries)
    return counts
