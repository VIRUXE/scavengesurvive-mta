"""Checks every DFF under resources/ for frame names the game reads as a damaged part.

Usage: python -m tools.dff_qa [DIR_OR_FILE ...]

GTA keeps 23 characters of a frame name and loads an atomic whose (cut) name ends in "_dam" as the damaged half of a
damageable object. On a model from engineRequestModel there is no such half: the 1.6 release client writes it past
the model info (heap corruption, clients crash at random later, 2026-11-22 to 28 with car_part_models) and newer
clients drop the atomic, so the model shows nothing. "sentinel_bump_front_dam_part" is such a name: the cut leaves
"sentinel_bump_front_dam". Exits 1 when a file has one.

A replacement for a whole vehicle may carry real *_dam panels; none is in the repo, so nothing is exempt yet.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "resources" / "[scavengesurvive]"
NAME_LEN = 23  # what the game keeps of a frame name
CLUMP, FRAME_LIST, EXTENSION, FRAME_NAME = 0x10, 0x0E, 0x03, 0x0253F2FE


def frame_names(data: bytes) -> list[str]:
    names: list[str] = []

    def walk(lo: int, hi: int) -> None:
        pos = lo
        while pos + 12 <= hi:
            kind, size, _version = struct.unpack_from("<III", data, pos)
            body = pos + 12
            if body + size > hi:
                return
            if kind == FRAME_NAME:
                names.append(data[body : body + size].split(b"\0", 1)[0].decode("latin1"))
            elif kind in (CLUMP, FRAME_LIST, EXTENSION):
                walk(body, body + size)
            pos = body + size

    walk(0, len(data))
    return names


def bad_names(path: Path) -> list[str]:
    return [n for n in frame_names(path.read_bytes()) if n[:NAME_LEN].lower().endswith("_dam")]


def main(argv: list[str]) -> int:
    targets = [Path(a) for a in argv] or [RESOURCES]
    files: list[Path] = []
    for target in targets:
        files += sorted(target.rglob("*.dff")) if target.is_dir() else [target]
    found = 0
    for path in files:
        for name in bad_names(path):
            found += 1
            shown = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
            print(f"{shown}: frame '{name}' is read as '{name[:NAME_LEN]}', a damaged part")
    print(f"dff_qa: {len(files)} files, {found} bad frame name(s)")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
