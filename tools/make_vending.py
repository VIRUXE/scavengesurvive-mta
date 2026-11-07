"""The snack machine and its snacks for the prop_models resource (ids 20223-20235): every model, collision and TXD.

    python -m tools.make_vending [--gta DIR] [--blender EXE] [--preview DIR] [--spots]

GTA's snack machine (CJ_EXT_CANDY 956 outside, CJ_CANDYVENDOR 1776 in the 24/7s) shows its snacks as one flat 128 px
photo (CJ_SWEETS) behind the glass. The port rebuilds it as a cabinet with depth: five wire trays of four spiral coils
behind a glass pane, the keypad column and delivery flap of the original (its own CJ_S_VENDOR and cj_sheetmetal2), so
the snacks it holds (items, one per coil) can stand in it. The glass is a model of its own, intact or broken.

    snack_machine  20233  the cabinet, 1.2 x 0.8 x 2.2 m, the front facing -Y like the vanilla machine (so a vanilla
                          placement's heading carries over); origin at the base's centre, z = 0 at the floor
    snack_glass    20234  the pane in its frame, see-through
    snack_glass_broken 20235  what is left of the pane once broken: jagged shards around the frame

The snacks lie flat with their label up (+Z) and their top toward +Y, origin at the centre of the base, z = 0 at the
lowest point; in the machine they stand rotated 90 degrees about X so the label faces out (-Y). Their labels are drawn
here (Blender text, Lato Black, GTA-universe brands), worn with noise and creases, except the cookies, which wear the
24/7's own GB_foodwrap03 box. Each SNACKS row is an item type (data/generated/item_types.lua, sql/seed) and its
`half` the half height it stands at in the machine (items/shared/logic/vending.lua SNACKS).

Outside Blender it writes props.lua and meta.xml through tools/make_props.py and runs itself in Blender (DragonFF);
--preview DIR also renders each model to DIR.
"""
from __future__ import annotations

import math
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
FILES = ROOT / "resources" / "[scavengesurvive]" / "prop_models" / "files"

# uname, item name, model id, shape, label (drawn) or vanilla texture, size (m, lying: x across, y top to bottom, z thick)
SNACKS = [
    {"uname": "PhatChips", "name": "Phat Chips", "id": 20223, "shape": "bag", "label": "phatchips", "dims": (0.16, 0.22, 0.05)},
    {"uname": "CheesyPuffs", "name": "Cheesy Puffs", "id": 20224, "shape": "bag", "label": "cheesypuffs", "dims": (0.16, 0.22, 0.05)},
    {"uname": "Pretzels", "name": "Twisted Pretzels", "id": 20225, "shape": "bag", "label": "pretzels", "dims": (0.15, 0.2, 0.045)},
    {"uname": "SaltedPeanuts", "name": "Salted Peanuts", "id": 20226, "shape": "bag", "label": "peanuts", "dims": (0.11, 0.15, 0.035)},
    {"uname": "BeefJerky", "name": "Beef Jerky", "id": 20227, "shape": "bag", "label": "jerky", "dims": (0.12, 0.17, 0.03)},
    {"uname": "MeteoriteBar", "name": "Meteorite Bar", "id": 20228, "shape": "bar", "label": "meteorite", "dims": (0.15, 0.045, 0.02)},
    {"uname": "ZebraBar", "name": "Zebra Bar", "id": 20229, "shape": "bar", "label": "zebrabar", "dims": (0.15, 0.045, 0.02)},
    {"uname": "EgoChaser", "name": "EgoChaser Bar", "id": 20230, "shape": "bar", "label": "egochaser", "dims": (0.14, 0.04, 0.018)},
    {"uname": "FruitCandy", "name": "Fruit Candy", "id": 20231, "shape": "box", "label": "candybox", "dims": (0.12, 0.075, 0.025)},
    {"uname": "Cookies", "name": "Chocolate Chip Cookies", "id": 20232, "shape": "cookies", "label": None, "dims": (0.14, 0.19, 0.04)},
]
MACHINE_ID, GLASS_ID, BROKEN_ID = 20233, 20234, 20235

# the cabinet (metres, machine space: front -Y): window opening, trays and coils; items/shared/logic/vending.lua
# mirrors WINDOW, TRAY_TOPS, COLUMNS and SLOT_Y
W, D, H = 1.2, 0.8, 2.2
WINDOW = (-0.52, 0.24, 0.56, 1.99)  # x0, x1, z0, z1 of the opening the glass fills
GLASS_Y = -0.385
ROWS, COLS = 5, 4
PITCH = (WINDOW[3] - WINDOW[2]) / ROWS
TRAY_TOPS = [round(WINDOW[2] + k * PITCH + 0.02, 4) for k in range(ROWS)]  # bottom tray first
COLUMNS = [round(WINDOW[0] + (WINDOW[1] - WINDOW[0]) / COLS * (c + 0.5), 4) for c in range(COLS)]
SLOT_Y = -0.25  # where the front snack of a coil stands

