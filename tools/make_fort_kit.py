"""The fort kit: scrap-metal set pieces (port models 20301+) the forts are rebuilt from, in place of upstream's stock props.

Upstream's Fort Defiance (LS/Fort Defiance.map) is a pile of stock GTA props that poke through the Rockstar houses
around Grove Street (tools/fort_survey.py measures it). The kit replaces them with walls, a gate, a watchtower, a lean-to
and a barricade that are built to fit: boxes of corrugated sheet, dark steel and planks, one shared texture dictionary,
dim day/night prelight and a collision box per solid part.

    python -m tools.make_fort_kit [--gta DIR] [--blender EXE]
    python -m tools.make_fort_kit --ariane <the Ariane game copy>   # pack the built kit for the editor

Outside Blender it writes models/files/fort_kit.txd (the five textures cut out of the vanilla dictionaries and merged)
and models/fort.lua, then runs itself in Blender (DragonFF) for one <piece>.dff and <piece>.col per piece, checks that
each COL model is named like its piece (GTA binds a COL to its model by name) and refreshes models/meta.xml.
"""
from __future__ import annotations

import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODELS = ROOT / "resources" / "[scavengesurvive]" / "models"
FILES = MODELS / "files"
FORT = MODELS / "fort.lua"
FORT_MODEL_MIN = 20301  # 200xx hats, 201xx doors, 202xx props, 203xx forts
TXD_NAME, PARENT, DIST = "fort_kit", 3406, 150  # PARENT: a static vanilla prop whose object.dat group the kit borrows
DAY, NIGHT = 0.5, (0.14, 0.14, 0.17, 1.0)

# kit texture -> (archive in the game's models folder, vanilla TXD in it, texture metres per repeat)
TEXTURES = {
    "ws_corrugated1": ("gta3.img", "des_ranch", 2.0),  # sheet metal: walls, roofs
    "was_scrpyd_rustmetal": ("gta3.img", "cw_junkyarddigcs_t", 2.0),  # steel: posts, rails, base
    "planks01": ("gta3.img", "woodpanels", 1.5),  # planks: caps, back walls
    "rustybolts": ("gta3.img", "station", 1.0),  # bolted steel: gate leaves, platform
    "cj_canvas2": ("gta_int.img", "cj_ammo", 1.0),  # canvas: sandbags
}
SHEET, STEEL, PLANK, BOLT, CANVAS = list(TEXTURES)
DARKEN = {STEEL: 0.55}  # the rust plate is bright orange as painted; scrap steel reads darker

# a part is (cx, cy, cz, sx, sy, sz, texture[, pitch degrees about the x axis, + raises the +y side])

def posts(xs, ys, z0, z1, size, tex=STEEL) -> list[tuple]:
    return [(x, y, (z0 + z1) / 2, size, size, z1 - z0, tex) for x in xs for y in ys]


def wall(length: float) -> tuple[list[tuple], list[tuple]]:
    half = length / 2
    seam = length / 4
    sheets = [(-seam, 0.0, 1.45, half, 0.05, 2.9, SHEET), (seam, 0.04, 1.3, half, 0.05, 2.6, SHEET)]
    parts = sheets + posts([-half + 0.1, half - 0.1] + ([0.0] if length > 3 else []), [-0.1], 0.0, 3.05, 0.14)
    parts += [(0.0, 0.0, 0.1, length, 0.3, 0.2, STEEL), (0.0, -0.08, 3.0, length, 0.2, 0.08, PLANK)]
    return parts, [(0.0, 0.0, 1.5, length, 0.3, 3.0)]


def corner() -> tuple[list[tuple], list[tuple]]:
    parts = [(0.0, 0.0, 1.6, 0.4, 0.4, 3.2, STEEL), (0.0, 0.0, 3.25, 0.5, 0.5, 0.1, PLANK)]
    parts += [(0.5, 0.0, 1.4, 0.6, 0.05, 2.8, SHEET), (0.0, -0.5, 1.4, 0.05, 0.6, 2.8, SHEET)]
    return parts, [(0.0, 0.0, 1.6, 0.4, 0.4, 3.2), (0.5, 0.0, 1.4, 0.6, 0.12, 2.8), (0.0, -0.5, 1.4, 0.12, 0.6, 2.8)]


