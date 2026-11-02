"""Draws the wiki's maps: GTA San Andreas' radar tiles stitched into one picture with the game's points of interest on
it, one image per wiki topic.

    python -m tools.render_map [--only NAME] [--size 1536] [--gta DIR] [--wiki DIR | --no-wiki]

The base map (docs/images/map/base.png, 1536 px for the 6000 m of the world) is stitched once from the 144 radar tiles
of gta3.img, decoded with DragonFF's pure-Python TXD reader (the Blender addon, found under the user's Blender
scripts); after that neither the game nor the addon is needed (`--only base` stitches it again). Every image gets a
title, a legend, a scale bar and the three city names, is written to docs/images/map/<name>.png and copied at most
1536 px wide to <wiki>/images/map/<name>.png. Images: zones, loot (spawn density), vehicles (spawns by group), drops
(supply drop and weapon cache points), fixtures (workbenches, machines, fuel outlets), features (ladders, ziplines),
puzzles, spawns (new characters), shelters (enterable houses, cabins, trailers) and overview.

World to pixel: px = (x + 3000) / 6000 * W, py = (3000 - y) / 6000 * H; tile n is column n % 12, row n // 12 from the
north-west corner (checked against Area 69 in the desert, Mount Chiliad south-west, Los Santos south-east).
"""
from __future__ import annotations

import argparse
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

RES = ROOT / "resources" / "[scavengesurvive]"
OUT = ROOT / "docs" / "images" / "map"
BASE = OUT / "base.png"
WIKI = ROOT.parent / "scavengesurvive-mta.wiki"
WIKI_MAX = 1536
WORLD = 6000.0  # metres across the map; x and y both run -3000..3000
TILES, TILE = 12, 128  # radar00..radar143: 12 x 12 tiles of 128 px, row 0 along the north edge
NUM = r"-?\d+(?:\.\d+)?"

ZONES_LUA = RES / "maps" / "data" / "zones.lua"
MAPS_DATA = RES / "maps" / "data"
FEATURES_LUA = RES / "world" / "data" / "features.lua"
PUZZLES_DATA = RES / "world" / "data" / "puzzles.lua"
PUZZLES_LUA = RES / "world" / "shared" / "logic" / "puzzles.lua"
AREA69_LUA = RES / "world" / "shared" / "logic" / "area69.lua"
SPAWNS_LUA = RES / "character" / "shared" / "logic" / "spawnpoints.lua"
FUEL_LUA = RES / "vehicles" / "shared" / "logic" / "fuel-pumps.lua"
TRAILERS_LUA = RES / "house_shell" / "trailers.lua"
CABINS_LUA = RES / "house_shell" / "cabins.lua"
SAMP_IDE = ROOT / "tools" / "data" / "samp.ide"
LOOT_SQL = ROOT / "sql" / "seed" / "0002_loot_spawns.sql"
VEHICLES_SQL = ROOT / "sql" / "seed" / "0004_vehicle_spawns.sql"
DROPS_SQL = ROOT / "sql" / "seed" / "0005_drop_points.sql"

# zone codes of maps/data/zones.lua (upstream pyss/data/regions.json, the loot and drop seeds' `zone` column) -> names;
# fc also covers Whetstone and Mount Chiliad, bc the desert with Area 69, tr the north-west
ZONE_NAMES = {"ls": "Los Santos", "sf": "San Fierro", "lv": "Las Venturas", "rc": "Red County", "fc": "Flint County", "bc": "Bone County", "tr": "Tierra Robada"}
ZONE_ANCHORS = {"ls": (1750, -1800), "sf": (-2150, 250), "lv": (2050, 1950), "rc": (1300, -150), "fc": (-1000, -1950), "bc": (-150, 2450), "tr": (-1750, 2300)}
ZONE_FILLS = {"ls": (255, 80, 80), "sf": (80, 160, 255), "lv": (255, 200, 0), "rc": (255, 130, 0), "fc": (0, 210, 130), "bc": (235, 190, 110), "tr": (200, 110, 255)}
CITIES = {"LOS SANTOS": (1750, -1800), "SAN FIERRO": (-2150, 250), "LAS VENTURAS": (2050, 1950)}
# the old west house (des_westrn9_, model 3250, the one house_shell opens): its only two placements, both vanilla
# (gta3.img countrye_stream7.ipl and countryw_stream3.ipl); the port's maps add none
OLD_WEST_HOUSES = ((1110.24, -298.95), (-348.67, -1041.96))
HOUSE_STYLE = {"ls": "Los Santos style", "lv": "Las Venturas style", "sf": "San Fierro style"}
VEHICLE_GROUPS = {"Civilian": "Civilian", "Industrial": "Industrial", "Unique": "Unique", "Police": "Emergency", "Medical": "Emergency", "Firetruck": "Emergency", "Military": "Military", "Barracks": "Military", "Patriot": "Military", "Rhino": "Military", "Maverick": "Military", "Coastguard": "Boats", "Dinghy": "Boats"}
VEHICLE_COLOURS = {"Civilian": (255, 255, 255), "Industrial": (255, 150, 0), "Emergency": (255, 60, 60), "Military": (150, 230, 60), "Boats": (0, 220, 255), "Unique": (255, 0, 220), "Other": (255, 230, 0)}
HEAT_RAMP = [(0.0, (255, 255, 160, 0)), (0.08, (255, 245, 120, 45)), (0.3, (255, 200, 0, 130)), (0.6, (255, 100, 0, 195)), (0.85, (225, 20, 0, 225)), (1.0, (130, 0, 50, 240))]
WHITE, BLACK = (255, 255, 255, 255), (0, 0, 0, 255)
TITLES = {
    "zones": "Zones",
    "loot": "Loot spawns",
    "vehicles": "Vehicle spawns",
    "drops": "Supply drops and weapon caches",
    "fixtures": "Workbenches, machines and fuel outlets",
    "features": "Ladders and ziplines",
    "puzzles": "Puzzles and locked places",
    "spawns": "Where new characters start",
    "shelters": "Enterable houses, cabins and trailers",
    "overview": "Overview",
}
FONTS: dict = {}