# label art: background, then rects (x0, y0, x1, y1), circles (x, y, r) and text (x, y, size, font, rotation) on a
# canvas `aspect` wide and 1 high; written into a `px` texture
LABELS = {
    "phatchips": {"aspect": 0.75, "px": (128, 128), "bg": "#f2c21b", "items": [
        ("rect", 0, 0.0, 1, 0.22, "#c8201e"), ("rect", 0, 0.78, 1, 1, "#c8201e"),
        ("circle", 0.5, 0.42, 0.30, "#e9a514"), ("circle", 0.5, 0.42, 0.24, "#f7dc6a"),
        ("text", "PHAT", 0.5, 0.62, 0.20, "black", "#c8201e", -6), ("text", "CHIPS", 0.5, 0.46, 0.17, "black", "#2a1a0a", -6),
        ("text", "ORIGINAL SALTED", 0.5, 0.30, 0.055, "bold", "#2a1a0a", 0), ("text", "FAMILY SIZE", 0.5, 0.86, 0.06, "black", "#ffffff", 0),
        ("text", "100% FAT", 0.5, 0.08, 0.06, "black", "#ffffff", 0)]},
    "cheesypuffs": {"aspect": 0.75, "px": (128, 128), "bg": "#f07a12", "items": [
        ("rect", 0, 0.0, 1, 0.18, "#5a2a8a"), ("rect", 0, 0.82, 1, 1, "#5a2a8a"),
        ("circle", 0.32, 0.36, 0.10, "#ffb52e"), ("circle", 0.52, 0.30, 0.09, "#ffb52e"), ("circle", 0.70, 0.38, 0.10, "#ffb52e"),
        ("text", "CHEESY", 0.5, 0.64, 0.16, "blacki", "#ffe23a", 8), ("text", "PUFFS", 0.5, 0.50, 0.17, "blacki", "#ffffff", 8),
        ("text", "ARTIFICIAL CHEESE FLAVOR", 0.5, 0.07, 0.045, "bold", "#ffffff", 0), ("text", "EXTRA ORANGE", 0.5, 0.88, 0.06, "black", "#ffe23a", 0)]},
    "pretzels": {"aspect": 0.75, "px": (128, 128), "bg": "#1f4fa8", "items": [
        ("rect", 0, 0.70, 1, 0.74, "#ffffff"), ("rect", 0, 0.26, 1, 0.30, "#ffffff"),
        ("circle", 0.5, 0.48, 0.15, "#9a5a1e"), ("circle", 0.5, 0.48, 0.10, "#1f4fa8"),
        ("text", "TWISTED", 0.5, 0.82, 0.12, "black", "#ffffff", 0), ("text", "PRETZELS", 0.5, 0.14, 0.12, "black", "#ffd23a", 0),
        ("text", "SALTED", 0.5, 0.48, 0.06, "black", "#ffffff", 0), ("text", "NET WT 3OZ", 0.5, 0.04, 0.04, "bold", "#ffffff", 0)]},
    "peanuts": {"aspect": 0.75, "px": (128, 128), "bg": "#c51d2a", "items": [
        ("rect", 0, 0.34, 1, 0.66, "#ffffff"),
        ("circle", 0.20, 0.50, 0.08, "#c99a55"), ("circle", 0.80, 0.50, 0.08, "#c99a55"),
        ("text", "SALTED", 0.5, 0.78, 0.13, "black", "#ffffff", 0), ("text", "PEANUTS", 0.5, 0.50, 0.09, "black", "#c51d2a", 0),
        ("text", "ROASTED", 0.5, 0.20, 0.09, "black", "#ffe23a", 0), ("text", "NET WT 1.75OZ", 0.5, 0.06, 0.045, "bold", "#ffffff", 0)]},
    "jerky": {"aspect": 0.75, "px": (128, 128), "bg": "#3b2414", "items": [
        ("rect", 0, 0.40, 1, 0.68, "#d8b880"), ("rect", 0, 0.40, 1, 0.42, "#7a1a10"), ("rect", 0, 0.66, 1, 0.68, "#7a1a10"),
        ("text", "BEEF", 0.5, 0.57, 0.11, "serif", "#7a1a10", 0), ("text", "JERKY", 0.5, 0.45, 0.10, "serif", "#3b2414", 0),
        ("text", "RED COUNTY", 0.5, 0.82, 0.09, "black", "#e0c080", 0), ("text", "ORIGINAL", 0.5, 0.24, 0.07, "black", "#e0c080", 0),
        ("text", "HIGH PROTEIN", 0.5, 0.10, 0.05, "bold", "#ffffff", 0)]},
    "meteorite": {"aspect": 4.0, "px": (128, 32), "bg": "#2a1240", "items": [
        ("circle", 0.86, 0.5, 0.32, "#ff7a1a"), ("circle", 0.86, 0.5, 0.20, "#ffd23a"),
        ("text", "METEORITE", 0.42, 0.50, 0.62, "blacki", "#ffd23a", 6), ("rect", 0, 0, 1, 0.08, "#9a7a2a"), ("rect", 0, 0.92, 1, 1, "#9a7a2a")]},
    "zebrabar": {"aspect": 4.0, "px": (128, 32), "bg": "#f5f5f0", "items": [
        ("rect", 0.04, 0, 0.10, 1, "#111111"), ("rect", 0.16, 0, 0.20, 1, "#111111"), ("rect", 0.80, 0, 0.84, 1, "#111111"),
        ("rect", 0.90, 0, 0.96, 1, "#111111"), ("rect", 0.24, 0.18, 0.76, 0.82, "#111111"),
        ("text", "ZEBRA", 0.5, 0.50, 0.56, "black", "#ffffff", 0)]},
    "egochaser": {"aspect": 4.0, "px": (128, 32), "bg": "#1d7a3a", "items": [
        ("rect", 0, 0.0, 1, 0.28, "#c8d0d0"), ("rect", 0.70, 0, 1, 1, "#c8d0d0"),
        ("text", "EgoChaser", 0.36, 0.58, 0.48, "blacki", "#ffffff", 0), ("text", "ENERGY BAR", 0.36, 0.14, 0.20, "black", "#1d7a3a", 0),
        ("text", "30g", 0.85, 0.50, 0.40, "black", "#1d7a3a", 0)]},
    "candybox": {"aspect": 1.6, "px": (128, 64), "bg": "#e8458c", "items": [
        ("circle", 0.18, 0.30, 0.12, "#ffe23a"), ("circle", 0.30, 0.66, 0.10, "#3ad0ff"), ("circle", 0.84, 0.30, 0.11, "#7aff3a"),
        ("circle", 0.80, 0.72, 0.09, "#ff8a1a"),
        ("text", "P's & Q's", 0.5, 0.52, 0.24, "blacki", "#ffffff", 0), ("text", "FRUIT CANDY", 0.5, 0.20, 0.10, "black", "#5a0a3a", 0)]},
}
FONTS = {
    "black": "/usr/share/fonts/truetype/lato/Lato-Black.ttf",
    "blacki": "/usr/share/fonts/truetype/lato/Lato-BlackItalic.ttf",
    "bold": "/usr/share/fonts/truetype/lato/Lato-Bold.ttf",
    "serif": "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
}

