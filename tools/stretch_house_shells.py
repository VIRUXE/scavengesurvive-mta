"""Stretched copies of SA-MP house shells, for plots cut for a deeper vanilla house.

    python -m tools.stretch_house_shells

SA-MP's sfhouse3 is box_hse_01 made enterable. Upstream also stands it on ten San Fierro plots of box_hse_08, which is
box_hse_01 with everything in front of x 2.25 moved 0.4547 m forward and everything behind x 5.31 moved 0.4574 m back
(nothing lies between). The ground there is cut to hse_08's walls and sunk 0.4 m inside them, so a strip of it showed in
front of and behind the shell. This tool makes hse_08's shape out of sfhouse3 the same way: every vertex of the shell and
of its interior in front of CUT moves FRONT along x, every one behind it BACK, in the DFF and in the COL (bounds,
spheres, boxes, face groups, mesh and shadow mesh vertices). The interior has nothing between x 3.64 and 4.80, so only
whole floors, ceilings, side walls and the roof's slopes span the cut, and those stretch.

Reads samp_models/files/<src>.dff/.col and writes:

- samp_models/files/<name>.dff/.col and samp_models/stretched.lua (port id -> files, as manifest.lua), then
  samp_models/meta.xml (tools/extract_samp_models.py write_meta);
- maps/shared/stretched_shells.lua: per stretched id its base shell and the move, so the maps hang the base shell's
  fitted doors in it (shared/logic/placement.lua stretchShells) and drop upstream's panes by the base shell's openings.
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.extract_samp_models import write_meta  # noqa: E402

RES = ROOT / "resources" / "[scavengesurvive]"
MODELS = RES / "samp_models"
FILES = MODELS / "files"
MAPS_LUA = RES / "maps" / "shared" / "stretched_shells.lua"

CUT = 4.2  # x in the shell's frame: in front of it moves FRONT, behind it BACK
FRONT, BACK = -0.4547, 0.4574  # box_hse_08 against box_hse_01: -6.2044 / -5.7497 and 6.2162 / 5.7588
SHELLS = [
    {"model": 20304, "base": 19493, "src": "sfhouse3", "name": "sfhouse3w", "txdModel": 3820, "dist": 200},
    {"model": 20305, "base": 19494, "src": "sfhouse3int", "name": "sfhouse3wint", "txd": "all_walls", "dist": 200},
]


def moved(x: float) -> float:
    return x + (FRONT if x < CUT else BACK)


def chunks(b, off, end):
    while off + 12 <= end:
        t, s, _ = struct.unpack_from("<III", b, off)
        yield t, off + 12, off + 12 + s
        off += 12 + s


def stretch_dff(src: bytes) -> bytes:
    """Every geometry's morph target vertices moved by moved(x), its bounding sphere widened to match."""
    b = bytearray(src)
    done = 0

    def walk(off, end):
        nonlocal done
        for t, s, e in chunks(b, off, end):
            if t in (0x10, 0x1A):  # clump, geometry list
                walk(s, e)
            elif t == 0x0F:
                _, p, _ = next(chunks(b, s, e))  # the geometry's struct
                flags, uvs, native, tris, verts, morphs = struct.unpack_from("<HBBIII", b, p)
                assert not native, "native geometry not handled"
                uvs = uvs or (2 if flags & 0x80 else 1 if flags & 0x04 else 0)
                p += 16 + (verts * 4 if flags & 0x08 else 0) + uvs * verts * 8 + tris * 8
                for _ in range(morphs):
                    cx, cy, cz, r = struct.unpack_from("<4f", b, p)
                    struct.pack_into("<4f", b, p, cx + (FRONT + BACK) / 2, cy, cz, r + max(-FRONT, BACK))
                    has_verts, has_normals = struct.unpack_from("<II", b, p + 16)
                    p += 24
                    if has_verts:
                        for i in range(verts):
                            x = struct.unpack_from("<f", b, p + i * 12)[0]
                            struct.pack_into("<f", b, p + i * 12, moved(x))
                        p += verts * 12
                    if has_normals:  # a move along x keeps every face's plane facing the same way
                        p += verts * 12
                done += 1

    walk(0, len(b))
    assert done, "no geometry"
    return bytes(b)


