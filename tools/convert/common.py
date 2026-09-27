from __future__ import annotations

import re
from pathlib import Path

HEADER = ("-- Derived from Southclaws/ScavengeSurvive (MPL-2.0). See THIRD_PARTY_NOTICES.md\n"
          "-- GENERATED FILE - do not edit; run: python -m tools.convert all\n")
SEED_HEADER = ("-- Derived from Southclaws/ScavengeSurvive (MPL-2.0). See THIRD_PARTY_NOTICES.md\n"
               "-- GENERATED FILE - do not edit; run: python -m tools.convert all\n")
NUM = r"[-+]?\d+(?:\.\d+)?"
LUA_IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
LUA_KEYWORDS = {"and", "break", "do", "else", "elseif", "end", "false", "for", "function", "if", "in", "local", "nil",
                "not", "or", "repeat", "return", "then", "true", "until", "while"}


class UnparsedLine(Exception):
    pass


def lua_str(s: str) -> str:
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t") + '"'


def lua_key(k: str) -> str:
    return k if LUA_IDENT.fullmatch(k) and k not in LUA_KEYWORDS else "[" + lua_str(k) + "]"


def lua_index(k: str) -> str:
    """Field access suffix: `.name` for identifiers, `["na me"]` otherwise."""
    key = lua_key(k)
    return "." + key if key == k else key


def lua_value(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "nil"
    if isinstance(v, float):
        return repr(v)
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, (list, tuple)):
        return "{ " + ", ".join(lua_value(x) for x in v) + " }"
    if isinstance(v, dict):
        return "{ " + ", ".join(f"{lua_key(k)} = {lua_value(v[k])}" for k in sorted(v)) + " }"
    raise TypeError(type(v))


def sql_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "''") + "'"


def read_text(path: Path, encoding: str = "utf-8") -> str:
    return path.read_bytes().decode(encoding, errors="replace").replace("\r\n", "\n").replace("\r", "\n")


def write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
