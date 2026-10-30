"""Writes the window pane texture of the SA-MP house shells: see-through glass, lighter at the head where it reflects the
sky and darker toward the sill, with one soft reflection band (the opaque border is no longer sampled). Output: models/files/house_window.txd (what the client imports) and, for Blender, house_window.PNG
(tools/glaze_house_windows.py reads it from its texture directory).

    python tools/make_house_window.py GTA_DIR OUT_TXD OUT_PNG

The same TXD carries the curtains and blinds hung behind the glass and the frames' painted wood
(tools/glaze_house_windows.py): vanilla textures copied byte for byte out of the game's IMGs, so the shells'
dictionaries get them with the pane in one import.
"""
import os
import struct
import sys
import zlib

SIZE = 128
FRAME = 9
FRAME_RGBA = (206, 208, 212, 255)
GLASS_TOP = (178, 196, 206, 150)  # sky reflected at the head of the pane
GLASS_BOTTOM = (64, 76, 84, 110)  # darker street reflection at the sill, more of the room showing through
VERSION = 0x1803FFFF  # GTA:SA
HANGINGS = (  # texture, IMG, TXD it lives in
    ("ah_curtains1", "gta_int.img", "ganghoos.txd"),
    ("AH_blucurtain", "gta_int.img", "sfhosemed2.txd"),
    ("AH_pinkcurtain", "gta_int.img", "cuntcuts.txd"),
    ("CJ_H_CURTAIN1", "gta_int.img", "hospital.txd"),
    ("curtain_sink2", "gta3.img", "col_wall2x.txd"),
    ("curtain_sinkb", "gta_int.img", "carls_kit2.txd"),
    ("AH_BLINDSM", "gta_int.img", "newcrak.txd"),
    ("AH_wdblinds", "gta_int.img", "whorebar.txd"),
    ("Bdup_Blinds", "gta_int.img", "lee_bdupsmain.txd"),
    ("HS2_Blind2", "gta_int.img", "lahss2int2.txd"),
    ("HS2_Blind3", "gta_int.img", "lahss2aint2.txd"),
    ("ab_blinds", "gta_int.img", "papaerchaseoffice.txd"),
    ("ws_doorframe", "gta3.img", "boxhses_sfsx.txd"),  # the window frames; the LS and LV shells' dictionaries lack it
)


def pixel(x: int, y: int) -> tuple[int, int, int, int]:
    border = x < FRAME or y < FRAME or x >= SIZE - FRAME or y >= SIZE - FRAME
    if border:
        shade = 18 if (x + y) % 2 else 0  # a little grain so the frame is not flat
        return tuple(c - shade for c in FRAME_RGBA[:3]) + (255,)
    t = (y - FRAME) / (SIZE - 2 * FRAME - 1)  # 0 at the top row, 1 at the bottom
    band = 18 if abs((x - y) - 20) < 16 else 0  # one soft, wide reflection across the pane
    return tuple(min(255, round(a + (b - a) * t) + band) for a, b in zip(GLASS_TOP[:3], GLASS_BOTTOM[:3])) + (round(GLASS_TOP[3] + (GLASS_BOTTOM[3] - GLASS_TOP[3]) * t),)


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
    for texture, img, name in HANGINGS:
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
