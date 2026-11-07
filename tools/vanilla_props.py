"""Vanilla models copied into prop_models (ids 20201+) unchanged, so the game draws them as ordinary objects.

    python -m tools.vanilla_props [--gta DIR]

GTA draws its vehicle wheel models (veh_mods.ide 1025-1193) specially: as an object, the Wheel item's 1079 ignores any
pitch or roll and renders as a thin strip instead of lying on its side. The same dff, given an object id of its own,
rotates like any prop. Each row writes prop_models/files/<name>.dff (the vanilla dff as is), .txd (its source TXD cut
down to the textures the dff uses) and .col (one box over the mesh bounds, so culling and the bounding sphere fit);
tools/make_props.py lists the rows in props.lua and meta.xml.
"""
from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

FILES = ROOT / "resources" / "[scavengesurvive]" / "prop_models" / "files"

# name: port id, vanilla dff in gta3.img, its TXD (path under models/), draw distance
COPIES = [
    {"name": "wheel", "id": 20222, "dff": "wheel_sr1.dff", "txd": "generic/vehicle.txd", "dist": 80},
]


def geometry_bounds(dff: bytes) -> tuple[tuple[float, float, float], tuple[float, float, float]]:
    """(min, max) over every geometry's vertices (frames are identity for these models)."""
    lo, hi = [math.inf] * 3, [-math.inf] * 3

    def walk(off, end):
        while off + 12 <= end:
            kind, size, _v = struct.unpack_from("<III", dff, off)
            if kind == 0x0F:
                g = off + 24
                flags, nuv, _native, ntri, nv, _nm = struct.unpack_from("<HBBIII", dff, g)
                q = g + 16
                if flags & 0x08:
                    q += 4 * nv
                q += 8 * nv * (nuv or (2 if flags & 0x80 else 1 if flags & 0x04 else 0)) + 8 * ntri
                q += 24  # bounding sphere, has-vertices, has-normals
                for i in range(nv):
                    v = struct.unpack_from("<3f", dff, q + 12 * i)
                    for k in range(3):
                        lo[k], hi[k] = min(lo[k], v[k]), max(hi[k], v[k])
            elif kind in (0x10, 0x1A):
                walk(off + 12, off + 12 + size)
            off += 12 + size

    walk(0, len(dff))
    return tuple(lo), tuple(hi)


def box_col(name: str, lo, hi) -> bytes:
    """A COL3 model: the bounds and one box over them."""
    centre = [(a + b) / 2 for a, b in zip(lo, hi)]
    radius = math.dist(centre, hi)
    header_end = 120  # offsets below count from byte 4
    box = struct.pack("<3f3f4B", *lo, *hi, 0, 0, 0, 0)
    body = bytearray()
    body += name.encode("ascii").ljust(22, b"\0")[:22] + struct.pack("<H", 0)
    body += struct.pack("<3f3f3ff", *lo, *hi, *centre, radius)
    body += struct.pack("<HHHBBI", 0, 1, 0, 0, 0, 0x02)
    box_at = header_end - 4
    body += struct.pack("<6I", 0, box_at, 0, 0, 0, 0)
    body += struct.pack("<3I", 0, 0, 0)
    body += box
    return b"COL3" + struct.pack("<I", len(body)) + bytes(body)


def main(argv=None) -> int:
    from tools.extract_samp_models import detect_gta, dff_strings, read_img_entry, read_img_index, trim_txd

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: detected)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    img = gta / "models" / "gta3.img" if gta else None
    if not img or not img.is_file():
        print("vanilla_props: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    index = read_img_index(img)
    for c in COPIES:
        dff = read_img_entry(img, index[c["dff"]])
        txd_src = (gta / "models" / c["txd"]).read_bytes()
        (FILES / f"{c['name']}.dff").write_bytes(dff)
        (FILES / f"{c['name']}.txd").write_bytes(trim_txd(txd_src, dff_strings(dff)))
        lo, hi = geometry_bounds(dff)
        (FILES / f"{c['name']}.col").write_bytes(box_col(c["name"], lo, hi))
        print(f"vanilla_props: {c['name']} ({c['id']}) from {c['dff']}, bounds {lo} .. {hi}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
