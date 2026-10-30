"""Craft sets from init.pwn's CRAFTING SET DEFINITIONS block -> data/generated/recipes.lua.

Three statement shapes, as upstream writes them:
  DefineItemCraftSet(result, item, keep, ...);                                    combined in an inventory screen
  SetCraftSetConstructible(buildtime, tool, DefineItemCraftSet(...)[, removal, removaltime, tweak][, .tweak = x]
                           [, .defence = x]);                                     built on the ground with the tool
  SetConstructionSetWorkbench(SetCraftSetConstructible(...));                     built at a workbench with the tool
Ingredients keep upstream's (result, item, keep) argument order; the craft library matches them as a multiset.
"""
from __future__ import annotations

import re
from pathlib import Path

from .common import HEADER, UnparsedLine, lua_str, read_text, write_text
from .item_types import parse_item_types, split_args

BLOCK_START = "// CRAFTING SET DEFINITIONS"
BLOCK_END = "WriteAllCombosToFile"
CALL_RE = re.compile(r"^(\w+)\((.*)\)$", re.S)
# SetCraftSetConstructible(buildtime, tool, craftset, removal = INVALID_ITEM_TYPE, removaltime = 0, tweak = true,
# defence = false)
CONSTRUCT_ARGS = ["buildtime", "tool", "craftset", "removal", "removaltime", "tweak", "defence"]


def _call(text: str) -> tuple[str, list[str]]:
    m = CALL_RE.match(text.strip())
    if not m:
        raise UnparsedLine(text)
    return m.group(1), split_args(m.group(2))


def _craftset(text: str, unames: dict[str, str]) -> dict:
    name, args = _call(text)
    if name != "DefineItemCraftSet" or len(args) % 2 != 1:
        raise UnparsedLine(text)

    def uname(sym):
        if sym not in unames:
            raise UnparsedLine(f"unknown item type {sym} in {text}")
        return unames[sym]

    ingredients = []
    for i in range(1, len(args), 2):
        if args[i + 1] not in ("true", "false"):
            raise UnparsedLine(text)
        ingredients.append({"uname": uname(args[i]), "keep": args[i + 1] == "true"})
    return {"result": uname(args[0]), "ingredients": ingredients}


def _constructible(text: str, unames: dict[str, str]) -> dict:
    name, args = _call(text)
    if name != "SetCraftSetConstructible":
        raise UnparsedLine(text)
    fields = {"removal": "INVALID_ITEM_TYPE", "removaltime": "0", "tweak": "true", "defence": "false"}
    pos = 0
    for arg in args:
        if arg.startswith("."):
            k, v = (s.strip() for s in arg[1:].split("=", 1))
            fields[k] = v
        else:
            fields[CONSTRUCT_ARGS[pos]] = arg
            pos += 1
    recipe = _craftset(fields["craftset"], unames)
    recipe.update(kind="construct", buildTime=int(fields["buildtime"]), tool=unames[fields["tool"]],
                  tweak=fields["tweak"] == "true", defence=fields["defence"] == "true")
    if fields["removal"] != "INVALID_ITEM_TYPE":
        recipe.update(removalTool=unames[fields["removal"]], removalTime=int(fields["removaltime"]))
    return recipe


def parse_recipes(src: str, unames: dict[str, str]) -> list[dict]:
    """unames: Pawn symbol (item_Knife) -> item type uname (Knife)."""
    start, end = src.find(BLOCK_START), src.find(BLOCK_END)
    if start < 0 or end < start:
        raise UnparsedLine("no CRAFTING SET DEFINITIONS block in init.pwn")
    recipes = []
    for line in src[start:end].splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue
        if not line.endswith(";"):
            raise UnparsedLine(line)
        stmt = line[:-1]
        name, args = _call(stmt)
        if name == "DefineItemCraftSet":
            recipe = _craftset(stmt, unames)
            recipe["kind"] = "combine"
        elif name == "SetCraftSetConstructible":
            recipe = _constructible(stmt, unames)
        elif name == "SetConstructionSetWorkbench" and len(args) == 1:
            recipe = _constructible(args[0], unames)
            recipe["kind"] = "workbench"
        else:
            raise UnparsedLine(line)
        recipes.append(recipe)
    return recipes


def render_lua(recipes: list[dict]) -> str:
    out = [HEADER, "-- init.pwn CRAFTING SET DEFINITIONS, in upstream order (the craft set ids).\n", "return {\n"]
    for r in recipes:
        ings = ", ".join(f"{{ uname = {lua_str(i['uname'])}, keep = {'true' if i['keep'] else 'false'} }}"
                         for i in r["ingredients"])
        fields = [f"result = {lua_str(r['result'])}", f"kind = {lua_str(r['kind'])}"]
        if r["kind"] != "combine":
            fields += [f"tool = {lua_str(r['tool'])}", f"buildTime = {r['buildTime']}"]
        if r["kind"] == "construct":
            fields += [f"tweak = {'true' if r['tweak'] else 'false'}", f"defence = {'true' if r['defence'] else 'false'}"]
            if "removalTool" in r:
                fields += [f"removalTool = {lua_str(r['removalTool'])}", f"removalTime = {r['removalTime']}"]
        fields.append(f"ingredients = {{ {ings} }}")
        out.append("    { " + ", ".join(fields) + " },\n")
    out.append("}\n")
    return "".join(out)


def convert(src_root, out_data) -> list[dict]:
    init = read_text(Path(src_root) / "gamemodes/sss/core/server/init.pwn")
    unames = {t["_symbol"]: u for u, t in parse_item_types(init).items()}
    recipes = parse_recipes(init, unames)
    write_text(Path(out_data) / "recipes.lua", render_lua(recipes))
    return recipes
