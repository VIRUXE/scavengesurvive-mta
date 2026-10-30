from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import features, houseloot, item_types, lang, loot_tables, maps, puzzles, settings, vspawn, zones
from .common import read_text

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "resources" / "[scavengesurvive]" / "data" / "generated"
SEED = ROOT / "sql" / "seed"
MAPS = ROOT / "resources" / "[scavengesurvive]" / "maps"
WORLD = ROOT / "resources" / "[scavengesurvive]" / "world"
MAPS_REPORT = ROOT / "docs" / "maps-census.md"
SAMP_ONLY = lambda model: 18631 <= model < 20001 or 11682 <= model <= 11753  # noqa: E731 (port hats sit at 20001+)


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python -m tools.convert")
    p.add_argument("kind", choices=["all", "items", "loot", "zones", "lang", "maps", "vspawn"])
    p.add_argument("--src", default=str(ROOT.parent / "ScavengeSurvive"))
    args = p.parse_args(argv)
    DATA.mkdir(parents=True, exist_ok=True)
    SEED.mkdir(parents=True, exist_ok=True)
    if args.kind in ("all", "items"):
        types = item_types.convert(args.src, DATA, SEED)
        real = {u: t for u, t in types.items() if not u.startswith("_")}
        samp_only = sorted(u for u, t in real.items() if SAMP_ONLY(int(t["model"])))
        print(f"items: {len(real)} types, {len(samp_only)} with SA-MP-only models: {', '.join(samp_only)}")
        settings.write_settings_seed(SEED)
    if args.kind in ("all", "loot"):
        init = read_text(Path(args.src) / "gamemodes/sss/core/server/init.pwn")
        unames = list(item_types.parse_item_types(init))
        print(f"loot: {len(loot_tables.convert(args.src, DATA, unames))} tables")
    if args.kind in ("all", "zones"):
        print(f"zones: {len(zones.convert(args.src, SEED))} loot spawns")
        print(f"house loot: {len(houseloot.convert(args.src, SEED))} loot points in half of the hollow houses")
        init = read_text(Path(args.src) / "gamemodes/sss/core/server/init.pwn")
        nl, nz, nf = features.convert(args.src, WORLD, list(item_types.parse_item_types(init)))
        print(f"features: {nl} ladders, {nz} ziplines, {nf} fixed items -> world/data/features.lua")
        no, ni = puzzles.convert(args.src, WORLD)
        print(f"puzzles: {no} objects, {ni} puzzle items -> world/data/puzzles.lua")
    if args.kind in ("all", "lang"):
        print("lang:", lang.convert(args.src, DATA))
    if args.kind in ("all", "vspawn"):
        types, rows, dropped = vspawn.convert(args.src, DATA, SEED)
        for d in dropped:
            print(f"vspawn: dropped {d} (upstream skips it too)")
        typed = sum(1 for r in rows if r["type"])
        files = len({r["file"] for r in rows})
        print(f"vspawn: {len(types)} vehicle types, {len(rows)} spawns ({typed} explicit types) from {files} files")
    if args.kind in ("all", "maps"):
        zones_ = maps.convert(args.src, MAPS, MAPS_REPORT)
        n = sum(len(z["objects"]) for z in zones_.values())
        print(f"maps: {len(zones_)} zones, {n} objects, {sum(len(z['removals']) for z in zones_.values())} removals"
              f" -> {MAPS_REPORT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