# vanilla textures: (IMG, TXD, texture)
SHEET = ("gta3.img", "cj_ext_vend2.txd", "cj_sheetmetal2")
PANEL = ("gta3.img", "cj_ext_vend2.txd", "CJ_S_VENDOR")
DARK = ("gta_int.img", "cj_ss_1.txd", "CJ_Black_metal")
EDGE = ("gta_int.img", "cj_ss_1.txd", "CJ_7_11_edge")
CHROME = ("gta3.img", "industrialext.txd", "cj_chromepipe")
COOKIES = ("gta_int.img", "gb_foodwrap01.txd", "GB_foodwrap03")


def props_rows() -> list[dict]:
    """props.lua rows for tools/make_props.py render_props."""
    rows = [{"id": s["id"], "name": "snack_" + s["uname"].lower(), "dist": 40} for s in SNACKS]
    rows += [
        {"id": MACHINE_ID, "name": "snack_machine", "dist": 150},
        {"id": GLASS_ID, "name": "snack_glass", "dist": 100},
        {"id": BROKEN_ID, "name": "snack_glass_broken", "dist": 100},
    ]
    return rows


# ---------------------------------------------------------------------------------------------------------- TXD


def chunk(kind: int, body: bytes) -> bytes:
    return struct.pack("<III", kind, len(body), 0x1803FFFF) + body


def native_rgba(name: str, w: int, h: int, bgra: bytes, alpha: bool) -> bytes:
    head = struct.pack("<II", 9, 0x1106)
    head += name.encode()[:31].ljust(32, b"\0") + b"".ljust(32, b"\0")
    head += struct.pack("<II", 0x0500 if alpha else 0x0600, 21 if alpha else 22)
    head += struct.pack("<HHBBBB", w, h, 32, 1, 4, 0x01 if alpha else 0x00)
    head += struct.pack("<I", len(bgra)) + bgra
    return chunk(0x15, chunk(1, head) + chunk(3, b""))


def write_txd(path: Path, natives: list[bytes]) -> None:
    path.write_bytes(chunk(0x16, chunk(1, struct.pack("<HH", len(natives), 0)) + b"".join(natives) + chunk(3, b"")))


# ------------------------------------------------------------------------------------------------------- Blender


