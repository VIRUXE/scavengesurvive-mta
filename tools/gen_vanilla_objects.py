"""Write tools/data/vanilla_objects.txt: every object model id GTA:SA defines (objs/tobj/anim/weap sections of the
game's .ide files), as sorted inclusive ranges. tools/convert/maps.py uses it to classify the upstream map objects
as vanilla / SA-MP-only / unknown. Rerun only if the list is suspected wrong; the output is committed.

    python -m tools.gen_vanilla_objects [--gta DIR]
"""
from __future__ import annotations

import argparse
import glob
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "tools" / "data" / "vanilla_objects.txt"
DEFAULT_GTA = r"D:\Games\GTA San Andreas\GTA San Andreas"
OBJECT_SECTIONS = {"objs", "tobj", "anim", "weap"}  # weapon models are valid object ids too


def parse_object_ids(text: str) -> set[int]:
    ids, section = set(), None
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "," not in line:
            section = None if line.lower() == "end" else line.lower()
            continue
        if section in OBJECT_SECTIONS:
            head = line.split(",", 1)[0].strip()
            if head.isdigit():
                ids.add(int(head))
    return ids


def to_ranges(ids) -> list[tuple[int, int]]:
    out, start, prev = [], None, None
    for i in sorted(ids):
        if start is None:
            start = prev = i
        elif i == prev + 1:
            prev = i
        else:
            out.append((start, prev))
            start = prev = i
    if start is not None:
        out.append((start, prev))
    return out


def render(ranges) -> str:
    lines = ["# GTA:SA object model ids (objs/tobj/anim/weap of data/**/*.ide), inclusive ranges; tools/gen_vanilla_objects.py"]
    lines += [f"{a}-{b}" if a != b else str(a) for a, b in ranges]
    return "\n".join(lines) + "\n"


def load(path: Path = OUT) -> set[int]:
    ids = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        a, _, b = line.partition("-")
        ids.update(range(int(a), int(b or a) + 1))
    return ids


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="python -m tools.gen_vanilla_objects")
    p.add_argument("--gta", default=os.environ.get("GTA_SA_DIR", DEFAULT_GTA))
    args = p.parse_args(argv)
    gta = Path(args.gta)
    paths = sorted(glob.glob(str(gta / "data" / "maps" / "**" / "*.ide"), recursive=True))
    paths += [str(gta / "data" / "default.ide")]
    ids = set()
    for path in paths:
        if os.path.exists(path):
            ids |= parse_object_ids(Path(path).read_text(encoding="latin1", errors="replace"))
    if not ids:
        print(f"no .ide files under {gta}", file=sys.stderr)
        return 1
    OUT.write_text(render(to_ranges(ids)), encoding="utf-8", newline="\n")
    print(f"{len(ids)} object ids in {len(to_ranges(ids))} ranges -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