# ---------------------------------------------------------------------------------------------------- data parsing
def lua_value(v: str):
    v = v.strip()
    if v.startswith('"'):
        return v.strip('"')
    try:
        return float(v)
    except ValueError:
        return v


def lua_rows(text: str, section: str) -> list[list]:
    """The `{ ... },` rows of a generated Lua file's `    section = {` block (one flat row per line)."""
    start = text.index(f"\n    {section} = {{")
    end = text.index("\n    },", start)
    return [[lua_value(v) for v in m.group(1).split(", ")] for m in re.finditer(r"\{ ([^{}]*) \}", text[start:end])]


def sql_rows(path: Path, table: str) -> list[list]:
    """The value tuples of a seed's `INSERT INTO table (...) VALUES` blocks (the converters write one per 500 rows):
    quoted strings, NULL as None, numbers as floats (a trailing POINT(x, y) adds its two numbers at the end, which
    nothing reads)."""
    text = path.read_text(encoding="utf8")
    rows = []
    for block in re.finditer(rf"^INSERT INTO {table} \(.*?;$", text, re.M | re.S):
        for m in re.finditer(r"^\((.*)\)[,;]?\s*$", block.group(0), re.M):
            row = []
            for tok in re.finditer(rf"'((?:[^']|'')*)'|(NULL)|({NUM})", m.group(1)):
                row.append(None if tok.group(2) else float(tok.group(3)) if tok.group(3) else tok.group(1).replace("''", "'"))
            rows.append(row)
    return rows


def read_zones() -> dict[str, list[tuple[float, float]]]:
    out = {}
    for m in re.finditer(r"^    (\w+) = \{ (.*) \},$", ZONES_LUA.read_text(encoding="utf8"), re.M):
        out[m.group(1)] = [(float(x), float(y)) for x, y in re.findall(rf"\{{ ({NUM}), ({NUM}) \}}", m.group(2))]
    return out


def read_buttons(path: Path) -> dict[str, tuple[float, float, int, str]]:
    """id -> (x, y, world, label) of a puzzle module's BUTTONS table."""
    pattern = rf'\{{ id = "(\w+)", ({NUM}), ({NUM}), {NUM}, (\d), "([^"]*)"'
    return {i: (float(x), float(y), int(w), lbl) for i, x, y, w, lbl in re.findall(pattern, path.read_text(encoding="utf8"))}


def read_area69_counts() -> tuple[int, int]:
    """(doors behind keypads, code consoles) of Area 69's M.KEYPADS table."""
    text = AREA69_LUA.read_text(encoding="utf8")
    block = text[text.index("M.KEYPADS = {") : text.index("\n}", text.index("M.KEYPADS = {"))]
    doors = sum(len(re.findall(r'"\w+"', m)) for m in re.findall(r"doors = \{([^}]*)\}", block))
    return doors, len(re.findall(r"list = \d", block))


def read_code_spots() -> list[tuple[float, float]]:
    text = PUZZLES_LUA.read_text(encoding="utf8")
    block = text[text.index("M.CODE_SPOTS = {") : text.index("\n}", text.index("M.CODE_SPOTS = {"))]
    return [(float(x), float(y)) for x, y, _z in re.findall(rf"\{{ ({NUM}), ({NUM}), ({NUM}) \}}", block)]


def read_maps_objects() -> list[tuple[int, float, float]]:
    """(model, x, y) of every object the maps resource builds (maps/data/<ZONE>.lua `objects`)."""
    out = []
    for path in sorted(MAPS_DATA.glob("*.lua")):
        text = path.read_text(encoding="utf8")
        if "\n    objects = {" in text:
            out += [(int(r[0]), r[1], r[2]) for r in lua_rows(text, "objects")]
    return out


def house_shell_models() -> dict[int, str]:
    """SA-MP house shell model id -> style code (lshouse1..4, lvhouse1..4, sfhouse1..4 in tools/data/samp.ide)."""
    from tools.extract_samp_models import parse_ide  # noqa: PLC0415

    out = {}
    for model, (dff, _txd, _dist) in parse_ide(SAMP_IDE.read_text(encoding="latin1")).items():
        m = re.fullmatch(r"(ls|lv|sf)house\d", dff.lower())
        if m:
            out[model] = m.group(1)
    return out