def build_in_blender(gta: Path, out: Path, preview: Path | None) -> None:
    import bmesh
    import bpy
    import numpy as np
    from mathutils import Vector

    from tools.extract_samp_models import read_img_entry, read_img_index
    from tools.make_house_window import native_texture

    indexes = {}

    def vanilla(src):
        img, txd, tex = src
        if img not in indexes:
            indexes[img] = read_img_index(gta / "models" / img)
        blob = read_img_entry(gta / "models" / img, indexes[img][txd])
        return native_texture(blob, tex)

    rng = np.random.default_rng(1956)

    def lin(c):
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    def rgb(h):
        h = h.lstrip("#")
        return tuple(lin(int(h[i : i + 2], 16) / 255) for i in (0, 2, 4)) + (1,)

    def reset():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")

    # ---- labels: rendered flat (Workbench, object colours), then worn: noise, blotches, vignette, crease shine
    def render_label(key):
        spec = LABELS[key]
        reset()
        scn = bpy.context.scene
        scn.render.engine = "BLENDER_WORKBENCH"
        sh = scn.display.shading
        sh.light, sh.color_type, sh.show_cavity = "FLAT", "OBJECT", False
        scn.view_settings.view_transform = "Standard"
        fonts = {k: bpy.data.fonts.load(v) for k, v in FONTS.items()}
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        scn.camera = cam
        cam.data.type = "ORTHO"
        a = spec["aspect"]
        bpy.ops.mesh.primitive_plane_add(size=1)
        bg = bpy.context.object
        bg.scale, bg.location, bg.color = (a, 1, 1), (a / 2, 0.5, 0), rgb(spec["bg"])
        z = 0.01
        for it in spec["items"]:
            z += 0.01
            if it[0] == "rect":
                _, x0, y0, x1, y1, c = it
                bpy.ops.mesh.primitive_plane_add(size=1)
                o = bpy.context.object
                o.scale, o.location = ((x1 - x0) * a, y1 - y0, 1), ((x0 + x1) / 2 * a, (y0 + y1) / 2, z)
            elif it[0] == "circle":
                _, x, y, r, c = it
                bpy.ops.mesh.primitive_circle_add(radius=r, fill_type="NGON", vertices=48)
                o = bpy.context.object
                o.location = (x * a, y, z)
            else:
                _, text, x, y, size, font, c, rot = it
                cu = bpy.data.curves.new("t", "FONT")
                cu.body, cu.font, cu.size, cu.align_x, cu.align_y = text, fonts[font], size, "CENTER", "CENTER"
                o = bpy.data.objects.new("t", cu)
                scn.collection.objects.link(o)
                o.location, o.rotation_euler = (x * a, y, z), (0, 0, math.radians(rot))
                bpy.context.view_layer.update()
                if o.dimensions.x > a * 0.94:
                    s = a * 0.94 / o.dimensions.x
                    o.scale = (s, s, 1)
            o.color = rgb(c)
        cam.data.ortho_scale = max(a, 1)
        cam.location = (a / 2, 0.5, 5)
        base = 256
        scn.render.resolution_x, scn.render.resolution_y = (round(base * a), base) if a <= 1 else (base, round(base / a))
        path = out / f"_label_{key}.png"
        scn.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(str(path))
        w, h = spec["px"]
        img.scale(w, h)
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        yy, xx = np.mgrid[0:h, 0:w]
        u, v = xx / w, yy / h
        vig = 1 - 0.22 * (((u - 0.5) * 2) ** 2 + ((v - 0.5) * 2) ** 2)
        noise = 1 + rng.normal(0, 0.035, (h, w))
        m = (vig * noise)[..., None]
        px[..., :3] = np.clip(px[..., :3] * m, 0, 1)
        if a <= 1:  # a bag: soft vertical creases catch the light
            for cx in rng.uniform(0.2, 0.8, 3):
                px[..., :3] = np.clip(px[..., :3] + (np.exp(-(((u - cx) / 0.03) ** 2)) * 0.16)[..., None], 0, 1)
        path.unlink()
        return w, h, px

    def to_bgra(px):
        """Blender pixels (rows bottom-up, RGBA float) as a D3D A8R8G8B8 top-down byte string."""
        b = (np.clip(px[::-1], 0, 1) * 255 + 0.5).astype(np.uint8)
        return b[..., [2, 1, 0, 3]].tobytes()

    labels = {}
    for key in LABELS:
        w, h, px = render_label(key)
        labels[key] = (w, h, px)
        print(f"make_vending: label {key} {w}x{h}")

    # the glass: an even grey-blue tint you see the snacks through, a little lighter toward the top where it catches the
    # sky, and one soft wide reflection band; smooth, so no patch of it reads as a shard
    def glass_pixels(w=64, h=128):
        yy, xx = np.mgrid[0:h, 0:w]
        u, v = xx / w, yy / h  # v: 0 at the bottom row of the image as Blender stores it, 1 at the top
        px = np.zeros((h, w, 4), dtype=np.float32)
        band = 0.12 * np.exp(-(((u * 0.6 - v * 0.8) + 0.2) / 0.18) ** 2)
        tint = 0.62 + 0.12 * v
        px[..., 0] = tint * 0.86 + band
        px[..., 1] = tint * 0.93 + band
        px[..., 2] = tint * 1.0 + band
        px[..., 3] = 0.30 + 0.08 * v + band * 0.6
        return np.clip(px, 0, 1)

    glass_px = glass_pixels()

    # ---- mesh building
    class Mesh:
        def __init__(self, textures):
            self.bm = bmesh.new()
            self.uv = self.bm.loops.layers.uv.new("UVMap")
            self.day = self.bm.loops.layers.color.new("Day")
            self.night = self.bm.loops.layers.color.new("Night")
            self.textures = textures  # material index -> texture name

        def face(self, co, uvs, mat, shade=0.9, night=None):
            vs = [self.bm.verts.new(c) for c in co]
            f = self.bm.faces.new(vs)
            f.material_index = mat
            n = night if night is not None else shade * 0.3
            for loop, (u, v) in zip(f.loops, uvs):
                loop[self.uv].uv = (u, v)
                loop[self.day] = (shade, shade, shade, 1.0)
                loop[self.night] = (n, n, n * 1.05, 1.0)
            return f

        def quad(self, a, b, c, d, mat, rect=(0, 0, 1, 1), shade=0.9, double=False):
            u0, v0, u1, v1 = rect
            uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)]
            self.face([a, b, c, d], uvs, mat, shade)
            if double:
                self.face([d, c, b, a], uvs[::-1], mat, shade)

        def box(self, lo, hi, mats, rects=None, shade=0.9, shades=None):
            """Axis-aligned box; mats/rects/shades map a face key (-x +x -y +y -z +z) to a material, uv rect, shade
            (a missing material leaves the face out)."""
            x0, y0, z0 = lo
            x1, y1, z1 = hi
            faces = {
                "-y": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
                "+y": [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
                "-x": [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
                "+x": [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
                "-z": [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],
                "+z": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
            }
            for key, co in faces.items():
                mat = mats.get(key, mats.get("*")) if isinstance(mats, dict) else mats
                if mat is None:
                    continue
                rect = (rects or {}).get(key, (rects or {}).get("*", (0, 0, 1, 1)))
                s = (shades or {}).get(key, shade)
                self.quad(*co, mat, rect, s)

        def sweep(self, path, radius, sides, mat, shade=0.9):
            """A tube along `path` (closed rings, no caps)."""
            rings = []
            for i, p in enumerate(path):
                a = Vector(path[min(i + 1, len(path) - 1)]) - Vector(path[max(i - 1, 0)])
                a.normalize()
                helper = Vector((0, 0, 1)) if abs(a.z) < 0.9 else Vector((1, 0, 0))
                u = a.cross(helper)
                u.normalize()
                w = a.cross(u)
                rings.append([Vector(p) + (u * math.cos(2 * math.pi * k / sides) + w * math.sin(2 * math.pi * k / sides)) * radius for k in range(sides)])
            for i in range(len(rings) - 1):
                for k in range(sides):
                    j = (k + 1) % sides
                    self.quad(rings[i][k], rings[i][j], rings[i + 1][j], rings[i + 1][k], mat, (0, 0, 1, 1), shade)

        def finish(self, name, natives, cols, recalc=True):
            bm = self.bm
            if recalc:
                bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
            mesh = bpy.data.meshes.new(name)
            bm.to_mesh(mesh)
            bm.free()
            for tex in self.textures:
                image = bpy.data.images.new(tex + ".png", 8, 8)
                material = bpy.data.materials.new(tex)
                material.use_nodes = True
                bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
                node = material.node_tree.nodes.new("ShaderNodeTexImage")
                node.image = image
                material.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
                mesh.materials.append(material)
            coll = bpy.data.collections.new(name)
            bpy.context.scene.collection.children.link(coll)
            obj = bpy.data.objects.new(name, mesh)
            obj.dff.type, obj.dff.day_cols, obj.dff.night_cols = "OBJ", True, True
            coll.objects.link(obj)
            for i, (centre, half) in enumerate(cols):
                col = bpy.data.objects.new(f"{name}_col{i}", None)
                col.empty_display_type = "CUBE"
                col.location, col.scale = centre, half
                col.dff.type = "COL"
                coll.objects.link(col)
            bpy.ops.export_dff.scene(filepath=str(out / f"{name}.dff"), export_coll=False, only_selected=False, export_version="0x36003")
            bpy.ops.export_col.scene(filepath=str(out / f"{name}.col"), export_version="3", only_selected=False)
            write_txd(out / f"{name}.txd", natives)
            print(f"make_vending: wrote {name}")

    # ---- snacks
    def build_bag(m, dims):
        """A pillow bag: front and back sheets bulging in the middle, pinched flat at the crimped seals (top and bottom
        ends, a zigzag) and along the sides."""
        bw, bl, bt = dims
        nx, ny, seal = 8, 12, 0.08  # seal: the share of the length each crimped end takes
        def thick(i, j):
            x = i / nx * 2 - 1
            y = j / ny * 2 - 1
            ey = 1 - seal * 2
            if abs(y) > ey:  # crimp: tiny zigzag ridges
                return 0.0015 + (0.0015 if i % 2 else 0)
            fy = math.cos(y / ey * math.pi / 2) ** 0.6
            fx = max(0.0, 1 - abs(x) ** 3) ** 0.5
            return bt / 2 * fx * fy + 0.0008
        grid = {}
        for side in (1, -1):
            for i in range(nx + 1):
                for j in range(ny + 1):
                    x = (i / nx - 0.5) * bw * (1 - 0.06 * (1 - abs(j / ny * 2 - 1) ** 4) * (side * 0 + 1))
                    y = (j / ny - 0.5) * bl
                    grid[side, i, j] = (x, y, bt / 2 + side * thick(i, j))
        for side in (1, -1):
            for i in range(nx):
                for j in range(ny):
                    a, b, c, d = grid[side, i, j], grid[side, i + 1, j], grid[side, i + 1, j + 1], grid[side, i, j + 1]
                    u0, u1 = i / nx, (i + 1) / nx
                    v0, v1 = j / ny, (j + 1) / ny
                    if side < 0:  # the back reads mirrored from behind: mirror u so its print reads right
                        u0, u1 = 1 - u0, 1 - u1
                    s = 0.95 if side > 0 else 0.8
                    co = [a, b, c, d] if side > 0 else [d, c, b, a]
                    uv = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)] if side > 0 else [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
                    m.face(co, uv, 0, s)
        for i in (0, nx):  # the side edges: thin strips joining front and back
            for j in range(ny):
                a, b = grid[1, i, j], grid[1, i, j + 1]
                c, d = grid[-1, i, j + 1], grid[-1, i, j]
                m.face([a, b, c, d], [(i / nx, j / ny), (i / nx, (j + 1) / ny)] * 2, 0, 0.7)
        for j in (0, ny):
            for i in range(nx):
                a, b = grid[1, i, j], grid[1, i + 1, j]
                c, d = grid[-1, i + 1, j], grid[-1, i, j]
                m.face([a, b, c, d], [(i / nx, j / ny), ((i + 1) / nx, j / ny)] * 2, 0, 0.7)

    def build_bar(m, dims):
        """A wrapped bar: a rounded body along X with the label wrapped round it, flattened crimped fins at both ends."""
        bw, bl, bt = dims  # bw along X (length), bl across (Y), bt thick
        fin = 0.012
        x0, x1 = -bw / 2 + fin, bw / 2 - fin
        segs = 10
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            ring.append((bl / 2 * math.cos(a), bt / 2 * math.sin(a) + bt / 2))
        for k in range(segs):
            (y0, z0), (y1, z1) = ring[k], ring[(k + 1) % segs]
            v0, v1 = k / segs, (k + 1) / segs
            # the top half shows the label, the underside its back: v runs across, u along the bar
            vv0, vv1 = (0.5 + 0.5 * math.cos(2 * math.pi * k / segs) * 0.98), (0.5 + 0.5 * math.cos(2 * math.pi * (k + 1) / segs) * 0.98)
            m.face([(x0, y0, z0), (x1, y0, z0), (x1, y1, z1), (x0, y1, z1)], [(0.06, vv0), (0.94, vv0), (0.94, vv1), (0.06, vv1)], 0, 0.9)
        for sgn, xe, xi in ((-1, -bw / 2, x0), (1, bw / 2, x1)):
            # the fin: from the body's outline down to a flat crimped edge
            for k in range(segs):
                (y0, z0), (y1, z1) = ring[k], ring[(k + 1) % segs]
                f0, f1 = (y0 * 1.05, bt / 2), (y1 * 1.05, bt / 2)
                u = 0.0 if sgn < 0 else 1.0
                co = [(xi, y0, z0), (xi, y1, z1), (xe, f1[0], f1[1]), (xe, f0[0], f0[1])]
                if sgn > 0:
                    co = co[::-1]
                m.face(co, [(0.06 if sgn < 0 else 0.94, 0.5)] * 2 + [(u, 0.5)] * 2, 0, 0.75)

    def build_box(m, dims, front=(0, 0, 1, 1), back=None, side=None):
        bw, bl, bt = dims
        side = side or (0.02, 0.02, 0.08, 0.08)
        m.box((-bw / 2, -bl / 2, 0), (bw / 2, bl / 2, bt), 0,
              {"+z": front, "-z": back or front, "*": side}, shades={"+z": 0.95, "-z": 0.8})

    for s in SNACKS:
        reset()
        name = "snack_" + s["uname"].lower()
        tex = name
        m = Mesh([tex])
        if s["shape"] == "bag":
            build_bag(m, s["dims"])
        elif s["shape"] == "bar":
            build_bar(m, s["dims"])
        elif s["shape"] == "box":
            build_box(m, s["dims"], side=(0.45, 0.1, 0.55, 0.2))
        else:  # the 24/7's cookie box: the white front half, the green back half
            build_box(m, s["dims"], front=(0.0, 0.0, 0.5, 1.0), back=(0.5, 0.0, 1.0, 1.0), side=(0.55, 0.05, 0.6, 0.1))
        if s["label"]:
            w, h, px = labels[s["label"]]
            natives = [native_rgba(tex, w, h, to_bgra(px), False)]
        else:
            nat = vanilla(COOKIES)
            natives = [nat[:12] + nat[12:12 + 12 + 8] + tex.encode().ljust(32, b"\0") + nat[12 + 12 + 8 + 32:]]
        bw, bl, bt = s["dims"]
        m.finish(name, natives, [((0, 0, bt / 2), (bw / 2, bl / 2, max(bt / 2, 0.01)))], recalc=s["shape"] not in ("bag", "bar"))

    # ---- the machine
    reset()
    SH, PN, DK, ED, CH = 0, 1, 2, 3, 4
    m = Mesh([SHEET[2], PANEL[2], DARK[2], EDGE[2], CHROME[2]])
    x0w, x1w, z0w, z1w = WINDOW
    hx, hy = W / 2, D / 2
    inner = 0.45  # interior prelight: the cabinet is dark inside
    # shell: back, left side, keypad column, top, plinth; the faces toward the interior dark metal
    m.box((-hx, hy - 0.04, 0), (hx, hy, H), {"*": SH, "-y": DK}, shades={"-y": inner})
    m.box((-hx, -hy, 0), (x0w - 0.04, hy - 0.04, H), {"*": SH, "+x": DK, "-y": SH}, shades={"+x": inner})
    m.box((x1w + 0.04, -hy, 0), (hx, hy - 0.04, H), {"*": SH, "-x": DK, "-y": PN},
          rects={"-y": (0.66, 0.03, 0.95, 0.97)}, shades={"-x": inner})
    m.box((x0w - 0.04, -hy, z1w + 0.06), (x1w + 0.04, hy - 0.04, H), {"*": SH, "-z": DK, "-y": PN},
          rects={"-y": (0.05, 0.88, 0.62, 0.99)}, shades={"-z": inner})
    m.box((x0w - 0.04, -hy, 0), (x1w + 0.04, hy - 0.04, z0w - 0.06), {"*": SH, "+z": DK, "-y": PN},
          rects={"-y": (0.02, 0.0, 0.64, 0.26)}, shades={"+z": inner})
    # the window frame, standing proud of the front
    fy0, fy1 = -hy - 0.012, -hy + 0.03
    m.box((x0w - 0.04, fy0, z0w - 0.06), (x0w, fy1, z1w + 0.06), SH)
    m.box((x1w, fy0, z0w - 0.06), (x1w + 0.04, fy1, z1w + 0.06), SH)
    m.box((x0w, fy0, z1w), (x1w, fy1, z1w + 0.06), SH)
    m.box((x0w, fy0, z0w - 0.06), (x1w, fy1, z0w), SH)
    # the delivery flap in the plinth: a dark push flap in a recess
    m.box((-0.46, -hy - 0.006, 0.14), (0.18, -hy + 0.02, 0.38), {"-y": DK, "-z": DK, "+z": DK, "-x": DK, "+x": DK}, shades={"-y": 0.35})
    m.box((-0.44, -hy - 0.012, 0.32), (0.16, -hy, 0.37), SH)  # its hinge bar
    # trays: wire shelf, a price strip along the front lip, four spiral coils each
    for zt in TRAY_TOPS:
        m.box((x0w, -0.34, zt - 0.012), (x1w, hy - 0.04, zt), DK, shades={"*": 0.55})
        m.box((x0w, -0.355, zt - 0.03), (x1w, -0.34, zt + 0.004), {"-y": ED, "*": DK}, rects={"-y": (0, 0.1, 1, 0.9)}, shades={"-y": 0.6})
        for cx in COLUMNS:
            r, turns, steps = 0.062, 6, 10
            path = []
            for k in range(turns * steps + 1):
                a = 2 * math.pi * k / steps
                path.append((cx + r * math.cos(a), -0.33 + 0.64 * k / (turns * steps), zt + r + 0.004 + r * math.sin(a)))
            m.sweep(path, 0.0035, 4, CH, 0.75)
    natives = [vanilla(SHEET), vanilla(PANEL), vanilla(DARK), vanilla(EDGE), vanilla(CHROME)]
    m.finish("snack_machine", natives, [((0, 0, H / 2), (hx, hy, H / 2))])

    # ---- the glass, intact
    def glass_mesh(name, broken):
        reset()
        m = Mesh(["snack_glass"])
        gx0, gx1, gz0, gz1 = WINDOW
        gw, gh = gx1 - gx0, gz1 - gz0

        def at(x, z):
            return (x, GLASS_Y, z)

        def uv(x, z):
            return ((x - gx0) / gw, (z - gz0) / gh)

        if not broken:
            for co in ([at(gx0, gz0), at(gx1, gz0), at(gx1, gz1), at(gx0, gz1)],):
                m.face(co, [uv(c[0], c[2]) for c in co], 0, 1.0, 0.6)
                m.face(co[::-1], [uv(c[0], c[2]) for c in co[::-1]], 0, 1.0, 0.6)
        else:
            # the frame's outline walked round, each point paired with a jagged inner one: shards stuck in the frame,
            # a few of them long
            n = 40
            outer, inner_pts = [], []
            for k in range(n):
                t = k / n * 2 * (gw + gh)
                if t < gw:
                    p, inward = (gx0 + t, gz0), (0, 1)
                elif t < gw + gh:
                    p, inward = (gx1, gz0 + t - gw), (-1, 0)
                elif t < 2 * gw + gh:
                    p, inward = (gx1 - (t - gw - gh), gz1), (0, -1)
                else:
                    p, inward = (gx0, gz1 - (t - 2 * gw - gh)), (1, 0)
                depth = rng.uniform(0.006, 0.05) if rng.random() > 0.15 else rng.uniform(0.09, 0.2)
                outer.append(p)
                inner_pts.append((min(max(p[0] + inward[0] * depth, gx0), gx1), min(max(p[1] + inward[1] * depth, gz0), gz1)))
            for k in range(n):
                j = (k + 1) % n
                a, b = outer[k], outer[j]
                c = inner_pts[k] if k % 2 == 0 else inner_pts[j]
                for tri in ([a, b, c], [a, c, b]):
                    co = [at(*p) for p in tri]
                    m.face(co, [uv(*p) for p in tri], 0, 1.0, 0.6)
                if k % 2 == 0:
                    tri = [b, inner_pts[j], c]
                    for t2 in (tri, tri[::-1]):
                        m.face([at(*p) for p in t2], [uv(*p) for p in t2], 0, 1.0, 0.6)
        w, h = glass_px.shape[1], glass_px.shape[0]
        m.finish(name, [native_rgba("snack_glass", w, h, to_bgra(glass_px), True)],
                 [((0, GLASS_Y, (WINDOW[2] + WINDOW[3]) / 2), ((WINDOW[1] - WINDOW[0]) / 2, 0.005, (WINDOW[3] - WINDOW[2]) / 2))], recalc=False)

    glass_mesh("snack_glass", False)
    glass_mesh("snack_glass_broken", True)

    if preview:
        render_previews(preview)


def render_previews(preview: Path) -> None:
    """Each model rendered textured (DragonFF import with its TXD), and the machine stocked with one of each snack."""
    import bpy
    from mathutils import Vector

    from DragonFF.ops import dff_importer, txd_importer

    preview.mkdir(parents=True, exist_ok=True)

    def load(name, loc=(0, 0, 0), rot=(0, 0, 0)):
        imgs = txd_importer.import_txd({"file_name": str(FILES / f"{name}.txd"), "skip_mipmaps": True, "pack": True}).images
        before = set(bpy.data.objects)
        dff_importer.import_dff({"file_name": str(FILES / f"{name}.dff"), "txd_images": {k.lower(): v for k, v in imgs.items()}, "image_ext": None,
                                 "connect_bones": False, "use_mat_split": True, "remove_doubles": False, "create_backfaces": False,
                                 "group_materials": False, "import_normals": False, "materials_naming": "DEFAULT", "hide_damage_parts": False})
        for o in set(bpy.data.objects) - before:
            if o.parent is None:
                o.rotation_mode = "XYZ"
                o.location, o.rotation_euler = loc, tuple(math.radians(r) for r in rot)
            if o.type == "MESH":
                for sl in o.material_slots:
                    if sl.material and sl.material.node_tree:
                        for n in sl.material.node_tree.nodes:
                            if n.type == "TEX_IMAGE" and not n.image and n.label.lower() in {k.lower() for k in imgs}:
                                n.image = imgs[next(k for k in imgs if k.lower() == n.label.lower())][0]
                    if sl.material:
                        sl.material.blend_method = "BLEND" if "glass" in name else "OPAQUE"

    def shoot(path, target, dist, direction, size=900):
        scn = bpy.context.scene
        scn.render.engine = "BLENDER_WORKBENCH"
        scn.render.resolution_x = scn.render.resolution_y = size
        sh = scn.display.shading
        sh.light, sh.color_type, sh.show_cavity = "STUDIO", "TEXTURE", False
        sh.background_type, sh.background_color = "VIEWPORT", (0.16, 0.17, 0.19)
        scn.view_settings.view_transform = "Standard"
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        scn.camera = cam
        cam.data.lens = 50
        t = Vector(target)
        cam.location = t + Vector(direction).normalized() * dist
        cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = str(path)
        bpy.ops.render.render(write_still=True)

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    for i, s in enumerate(SNACKS):
        load("snack_" + s["uname"].lower(), ((i % 5) * 0.25 - 0.5, (i // 5) * 0.3, 0))
    shoot(preview / "snacks.png", (0, 0.15, 0), 1.6, (0.3, -1, 1.1))
    for broken in (False, True):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        load("snack_machine")
        load("snack_glass_broken" if broken else "snack_glass")
        for slot in range(ROWS * COLS):
            s = SNACKS[slot % len(SNACKS)]
            row, col = slot // COLS, slot % COLS
            zt = TRAY_TOPS[ROWS - 1 - row]
            load("snack_" + s["uname"].lower(), (COLUMNS[col], SLOT_Y, zt + s["dims"][1] / 2), (90, 0, 0))
        shoot(preview / ("machine_broken.png" if broken else "machine.png"), (-0.1, 0, 1.15), 4.2, (0.45, -1, 0.25))
    shoot(preview / "machine_close.png", (-0.14, -0.2, 1.3), 1.9, (0.15, -1, 0.1))


# the vanilla snack machines: model -> the height of its origin above its base (956 stands 0.404 m up, 1776 1.099 m)
SOURCES = {956: 0.404, 1776: 1.099}
SPOTS = ROOT / "resources" / "[scavengesurvive]" / "world" / "data" / "vending.lua"
REMOVALS = ROOT / "resources" / "[scavengesurvive]" / "maps" / "data" / "VENDING.lua"


def write_spots(gta: Path) -> int:
    """Every Rockstar placement of SOURCES as a machine spot (world/data/vending.lua: base centre, heading, interior)
    and a removal (maps/data/VENDING.lua); returns how many."""
    from tools.ipl_natives import native_placements

    found = sorted(native_placements(gta, set(SOURCES)), key=lambda p: (p[0], p[3], p[1]))
    spots, removals = [], []
    for model, (x, y, z), rot, interior in found:
        heading = math.degrees(math.atan2(rot[1][0], rot[0][0])) % 360  # the model's +X axis, turned about Z
        spots.append(f"        {{ {x:.3f}, {y:.3f}, {z - SOURCES[model]:.3f}, {heading:.1f}, {interior} }}, -- {model}")
        removals.append(f"        {{ {model}, {x:.4f}, {y:.4f}, {z:.4f}, 0.25 }},")
    SPOTS.write_text(
        "-- Generated by tools/make_vending.py; do not edit. GTA's snack machines (956 outside, 1776 in the 24/7s) as\n"
        "-- SnackMachine spots: { x, y, z, rz, interior }, the base's centre and heading; world/server/vending.lua keeps one\n"
        "-- machine on each, the vanilla model is removed (maps/data/VENDING.lua).\n"
        "return {\n    spots = {\n" + "\n".join(spots) + "\n    },\n}\n", encoding="ascii", newline="\n")
    REMOVALS.write_text(
        "-- Generated by tools/make_vending.py; do not edit. GTA's snack machines, removed: each placement is a SnackMachine\n"
        "-- item (world/data/vending.lua) that clients draw with its glass and its snacks.\n\n"
        "return {\n    zone = \"VENDING\",\n    files = {},\n    objects = {},\n    -- { model, x, y, z, radius }\n"
        "    removals = {\n" + "\n".join(removals) + "\n    },\n}\n", encoding="ascii", newline="\n")
    return len(spots)


def main(argv=None) -> int:
    import argparse
    import subprocess

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta
    from tools.make_props import PROP_MODELS, PROPS, render_props, write_meta

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender executable (default: BLENDER or the newest install)")
    ap.add_argument("--preview", type=Path, help="also render previews into this folder")
    ap.add_argument("--spots", action="store_true", help="only write the machine spots and removals")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        print("make_vending: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    print(f"make_vending: {write_spots(gta)} machine spots")
    if args.spots:
        return 0
    blender = find_blender(args.blender)
    if not blender:
        print("make_vending: no Blender found (pass --blender)", file=sys.stderr)
        return 2
    PROPS.write_text(render_props(), encoding="ascii", newline="\n")
    write_meta(PROP_MODELS)
    cmd = [str(blender), "-b", "--python", __file__, "--", str(gta), str(FILES), str(args.preview or "")]
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    print("\n".join(line for line in out.splitlines() if "make_vending" in line or "Error" in line or "Traceback" in line))
    names = [r["name"] for r in props_rows()]
    return 0 if res.returncode == 0 and all((FILES / f"{n}.dff").is_file() for n in names) else 1


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        build_in_blender(Path(rest[0]), Path(rest[1]), Path(rest[2]) if len(rest) > 2 and rest[2] else None)
    else:
        sys.exit(main())
