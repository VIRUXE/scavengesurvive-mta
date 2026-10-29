"""Writes the window pane texture of the SA-MP house shells: an opaque frame border (sampled by the frame and sill geometry) around tinted, mostly
transparent glass. Output: models/files/house_window.txd (what the client imports) and, for Blender, house_window.PNG
(tools/glaze_house_windows.py reads it from its texture directory).

    python tools/make_house_window.py OUT_TXD OUT_PNG
"""
import struct
import sys
import zlib

SIZE = 128
FRAME = 9
FRAME_RGBA = (206, 208, 212, 255)
GLASS_RGBA = (150, 196, 222, 70)
SHADE_RGBA = (255, 255, 255, 110)  # a faint diagonal glint across the glass
VERSION = 0x1803FFFF  # GTA:SA


def pixel(x: int, y: int) -> tuple[int, int, int, int]:
    border = x < FRAME or y < FRAME or x >= SIZE - FRAME or y >= SIZE - FRAME
    if border:
        shade = 18 if (x + y) % 2 else 0  # a little grain so the frame is not flat
        return tuple(c - shade for c in FRAME_RGBA[:3]) + (255,)
    if 0 <= (x + y) % 56 < 6 and (x + y) < SIZE * 1.5:
        return SHADE_RGBA
    return GLASS_RGBA


def chunk(kind: int, body: bytes) -> bytes:
    return struct.pack("<III", kind, len(body), VERSION) + body


def txd() -> bytes:
    data = b"".join(struct.pack("<4B", b, g, r, a) for y in range(SIZE) for x in range(SIZE) for r, g, b, a in [pixel(x, y)])
    head = struct.pack("<II", 9, 0x1106)  # D3D9, linear filter, wrap
    head += b"house_window".ljust(32, b"\0") + b"".ljust(32, b"\0")
    head += struct.pack("<II", 0x0500, 21)  # 8888, D3DFMT_A8R8G8B8
    head += struct.pack("<HHBBBB", SIZE, SIZE, 32, 1, 4, 0x01)  # one mip, has alpha
    head += struct.pack("<I", len(data)) + data
    native = chunk(0x15, chunk(1, head) + chunk(3, b""))
    return chunk(0x16, chunk(1, struct.pack("<HH", 1, 0)) + native + chunk(3, b""))


def png() -> bytes:
    rows = b"".join(b"\0" + b"".join(struct.pack("<4B", *pixel(x, y)) for x in range(SIZE)) for y in range(SIZE))

    def part(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + part(b"IHDR", ihdr) + part(b"IDAT", zlib.compress(rows, 9)) + part(b"IEND", b"")


if __name__ == "__main__":
    with open(sys.argv[1], "wb") as f:
        f.write(txd())
    with open(sys.argv[2], "wb") as f:
        f.write(png())