def clusters(points, radius: float) -> list[list]:
    """Greedy grouping of (x, y) points within `radius` m of a group's centre: [cx, cy, count] per group."""
    out: list[list] = []
    for x, y in points:
        for c in out:
            if math.hypot(c[0] - x, c[1] - y) <= radius:
                c[0], c[1], c[2] = (c[0] * c[2] + x) / (c[2] + 1), (c[1] * c[2] + y) / (c[2] + 1), c[2] + 1
                break
        else:
            out.append([x, y, 1])
    return out


def load_world() -> dict:
    """Everything the images draw, read once from the port's own data files and seeds."""
    features = FEATURES_LUA.read_text(encoding="utf8")
    puzzles = PUZZLES_DATA.read_text(encoding="utf8")
    trailers_text = TRAILERS_LUA.read_text(encoding="utf8")
    trailer_models = {int(m) for m in re.findall(r"^        \[(\d+)\] = \{", trailers_text, re.M)}
    shells = house_shell_models()
    houses = {code: [] for code in HOUSE_STYLE}
    trailers = [(r[1], r[2]) for r in lua_rows(trailers_text, "placements")]
    for model, x, y in read_maps_objects():
        if model in shells:
            houses[shells[model]].append((x, y))
        elif model in trailer_models and all(math.hypot(x - tx, y - ty) > 2 for tx, ty in trailers):
            trailers.append((x, y))
    w = {
        "zones": read_zones(),
        "loot": [(r[0], r[1], r[3], r[8]) for r in sql_rows(LOOT_SQL, "loot_spawns")],
        "vehicles": [(r[0], r[1], r[4]) for r in sql_rows(VEHICLES_SQL, "vehicle_spawns")],
        "drops": [(r[1], r[2], r[0]) for r in sql_rows(DROPS_SQL, "supply_drop_points")],
        "caches": [(r[0], r[1]) for r in sql_rows(DROPS_SQL, "weapon_cache_points")],
        "ladders": [(r[0], r[1]) for r in lua_rows(features, "ladders")],
        "ziplines": [(r[0], r[1], r[3], r[4]) for r in lua_rows(features, "ziplines")],
        "fixtures": [(r[0], r[1], r[2]) for r in lua_rows(features, "fixtures")],
        "puzzle_items": [(r[0], r[1], r[2], r[5]) for r in lua_rows(puzzles, "fixtures")],
        "buttons": read_buttons(PUZZLES_LUA),
        "area69": read_buttons(AREA69_LUA),
        "area69_counts": read_area69_counts(),
        "code_spots": read_code_spots(),
        "spawns": [(float(x), float(y)) for x, y, _z, _a in re.findall(rf"\{{ ({NUM}), ({NUM}), ({NUM}), ({NUM}) \}}", SPAWNS_LUA.read_text(encoding="utf8"))],
        "pumps": [(float(x), float(y)) for x, y in re.findall(rf"x = ({NUM}), y = ({NUM})", FUEL_LUA.read_text(encoding="utf8"))],
        "houses": houses,
        "cabins": [(r[0], r[1]) for r in lua_rows(CABINS_LUA.read_text(encoding="utf8"), "placements")],
        "trailers": trailers,
    }
    w["stations"] = clusters(w["pumps"], 80.0)
    return w


# ---------------------------------------------------------------------------------------------------- base map
def find_dragonff() -> Path | None:
    """The DragonFF Blender addon folder (its gtaLib/txd.py decodes DXT textures without Blender)."""
    roots = []
    if os.environ.get("APPDATA"):
        roots.append(Path(os.environ["APPDATA"]) / "Blender Foundation" / "Blender")
    for base in (os.environ.get("ProgramFiles", r"C:\Program Files"), os.environ.get("ProgramFiles(x86)", "")):
        if base:
            roots.append(Path(base) / "Blender Foundation")
    patterns = ("*/scripts/addons/DragonFF/gtaLib/txd.py", "*/extensions/*/DragonFF/gtaLib/txd.py", "Blender */*/scripts/addons_core/DragonFF/gtaLib/txd.py")
    found = sorted(p for root in roots if root.is_dir() for pat in patterns for p in root.glob(pat))
    return found[-1].parents[1] if found else None