def gate(closed: bool) -> tuple[list[tuple], list[tuple]]:
    parts = posts([-2.1, 2.1], [0.0], 0.0, 3.6, 0.4) + [(0.0, 0.0, 3.5, 4.6, 0.3, 0.3, PLANK)]
    parts += [(-2.1, 0.0, 3.7, 0.5, 0.5, 0.1, PLANK), (2.1, 0.0, 3.7, 0.5, 0.5, 0.1, PLANK)]
    cols = [(-2.1, 0.0, 1.8, 0.4, 0.4, 3.6), (2.1, 0.0, 1.8, 0.4, 0.4, 3.6), (0.0, 0.0, 3.5, 4.6, 0.3, 0.3)]
    if closed:  # a bolted leaf across the opening, a brace and its rail
        parts += [(0.0, 0.2, 1.4, 3.8, 0.1, 2.6, BOLT), (0.0, 0.28, 1.4, 3.8, 0.06, 0.2, STEEL), (0.0, 0.2, 0.1, 4.0, 0.12, 0.2, STEEL)]
        cols.append((0.0, 0.2, 1.4, 3.8, 0.12, 2.6))
    else:  # the leaf slid back and folded against the left post
        parts += [(-1.4, 0.3, 1.4, 1.2, 0.1, 2.6, BOLT), (-1.4, 0.38, 1.4, 1.2, 0.06, 0.2, STEEL), (0.0, 0.2, 0.05, 4.0, 0.12, 0.1, STEEL)]
        cols.append((-1.4, 0.3, 1.4, 1.2, 0.12, 2.6))
    return parts, cols


def tower() -> tuple[list[tuple], list[tuple]]:
    parts = posts([-1.4, 1.4], [-1.4, 1.4], 0.0, 6.2, 0.25)
    parts += [(0.0, 0.0, 4.075, 3.1, 3.1, 0.15, PLANK), (0.0, 0.0, 6.3, 3.5, 3.5, 0.08, SHEET, 6.0)]
    parts += [(0.0, 1.5, 4.65, 3.0, 0.05, 1.0, SHEET), (-1.5, 0.0, 4.65, 0.05, 3.0, 1.0, SHEET), (1.5, 0.0, 4.65, 0.05, 3.0, 1.0, SHEET)]
    parts += [(-0.95, -1.5, 4.65, 1.1, 0.05, 1.0, SHEET), (0.95, -1.5, 4.65, 1.1, 0.05, 1.0, SHEET)]
    parts += [(-0.25, -1.55, 2.2, 0.06, 0.06, 4.4, STEEL), (0.25, -1.55, 2.2, 0.06, 0.06, 4.4, STEEL)]
    parts += [(0.0, -1.55, 0.3 + 0.3 * i, 0.5, 0.05, 0.05, STEEL) for i in range(14)]
    cols = [(x, y, 3.1, 0.25, 0.25, 6.2) for x in (-1.4, 1.4) for y in (-1.4, 1.4)]
    cols += [(0.0, 0.0, 4.075, 3.1, 3.1, 0.15), (0.0, 0.0, 6.3, 3.5, 3.5, 0.08)]
    cols += [(0.0, 1.5, 4.65, 3.0, 0.1, 1.0), (-1.5, 0.0, 4.65, 0.1, 3.0, 1.0), (1.5, 0.0, 4.65, 0.1, 3.0, 1.0)]
    cols += [(-0.95, -1.5, 4.65, 1.1, 0.1, 1.0), (0.95, -1.5, 4.65, 1.1, 0.1, 1.0), (0.0, -1.55, 2.2, 0.55, 0.1, 4.4)]
    return parts, cols


def leanto() -> tuple[list[tuple], list[tuple]]:
    parts = posts([-2.9, 0.0, 2.9], [1.9], 0.0, 3.2, 0.2) + posts([-2.9, 0.0, 2.9], [-1.9], 0.0, 2.6, 0.2)
    parts += [(0.0, 0.0, 2.9, 6.4, 4.4, 0.08, SHEET, 8.5), (0.0, 1.95, 1.3, 6.0, 0.1, 2.6, PLANK)]
    parts += [(0.0, 0.0, 0.08, 6.0, 3.6, 0.16, STEEL)]
    cols = [(x, 1.9, 1.6, 0.2, 0.2, 3.2) for x in (-2.9, 0.0, 2.9)] + [(x, -1.9, 1.3, 0.2, 0.2, 2.6) for x in (-2.9, 0.0, 2.9)]
    cols += [(0.0, 0.0, 2.9, 6.4, 4.4, 0.1), (0.0, 1.95, 1.3, 6.0, 0.15, 2.6)]
    return parts, cols


def barricade() -> tuple[list[tuple], list[tuple]]:
    parts = []
    for row, count in enumerate((3, 2, 3)):
        z = 0.15 + 0.3 * row
        step = 1.0
        x0 = -step * (count - 1) / 2
        parts += [(x0 + step * i, 0.1 if (i + row) % 2 else -0.1, z, 0.95, 0.5, 0.3, CANVAS) for i in range(count)]
    return parts, [(0.0, 0.0, 0.45, 3.0, 0.7, 0.9)]


