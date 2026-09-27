from __future__ import annotations

import argparse
import sys
from pathlib import Path

from . import item_types, lang, loot_tables, settings, zones
from .common import read_text

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "resources" / "[scavengesurvive]" / "data" / "generated"
SEED = ROOT / "sql" / "seed"
SAMP_ONLY = lambda model: model >= 18631 or 11682 <= model <= 11753  # noqa: E731


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python -m tools.convert")
    p.add_argument("kind", choices=["all", "items", "loot", "zones", "lang"])
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
    if args.kind in ("all", "lang"):
        print("lang:", lang.convert(args.src, DATA))
    return 0


if __name__ == "__main__":
    sys.exit(main())