def stitch_base(gta: Path, dragonff: Path) -> Image.Image:
    sys.path.insert(0, str(dragonff))
    from gtaLib import txd as gtxd  # noqa: PLC0415
    from tools.extract_samp_models import read_img_entry, read_img_index  # noqa: PLC0415

    img = gta / "models" / "gta3.img"
    index = read_img_index(img)
    base = Image.new("RGB", (TILES * TILE, TILES * TILE))
    for n in range(TILES * TILES):
        t = gtxd.txd()
        t.load_memory(read_img_entry(img, index[f"radar{n:02d}.txd"]))
        nt = t.native_textures[0]
        tile = Image.frombytes("RGBA", (nt.get_width(0), nt.get_height(0)), nt.to_rgba(0)).convert("RGB")
        if tile.size != (TILE, TILE):
            tile = tile.resize((TILE, TILE), Image.LANCZOS)
        base.paste(tile, ((n % TILES) * TILE, (n // TILES) * TILE))
    return base


def base_map(gta_arg: str | None, rebuild: bool) -> Image.Image:
    if BASE.is_file() and not rebuild:
        return Image.open(BASE).convert("RGB")
    from tools.extract_samp_models import detect_gta  # noqa: PLC0415

    gta = Path(gta_arg) if gta_arg else detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        sys.exit("render_map: no GTA San Andreas install found; pass --gta DIR (needs models/gta3.img)")
    dragonff = find_dragonff()
    if not dragonff:
        sys.exit("render_map: the DragonFF Blender addon was not found (its gtaLib decodes the radar tiles)")
    base = stitch_base(gta, dragonff)
    OUT.mkdir(parents=True, exist_ok=True)
    base.save(BASE, optimize=True)
    print(f"stitched {BASE} from {gta / 'models' / 'gta3.img'} with {dragonff}")
    return base


# ---------------------------------------------------------------------------------------------------- drawing
def shape(d: ImageDraw.ImageDraw, kind: str, cx: float, cy: float, r: float, fill, outline=BLACK, width: int = 1):
    if kind == "circle":
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=outline, width=width)
    elif kind == "dot":
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)
    elif kind == "square":
        d.rectangle((cx - r, cy - r, cx + r, cy + r), fill=fill, outline=outline, width=width)
    elif kind == "diamond":
        d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=fill, outline=outline, width=width)
    elif kind == "triangle":
        d.polygon([(cx, cy - r), (cx + r, cy + r * 0.8), (cx - r, cy + r * 0.8)], fill=fill, outline=outline, width=width)
    elif kind == "hex":
        d.regular_polygon((cx, cy, r), 6, rotation=30, fill=fill, outline=outline, width=width)
    elif kind == "star":
        pts = [(cx + (r if i % 2 == 0 else r * 0.45) * math.cos(-math.pi / 2 + i * math.pi / 5), cy + (r if i % 2 == 0 else r * 0.45) * math.sin(-math.pi / 2 + i * math.pi / 5)) for i in range(10)]
        d.polygon(pts, fill=fill, outline=outline, width=width)
    elif kind == "line":
        d.line((cx - r, cy, cx + r, cy), fill=fill, width=max(2, width + 1))
        d.ellipse((cx - r - 2, cy - 2, cx - r + 2, cy + 2), fill=fill)
    elif kind == "fill":
        d.rectangle((cx - r, cy - r * 0.7, cx + r, cy + r * 0.7), fill=fill[:3] + (90,), outline=fill[:3] + (255,), width=1)
    else:
        raise ValueError(kind)


def ramp_image(width: int, height: int) -> Image.Image:
    t = np.linspace(0.0, 1.0, width, dtype=np.float32)
    rgba = ramp_lookup(np.tile(t, (height, 1)))
    rgba[..., 3] = 255
    return Image.fromarray(rgba, "RGBA")


def ramp_lookup(v: np.ndarray) -> np.ndarray:
    xs = [s for s, _ in HEAT_RAMP]
    out = np.zeros(v.shape + (4,), np.uint8)
    for ch in range(4):
        out[..., ch] = np.interp(v, xs, [c[ch] for _, c in HEAT_RAMP]).astype(np.uint8)
    return out


