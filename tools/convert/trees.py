"""Choppable trees (upstream core/world/tree.pwn, DefineTreeSpecies in core/server/init.pwn) -> world/data/trees.lua.

Upstream placed its wild trees from .tpl files that are not in the checkout (#22), so the trees come from where those
files took them: GTA's own placements of the species' models in the game copy's IPLs (tools/ipl_natives.py). Only the
species a Chainsaw fells for Wood Logs are kept (the Knife species give Cake Slices upstream and are not ported), in
the open world (interior 0). The species rows are { diameter, health, chop damage per second, pieces, fall }.
"""
from __future__ import annotations

import math
import re
from pathlib import Path

from tools.ipl_natives import native_placements

from .common import NUM, read_text, write_text

SPECIES_RE = re.compile(r"DefineTreeSpecies\(\s*(\d+)\s*,\s*(" + NUM + r")\s*,\s*(" + NUM + r")\s*,\s*(" + NUM
                        + r")\s*,\s*(\d+)\s*,\s*\w+\s*,\s*FALL_TYPE_(ROTATE|ZDROP)\s*,\s*item_(\w+)\s*,\s*item_(\w+)")
TOOL, YIELD = "Chainsaw", "WoodLog"
HEADER = ("-- Derived from Southclaws/ScavengeSurvive (MPL-2.0). See THIRD_PARTY_NOTICES.md\n"
          "-- GENERATED FILE - do not edit; run: python -m tools.convert trees (needs the game copy, --gta)\n")


def parse_species(init: str) -> dict[int, list]:
    out = {}
    for m in SPECIES_RE.finditer(init):
        model, diameter, health, chop, pieces, fall, tool, yields = m.groups()
        if (tool, yields) == (TOOL, YIELD):
            out[int(model)] = [float(diameter), float(health), float(chop), int(pieces), fall.lower()]
    return out


def render_lua(species: dict[int, list], trees: list[list]) -> str:
    out = [HEADER, "-- Upstream DefineTreeSpecies(model, diameter, health, chop damage, pieces, category, fall type, Chainsaw,",
           "-- Wood Log) and GTA's own placements of those models. Species: [model] = { diameter, health, chop damage per",
           "-- second, pieces, fall }; trees: { model, x, y, z, rz }, sorted.", "", "return {", "    species = {"]
    for model in sorted(species):
        d, h, c, p, f = species[model]
        out.append(f"        [{model}] = {{ {d!r}, {h!r}, {c!r}, {p}, \"{f}\" }},")
    out += ["    },", "    trees = {"]
    out += [f"        {{ {t[0]}, {t[1]!r}, {t[2]!r}, {t[3]!r}, {t[4]!r} }}," for t in trees]
    out += ["    },", "}", ""]
    return "\n".join(out)


def convert(src_root, gta, out_resource) -> tuple[int, int]:
    species = parse_species(read_text(Path(src_root) / "gamemodes/sss/core/server/init.pwn"))
    trees = []
    for model, pos, rot, interior in native_placements(Path(gta), set(species)):
        if interior == 0:
            trees.append([model, round(pos[0], 3), round(pos[1], 3), round(pos[2], 3),
                          round(math.degrees(math.atan2(rot[1][0], rot[0][0])) % 360, 1)])
    trees.sort(key=lambda t: (t[0], t[1], t[2], t[3]))
    write_text(Path(out_resource) / "data" / "trees.lua", render_lua(species, trees))
    return len(species), len(trees)
