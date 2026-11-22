"""Swap repainted high-resolution textures into a skin twin's TXD in `skin_models/files`.

A twin's TXD (`<name>_nohat.txd`, written by tools/hatless_rebuild.py at the game's 128x256) can carry textures
repainted at 4x. Their sources are `tools/data/ped_hd/<twin>/<texture>.png` (same atlas layout as the texture they
replace, so the DFF's UVs still fit); this writes each as a DXT1 native with a full mip chain under the same name,
keeping every other texture of the TXD as it is. `hatless_rebuild build` runs it after installing a twin, so a
rebuilt twin keeps its HD textures.

    python -m tools.ped_hd                 # every twin with a folder in tools/data/ped_hd
    python -m tools.ped_hd csher_nohat     # only these
"""
import io
import struct
import sys
from pathlib import Path

from PIL import Image

from tools.extract_samp_models import txd_natives
from tools.make_vending import chunk

ROOT = Path(__file__).resolve().parents[1]
HD = ROOT / "tools" / "data" / "ped_hd"
FILES = ROOT / "resources" / "[scavengesurvive]" / "skin_models" / "files"


def dxt1(im: Image.Image) -> bytes:
    buf = io.BytesIO()
    im.save(buf, "DDS", pixel_format="DXT1")
    data = buf.getvalue()
    assert data[:4] == b"DDS " and data[84:88] == b"DXT1", "unexpected DDS header"
    return data[128:]


def native_dxt1(name: str, im: Image.Image) -> bytes:
    """D3D9 texture native: DXT1, 565 raster with mipmaps, every level down to 4x4."""
    im = im.convert("RGB")
    w, h = im.size
    levels, level = [], im
    while True:
        levels.append(dxt1(level))
        if min(level.size) <= 4:
            break
        level = level.resize((level.width // 2, level.height // 2), Image.Resampling.LANCZOS)
    head = struct.pack("<II", 9, 0x1106)
    head += name.encode()[:31].ljust(32, b"\0") + b"".ljust(32, b"\0")
    head += struct.pack("<I4s", 0x8200, b"DXT1")
    head += struct.pack("<HHBBBB", w, h, 16, len(levels), 4, 0x08)
    head += b"".join(struct.pack("<I", len(d)) + d for d in levels)
    return chunk(0x15, chunk(1, head) + chunk(3, b""))


def native_name(native: bytes) -> str:
    return native[32:64].split(b"\0")[0].decode("latin1")


def apply(twin: str) -> list[str]:
    """Replace the textures of skin_models/files/<twin>.txd that have an HD source; returns their names."""
    src, txd = HD / twin, FILES / f"{twin}.txd"
    if not src.is_dir() or not txd.is_file():
        return []
    hd = {p.stem.lower(): p for p in src.glob("*.png")}
    data = txd.read_bytes()
    _version, device, natives = txd_natives(data)
    done, out = [], []
    for n in natives:
        name = native_name(n)
        if name.lower() in hd:
            n = native_dxt1(name, Image.open(hd.pop(name.lower())))
            done.append(name)
        out.append(n)
    if hd:
        raise SystemExit(f"ped_hd: {twin}.txd has no texture named {', '.join(sorted(hd))}")
    header = chunk(1, struct.pack("<HH", len(out), device))
    txd.write_bytes(chunk(0x16, header + b"".join(out) + chunk(3, b"")))
    return done


def main(argv=None) -> int:
    twins = (argv if argv is not None else sys.argv[1:]) or sorted(p.name for p in HD.iterdir() if p.is_dir())
    for twin in twins:
        done = apply(twin)
        print(f"{twin}: {', '.join(done) if done else 'nothing to swap'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