class Canvas:
    def __init__(self, base: Image.Image, size: int, title: str):
        self.size, self.k, self.title = size, size / 1536.0, title
        self.im = base.convert("RGBA")
        if self.im.width != size:
            self.im = self.im.resize((size, size), Image.LANCZOS)
        self.draw = ImageDraw.Draw(self.im)

    def font(self, px: float, bold: bool = False):
        key = (max(8, round(px * self.k)), bold)
        if key not in FONTS:
            try:
                FONTS[key] = ImageFont.truetype("arialbd.ttf" if bold else "arial.ttf", key[0])
            except OSError:
                FONTS[key] = ImageFont.load_default(key[0])
        return FONTS[key]

    def pt(self, x: float, y: float) -> tuple[float, float]:
        return (x + 3000.0) / WORLD * self.size, (3000.0 - y) / WORLD * self.size

    def layer(self):
        im = Image.new("RGBA", (self.size, self.size), (0, 0, 0, 0))
        return im, ImageDraw.Draw(im)

    def merge(self, im: Image.Image):
        self.im.alpha_composite(im)
        self.draw = ImageDraw.Draw(self.im)

    def marker(self, x: float, y: float, kind: str, fill, r: float = 5.0, outline=BLACK, width: int = 1, d=None):
        cx, cy = self.pt(x, y)
        shape(d or self.draw, kind, cx, cy, r * self.k, fill, outline, max(1, round(width * self.k)))

    def text(self, x: float, y: float, s: str, size: float = 11, fill=WHITE, bold=False, anchor="lm", dx: float = 8, dy: float = 0, d=None):
        cx, cy = self.pt(x, y)
        (d or self.draw).text((cx + dx * self.k, cy + dy * self.k), s, font=self.font(size, bold), fill=fill, anchor=anchor, stroke_width=max(1, round(2 * self.k)), stroke_fill=BLACK)

    def zone_outlines(self, zones: dict, alpha: int = 110, width: float = 1.5, labels: bool = False):
        layer, d = self.layer()
        for code, poly in zones.items():
            pts = [self.pt(x, y) for x, y in poly]
            d.polygon(pts, outline=(255, 255, 255, alpha), width=max(1, round(width * self.k)))
            if labels:
                self.text(*ZONE_ANCHORS[code], ZONE_NAMES[code], 15, (255, 255, 255, 230), True, "mm", 0, 0, d)
        self.merge(layer)

    def zone_fills(self, zones: dict):
        layer, d = self.layer()
        for code, poly in zones.items():
            pts = [self.pt(x, y) for x, y in poly]
            d.polygon(pts, fill=ZONE_FILLS[code] + (70,), outline=ZONE_FILLS[code] + (255,), width=max(2, round(2 * self.k)))
        self.merge(layer)

    def cities(self, size: float = 22):
        for name, (x, y) in CITIES.items():
            self.text(x, y, name, size, (255, 255, 255, 235), True, "mm", 0, 0)

    def heat(self, points, sigma_m: float = 50.0, res: int = 2, gamma: float = 0.8):
        """Soft density blobs of (x, y) points through HEAT_RAMP, scaled so the densest 0.3% of the lit cells
        reach the top of the ramp (a city core) without flattening the countryside's single points."""
        n = self.size // res
        grid = np.zeros((n, n), np.float32)
        for x, y in points:
            i, j = int((3000.0 - y) / WORLD * n), int((x + 3000.0) / WORLD * n)
            if 0 <= i < n and 0 <= j < n:
                grid[i, j] += 1.0
        sigma = sigma_m / WORLD * n
        r = int(3 * sigma) + 1
        k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2).astype(np.float32)
        k /= k.sum()
        grid = np.apply_along_axis(lambda row: np.convolve(row, k, mode="same"), 1, grid)
        grid = np.apply_along_axis(lambda col: np.convolve(col, k, mode="same"), 0, grid)
        lit = grid[grid > 0]
        cap = float(np.percentile(lit, 99.7)) if lit.size else 1.0
        v = np.clip(grid / cap, 0.0, 1.0) ** gamma
        layer = Image.fromarray(ramp_lookup(v), "RGBA").resize((self.size, self.size), Image.BILINEAR)
        self.merge(layer)

    def legend(self, entries, title: str | None = None, corner: str = "br"):
        """entries: (kind, colour, label); kind is a marker shape, "line", "fill", "ramp" or "text"."""
        f, fb, k = self.font(13), self.font(13, True), self.k
        pad, row, sw = 10 * k, 20 * k, 30 * k
        widest = max([f.getlength(lbl) for _, _, lbl in entries] + [fb.getlength(title) if title else 0])
        width, height = widest + sw + 2 * pad, 2 * pad + row * (len(entries) + (1 if title else 0))
        x0 = self.size - width - 14 * k if corner.endswith("r") else 14 * k
        y0 = self.size - height - 14 * k if corner.startswith("b") else 44 * k
        layer, d = self.layer()
        d.rounded_rectangle((x0, y0, x0 + width, y0 + height), radius=6 * k, fill=(15, 15, 20, 190))
        y = y0 + pad
        if title:
            d.text((x0 + pad, y + row / 2), title, font=fb, fill=WHITE, anchor="lm")
            y += row
        for kind, colour, label in entries:
            cx, cy = x0 + pad + sw / 2 - 4 * k, y + row / 2
            if kind == "ramp":
                layer.paste(ramp_image(round(sw - 6 * k), round(10 * k)), (round(cx - sw / 2 + 3 * k), round(cy - 5 * k)))
            elif kind != "text":
                shape(d, kind, cx, cy, 6 * k, colour if len(colour) == 4 else colour + (255,), BLACK, max(1, round(k)))
            d.text((x0 + pad + sw, cy), label, font=f, fill=WHITE, anchor="lm")
            y += row
        self.merge(layer)

    def finish(self, subtitle: str | None = None):
        k = self.k
        self.draw.text((14 * k, 10 * k), f"Scavenge & Survive Reborn: {self.title}", font=self.font(20, True), fill=WHITE, stroke_width=round(3 * k), stroke_fill=BLACK)
        if subtitle:
            self.draw.text((14 * k, 36 * k), subtitle, font=self.font(12), fill=WHITE, stroke_width=round(2 * k), stroke_fill=BLACK)
        km = self.size / (WORLD / 1000.0)
        x0, y0 = 14 * k, self.size - 14 * k - 36 * k
        layer, d = self.layer()
        d.rounded_rectangle((x0, y0, x0 + km + 2 * 12 * k, y0 + 36 * k), radius=6 * k, fill=(15, 15, 20, 190))
        bx, by = x0 + 12 * k, y0 + 24 * k
        d.line((bx, by, bx + km, by), fill=WHITE, width=max(2, round(2 * k)))
        for frac, lbl in ((0.0, "0"), (0.5, "500 m"), (1.0, "1 km")):
            d.line((bx + km * frac, by - 5 * k, bx + km * frac, by + 3 * k), fill=WHITE, width=max(1, round(k)))
            d.text((bx + km * frac, by - 8 * k), lbl, font=self.font(11), fill=WHITE, anchor="mb")
        self.merge(layer)


# ---------------------------------------------------------------------------------------------------- the images
def draw_fuel(c: Canvas, w: dict, label: bool = True):
    for x, y, n in w["stations"]:
        c.marker(x, y, "hex", (255, 230, 0, 255), 7)
        if label:
            c.text(x, y, f"{n} pumps", 10, dx=10)


