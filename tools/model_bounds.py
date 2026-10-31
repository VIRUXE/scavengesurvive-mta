"""Bounding boxes of GTA:SA models read straight from the IMG archives, for tools that measure placements without
Blender (tools/fort_survey.py): the vertices of every geometry in a DFF, and the bounds of every model in a COL library.

    python -m tools.model_bounds <gta dir> <out.json>

Keys are lowercase model (file) names without the extension. Ported from gta-scout's ad-hoc hatch-search scripts.
"""
from __future__ import annotations

import json
import struct
import sys
from pathlib import Path

from tools.extract_samp_models import read_img_entry, read_img_index

Box = tuple[float, float, float, float, float, float]  # min x, y, z, max x, y, z

CLUMP, GEOMETRY_LIST, GEOMETRY = 0x10, 0x1A, 0x0F
COL_MAGICS = (b"COLL", b"COL2", b"COL3", b"COL4")
IMAGES = ("models/gta3.img", "models/gta_int.img", "SAMP/SAMP.img", "SAMP/SAMPCOL.img")


def _struct_box(data: bytes, q: int, version: int) -> Box | None:
    """The vertex bounds of one geometry's struct section, which starts at q."""
    flags, uv_count, native = struct.unpack_from("<HBB", data, q)
    tri_count, vert_count, _morphs = struct.unpack_from("<iii", data, q + 4)
    q += 16
    if version < 0x34000:
        q += 12  # ambient, specular, diffuse of the old lighting model
    if native or not vert_count:
        return None
    if flags & 8:
        q += 4 * vert_count  # prelight
    uvs = uv_count or (2 if flags & 0x80 else 1 if flags & 4 else 0)
    q += 8 * vert_count * uvs + 8 * tri_count
    q += 16  # bounding sphere
    has_vertices = struct.unpack_from("<i", data, q)[0]
    q += 8  # has vertices, has normals
    if not has_vertices:
        return None
    vs = struct.unpack_from(f"<{3 * vert_count}f", data, q)
    return (min(vs[0::3]), min(vs[1::3]), min(vs[2::3]), max(vs[0::3]), max(vs[1::3]), max(vs[2::3]))


def _geometry_boxes(data: bytes, p: int, end: int, out: list[Box]) -> None:
    while p + 12 <= end:
        kind, size, version = struct.unpack_from("<III", data, p)
        body = p + 12
        if kind in (CLUMP, GEOMETRY_LIST):
            _geometry_boxes(data, body, min(end, body + size), out)
        elif kind == GEOMETRY:
            box = _struct_box(data, body + 12, version)
            if box:
                out.append(box)
        if size == 0:
            break
        p = body + size


def union(boxes: list[Box]) -> Box | None:
    if not boxes:
        return None
    lo = [min(b[i] for b in boxes) for i in range(3)]
    hi = [max(b[i] for b in boxes) for i in range(3, 6)]
    return (*lo, *hi)


def dff_box(data: bytes) -> Box | None:
    """The bounds of every vertex of every geometry in a DFF file, or None when it has none we can read."""
    boxes: list[Box] = []
    try:
        _geometry_boxes(data, 0, len(data), boxes)
    except struct.error:
        return None
    return union(boxes)


def col_models(data: bytes) -> dict[str, dict]:
    """Every model in a COL file (one or many concatenated chunks): lowercase name -> {box, has_geom}."""
    out = {}
    p = 0
    while p + 72 <= len(data) and data[p : p + 4] in COL_MAGICS:
        size = struct.unpack_from("<I", data, p + 4)[0]
        name = data[p + 8 : p + 30].split(b"\0")[0].decode("latin1").lower()
        if data[p : p + 4] == b"COLL":
            _r, _cx, _cy, _cz, x0, y0, z0, x1, y1, z1 = struct.unpack_from("<10f", data, p + 32)
            has_geom = size > 64
        else:
            x0, y0, z0, x1, y1, z1, _cx, _cy, _cz, _r = struct.unpack_from("<10f", data, p + 32)
            spheres, boxes, faces = struct.unpack_from("<HHH", data, p + 72)
            has_geom = spheres + boxes + faces > 0
        out[name] = {"box": (x0, y0, z0, x1, y1, z1), "has_geom": has_geom}
        p += 8 + size
    return out


def scan(gta: Path) -> dict[str, dict]:
    """{"dff": {name: box}, "col": {name: {box, has_geom}}} over the game's IMG archives (and SA-MP's when present)."""
    dffs, cols = {}, {}
    for rel in IMAGES:
        img = gta / rel
        if not img.is_file():
            continue
        for entry, where in read_img_index(img).items():
            if entry.endswith(".dff"):
                box = dff_box(read_img_entry(img, where))
                if box:
                    dffs[entry[:-4]] = box
            elif entry.endswith(".col"):
                cols.update(col_models(read_img_entry(img, where)))
    return {"dff": dffs, "col": cols}


def load(gta: Path, cache: Path | None = None) -> dict[str, dict]:
    """scan(), kept in `cache` between runs (the scan reads ~1 GB of archives)."""
    if cache and cache.is_file():
        return json.loads(cache.read_text(encoding="utf-8"))
    bounds = scan(gta)
    if cache:
        cache.parent.mkdir(parents=True, exist_ok=True)
        cache.write_text(json.dumps(bounds), encoding="utf-8")
    return bounds


def main(argv=None) -> int:
    argv = sys.argv[1:] if argv is None else argv
    if len(argv) != 2:
        print(__doc__.split("\n\n")[1].strip(), file=sys.stderr)
        return 2
    bounds = scan(Path(argv[0]))
    Path(argv[1]).write_text(json.dumps(bounds), encoding="utf-8")
    print(f"model_bounds: {len(bounds['dff'])} DFFs, {len(bounds['col'])} COL models")
    return 0


if __name__ == "__main__":
    sys.exit(main())
