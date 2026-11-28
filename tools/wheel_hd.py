"""Build the wheel dictionaries from the reviewed, UV-compatible PNGs in data/wheel_hd.

    python -m tools.wheel_hd build
    python -m tools.wheel_hd audit
    python -m tools.wheel_hd render --phase before --output DIR
    python -m tools.wheel_hd render --phase after --output DIR
    python -m tools.wheel_hd compare --output DIR

The dictionaries are wheel.txd (the generic Wheel), stock_wheels.txd (the ten stock styles) and
special_wheels.txd (the five special vehicle wheels). Rendering imports the actual DFFs and TXDs with DragonFF
in background Blender. Both
phases use identical framing and shading; compare joins the saved renders. Run the
before phase before replacing the dictionaries. No item, registration or collision
files are written. Source provenance and repaint instructions live beside the PNGs.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
from pathlib import Path
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / "resources" / "[scavengesurvive]" / "prop_models" / "files"
SOURCE = ROOT / "tools" / "data" / "wheel_hd"
DEFAULT_OUTPUT = Path(os.environ.get("TEMP", "/tmp")) / "codex_tyres"
STYLES = ("smallcar", "offroad", "truck", "rim", "alloy", "lightvan", "lighttruck", "classic", "saloon", "sport")
SPECIAL_STYLES = ("heavy", "monster", "tractor", "kart", "racing")
ASSETS = ["wheel"] + [f"wheel_{s}{suffix}" for styles in (STYLES, SPECIAL_STYLES)
                      for suffix in ("", "_flat") for s in styles]
SIZES = {
    "stock_wheels": {**{f"wheel_{s}64": (256, 256) for s in STYLES if s != "rim"},
                     "whee_rim64": (256, 256), "tyre64a": (256, 256)},
    "wheel": {"vehicletyres128": (256, 512), "vehiclegeneric256": (1024, 1024),
              "vehiclespecdot64": (256, 256)},
    # rendered from the vehicles' own wheels by python -m tools.stock_wheels textures
    "special_wheels": {**{f"wheel_{s}_face": (256, 256) if s == "kart" else (512, 512) for s in SPECIAL_STYLES},
                       **{f"wheel_{s}_tread": (256, 256) for s in SPECIAL_STYLES}},
}


def dictionary_of(asset):
    """The TXD an asset's DFF uses."""
    if asset == "wheel":
        return "wheel"
    style = asset.removeprefix("wheel_").removesuffix("_flat")
    return "special_wheels" if style in SPECIAL_STYLES else "stock_wheels"