def draw_fixtures(c: Canvas, w: dict, label: bool = True):
    kinds = {"Workbench": ("square", (255, 140, 0, 255)), "ScrapMachine": ("diamond", (200, 80, 255, 255)), "RefineMachine": ("diamond", (0, 210, 255, 255)), "Barbecue": ("triangle", (255, 70, 70, 255))}
    for uname, x, y in w["fixtures"]:
        if uname not in kinds:  # upstream's joke fixtures (a Dildo2 at Come-A-Lot) are not worth a marker
            continue
        kind, colour = kinds[uname]
        c.marker(x, y, kind, colour, 6)
        if label and uname not in ("Workbench",):
            c.text(x, y, {"ScrapMachine": "Scrap Machine", "RefineMachine": "Refining Machine", "Barbecue": "BBQ"}.get(uname, uname), 10, dx=9)


def fixture_legend(w: dict):
    counts = {}
    for uname, _x, _y in w["fixtures"]:
        counts[uname] = counts.get(uname, 0) + 1
    pumps, stations = len(w["pumps"]), len(w["stations"])
    entries = [("square", (255, 140, 0), f"Workbench ({counts.get('Workbench', 0)})"), ("diamond", (200, 80, 255), "Scrap Machine"), ("diamond", (0, 210, 255), "Refining Machine"), ("triangle", (255, 70, 70), "Barbecue")]
    entries.append(("hex", (255, 230, 0), f"Fuel outlet ({pumps} pumps at {stations} stations)"))
    return entries


def draw_drops(c: Canvas, w: dict, label: bool = True, caches: bool = True):
    if caches:
        for x, y in w["caches"]:
            c.marker(x, y, "circle", (255, 0, 220, 255), 2.5)
    for x, y, name in w["drops"]:
        c.marker(x, y, "star", (255, 110, 0, 255), 8)
        if label:
            short = re.sub(r"^(Los Santos|San Fierro|Las Venturas|Bone County|Flint County|Tierra Robada|Red County) ", "", name)
            c.text(x, y, short, 10, dx=10)


def draw_spawns(c: Canvas, w: dict, r: float = 9):
    for x, y in w["spawns"]:
        c.marker(x, y, "star", (255, 255, 0, 255), r, width=1)


def draw_shelters(c: Canvas, w: dict, r: float = 3.0, alpha: int = 255):
    colours = {"ls": (255, 120, 0, alpha), "lv": (255, 0, 190, alpha), "sf": (0, 200, 255, alpha)}
    for code, pts in w["houses"].items():
        for x, y in pts:
            c.marker(x, y, "square", colours[code], r)
    for x, y in w["trailers"]:
        c.marker(x, y, "diamond", (255, 255, 255, alpha), r + 0.5)
    for x, y in w["cabins"]:
        c.marker(x, y, "hex", (90, 255, 90, alpha), r + 4)
    for x, y in OLD_WEST_HOUSES:
        c.marker(x, y, "square", (255, 240, 0, alpha), r + 3)


def shelter_legend(w: dict):
    entries = [("square", colour, f"Town house, {HOUSE_STYLE[code]} ({len(w['houses'][code])})") for code, colour in (("ls", (255, 120, 0)), ("lv", (255, 0, 190)), ("sf", (0, 200, 255)))]
    entries.append(("square", (255, 240, 0), f"Old west house ({len(OLD_WEST_HOUSES)})"))
    entries.append(("hex", (90, 255, 90), f"Log cabin row, 6 cabins ({len(w['cabins'])})"))
    entries.append(("diamond", (255, 255, 255), f"Trailer ({len(w['trailers'])})"))
    return entries


def puzzle_sites(w: dict) -> list[tuple]:
    """(x, y, marker, colour, map label, legend text) of the puzzle places in the normal world (dimension 0)."""
    b, a69 = w["buttons"], w["area69"]
    doors, consoles = w["area69_counts"]
    gate = a69["a69MainGate"]
    sites = [(gate[0], gate[1], "star", (255, 60, 60, 255), "Area 69", f"Area 69: {doors} doors behind keypads and {consoles} code consoles")]
    sites.append((b["chDoor"][0], b["chDoor"][1], "diamond", (255, 60, 60, 255), "Chiliad radio station", "Mount Chiliad radio station: gate, door, battery and fusebox"))
    sites.append((b["ranchPc"][0], b["ranchPc"][1], "diamond", (90, 255, 90, 255), "Ranch PC", "Ranch PC: the hard drive goes back in here"))
    sites.append((b["quarryDoor"][0], b["quarryDoor"][1], "diamond", (255, 180, 60, 255), "Quarry door", "Hunter Quarry door: the key opens the way into the caves"))
    sites.append((b["lsLadder"][0], b["lsLadder"][1], "diamond", (255, 180, 60, 255), "Ganton hatch", "Ganton hatch: ladder down to the metro"))
    sites.append((b["fcTop"][0], b["fcTop"][1], "diamond", (255, 180, 60, 255), "Blueberry passage", "Blueberry passage: down into the Fort Claw cellar"))
    sites.append((b["lockupKeypad"][0], b["lockupKeypad"][1], "diamond", (0, 220, 255, 255), "SF lockup", "San Fierro lockup: its keypad takes the hunted code"))
    for uname, x, y, _puzzle in w["puzzle_items"]:
        if uname == "Key":
            sites.append((x, y, "triangle", (255, 180, 60, 255), "Quarry key", "Quarry door key: lies at the west foot of Mount Chiliad"))
    return sites