PIECES = {
    "fort_wall4": lambda: wall(4.0),
    "fort_wall2": lambda: wall(2.0),
    "fort_corner": corner,
    "fort_gate": lambda: gate(False),
    "fort_gate_closed": lambda: gate(True),
    "fort_tower": tower,
    "fort_leanto": leanto,
    "fort_barricade": barricade,
}


sys.path.insert(0, str(ROOT))  # Blender runs this file by path
from tools import fort_walkways  # noqa: E402

PIECES.update({name: (lambda name=name: fort_walkways.piece(name)) for name in fort_walkways.SPANS})  # one model per walkway span


def model_ids() -> dict[str, int]:
    return {name: FORT_MODEL_MIN + i for i, name in enumerate(PIECES)}


def render_fort() -> str:
    lines = [
        "-- Generated by tools/make_fort_kit.py; do not edit. Port model id -> a piece of the fort kit the maps build the",
        "-- forts from (models/files/: its own DFF and COL, the shared fort_kit TXD).",
        "return {",
    ]
    lines += [f'    [{i}] = {{ dff = "{n}", txd = "{TXD_NAME}", dist = {DIST}, parent = {PARENT} }},' for n, i in model_ids().items()]
    return "\n".join(lines + ["}", ""])


def txd_natives(data: bytes) -> tuple[int, int, list[bytes]]:
    """(version, device, texture native chunks) of a TXD."""
    _kind, size, version = struct.unpack_from("<III", data, 0)
    pos, end, natives, device = 12, 12 + size, [], 0
    while pos < end:
        kind, csize, _v = struct.unpack_from("<III", data, pos)
        if kind == 0x01:
            device = struct.unpack_from("<H", data, pos + 14)[0]
        elif kind == 0x15:
            natives.append(data[pos : pos + 12 + csize])
        pos += 12 + csize
    return version, device, natives


def merge_txd(parts: list[bytes]) -> bytes:
    """One texture dictionary holding every texture of `parts` (already trimmed dictionaries)."""
    version, device, natives = 0, 0, []
    for data in parts:
        version, device, chunks = txd_natives(data)
        natives += chunks
    body = struct.pack("<IIIHH", 0x01, 4, version, len(natives), device) + b"".join(natives)
    body += struct.pack("<III", 0x03, 0, version)
    return struct.pack("<III", 0x16, len(body), version) + body


def build_txd(img: Path) -> bytes:
    from tools.extract_samp_models import read_img_entry, read_img_index, trim_txd

    by_txd: dict[tuple[str, str], set[str]] = {}
    for texture, (archive, txd, _scale) in TEXTURES.items():
        by_txd.setdefault((archive, txd), set()).add(texture)
    parts = []
    for (archive, txd), keep in by_txd.items():
        path = img.parent / archive
        parts.append(trim_txd(read_img_entry(path, read_img_index(path)[txd + ".txd"]), keep))
    return merge_txd(parts)


def build_in_blender(out_dir: Path) -> None:
    import bmesh
    import bpy
    from math import radians

    from mathutils import Matrix, Vector

    def rect(bm, uv, day, night, material, verts, size_u, size_v, tex_scale, shade):
        face = bm.faces.new([bm.verts.new(v) for v in verts])
        face.material_index = material
        uvs = [(0.0, 0.0), (size_u / tex_scale, 0.0), (size_u / tex_scale, size_v / tex_scale), (0.0, size_v / tex_scale)]
        for loop, coord in zip(face.loops, uvs):
            loop[uv].uv = coord
            loop[day] = (DAY * shade, DAY * shade, DAY * shade, 1.0)
            loop[night] = (NIGHT[0] * shade, NIGHT[1] * shade, NIGHT[2] * shade, 1.0)

    def add_box(bm, layers, material, scale, part, shade):
        cx, cy, cz, sx, sy, sz = part[:6]
        pitch = part[7] if len(part) > 7 else 0.0
        x0, x1, y0, y1, z0, z1 = -sx / 2, sx / 2, -sy / 2, sy / 2, -sz / 2, sz / 2
        turn, centre = Matrix.Rotation(radians(pitch), 3, "X"), Vector((cx, cy, cz))
        faces = [
            ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], sy, sz),
            ([(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)], sy, sz),
            ([(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], sx, sz),
            ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], sx, sz),
            ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], sx, sy),
        ]
        if cz - sz / 2 > 0.02:
            faces.append(([(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)], sx, sy))
        for verts, su, sv in faces:
            rect(bm, *layers, material, [tuple(turn @ Vector(v) + centre) for v in verts], su, sv, scale, shade)

    def build(name: str, parts: list[tuple], cols: list[tuple]) -> None:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        model = bpy.data.collections.new(name)
        bpy.context.scene.collection.children.link(model)
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        layers = (bm.loops.layers.uv.new("UVMap"), bm.loops.layers.color.new("Day"), bm.loops.layers.color.new("Night"))
        for texture in TEXTURES:
            image = bpy.data.images.new(texture + ".png", 8, 8)  # DragonFF writes the name; the pixels are the TXD's
            material = bpy.data.materials.new(texture)
            material.use_nodes = True
            bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            node = material.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            material.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            mesh.materials.append(material)
        order = list(TEXTURES)
        for n, part in enumerate(parts):
            add_box(bm, layers, order.index(part[6]), TEXTURES[part[6]][2], part, DARKEN.get(part[6], 1.0) * (0.9 + 0.1 * ((n * 7) % 3)))
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(name, mesh)
        obj.dff.type = "OBJ"
        obj.dff.day_cols = True
        obj.dff.night_cols = True
        model.objects.link(obj)
        for i, (cx, cy, cz, sx, sy, sz) in enumerate(cols):
            box = bpy.data.objects.new(f"{name}_col{i}", None)
            box.empty_display_type = "CUBE"
            box.location = (cx, cy, cz)
            box.scale = (sx / 2, sy / 2, sz / 2)
            box.dff.type = "COL"
            model.objects.link(box)
        dff_path, col_path = out_dir / f"{name}.dff", out_dir / f"{name}.col"
        bpy.ops.export_dff.scene(filepath=str(dff_path), export_coll=False, only_selected=False, export_version="0x36003")
        bpy.ops.export_col.scene(filepath=str(col_path), export_version="3", only_selected=False)
        print(f"make_fort_kit: wrote {dff_path.name} and {col_path.name} ({len(parts)} parts, {len(cols)} collision boxes)")

    for name, make in PIECES.items():
        parts, cols = make()
        build(name, parts, cols)