def native_dxt1(name, image):
    """D3D9 BC1/565 opaque native, trilinear repeat, full chain through 1x1.

    The last levels still occupy a complete BC1 block. Keeping them avoids the
    incomplete chain of older tools that stopped at 4x4.
    """
    from tools.make_vending import chunk

    image = image.convert("RGB")
    w, h = image.size
    levels = []
    while True:
        buf = io.BytesIO()
        image.save(buf, "DDS", pixel_format="DXT1")
        dds = buf.getvalue()
        assert dds[:4] == b"DDS " and dds[84:88] == b"DXT1"
        payload = dds[128:]
        assert len(payload) == max(1, (image.width + 3) // 4) * max(1, (image.height + 3) // 4) * 8
        levels.append(payload)
        if image.size == (1, 1):
            break
        from PIL import Image

        image = image.resize((max(1, image.width // 2), max(1, image.height // 2)), Image.Resampling.LANCZOS)
    head = struct.pack("<II", 9, 0x1106)
    head += name.encode("ascii").ljust(32, b"\0") + bytes(32)
    head += struct.pack("<I4sHHBBBB", 0x8200, b"DXT1", w, h, 16, len(levels), 4, 8)
    head += b"".join(struct.pack("<I", len(level)) + level for level in levels)
    return chunk(0x15, chunk(1, head) + chunk(3, b""))


def build(only=None):
    from PIL import Image
    from tools.make_vending import write_txd

    for dictionary, expected in SIZES.items():
        if only and dictionary != only:
            continue
        actual = {p.stem for p in (SOURCE / dictionary).glob("*.png")}
        if actual != set(expected):
            raise ValueError(f"{dictionary}: missing/extra PNGs: {set(expected) ^ actual}")
        natives = []
        for name, size in expected.items():
            with Image.open(SOURCE / dictionary / f"{name}.png") as image:
                if image.size != size:
                    raise ValueError(f"{name}: expected {size}, got {image.size}")
                if image.convert("RGBA").getextrema()[3] != (255, 255):
                    raise ValueError(f"{name}: wheel textures must be opaque")
                natives.append(native_dxt1(name, image))
        write_txd(FILES / f"{dictionary}.txd", natives)
    audit(only)


def audit(only=None):
    from PIL import Image
    from tools.extract_samp_models import txd_natives

    template = io.BytesIO()
    Image.new("RGB", (4, 4)).save(template, "DDS", pixel_format="DXT1")
    dds_header = template.getvalue()[:128]
    for dictionary, expected in SIZES.items():
        if only and dictionary != only:
            continue
        path = FILES / f"{dictionary}.txd"
        assert path.stat().st_size < 1_500_000, f"{path.name} exceeds texture budget"
        _, _, natives = txd_natives(path.read_bytes())
        assert len(natives) == len(expected)
        names = set()
        for native in natives:
            head = native[24:]
            platform, filtering = struct.unpack_from("<II", head)
            name = head[8:40].split(b"\0")[0].decode("ascii")
            w, h, depth, count, raster_type, flags = struct.unpack_from("<HHBBBB", head, 80)
            assert platform == 9 and filtering == 0x1106 and head[76:80] == b"DXT1"
            assert (w, h) == expected[name] and depth == 16 and raster_type == 4 and flags == 8
            assert count == int(math.log2(max(w, h))) + 1
            pos = 88
            for level in range(count):
                size = struct.unpack_from("<I", head, pos)[0]
                assert size == max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 8
                # Decode every stored level independently, including sub-block sizes.
                # DragonFF's BC1 reader overruns its RGBA buffer below four pixels wide.
                header = bytearray(dds_header)
                struct.pack_into("<III", header, 12, h, w, size)
                decoded = Image.open(io.BytesIO(header + head[pos + 4:pos + 4 + size])).convert("RGBA")
                assert decoded.size == (w, h) and decoded.getextrema()[3] == (255, 255)
                pos += 4 + size
                w, h = max(1, w // 2), max(1, h // 2)
            assert len(head) == pos + 12  # empty native extension chunk
            names.add(name)
            print(f"{dictionary}/{name}: {expected[name]}, BC1, {count} mip levels")
        assert names == set(expected)
        print(f"{path.name}: {path.stat().st_size:,} bytes")


def render_blender(output, phase, selected, asset_files):
    import bpy
    from mathutils import Matrix, Vector

    # Use an existing DragonFF installation without changing the user's Blender settings.
    addon = os.environ.get("DRAGONFF_PATH")
    if not addon:
        base = Path(os.environ.get("APPDATA", "")) / "Blender Foundation" / "Blender"
        addon = next((str(p) for p in sorted(base.glob("*/scripts/addons/DragonFF"), reverse=True)), None)
    if addon:
        sys.path.insert(0, str(Path(addon).parent))
    bpy.ops.preferences.addon_enable(module="DragonFF")
    from DragonFF.ops import dff_importer, txd_importer

    dest = output / phase
    dest.mkdir(parents=True, exist_ok=True)
    manifest_path = dest / "manifest.json"
    manifest = {row["asset"]: row for row in json.loads(manifest_path.read_text())} if manifest_path.exists() else {}
    for asset in selected:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        scn = bpy.context.scene
        scn.render.engine = "BLENDER_WORKBENCH"
        scn.render.resolution_x = scn.render.resolution_y = 720
        scn.render.resolution_percentage = 100
        scn.render.image_settings.file_format = "PNG"
        scn.render.image_settings.color_mode = "RGB"
        scn.display.shading.light = "STUDIO"
        scn.display.shading.color_type = "TEXTURE"
        scn.display.shading.show_cavity = False
        scn.display.shading.show_shadows = False
        scn.display.shading.show_specular_highlight = False
        scn.display.shading.background_type = "WORLD"
        scn.world = bpy.data.worlds.new("WheelQA")
        scn.world.color = (0.065, 0.07, 0.08)
        scn.view_settings.view_transform = "Standard"
        dictionary = dictionary_of(asset)
        images = txd_importer.import_txd({"file_name": str(asset_files / f"{dictionary}.txd"),
                                          "skip_mipmaps": True, "pack": False}).images
        dff_importer.import_dff({"file_name": str(asset_files / f"{asset}.dff"), "txd_images": images,
                                "image_ext": None, "connect_bones": False, "use_mat_split": True,
                                "remove_doubles": False, "create_backfaces": False,
                                "group_materials": False, "import_normals": True,
                                "materials_naming": "DEFAULT"})
        meshes = [o for o in scn.objects if o.type == "MESH" and o.dff.type != "COL"]
        missing = []
        for obj in meshes:
            for mat in obj.data.materials:
                if not mat or not mat.node_tree:
                    continue
                for node in mat.node_tree.nodes:
                    if node.type == "TEX_IMAGE":
                        if not node.image:
                            missing.append(node.label)
                        node.interpolation = "Linear"
            if asset == "wheel":
                obj.matrix_world = Matrix.Rotation(-math.pi / 2, 4, "Y") @ obj.matrix_world
        if missing:
            raise ValueError(f"{asset}: missing textures {missing}")
        bpy.context.view_layer.update()
        points = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        lo = Vector([min(p[i] for p in points) for i in range(3)])
        hi = Vector([max(p[i] for p in points) for i in range(3)])
        mid = (lo + hi) / 2
        diameter = max(hi.x - lo.x, hi.y - lo.y)
        cam = bpy.data.objects.new("CAM_WheelQA", bpy.data.cameras.new("CAM_WheelQA"))
        scn.collection.objects.link(cam)
        scn.camera = cam
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = diameter * 1.13
        cam.data.clip_start, cam.data.clip_end = 0.001, 100
        # face and tread are three-quarter views from above and from the side, top the face seen straight on
        for view, direction in (("face", (0.65, -0.9, 1.7)), ("tread", (0.65, -1.0, 0.5)), ("top", (0.0, -0.001, 1.0))):
            cam.location = mid + Vector(direction).normalized() * diameter * 3
            cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
            scn.render.filepath = str(dest / f"{asset}_{view}.png")
            bpy.ops.render.render(write_still=True)
        manifest[asset] = {"asset": asset, "dictionary": dictionary, "missing": missing,
                           "blender": bpy.app.version_string,
                           "dff_sha256": hashlib.sha256((asset_files / f"{asset}.dff").read_bytes()).hexdigest(),
                           "txd_sha256": hashlib.sha256((asset_files / f"{dictionary}.txd").read_bytes()).hexdigest(),
                           "triangles": sum(len(p.vertices) - 2 for o in meshes for p in o.data.polygons)}
        print("WHEEL_QA", phase, asset, flush=True)
    manifest_path.write_text(json.dumps(list(manifest.values()), indent=2) + "\n")


def compare(output):
    from PIL import Image, ImageDraw, ImageFont

    font = ImageFont.truetype("arial.ttf", 24)
    for asset in ASSETS:
        sheet = Image.new("RGB", (1440, 1520), (35, 38, 43))
        draw = ImageDraw.Draw(sheet)
        for col, phase in enumerate(("before", "after")):
            for row, view in enumerate(("face", "tread")):
                image = Image.open(output / phase / f"{asset}_{view}.png")
                x, y = col * 720, row * 760
                sheet.paste(image, (x, y + 40))
                draw.text((x + 12, y + 7), f"{asset} | {phase.upper()} | {view}", fill="white", font=font)
        sheet.save(output / f"compare_{asset}.png")
    print(f"{len(ASSETS)} before/after comparisons: {output}")


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("build", "audit", "render", "compare"))
    parser.add_argument("--phase", choices=("before", "after"), default="after")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--assets", help="comma-separated subset for rendering")
    parser.add_argument("--files", type=Path, default=FILES, help="alternate DFF/TXD directory (e.g. saved originals)")
    args = parser.parse_args(argv)
    if args.command == "build":
        build()
    elif args.command == "audit":
        audit()
    elif args.command == "compare":
        compare(args.output)
    elif "bpy" in sys.modules:
        render_blender(args.output, args.phase, args.assets.split(",") if args.assets else ASSETS, args.files)
    else:
        from tools.extract_ped_models import find_blender

        blender = find_blender(None)
        if not blender:
            raise SystemExit("Blender not found; set BLENDER to its executable")
        args.output.mkdir(parents=True, exist_ok=True)
        cmd = [str(blender), "-b", "-t", "4", "--python-exit-code", "1", "--python", str(Path(__file__).resolve()),
               "--", "render", "--phase", args.phase, "--output", str(args.output), "--files", str(args.files)]
        if args.assets:
            cmd += ["--assets", args.assets]
        with (args.output / f"{args.phase}.log").open("w", encoding="utf8") as log:
            result = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT)
        if result.returncode:
            raise SystemExit(f"Blender failed ({result.returncode}); see {args.output / (args.phase + '.log')}")
        print(f"Rendered {args.phase}: {args.output / args.phase}")


if __name__ == "__main__":
    sys.path.insert(0, str(ROOT))
    main(sys.argv[sys.argv.index("--") + 1:] if "bpy" in sys.modules else None)