def img_zones(c: Canvas, w: dict):
    c.zone_fills(w["zones"])
    counts = {}
    for _x, _y, _t, zone in w["loot"]:
        counts[zone] = counts.get(zone, 0) + 1
    for code, (x, y) in ZONE_ANCHORS.items():
        c.text(x, y, ZONE_NAMES[code], 20, bold=True, anchor="mm", dx=0, dy=-10)
        c.text(x, y, f"zone '{code}'", 12, anchor="mm", dx=0, dy=12)
    entries = [("fill", ZONE_FILLS[code], f"{ZONE_NAMES[code]} ({code}): {counts.get(code, 0)} loot spawns") for code in ZONE_NAMES]
    c.legend(entries, "Server zones (maps/data/zones.lua)")
    c.finish("The seven zones the server, the loot tables and the supply drops use")


def img_loot(c: Canvas, w: dict):
    c.heat([(x, y) for x, y, _t, _z in w["loot"]])
    c.zone_outlines(w["zones"], 90)
    c.cities()
    tables = {}
    for _x, _y, t, _z in w["loot"]:
        tables[t] = tables.get(t, 0) + 1
    entries = [("ramp", None, "fewer -> more loot spawn points nearby")]
    entries += [("text", None, f"{t.replace('world_', '')}: {n} points") for t, n in sorted(tables.items(), key=lambda kv: -kv[1])]
    c.legend(entries, f"{len(w['loot'])} loot spawn points")
    c.finish("Density of the fixed loot spawn points (each rolls its table's items on its own timer)")


def img_vehicles(c: Canvas, w: dict):
    groups = {}
    for x, y, group in w["vehicles"]:
        groups.setdefault(VEHICLE_GROUPS.get(group, "Other"), []).append((x, y))
    for name in ("Civilian", "Industrial", "Emergency", "Military", "Boats", "Unique", "Other"):
        for x, y in groups.get(name, []):
            c.marker(x, y, "circle", VEHICLE_COLOURS[name] + (255,), 2.2 if name == "Civilian" else 3.2)
    c.zone_outlines(w["zones"], 90)
    c.cities()
    entries = [("circle", VEHICLE_COLOURS[n], f"{n} ({len(groups.get(n, []))})") for n in ("Civilian", "Industrial", "Emergency", "Military", "Boats", "Unique", "Other") if groups.get(n)]
    c.legend(entries, f"{len(w['vehicles'])} vehicle spawn points")
    c.finish("Every point can hold one vehicle of its group; emergency = police, medical and fire; other = airport tugs and one-offs")


def img_drops(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 90)
    c.cities(18)
    draw_drops(c, w)
    entries = [("star", (255, 110, 0), f"Supply drop landing point ({len(w['drops'])})"), ("circle", (255, 0, 220), f"Weapon cache point ({len(w['caches'])})")]
    c.legend(entries, "Supply drops and weapon caches")
    c.finish("A drop falls on one of the named points; a weapon cache appears at one of the small points")


def img_fixtures(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 90)
    c.cities(18)
    draw_fuel(c, w)
    draw_fixtures(c, w)
    c.legend(fixture_legend(w), "Fixed items and fuel outlets")
    c.finish("Workbenches and machines the world puts back when they are gone; petrol station pumps with their own stock")


def img_features(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 90)
    c.cities(18)
    for x1, y1, x2, y2 in w["ziplines"]:
        a, b = c.pt(x1, y1), c.pt(x2, y2)
        c.draw.line((a, b), fill=(0, 255, 255, 255), width=max(2, round(2 * c.k)))
        c.marker(x1, y1, "circle", (0, 255, 255, 255), 3.5)
    for x, y in w["ladders"]:
        c.marker(x, y, "triangle", (255, 170, 0, 255), 6)
    for x, y, n in clusters(w["ladders"], 120.0):
        if n > 1:
            c.text(x, y, f"{n} ladders", 10, dx=10)
    for x, y, n in clusters([(x1, y1) for x1, y1, _x2, _y2 in w["ziplines"]], 200.0):
        c.text(x, y, f"{n} zipline{'s' if n > 1 else ''}", 10, dx=10)
    entries = [("triangle", (255, 170, 0), f"Ladder ({len(w['ladders'])})"), ("line", (0, 255, 255), f"Zipline, from its start ({len(w['ziplines'])})")]
    c.legend(entries, "Ladders and ziplines")
    c.finish("Press F at the foot of a ladder or at the start of a zipline")


