"""Give SA-MP's bucket01 (19468) an inside that survives backface culling in MTA.

The original has 16 outward-facing wall triangles and eight downward-facing bottom
triangles, with no interior. Viewed from above it looks like a torn sheet. The TXD,
COL, pivot and exterior are correct; add an inset interior with inverted normals,
the same UVs and a narrow top rim. A 1 mm wall avoids coplanar backfaces/depth
artifacts. DragonFF writes both the geometry and BinMesh indices.

    python -m tools.repair_samp_bucket PATH/TO/SAMP.img [--dragonff ADDON_DIR]

The input may also be an extracted original bucket01.dff. Repaired inputs are
rejected. tools.extract_samp_models keeps existing pack files, so it preserves
this repair. Rebuild it with this command after extracting into an empty pack.
"""
from __future__ import annotations

import argparse
import math
import struct
import sys
from pathlib import Path

from tools.extract_samp_models import SAMP_MODELS, read_img_entry, read_img_index


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source", type=Path, help="original SAMP.img or bucket01.dff")
    ap.add_argument("--dragonff", type=Path, help="DragonFF addon directory containing gtaLib/")
    ap.add_argument("--out", type=Path, default=SAMP_MODELS / "files" / "bucket01.dff")
    args = ap.parse_args()
    if args.dragonff is None:
        from tools.render_map import find_dragonff

        args.dragonff = find_dragonff()
    if args.dragonff is None or not (args.dragonff / "gtaLib" / "dff.py").is_file():
        ap.error("DragonFF not found; pass --dragonff ADDON_DIR")
    sys.path.insert(0, str(args.dragonff))
    from gtaLib.dff import Triangle, Vector, dff

    if args.source.suffix.lower() == ".img":
        data = read_img_entry(args.source, read_img_index(args.source)["bucket01.dff"])
    else:
        data = args.source.read_bytes()
    model = dff()
    model.load_memory(data)
    if len(model.clumps) != 1 or len(model.clumps[0].geometry_list) != 1:
        ap.error("expected bucket01's single clump and geometry")
    clump = model.clumps[0]
    geo = clump.geometry_list[0]
    if len(clump.frame_list) != 1 or clump.frame_list[0].name != "bucket01":
        ap.error("expected bucket01's original frame")
    count = len(geo.vertices)
    if (count, len(geo.triangles)) == (98, 64):
        ap.error("input is already repaired; use the original SA-MP asset to rebuild")
    if (count, len(geo.triangles)) != (41, 24) or len(geo.normals) != count:
        ap.error("expected the original bucket01's 41 vertices, normals and 24 triangles")
    if geo.extensions.get("mat_split") != geo.triangles:
        ap.error("original geometry and BinMesh disagree")

    thickness = 0.001
    bottom = min(v.z for v in geo.vertices)
    top = max(v.z for v in geo.vertices)
    exterior = geo.vertices[:]
    for v in exterior:
        radius = math.hypot(v.x, v.y)
        scale = (radius - thickness) / radius if radius else 1.0
        z = v.z + thickness if v.z == bottom else v.z
        # RenderWare stores float32 coordinates; quantize before round-trip checks.
        geo.vertices.append(Vector(*struct.unpack("<3f", struct.pack("<3f", v.x * scale, v.y * scale, z))))
    geo.normals += [Vector(-n.x, -n.y, -n.z) for n in geo.normals]
    for layer in geo.uv_layers:
        layer += layer[:]
    geo.prelit_colors += geo.prelit_colors[:]
    geo.triangles += [
        Triangle(t.a + count, t.b + count, t.material, t.c + count)
        for t in geo.triangles
    ]
    # Separate rim vertices keep its upward normals independent of the walls.
    ring = {v: i for i, v in enumerate(exterior) if v.z == top}
    ring = sorted(ring.values(), key=lambda i: math.atan2(exterior[i].y, exterior[i].x))
    if len(ring) != 8:
        ap.error("expected bucket01's octagonal opening")
    start = len(geo.vertices)
    for i in ring:
        for source in (i, i + count):
            geo.vertices.append(geo.vertices[source])
            geo.normals.append(Vector(0.0, 0.0, 1.0))
            for layer in geo.uv_layers:
                layer.append(layer[source])
            if geo.prelit_colors:
                geo.prelit_colors.append(geo.prelit_colors[source])
    for i in range(8):
        a, b = start + 2 * i, start + 2 * ((i + 1) % 8)
        geo.triangles += [Triangle(b, a, 0, b + 1), Triangle(b + 1, a, 0, a + 1)]
    # An import-only list, not a serializable plugin. DragonFF regenerates BinMesh
    # from all 64 triangles, so the engine sees the interior as well as the exterior.
    del geo.extensions["mat_split"]
    output = model.write_memory(model.rw_version)
    check = dff()
    check.load_memory(output)
    rebuilt = check.clumps[0].geometry_list[0]
    if not (
        rebuilt.vertices == geo.vertices
        and rebuilt.normals == geo.normals
        and rebuilt.uv_layers == geo.uv_layers
        and rebuilt.triangles == geo.triangles == rebuilt.extensions["mat_split"]
    ):
        raise ValueError("DragonFF round-trip changed the rebuilt bucket geometry")
    args.out.write_bytes(output)
    print(f"Rebuilt {args.out}: 98 vertices, 64 triangles; TXD and COL unchanged")


if __name__ == "__main__":
    main()
