"""Writes the window pane texture of the SA-MP house shells: an opaque frame border (sampled by the frame and sill geometry) around tinted, mostly
transparent glass. Output: models/files/house_window.txd (what the client imports) and, for Blender, house_window.PNG
(tools/glaze_house_windows.py reads it from its texture directory).

    python tools/make_house_window.py GTA_DIR OUT_TXD OUT_PNG

The same TXD carries the curtains hung behind the glass (tools/glaze_house_windows.py): four vanilla textures copied
byte for byte out of the game's IMGs, so the shells' dictionaries get them with the pane in one import.
"""
import os
import struct
import sys
import zlib

SIZE = 128
FRAME = 9
FRAME_RGBA = (206, 208, 212, 255)
GLASS_RGBA = (150, 196, 222, 70)
SHADE_RGBA = (255, 255, 255, 110)  # a faint diagonal glint across the glass
VERSION = 0x1803FFFF  # GTA:SA
CURTAINS = (  # texture, IMG, TXD it lives in
    ("ah_curtains1", "gta_int.img", "ganghoos.txd"),
    ("AH_greencurtain", "gta_int.img", "kit3hghg.txd"),
    ("CJ_H_CURTAIN1", "gta_int.img", "hospital.txd"),
    ("curtain_sink2", "gta3.img", "col_wall2x.txd"),
)


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


def img_entry(path: str, name: str) -> bytes:
    with open(path, "rb") as f:
        count = struct.unpack("<I", f.read(8)[4:])[0]
        directory = f.read(count * 32)
        for i in range(count):
            offset, size1, size2 = struct.unpack_from("<IHH", directory, i * 32)
            if directory[i * 32 + 8 : i * 32 + 32].split(b"\0")[0].decode().lower() == name:
                f.seek(offset * 2048)
                return f.read((size1 or size2) * 2048)
    raise KeyError(f"{name} not in {path}")


def native_texture(blob: bytes, texture: str) -> bytes:
    """The whole texture-native chunk named `texture` out of a TXD."""
    pos = 12
    while pos < 12 + struct.unpack_from("<I", blob, 4)[0]:
        kind, size, _ = struct.unpack_from("<III", blob, pos)
        if kind == 0x15 and blob[pos + 32 : pos + 64].split(b"\0")[0].decode().lower() == texture.lower():
            return blob[pos : pos + 12 + size]
        pos += 12 + size
    raise KeyError(texture)


def txd(gta_dir: str) -> bytes:
    data = b"".join(struct.pack("<4B", b, g, r, a) for y in range(SIZE) for x in range(SIZE) for r, g, b, a in [pixel(x, y)])
    head = struct.pack("<II", 9, 0x1106)  # D3D9, linear filter, wrap
    head += b"house_window".ljust(32, b"\0") + b"".ljust(32, b"\0")
    head += struct.pack("<II", 0x0500, 21)  # 8888, D3DFMT_A8R8G8B8
    head += struct.pack("<HHBBBB", SIZE, SIZE, 32, 1, 4, 0x01)  # one mip, has alpha
    head += struct.pack("<I", len(data)) + data
    natives = [chunk(0x15, chunk(1, head) + chunk(3, b""))]
    for texture, img, name in CURTAINS:
        natives.append(native_texture(img_entry(os.path.join(gta_dir, "models", img), name), texture))
    return chunk(0x16, chunk(1, struct.pack("<HH", len(natives), 0)) + b"".join(natives) + chunk(3, b""))


def png() -> bytes:
    rows = b"".join(b"\0" + b"".join(struct.pack("<4B", *pixel(x, y)) for x in range(SIZE)) for y in range(SIZE))

    def part(tag: bytes, body: bytes) -> bytes:
        return struct.pack(">I", len(body)) + tag + body + struct.pack(">I", zlib.crc32(tag + body))

    ihdr = struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + part(b"IHDR", ihdr) + part(b"IDAT", zlib.compress(rows, 9)) + part(b"IEND", b"")


if __name__ == "__main__":
    with open(sys.argv[2], "wb") as f:
        f.write(txd(sys.argv[1]))
    with open(sys.argv[3], "wb") as f:
        f.write(png())