def check_cols(out_dir: Path) -> list[str]:
    """Problems with the exported COL files: GTA binds a COL to its model by name, so each must hold its piece's name."""
    from tools.model_bounds import col_models

    problems = []
    for name in PIECES:
        path = out_dir / f"{name}.col"
        models = col_models(path.read_bytes()) if path.is_file() else {}
        if list(models) != [name]:
            problems.append(f"{name}.col holds {sorted(models) or 'nothing'}")
    return problems


IMG_TOOL = Path("C:/dev/gta/sa/samp-house-shells/tools/img.py")


def pack_ariane(game: Path) -> None:
    """Puts the kit into the Ariane game copy: SAMP/custom.img (DFF, COL and the TXD) and SAMP/CUSTOM.ide, the empty
    slots gta.dat already loads, so the editor and tools/make_ipl.py know the ids."""
    import subprocess

    files = [str(FILES / f"{n}.{ext}") for n in PIECES for ext in ("dff", "col")] + [str(FILES / f"{TXD_NAME}.txd")]
    subprocess.run([sys.executable, "-I", str(IMG_TOOL), "build", str(game / "SAMP" / "custom.img"), *files], check=True)
    lines = ["objs"] + [f"{i}, {n}, {TXD_NAME}, {DIST}, 0" for n, i in model_ids().items()] + ["end", ""]
    text = "\r\n".join(lines)
    (game / "SAMP" / "CUSTOM.ide").write_text(text, encoding="ascii", newline="")
    print(f"make_fort_kit: packed {len(PIECES)} pieces into {game / 'SAMP'} (restart Ariane)")


def main(argv=None) -> int:
    import argparse
    import subprocess

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta, write_meta

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender.exe (default: BLENDER or the newest install)")
    ap.add_argument("--ariane", type=Path, help="Ariane game copy to pack the built kit into (skips the build)")
    args = ap.parse_args(argv)
    if args.ariane:
        pack_ariane(args.ariane)
        return 0
    gta = args.gta or detect_gta()
    img = gta / "models" / "gta3.img" if gta else None
    if not img or not img.is_file():
        print("make_fort_kit: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    blender = find_blender(args.blender)
    if not blender:
        print("make_fort_kit: no Blender found (pass --blender)", file=sys.stderr)
        return 2
    (FILES / f"{TXD_NAME}.txd").write_bytes(build_txd(img))
    FORT.write_text(render_fort(), encoding="ascii", newline="\n")
    cmd = [str(blender), "-b", "--python", __file__, "--", str(FILES)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    print("\n".join(line for line in out.splitlines() if "make_fort_kit" in line or "Error" in line))
    problems = check_cols(FILES)
    for p in problems:
        print(f"make_fort_kit: {p}", file=sys.stderr)
    write_meta(MODELS)
    return 0 if res.returncode == 0 and not problems else 1


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        build_in_blender(Path(sys.argv[sys.argv.index("--") + 1]))
    else:
        sys.exit(main())