def stretch_col(chunk: bytes, name: str) -> bytes:
    """A COL2/COL3 chunk with every x moved by moved(x) (vertices in 1/128 m steps), as tools/repivot_defences.py moves one."""
    c = bytearray(chunk)
    version = c[:4]
    assert version in (b"COL2", b"COL3"), f"{name}: {version!r} not handled"
    c[8:30] = name.encode("ascii").ljust(22, b"\0")[:22]

    def move(off):
        x = struct.unpack_from("<f", c, off)[0]
        struct.pack_into("<f", c, off, moved(x))

    def move_verts(at, count):
        for i in range(count):
            vx = struct.unpack_from("<h", c, at + i * 6)[0]
            struct.pack_into("<h", c, at + i * 6, round(moved(vx / 128) * 128))

    def faces_max(at, count):
        top = -1
        for i in range(count):
            top = max(top, *struct.unpack_from("<3H", c, at + i * 8))
        return top + 1

    move(32)  # bounds min
    move(44)  # bounds max
    lo, hi = struct.unpack_from("<f", c, 32)[0], struct.unpack_from("<f", c, 44)[0]
    r = struct.unpack_from("<f", c, 68)[0]
    struct.pack_into("<f", c, 56, (lo + hi) / 2)  # bounding sphere centre x
    struct.pack_into("<f", c, 68, r + max(-FRONT, BACK))
    spheres, boxes, faces = struct.unpack_from("<3H", c, 72)
    flags, sphere_at, box_at, _lines_at, verts_at, faces_at = struct.unpack_from("<6I", c, 80)
    for i in range(spheres):
        move(sphere_at + 4 + i * 20)
    for i in range(boxes):
        move(box_at + 4 + i * 28)
        move(box_at + 4 + i * 28 + 12)
    if faces:
        move_verts(verts_at + 4, faces_max(faces_at + 4, faces))
        if flags & 8:  # face groups: a count just before the faces, the groups before it
            groups = struct.unpack_from("<I", c, faces_at)[0]
            for i in range(groups):
                at = faces_at - groups * 28 + i * 28
                move(at)
                move(at + 12)
    if version == b"COL3":
        shadow_faces, shadow_verts_at, shadow_faces_at = struct.unpack_from("<3I", c, 108)
        if shadow_faces:
            move_verts(shadow_verts_at + 4, faces_max(shadow_faces_at + 4, shadow_faces))
    return bytes(c)


def render_models() -> str:
    lines = [
        "-- Generated by tools/stretch_house_shells.py; do not edit. Port model id -> a SA-MP house shell stretched to",
        "-- the plot of a deeper vanilla house, in samp_models/files/, loaded like manifest.lua's.",
        "return {",
    ]
    for s in SHELLS:
        tex = f'txdModel = {s["txdModel"]}' if "txdModel" in s else f'txd = "{s["txd"]}"'
        lines.append(f'    [{s["model"]}] = {{ dff = "{s["name"]}", {tex}, dist = {s["dist"]} }},')
    return "\n".join(lines + ["}", ""])


def render_maps() -> str:
    lines = [
        "-- Generated by tools/stretch_house_shells.py: SA-MP house shells stretched along x in their frame (in front of",
        "-- cut by front, behind it by back), each standing where upstream put its base shell. The maps derive a",
        "-- stretched shell's doors and glazed openings from its base's (shared/logic/placement.lua stretchShells).",
        "return {",
    ]
    for s in SHELLS:
        lines.append(f'    [{s["model"]}] = {{ base = {s["base"]}, cut = {CUT}, front = {FRONT}, back = {BACK} }},')
    return "\n".join(lines + ["}", ""])


def main() -> int:
    for s in SHELLS:
        dff = stretch_dff((FILES / f"{s['src']}.dff").read_bytes())
        col = stretch_col((FILES / f"{s['src']}.col").read_bytes(), s["name"])
        (FILES / f"{s['name']}.dff").write_bytes(dff)
        (FILES / f"{s['name']}.col").write_bytes(col)
        print(f"stretch_house_shells: {s['src']} -> {s['name']} ({s['model']})")
    (MODELS / "stretched.lua").write_text(render_models(), encoding="ascii", newline="\n")
    MAPS_LUA.write_text(render_maps(), encoding="ascii", newline="\n")
    write_meta(MODELS)
    return 0


if __name__ == "__main__":
    sys.exit(main())