def img_puzzles(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 90)
    c.cities(18)
    for x, y in w["code_spots"]:
        c.marker(x, y, "circle", (0, 220, 255, 255), 4)
    sites = puzzle_sites(w)
    for x, y, kind, colour, short, _long in sites:
        c.marker(x, y, kind, colour, 8)
        c.text(x, y, short, 11, dx=11)
    entries = [(kind, colour, long) for _x, _y, kind, colour, _short, long in sites]
    entries.append(("circle", (0, 220, 255), f"Possible Code spot: 4 of these {len(w['code_spots'])} hold a digit"))
    entries.append(("text", None, "The caves, the metro and the Fort Claw cellar lie north of"))
    entries.append(("text", None, "the map (y > 3000) and are reached through the passages"))
    c.legend(entries, "Puzzles")
    c.finish("Locked places and the parts that open them (Code Hunt & Puzzles, Keypads)")


def img_spawns(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 90, labels=True)
    draw_spawns(c, w, 10)
    c.legend([("star", (255, 255, 0), f"Spawn point ({len(w['spawns'])})")], "New characters")
    c.finish("A new character starts at one of these points, never the same one twice in a row")


def img_shelters(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 90)
    c.cities(18)
    draw_shelters(c, w, 3.0)
    c.legend(shelter_legend(w), "Enterable buildings")
    c.finish("Buildings with an open door and a room behind it (Houses & Trailers)")


def img_overview(c: Canvas, w: dict):
    c.zone_outlines(w["zones"], 120, 1.5, labels=True)
    draw_shelters(c, w, 1.6, 150)
    for x, y in w["ladders"]:
        c.marker(x, y, "triangle", (255, 170, 0, 255), 4)
    for x1, y1, x2, y2 in w["ziplines"]:
        c.draw.line((c.pt(x1, y1), c.pt(x2, y2)), fill=(0, 255, 255, 255), width=max(1, round(1.5 * c.k)))
    draw_drops(c, w, label=False, caches=False)
    draw_fuel(c, w, label=False)
    draw_fixtures(c, w, label=False)
    for x, y, kind, colour, short, _long in puzzle_sites(w):
        c.marker(x, y, kind, colour, 7)
        c.text(x, y, short, 10, dx=10)
    draw_spawns(c, w, 8)
    entries = [("star", (255, 255, 0), "New character spawn"), ("star", (255, 110, 0), "Supply drop point"), ("hex", (255, 230, 0), "Fuel outlet"), ("square", (255, 140, 0), "Workbench"), ("diamond", (200, 80, 255), "Scrap / Refining Machine (purple / blue)")]
    entries += [("triangle", (255, 70, 70), "Barbecue"), ("triangle", (255, 170, 0), "Ladder"), ("line", (0, 255, 255), "Zipline"), ("star", (255, 60, 60), "Area 69"), ("diamond", (255, 60, 60), "Puzzle site (labelled)")]
    entries += [("square", (255, 120, 0), "Town house (orange LS, pink LV, blue SF)"), ("diamond", (255, 255, 255), "Trailer"), ("hex", (90, 255, 90), "Log cabins")]
    c.legend(entries, "Overview")
    c.finish("The fixed points of interest; loot and vehicle spawns have maps of their own")


IMAGES = {"zones": img_zones, "loot": img_loot, "vehicles": img_vehicles, "drops": img_drops, "fixtures": img_fixtures, "features": img_features, "puzzles": img_puzzles, "spawns": img_spawns, "shelters": img_shelters, "overview": img_overview}


def palette_png(im: Image.Image, path: Path):
    """256-colour PNG with dithering: a third of the size of the RGB file, no visible loss on the flat radar map."""
    im.convert("RGB").quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.FLOYDSTEINBERG).save(path, optimize=True)


def publish(name: str, im: Image.Image, wiki: Path | None):
    path = OUT / f"{name}.png"
    palette_png(im, path)
    line = f"wrote {path} ({im.width} px)"
    if wiki:
        (wiki / "images" / "map").mkdir(parents=True, exist_ok=True)
        small = im if im.width <= WIKI_MAX else im.resize((WIKI_MAX, round(im.height * WIKI_MAX / im.width)), Image.LANCZOS)
        palette_png(small, wiki / "images" / "map" / f"{name}.png")
        line += f" + {wiki / 'images' / 'map' / (name + '.png')} ({small.width} px)"
    print(line)


def main():
    ap = argparse.ArgumentParser(description="Draws the wiki's maps of Scavenge & Survive Reborn on GTA San Andreas' radar map.")
    ap.add_argument("--only", choices=["base"] + list(IMAGES), help="one image only; `base` stitches the base map again")
    ap.add_argument("--size", type=int, default=1536, help="output size in px (the base map is 1536; larger sizes upscale it)")
    ap.add_argument("--gta", help="GTA San Andreas folder (default: the registry), only needed to stitch the base map")
    ap.add_argument("--wiki", default=str(WIKI), help="the wiki clone that gets copies at most 1536 px wide")
    ap.add_argument("--no-wiki", action="store_true", help="write docs/images/map only")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    base = base_map(args.gta, args.only == "base")
    if args.only == "base":
        return
    wiki = None if args.no_wiki else Path(args.wiki)
    if wiki and not wiki.is_dir():
        print(f"render_map: no wiki clone at {wiki}, writing docs/images/map only")
        wiki = None
    world = load_world()
    for name in [args.only] if args.only else list(IMAGES):
        c = Canvas(base, args.size, TITLES[name])
        IMAGES[name](c, world)
        publish(name, c.im, wiki)


if __name__ == "__main__":
    main()
