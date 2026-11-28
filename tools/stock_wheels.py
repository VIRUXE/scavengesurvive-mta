"""Wheel items: one wheel per GTA SA wheel style and five special vehicle wheels, each inflated and flat.

    python -m tools.stock_wheels                       # all thirty models, then registration and item rows
    python -m tools.stock_wheels --only heavy,monster  # just those styles' two models each, then the same
    python -m tools.stock_wheels textures              # the special wheels' PNGs, rendered from the game's wheels

Models each wheel in Blender as a lathe (rounded tyre, dished rim, open barrel at the back) at the size of the
vehicles that drop it, and writes prop_models/files/wheel_<type>.dff and wheel_<type>_flat.dff (face up, origin on
the ground) with day and night vertex colours, a box collision each, then props.lua and the new files' lines in
meta.xml. Item rows go into data/generated/item_types.lua and sql/seed/0001_item_types.sql. The converter is
retired, so those two files are edited in place.

The ten stock styles (TYPES) share stock_wheels.txd, the textures of models/generic/wheels.txd. Ids 20237-20246
are the inflated wheels, 20247-20256 the same wheels with the tyre caved in. The generic Wheel item (20222) is
unchanged.

The five special wheels (SPECIAL_TYPES: heavy plant, monster truck, tractor, kart, racing) are the wheels of
particular vehicles, shaped after their wheel atomics (SPECIAL_SHAPES) and textured from them in
special_wheels.txd: a face texture rendered from the real wheel face-on (orthographic, unlit, with the vehicle
wheel HD repaints of tools/data/vehicle_wheel_hd) and a tread texture cut from the vehicle's own tyre texture.
The tractor's tyre carries lugs. Ids 20313-20317 are the inflated ones, 20318-20322 the flat ones.

All thirty lie face-up: that is how a wheel item rests, so rotx/roty/rotz stay 0 and modelz stays 0.

The reviewed HD PNGs in tools/data/wheel_hd/stock_wheels supersede the game's 64px textures and
tools/data/wheel_hd/special_wheels holds the special wheels' (written by the textures command, which needs the
game and DragonFF). A build only rewrites the dictionaries of the styles it builds; python -m tools.wheel_hd
build writes the wheel TXDs alone, without changing models, collisions, item rows or registration.
"""
from __future__ import annotations

import os
import re
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
FILES = ROOT / "resources" / "[scavengesurvive]" / "prop_models" / "files"
ITEM_LUA = ROOT / "resources" / "[scavengesurvive]" / "data" / "generated" / "item_types.lua"
ITEM_SQL = ROOT / "sql" / "seed" / "0001_item_types.sql"
GTA = Path("/gta/sa/gamefiles/GTA San Andreas/models/generic")
TXD = GTA / "wheels.txd"
TXD_NAME = "stock_wheels"
FIRST_ID = 20237
SPECIAL_TXD = "special_wheels"
SPECIAL_FIRST_ID = 20313
# the game install the special wheels' textures are rendered from: $GTA_SA, the Windows box, the Linux box
GTA_DIRS = [os.environ.get("GTA_SA", ""), "D:/Games/gtasa", "/gta/sa/gamefiles/GTA San Andreas"]

# style key, display label, uname stem (Wheel + stem, Wheel + stem + Flat)
TYPES = [
    ("smallcar", "Small Car", "Smallcar"),
    ("offroad", "Offroad", "Offroad"),
    ("truck", "Truck", "Truck"),
    ("rim", "Steel Rim", "Rim"),
    ("alloy", "Alloy", "Alloy"),
    ("lightvan", "Light Van", "Lightvan"),
    ("lighttruck", "Light Truck", "Lighttruck"),
    ("classic", "Classic", "Classic"),
    ("saloon", "Saloon", "Saloon"),
    ("sport", "Sport", "Sport"),
]
# the special wheels, after the vehicles in brackets: Dumper and Dozer; Monster, Monster A and B; Tractor and
# Combine; Kart; Hotring Racers
SPECIAL_TYPES = [
    ("heavy", "Heavy Plant", "Heavy"),
    ("monster", "Monster Truck", "Monster"),
    ("tractor", "Tractor", "Tractor"),
    ("kart", "Kart", "Kart"),
    ("racing", "Racing", "Racing"),
]
SPECIAL = {key for key, _label, _stem in SPECIAL_TYPES}

# How the generic Wheel (20222) is carried: upright in both hands, resting on them. Its axle is its own X and its
# origin its centre; it is 0.984 m across.
GENERIC_HOLD = dict(attrx=258.455596, attry=346.618103, attrz=354.313049, attx=-0.098016, atty=0.356168, attz=-0.309851)
GENERIC_RADIUS = 0.492


def _rotation(rx: float, ry: float, rz: float) -> list[list[float]]:
    """items/client/attach.lua rotationMatrix: rows, a vertex is turned about Z, then Y, then X."""
    import math

    cx, sx = math.cos(math.radians(rx)), math.sin(math.radians(rx))
    cy, sy = math.cos(math.radians(ry)), math.sin(math.radians(ry))
    cz, sz = math.cos(math.radians(rz)), math.sin(math.radians(rz))
    return [
        [cz * cy, cz * sy * sx + sz * cx, -cz * sy * cx + sz * sx],
        [-sz * cy, -sz * sy * sx + cz * cx, sz * sy * cx + cz * sx],
        [sy, -cy * sx, cy * cx],
    ]


def hold(key: str) -> dict:
    """The attach offsets that carry a stock wheel as the generic Wheel is carried.

    A stock wheel lies face-up (axle on Z, origin on its back face), so it is first stood up with its face where
    the generic one's is, about its own centre, and then lowered until the smaller tyre rests on the hands again
    (the generic wheel's -Z is down in the carry).
    """
    import math

    dia, width, _k, _dish = SPECS[key]
    g = GENERIC_HOLD
    r = _rotation(g["attrx"], g["attry"], g["attrz"])
    # stock X, Y, Z in the generic wheel's axes: -Z, Y, X
    turned = [[-r[2][i] for i in range(3)], r[1], r[0]]
    drop = GENERIC_RADIUS - dia / 2
    half = width / 2
    pos = [(g["attx"], g["atty"], g["attz"])[i] - drop * r[2][i] - half * turned[2][i] for i in range(3)]
    ry = math.degrees(math.asin(max(-1.0, min(1.0, turned[2][0]))))
    rx = math.degrees(math.atan2(-turned[2][1], turned[2][2]))
    rz = math.degrees(math.atan2(-turned[1][0], turned[0][0]))
    return dict(
        attrx=round(rx % 360, 6), attry=round(ry % 360, 6), attrz=round(rz % 360, 6),
        attx=round(pos[0], 6), atty=round(pos[1], 6), attz=round(pos[2], 6),
    )  # fmt: skip


def catalog() -> list[dict]:
    """The stock wheels (20237+, inflated then flat), then the special ones (20313+, inflated then flat).

    Each set counts its ids from its own first id, so a set added later never moves an earlier set's ids.
    """
    rows = []
    for types, first, txd in ((TYPES, FIRST_ID, TXD_NAME), (SPECIAL_TYPES, SPECIAL_FIRST_ID, SPECIAL_TXD)):
        n = 0
        for flat in (False, True):
            for key, label, stem in types:
                rows.append({
                    "key": key,
                    "flat": flat,
                    "id": first + n,
                    "asset": f"wheel_{key}_flat" if flat else f"wheel_{key}",
                    "uname": f"Wheel{stem}Flat" if flat else f"Wheel{stem}",
                    "name": f"{label} Wheel (Flat)" if flat else f"{label} Wheel",
                    "dist": 80,
                    "txd": txd,
                })
                n += 1
    return rows


def props_rows() -> list[dict]:
    return [{"id": w["id"], "name": w["asset"], "dist": w["dist"], "prop_txd": w["txd"]} for w in catalog()]


# Per style: diameter and width in metres (the median wheel of the vehicles that drop it, measured from their
# DFFs), where the rim ends in the face texture as a fraction of the radius, and how deep the rim's dish is as a
# fraction of the width.
SPECS = {
    "smallcar": (0.64, 0.21, 0.77, 0.10),
    "offroad": (0.86, 0.29, 0.60, 0.22),
    "truck": (1.02, 0.33, 0.63, 0.24),
    "rim": (0.58, 0.20, 0.75, 0.20),
    "alloy": (0.72, 0.25, 0.81, 0.12),
    "lightvan": (0.72, 0.24, 0.67, 0.18),
    "lighttruck": (0.78, 0.26, 0.66, 0.20),
    "classic": (0.70, 0.24, 0.77, 0.10),
    "saloon": (0.70, 0.24, 0.75, 0.10),
    "sport": (0.70, 0.27, 0.78, 0.15),
    # The special wheels, from their vehicles' wheel atomics (diameter as the item, the rest in proportion): the
    # Dumper's (a Dozer's is the same wheel, narrower), the Monster's, the Tractor's (its rear wheel is the same
    # atomic at 1.3 m), the Kart's, the Hotring Racer's. The rim fraction is where the tyre's bead sits.
    "heavy": (1.50, 0.62, 0.48, 0.21),
    "monster": (1.50, 0.77, 0.56, 0.42),
    "tractor": (1.20, 0.43, 0.60, 0.26),
    "kart": (0.27, 0.134, 0.64, 0.45),
    "racing": (0.81, 0.30, 0.62, 0.30),
}
SEGMENTS = 20
TYRE_TEX = "tyre64a"
BARREL_COLOUR = (0.3, 0.3, 0.31)
# The game draws a prelit prop at about 2.8 times texture x vertex colour (measured in game on the tread), so the
# near-black 2001 tyre texture wants nearly full light and the bright wheel faces about half of it.
SURFACE_LIGHT = {"barrel": 0.8, "tread": 1.0, "face": 0.55}

# How each special wheel is made from its vehicle (vehicles.ide model in brackets): the DFF in gta3.img, and the
# pieces of the vehicle's tyre texture its tread texture is cut from, side by side across the tread. A piece is
# (texture, (u0, v0, u1, v1) in the DFF's UV space, how to turn it so u runs across the tread and v round it).
SPECIAL_SOURCES = {
    "heavy": ("dumper", [("vehicletyres128", (0.502, 0.252, 0.748, 0.498), "rotate")]),  # 406
    "monster": ("monster", [  # 444; the shoulder strip on either side of the chevrons, as the atomic maps it
        ("monster92tyre64", (0.375, 0.0, 0.5, 1.0), ""),
        ("monster92tyre64", (0.5, 0.0, 1.0, 1.0), "flip"),
        ("monster92tyre64", (0.375, 0.0, 0.5, 1.0), "flip"),
    ]),
    "tractor": ("tractor", [("tractor128", (0.128, 0.252, 0.247, 0.497), "rotate")]),  # 531
    "kart": ("kart", [("kart928bit128", (0.002, 0.752, 0.247, 0.873), "")]),  # 571
    "racing": ("hotring", [("hotring92tyre32", (0.0, 0.0, 1.0, 1.0), "rotate")]),  # 494
}  # fmt: skip
# Texture sizes in special_wheels.txd: faces of the big wheels at 512, the kart's and every tread at 256.
SPECIAL_FACE_SIZE = {"heavy": 512, "monster": 512, "tractor": 512, "kart": 256, "racing": 512}
SPECIAL_TREAD_SIZE = 256
# How many times the tread texture goes round: as often as on the vehicle's own wheel.
TREAD_REPEATS = {"heavy": 16, "monster": 16, "tractor": 16, "kart": 12, "racing": 12}
# How far a flat tyre's top sinks, as a fraction of the width (the stock wheels use 0.24).
FLAT_SAG = {"heavy": 0.3, "monster": 0.34, "tractor": 0.3, "kart": 0.34, "racing": 0.26}
# How much of the tyre's section, from the bead, the sag takes to reach its full depth (the stock wheels use 0.5):
# a tall sidewall folds over close to the rim instead of leaving a cone standing round it.
FLAT_RAMP = {"heavy": 0.3, "monster": 0.4, "tractor": 0.35}
# The tractor tyre's lugs: per side, height as a fraction of the radius, lean round the tyre and width (degrees).
LUGS = {"tractor": dict(count=16, height=0.07, lean=16.0, width=7.0)}


def face_texture(key: str) -> str:
    if key in SPECIAL:
        return f"wheel_{key}_face"
    return "whee_rim64" if key == "rim" else f"wheel_{key}64"


def tread_texture(key: str) -> str:
    return f"wheel_{key}_tread" if key in SPECIAL else TYRE_TEX


def special_textures() -> dict[str, tuple[int, int]]:
    """special_wheels.txd: texture name -> size."""
    sizes = {}
    for key, _label, _stem in SPECIAL_TYPES:
        sizes[face_texture(key)] = (SPECIAL_FACE_SIZE[key],) * 2
        sizes[tread_texture(key)] = (SPECIAL_TREAD_SIZE,) * 2
    return sizes


def _ellipse(cr: float, ch: float, rr: float, rh: float, a0: float, a1: float, n: int) -> list[tuple[float, float]]:
    """Points of a tyre shoulder: an ellipse round (cr, ch) with radii rr (radial) and rh (height), from angle a0 to
    a1 in degrees (0 points outward, 90 up), ends included."""
    import math

    angles = [math.radians(a0 + (a1 - a0) * i / n) for i in range(n + 1)]
    return [(cr + rr * math.cos(a), ch + rh * math.sin(a)) for a in angles]


def special_profile(key: str) -> list[tuple[float, float, str, float]]:
    """The lathe profile of a special wheel, in wheel_profile's form, from its vehicle's wheel atomic.

    The radii and heights are the atomic's, as fractions of its radius and width (the comments give the atomic's
    own numbers), so the item keeps the real wheel's section: how far the tyre stands out from the rim, how wide
    and round it is, how deep the dish sits and how far the hub comes out.
    """
    dia, w, k, _dish = SPECS[key]
    r = dia / 2
    rim = k * r

    def tyre(points, first_light, last_light):
        n = len(points) - 1
        step = (last_light - first_light) / n
        return [(pr, ph, "tread", first_light + step * i) for i, (pr, ph) in enumerate(points)]

    if key == "heavy":
        # Dumper, radius 1.198 width 1.172: bead 0.571, the sidewall out to the full width at 0.97-1.02, a flat
        # tread from -0.403 to 0.412, the disc dished in to 0.244-0.29 and the hub cap out at 0.48.
        pts = [
            (0.0, 0.34 * w, "face", 0.5),
            (0.41 * r, 0.34 * w, "barrel", 0.5),
            (0.41 * r, 0.09 * w, "barrel", 0.85),
            (rim, 0.09 * w, "face", 0.8),
            (0.56 * r, 0.035 * w, "face", 0.62),
            (0.7 * r, 0.0, "face", 0.7),
        ]
        shoulder = 0.19 * r, 0.16 * w
        pts += tyre(_ellipse(r - shoulder[0], shoulder[1], shoulder[0], shoulder[1], -90, 0, 3), 0.72, 0.84)
        pts += tyre(_ellipse(r - shoulder[0], w - shoulder[1], shoulder[0], shoulder[1], 0, 90, 3)[:-1], 0.9, 0.97)
        pts += [
            (r - shoulder[0], w, "face", 1.0),
            (0.66 * r, 0.985 * w, "face", 1.0),
            (0.55 * r, 0.95 * w, "face", 0.9),
            (rim, 0.923 * w, "barrel", 1.0),  # the rim's inner wall, bare metal as on the Dumper
            (0.44 * r, 0.71 * w, "face", 0.72),
            (0.4 * r, 0.745 * w, "face", 0.85),
            (0.35 * r, 0.735 * w, "face", 0.78),
            (0.31 * r, 0.86 * w, "face", 0.95),
            (0.14 * r, 0.9 * w, "face", 1.0),
            (0.0, 0.91 * w, "face", 1.0),
        ]
    elif key == "monster":
        # Monster, radius 0.752 width 0.768: a round balloon tyre (sidewalls flat to 0.609, then one curve over the
        # tread), the rim a deep metal barrel from 0.42 at the sidewall down to a small disc of 0.275 at 0.06-0.1.
        pts = [
            (0.0, 0.37 * w, "face", 0.5),
            (0.366 * r, 0.42 * w, "barrel", 0.5),
            (0.468 * r, 0.073 * w, "barrel", 0.8),
            (rim, 0.0, "face", 0.7),
            (0.62 * r, 0.0, "face", 0.7),
            (0.7 * r, 0.0, "face", 0.72),
        ]
        pts += tyre(_ellipse(0.81 * r, 0.5 * w, 0.19 * r, 0.5 * w, -90, 90, 10)[:-1], 0.72, 0.96)
        pts += [
            (0.81 * r, w, "face", 1.0),
            (0.72 * r, w, "face", 1.0),
            (0.64 * r, w, "face", 1.0),
            (0.6 * r, w, "face", 1.0),
            (rim, w, "face", 1.0),
            (0.468 * r, 0.927 * w, "face", 0.75),
            (0.366 * r, 0.579 * w, "face", 0.55),
            (0.3 * r, 0.6 * w, "face", 0.75),
            (0.15 * r, 0.625 * w, "face", 0.85),
            (0.0, 0.633 * w, "face", 0.9),
        ]
    elif key == "tractor":
        # Tractor, radius 0.345 (the lug tips; the carcass is 0.324) width 0.248: the bead at 0.207, a squarish
        # carcass, the disc dished in to 0.06-0.07 and the hub out at 0.12. The lugs are added by the export.
        pts = [
            (0.0, 0.45 * w, "face", 0.5),
            (0.52 * r, 0.45 * w, "barrel", 0.5),
            (0.52 * r, 0.06 * w, "barrel", 0.85),
            (rim, 0.0, "face", 0.8),
            (0.7 * r, 0.03 * w, "face", 0.65),
            (0.84 * r, 0.06 * w, "face", 0.7),
        ]
        pts += tyre([(0.89 * r, 0.075 * w), (0.925 * r, 0.11 * w), (0.94 * r, 0.2 * w), (0.945 * r, 0.5 * w),
                     (0.94 * r, 0.8 * w), (0.925 * r, 0.89 * w), (0.89 * r, 0.925 * w)], 0.74, 0.96)  # fmt: skip
        pts += [
            (0.84 * r, 0.94 * w, "face", 1.0),
            (0.72 * r, 0.975 * w, "face", 1.0),
            (rim, w, "face", 1.0),
            (0.56 * r, 0.74 * w, "face", 0.72),
            (0.5 * r, 0.785 * w, "face", 0.85),
            (0.44 * r, 0.77 * w, "face", 0.8),
            (0.4 * r, 0.92 * w, "face", 0.95),
            (0.2 * r, 0.935 * w, "face", 1.0),
            (0.0, 0.97 * w, "face", 1.0),
        ]
    elif key == "kart":
        # Kart, radius 0.135 width 0.134: a plain cylinder of a tyre (the back is a flat black disc), its face
        # rising to 0.067 at 0.086 and the hub sunk to 0.006 in a deep cone.
        pts = [
            (0.0, 0.0, "barrel", 0.45),
            (0.9 * r, 0.0, "barrel", 0.5),
        ]
        pts += tyre([(0.9 * r, 0.0), (0.97 * r, 0.02 * w), (r, 0.08 * w), (r, 0.5 * w), (r, 0.86 * w),
                     (0.985 * r, 0.91 * w)], 0.72, 0.95)  # fmt: skip
        pts += [
            (0.95 * r, 0.94 * w, "face", 1.0),
            (rim, w, "face", 1.0),
            (0.6 * r, 0.895 * w, "face", 0.8),
            (0.3 * r, 0.72 * w, "face", 0.75),
            (0.0, 0.545 * w, "face", 0.7),
        ]
    elif key == "racing":
        # Hotring Racer, radius 0.405 width 0.296: a slick from -0.132 to 0.118 with square shoulders, straight
        # sidewalls down to the bead at 0.252, five spokes sunk to 0.048 rising to the hub at 0.114.
        pts = [
            (0.0, 0.35 * w, "face", 0.5),
            (0.55 * r, 0.35 * w, "barrel", 0.5),
            (0.55 * r, 0.05 * w, "barrel", 0.85),
            (rim, 0.0, "face", 0.8),
            (0.8 * r, 0.0, "face", 0.65),
        ]
        pts += tyre([(0.93 * r, 0.015 * w), (0.98 * r, 0.035 * w), (r, 0.07 * w), (r, 0.5 * w), (r, 0.88 * w),
                     (0.98 * r, 0.93 * w)], 0.72, 0.96)  # fmt: skip
        pts += [
            (0.93 * r, 0.965 * w, "face", 1.0),  # the sidewall from here in carries the lettering
            (0.785 * r, w, "face", 1.0),
            (rim, 0.95 * w, "barrel", 0.45),  # the rim's inner wall, in the spokes' shadow
            (0.6 * r, 0.66 * w, "face", 0.72),
            (0.43 * r, 0.66 * w, "face", 0.8),
            (0.25 * r, 0.76 * w, "face", 0.9),
            (0.11 * r, 0.86 * w, "face", 1.0),
            (0.0, 0.88 * w, "face", 1.0),
        ]
    else:
        raise KeyError(key)
    return pts


def profile(key: str) -> list[tuple[float, float, str, float]]:
    return special_profile(key) if key in SPECIAL else wheel_profile(key)


def wheel_profile(key: str) -> list[tuple[float, float, str, float]]:
    """The lathe profile of a wheel lying face-up, back centre to front centre: (radius, height, surface, light).

    `surface` is what the band from this point to the next is drawn with: "barrel" (bare metal, untextured),
    "face" (the style's wheel texture, projected straight down) or "tread" (the tyre texture, wrapped round).
    `light` is the day vertex colour, darker where the wheel shades itself.
    """
    import math

    dia, w, k, dish = SPECS[key]
    r = dia / 2
    rim = k * r
    t = r - rim  # the tyre's section height
    s = min(0.5 * t, 0.22 * w)  # shoulder radius
    lo, hi = 0.02 * w, 0.98 * w
    barrel = rim * 0.86
    bulge = (rim + 0.06 * t + r - s) / 2  # the sidewall is widest midway between bead and shoulder
    pts = [
        (0.0, 0.58 * w, "face", 0.5),  # the back of the wheel face, seen down the barrel
        (barrel, 0.58 * w, "barrel", 0.5),
        (barrel, 0.07 * w, "barrel", 0.85),
        (rim, lo, "face", 0.8),
        (rim + 0.06 * t, 0.06 * w, "face", 0.62),
        (bulge, 0.0, "face", 0.7),
        (r - s, lo, "tread", 0.72),
    ]
    for a in (30, 60):
        pts.append((r - s + s * math.sin(math.radians(a)), lo + s - s * math.cos(math.radians(a)), "tread", 0.78))
    pts.append((r, lo + s, "tread", 0.84))
    pts.append((r, hi - s, "tread", 0.9))
    for a in (60, 30):
        pts.append((r - s + s * math.sin(math.radians(a)), hi - s + s * math.cos(math.radians(a)), "tread", 0.95))
    pts += [
        (r - s, hi, "face", 1.0),
        (bulge, w, "face", 1.0),
        (rim + 0.06 * t, 0.94 * w, "face", 0.82),
        (rim, hi, "face", 1.0),
        (rim - 0.05 * r, 0.965 * w, "face", 0.9),
        (rim * 0.66, w * (1 - dish), "face", 0.72),
        (rim * 0.42, w * (1 - dish * 0.8), "face", 0.82),
        (rim * 0.3, 0.96 * w, "face", 0.97),
        (0.0, 0.97 * w, "face", 1.0),
    ]
    return pts


def deflated(key: str, radius: float, height: float, angle: float) -> tuple[float, float]:
    """Where a tyre point ends up once the air is out: the upper sidewall caves in unevenly round the wheel
    and the carcass slumps outward at the ground. The rim does not move."""
    import math

    dia, w, k, _dish = SPECS[key]
    r = dia / 2
    rim = k * r
    if radius <= rim + 1e-6:
        return radius, height
    out = min((radius - rim) / (FLAT_RAMP.get(key, 0.5) * (r - rim)), 1.0)  # 0 at the bead, 1 from mid-sidewall out
    up = height / w
    sag = FLAT_SAG.get(key, 0.24) * w * (1.0 + 0.22 * math.sin(2 * angle + 1.0) + 0.14 * math.sin(5 * angle + 0.4))
    height = height - sag * out * up
    radius = radius + r * out * (0.045 * (1.0 - up) - 0.012 * up + 0.01 * math.sin(3 * angle + 2.0))
    return radius, max(height, 0.0)


def sync_items() -> None:
    """Insert the thirty item types that are not already in the hand-edited generated files."""
    rows = catalog()
    lua = ITEM_LUA.read_text(encoding="utf-8")
    missing = [w for w in rows if f'uname = "{w["uname"]}"' not in lua]
    if missing:
        lines = []
        for w in missing:
            lines.append(
                "M.byUname.{uname} = {{ attrx = {attrx}, attry = {attry}, attrz = {attrz}, "
                "attx = {attx}, atty = {atty}, attz = {attz}, boneid = 6, buttonz = 0.96, "
                'category = "generic", categoryData = nil, colour = -1, longPickup = false, '
                "maxHitpoints = 5, model = {id}, modelz = 0.0, name = \"{name}\", price = 1, "
                "rotx = 0.0, roty = 0.0, rotz = 0.0, size = 5, uname = \"{uname}\", useCarryAnim = true }}".format(
                    **w, **hold(w["key"])
                )
            )
        block = "\n".join(lines) + "\n"
        lua = lua.replace("M.order = ", block + "M.order = ", 1)
        unames = ", ".join(f'"{w["uname"]}"' for w in missing)
        order_at = lua.find("M.order = ")
        close = lua.find("}", order_at)
        if order_at < 0 or close < 0:
            raise SystemExit("item_types.lua: M.order line is not the shape this edit expects")
        lua = lua[:close] + ", " + unames + lua[close:]
        ITEM_LUA.write_text(lua, encoding="utf-8", newline="\n")
        print(f"stock_wheels: added {len(missing)} item types to item_types.lua")
    else:
        print("stock_wheels: item_types.lua already has every wheel")
    # the carry offsets follow the model's size, so rows already there are brought up to date
    lua = ITEM_LUA.read_text(encoding="utf-8")
    fresh = lua
    for w in rows:
        offsets = ", ".join(f"{k} = {v}" for k, v in hold(w["key"]).items())
        fresh = re.sub(
            rf"(M\.byUname\.{w['uname']} = \{{ )attrx = [^,]+, attry = [^,]+, attrz = [^,]+, attx = [^,]+, "
            r"atty = [^,]+, attz = [^,]+",
            lambda m, offsets=offsets: m.group(1) + offsets,
            fresh,
        )
    if fresh != lua:
        ITEM_LUA.write_text(fresh, encoding="utf-8", newline="\n")
        print("stock_wheels: carry offsets updated in item_types.lua")

    sql = ITEM_SQL.read_text(encoding="utf-8")
    missing_sql = [w for w in rows if f"('{w['uname']}'" not in sql]
    if missing_sql:
        values = ",\n".join(
            f"('{w['uname']}','{w['name']}',{w['id']},5,5,'generic',NULL)" for w in missing_sql
        )
        sql = sql.rstrip() + (
            "\n\nINSERT INTO item_types (uname,name,model,size,max_hitpoints,category,category_data) VALUES\n"
            + values
            + "\nON DUPLICATE KEY UPDATE name=VALUES(name), model=VALUES(model), size=VALUES(size), "
            "max_hitpoints=VALUES(max_hitpoints), category=VALUES(category), category_data=VALUES(category_data);\n"
        )
        ITEM_SQL.write_text(sql, encoding="utf-8", newline="\n")
        print(f"stock_wheels: added {len(missing_sql)} item types to 0001_item_types.sql")
    else:
        print("stock_wheels: item seed already has every wheel")


def write_stock_txd() -> None:
    """Prefer the UV-compatible HD repaints, encoded as D3D9 BC1 with full mipmaps."""
    from tools.wheel_hd import SOURCE, build

    if (SOURCE / TXD_NAME).is_dir():
        build(TXD_NAME)
        return

    # Legacy fallback: wheels.txd is D3D8 DXT1; MTA needs a D3D9 native.
    import sys

    sys.path.insert(0, "/root/.config/blender/5.2/scripts/addons/DragonFF")
    from gtaLib.txd import txd

    from tools.make_vending import native_rgba, write_txd

    src = txd()
    src.load_file(str(TXD))
    natives = []
    for tex in src.native_textures or src.textures:
        rgba = tex.to_rgba()
        bgra = bytearray(len(rgba))
        bgra[0::4] = rgba[2::4]
        bgra[1::4] = rgba[1::4]
        bgra[2::4] = rgba[0::4]
        bgra[3::4] = rgba[3::4]
        natives.append(native_rgba(tex.name, tex.width, tex.height, bytes(bgra), False))
    write_txd(FILES / f"{TXD_NAME}.txd", natives)
    print(f"stock_wheels: {TXD_NAME}.txd ({len(natives)} textures)")


def write_meta_rows(assets: list[str], txds: list[str]) -> None:
    """Add the files of these wheels to prop_models/meta.xml, each before the first listed file named after it.

    make_props.write_meta would regenerate the whole list, and the hand-edited meta.xml has lines it does not
    know about, so only the missing lines go in.
    """
    from tools.make_props import PROP_MODELS

    path = PROP_MODELS / "meta.xml"
    text = path.read_text(encoding="ascii")
    names = sorted({f"{a}.{ext}" for a in assets for ext in ("col", "dff")} | {f"{t}.txd" for t in txds})
    lines = text.split("\n")
    added = 0
    for name in names:
        line = f'    <file src="files/{name}"/>'
        if line in lines:
            continue
        files = [i for i, ln in enumerate(lines) if ln.startswith('    <file src="files/')]
        at = next((i for i in files if lines[i] > line and lines[i - 1] < line), files[-1] + 1)
        lines.insert(at, line)
        added += 1
    if added:
        path.write_text("\n".join(lines), encoding="ascii", newline="\n")
    print(f"stock_wheels: {added} files added to meta.xml")


def write_txds(keys: list[str]) -> None:
    """The dictionaries of these styles, from the reviewed PNGs."""
    from tools.wheel_hd import build

    if any(k not in SPECIAL for k in keys):
        write_stock_txd()
    if any(k in SPECIAL for k in keys):
        build(SPECIAL_TXD)


def register(keys: list[str]) -> None:
    from tools.make_props import PROPS, render_props

    PROPS.write_text(render_props(), encoding="ascii", newline="\n")
    rows = [w for w in catalog() if w["key"] in keys]
    write_meta_rows([w["asset"] for w in rows], sorted({w["txd"] for w in rows}))
    write_txds(keys)
    sync_items()
    print("stock_wheels: wrote props.lua and meta.xml")


def _export_in_blender(out_dir: str, keys: list[str]) -> None:
    import math
    import os

    import bmesh
    import bpy

    out = Path(out_dir)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")

    def material(name, texture, colour):
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (colour[0], colour[1], colour[2], 1)
        if texture:
            node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = bpy.data.images.new(texture + ".png", 4, 4)  # DragonFF writes the name; the TXD has the pixels
            mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        return mat

    def build(w):
        key, flat = w["key"], w["flat"]
        dia, width, _k, _dish = SPECS[key]
        r = dia / 2
        shape = profile(key)
        tread = [i for i, p in enumerate(shape) if p[2] == "tread"]
        first, last = tread[0], tread[-1] + 1
        # the tread texture spans the band once across, by distance, and repeats round it at the same scale (a
        # special wheel's as often as on its vehicle)
        along = [0.0]
        for i in range(first, last):
            along.append(along[-1] + math.dist(shape[i][:2], shape[i + 1][:2]))
        repeats = TREAD_REPEATS.get(key) or max(1, round(2 * math.pi * r / along[-1]))

        mesh = bpy.data.meshes.new(w["asset"])
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day = bm.loops.layers.color.new("Day")
        night = bm.loops.layers.color.new("Night")
        rings = []
        for radius, height, _surface, _light in shape:
            if radius < 1e-6:
                rings.append([bm.verts.new((0.0, 0.0, height))] * SEGMENTS)
                continue
            ring = []
            for s in range(SEGMENTS):
                angle = 2 * math.pi * s / SEGMENTS
                pr, pz = deflated(key, radius, height, angle) if flat else (radius, height)
                ring.append(bm.verts.new((pr * math.cos(angle), pr * math.sin(angle), pz)))
            rings.append(ring)

        slot = {"barrel": 0, "tread": 1, "face": 2}
        for i in range(len(shape) - 1):
            surface = shape[i][2]
            for s in range(SEGMENTS):
                n = (s + 1) % SEGMENTS
                corners = [(i, s, s), (i, n, s + 1), (i + 1, n, s + 1), (i + 1, s, s)]
                verts, keep = [], []
                for c in corners:
                    v = rings[c[0]][c[1]]
                    if v not in verts:
                        verts.append(v)
                        keep.append(c)
                if len(verts) < 3:
                    continue
                face = bm.faces.new(verts)
                face.material_index = slot[surface]
                face.smooth = True
                for loop, (pi, si, turn) in zip(face.loops, keep):
                    # the undeformed position maps the texture, so a flat tyre's sidewall keeps its lettering
                    radius = shape[pi][0]
                    angle = 2 * math.pi * si / SEGMENTS
                    if surface == "tread":
                        # the texture's ribs run up it, so v goes round the tyre and u across the tread
                        loop[uv].uv = (along[pi - first] / along[-1], turn * repeats / SEGMENTS)
                    else:
                        loop[uv].uv = (0.5 + 0.5 * radius * math.cos(angle) / r, 0.5 + 0.5 * radius * math.sin(angle) / r)
                    light = shape[pi][3] * SURFACE_LIGHT[surface]
                    if flat and surface != "barrel" and radius > SPECS[key][2] * r:
                        light *= 0.92
                    loop[day] = (light, light, light, 1.0)
                    loop[night] = (light * 0.3, light * 0.3, light * 0.32, 1.0)
        if key in LUGS:
            lugs(bm, key, flat, uv, day, night, repeats)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        mesh.set_sharp_from_angle(angle=math.radians(50))
        mesh.materials.append(material("wheel_barrel", None, BARREL_COLOUR))
        mesh.materials.append(material(tread_texture(key), tread_texture(key), (1, 1, 1)))
        mesh.materials.append(material(face_texture(key), face_texture(key), (1, 1, 1)))
        ob = bpy.data.objects.new(w["asset"], mesh)
        ob.dff.type = "OBJ"
        ob.dff.day_cols = True
        ob.dff.night_cols = True
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def lugs(bm, key, flat, uv, day, night, repeats):
        """Chevron lugs on the tread, each a closed block from just under the carcass out to the full radius,
        running from the middle of the tread out to a shoulder and leaning round the tyre as it goes."""
        dia, width, _k, _dish = SPECS[key]
        r = dia / 2
        spec = LUGS[key]
        base, top = r * (1.0 - spec["height"]) - 0.02 * r, r
        for side in (-1, 1):
            for j in range(spec["count"]):
                start = 2 * math.pi * (j + (0.5 if side > 0 else 0.0)) / spec["count"]
                block = []
                for radius, narrow in ((base, 1.0), (top, 0.75)):
                    for t in (0.0, 1.0):
                        height = width * (0.5 - side * 0.03 + side * 0.4 * t)
                        centre = start + math.radians(spec["lean"]) * t
                        half = math.radians(spec["width"]) / 2 * narrow
                        for a in (centre - half, centre + half):
                            pr, pz = deflated(key, radius, height, a) if flat else (radius, height)
                            block.append((bm.verts.new((pr * math.cos(a), pr * math.sin(a), pz)), a, height))
                # base: 0 1 (middle end), 2 3 (shoulder end); top: 4 5, 6 7
                for quad, light in (((4, 5, 7, 6), 0.95), ((0, 1, 5, 4), 0.8), ((2, 3, 7, 6), 0.8),
                                    ((0, 2, 6, 4), 0.75), ((1, 3, 7, 5), 0.75), ((0, 1, 3, 2), 0.5)):  # fmt: skip
                    face = bm.faces.new([block[q][0] for q in quad])
                    face.material_index = 1
                    face.smooth = False
                    lit = light * SURFACE_LIGHT["tread"] * (0.92 if flat else 1.0)
                    for loop, q in zip(face.loops, quad):
                        _v, a, height = block[q]
                        loop[uv].uv = (height / width, a * repeats / (2 * math.pi))
                        loop[day] = (lit, lit, lit, 1.0)
                        loop[night] = (lit * 0.3, lit * 0.3, lit * 0.32, 1.0)

    for w in [w for w in catalog() if w["key"] in keys]:
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        # a texture an earlier wheel used would come back as "name.png.001", and DragonFF writes that name into the DFF
        for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
            for item in list(block):
                block.remove(item)
        ob = build(w)
        bpy.context.view_layer.update()
        bpy.ops.export_dff.scene(
            filepath=str(out / f"{w['asset']}.dff"),
            export_coll=False,
            only_selected=False,
            export_version="0x36003",
        )
        dims = tuple(round(v, 3) for v in ob.dimensions)
        print(f"stock_wheels: {w['asset']} tris={sum(len(p.vertices) - 2 for p in ob.data.polygons)} size={dims}")
    os._exit(0)


def export_models(keys: list[str]) -> None:
    import subprocess

    from tools.extract_ped_models import find_blender
    from tools.vanilla_props import box_col, geometry_bounds

    blender = find_blender(None) or shutil.which("blender")
    if not blender:
        raise SystemExit("stock_wheels: blender not found")
    addon = Path("/root/.config/blender/5.3/scripts/addons/DragonFF")
    src = Path("/root/.config/blender/5.2/scripts/addons/DragonFF")
    if not addon.exists() and src.is_dir():
        addon.parent.mkdir(parents=True, exist_ok=True)
        addon.symlink_to(src)
    FILES.mkdir(parents=True, exist_ok=True)
    cmd = [str(blender), "-b", "--python", str(Path(__file__).resolve()), "--", str(FILES), ",".join(keys)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    interesting = [ln for ln in (res.stdout + res.stderr).splitlines() if "stock_wheels" in ln or "Error" in ln or "Traceback" in ln]
    print("\n".join(interesting[-40:]))
    if res.returncode != 0:
        raise SystemExit(f"stock_wheels: blender export failed ({res.returncode})")
    for w in [w for w in catalog() if w["key"] in keys]:
        path = FILES / f"{w['asset']}.dff"
        if not path.is_file() or path.stat().st_size < 500:
            raise SystemExit(f"stock_wheels: missing {path.name}")
        lo, hi = geometry_bounds(path.read_bytes())
        if not all(map(math_finite, lo + hi)):
            raise SystemExit(f"stock_wheels: bad bounds on {path.name}: {lo} .. {hi}")
        (FILES / f"{w['asset']}.col").write_bytes(box_col(w["asset"], lo, hi))
        print(f"stock_wheels: {w['asset']} bounds {tuple(round(v, 3) for v in lo)} .. {tuple(round(v, 3) for v in hi)}")


def math_finite(v: float) -> bool:
    return v == v and abs(v) != float("inf")


def _gta_dir() -> Path:
    for cand in GTA_DIRS:
        if cand and (Path(cand) / "models" / "gta3.img").is_file():
            return Path(cand)
    raise SystemExit("stock_wheels: GTA San Andreas not found; set GTA_SA to the install")


def make_textures(keys: list[str]) -> None:
    """Render each special wheel's face and cut its tread into tools/data/wheel_hd/special_wheels.

    The face is the vehicle's wheel atomic seen straight on from outside, orthographic and unlit, with the
    vehicle wheel HD repaints (tools/data/vehicle_wheel_hd), the disc filling the square as the lathe's projection
    expects. The tread is the pieces of SPECIAL_SOURCES side by side, scaled to a square.
    """
    import json
    import subprocess
    import tempfile

    from PIL import Image

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import read_img_entry, read_img_index
    from tools.wheel_hd import SOURCE

    hd = ROOT / "tools" / "data" / "vehicle_wheel_hd"
    inventory = json.loads((hd / "inventory.json").read_text(encoding="utf-8"))
    models = {m["name"]: m for m in inventory["models"]}
    img = _gta_dir() / "models" / "gta3.img"
    index = read_img_index(img)
    out = SOURCE / SPECIAL_TXD
    out.mkdir(parents=True, exist_ok=True)

    def repaint(model: str, texture: str) -> Path:
        return hd / inventory["textures"][models[model]["textures"][texture]]["repaint"]

    with tempfile.TemporaryDirectory() as tmp:
        jobs = []
        for key in keys:
            model, _pieces = SPECIAL_SOURCES[key]
            dff = Path(tmp) / f"{model}.dff"
            dff.write_bytes(read_img_entry(img, index[f"{model}.dff"]))
            jobs.append({
                "dff": str(dff),
                "textures": {name: str(repaint(model, name)) for name in models[model]["textures"]},
                "out": str(out / f"{face_texture(key)}.png"),
                "size": SPECIAL_FACE_SIZE[key],
            })  # fmt: skip
        (Path(tmp) / "jobs.json").write_text(json.dumps(jobs), encoding="utf-8")
        blender = find_blender(None) or shutil.which("blender")
        if not blender:
            raise SystemExit("stock_wheels: blender not found")
        cmd = [str(blender), "-b", "--python-exit-code", "1", "--python", str(Path(__file__).resolve()),
               "--", "faces", str(Path(tmp) / "jobs.json")]  # fmt: skip
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode != 0:
            print((res.stdout + res.stderr)[-3000:])
            raise SystemExit(f"stock_wheels: face render failed ({res.returncode})")
    for key in keys:
        with Image.open(out / f"{face_texture(key)}.png") as face:
            face = face.convert("RGB")
        face.save(out / f"{face_texture(key)}.png")
        model, pieces = SPECIAL_SOURCES[key]
        cut = []
        for texture, (u0, v0, u1, v1), turn in pieces:
            with Image.open(repaint(model, texture)) as src:
                src = src.convert("RGB")
            w, h = src.size
            piece = src.crop((round(u0 * w), round(v0 * h), round(u1 * w), round(v1 * h)))
            if turn == "rotate":
                piece = piece.transpose(Image.Transpose.ROTATE_90)
            elif turn == "flip":
                piece = piece.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            cut.append(piece)
        height = max(p.height for p in cut)
        cut = [p.resize((max(1, round(p.width * height / p.height)), height), Image.Resampling.LANCZOS) for p in cut]
        tread = Image.new("RGB", (sum(p.width for p in cut), height))
        x = 0
        for p in cut:
            tread.paste(p, (x, 0))
            x += p.width
        tread = tread.resize((SPECIAL_TREAD_SIZE,) * 2, Image.Resampling.LANCZOS)
        tread.save(out / f"{tread_texture(key)}.png")
        print(f"stock_wheels: {key} face and tread in {out}")


def _render_faces_in_blender(jobs_path: str) -> None:
    import json
    import math

    import bpy
    from mathutils import Vector

    for job in json.loads(Path(jobs_path).read_text(encoding="utf-8")):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        from DragonFF.gtaLib import dff as gdff

        scene = bpy.context.scene
        scene.render.engine = "BLENDER_WORKBENCH"
        scene.render.resolution_x = scene.render.resolution_y = job["size"]
        scene.render.resolution_percentage = 100
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGB"
        scene.display.shading.light = "FLAT"
        scene.display.shading.color_type = "TEXTURE"
        scene.display.shading.show_cavity = False
        scene.display.shading.show_shadows = False
        scene.display.shading.show_specular_highlight = False
        scene.display.shading.background_type = "WORLD"
        scene.world = bpy.data.worlds.new("WheelFace")
        scene.world.color = (0.02, 0.02, 0.02)
        scene.view_settings.view_transform = "Standard"
        scene.display.render_aa = "32"

        model = gdff.dff()
        model.load_file(job["dff"])
        clump = model.clumps[0]
        geometry = None
        for atomic in clump.atomic_list:
            chain, frame = [], atomic.frame
            while frame >= 0:
                chain.append(clump.frame_list[frame].name.lower())
                frame = clump.frame_list[frame].parent
            g = clump.geometry_list[atomic.geometry]
            if g.triangles and any(re.match(r"^wheel(?:$|_)", n) for n in chain):
                geometry = g
                break
        if geometry is None:
            raise ValueError(f"{job['dff']}: no wheel atomic")
        verts = [Vector(v) for v in geometry.vertices]
        mesh = bpy.data.meshes.new("Wheel")
        mesh.from_pydata(verts, [], [(t.a, t.b, t.c) for t in geometry.triangles])
        wheel = bpy.data.objects.new("Wheel", mesh)
        scene.collection.objects.link(wheel)
        for slot, mat in enumerate(geometry.materials):
            material = bpy.data.materials.new(f"MAT_{slot}")
            material.use_nodes = True
            material.diffuse_color = tuple(c / 255 for c in mat.color)
            if mat.textures:
                node = material.node_tree.nodes.new("ShaderNodeTexImage")
                node.interpolation = "Linear"
                node.image = bpy.data.images.load(job["textures"][mat.textures[0].name.lower()], check_existing=True)
                material.node_tree.nodes.active = node
            mesh.materials.append(material)
        uv = mesh.uv_layers.new()
        for polygon, tri in zip(mesh.polygons, geometry.triangles):
            polygon.material_index = tri.material
            for loop, vertex in zip(polygon.loop_indices, (tri.a, tri.b, tri.c)):
                coord = geometry.uv_layers[0][vertex]
                uv.data[loop].uv = (coord.u, 1 - coord.v)
        # the axle is the thinnest extent (X on these wheels, whose outside is +X); the disc is centred round it
        lo = Vector([min(v[i] for v in verts) for i in range(3)])
        hi = Vector([max(v[i] for v in verts) for i in range(3)])
        radius = max(math.hypot(v.y - (lo.y + hi.y) / 2, v.z - (lo.z + hi.z) / 2) for v in verts)
        camera = bpy.data.objects.new("Camera", bpy.data.cameras.new("Camera"))
        scene.collection.objects.link(camera)
        scene.camera = camera
        camera.data.type = "ORTHO"
        camera.data.ortho_scale = 2 * radius
        camera.data.clip_start, camera.data.clip_end = 0.001, 100
        camera.location = Vector((hi.x + 1.0, (lo.y + hi.y) / 2, (lo.z + hi.z) / 2))
        camera.rotation_euler = (math.pi / 2, 0, math.pi / 2)  # looking down -X, Z up
        scene.render.filepath = job["out"]
        bpy.ops.render.render(write_still=True)
        print("stock_wheels: face", job["out"], flush=True)


def main(argv: list[str] | None = None) -> int:
    import argparse

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", choices=("build", "textures"), default="build")
    parser.add_argument("--only", help="comma-separated style keys (default: every style; textures: the special ones)")
    args = parser.parse_args(argv)
    every = [key for key, _label, _stem in TYPES + SPECIAL_TYPES]
    keys = args.only.split(",") if args.only else None
    if keys and set(keys) - set(every):
        raise SystemExit(f"stock_wheels: unknown styles {sorted(set(keys) - set(every))}")
    if args.command == "textures":
        keys = keys or [key for key, _label, _stem in SPECIAL_TYPES]
        if set(keys) - SPECIAL:
            raise SystemExit("stock_wheels: only the special wheels' textures are rendered")
        make_textures(keys)
        return 0
    keys = keys or every
    export_models(keys)
    register(keys)
    return 0


if __name__ == "__main__":
    if "bpy" in sys.modules:
        args = sys.argv[sys.argv.index("--") + 1 :]
        if args[0] == "faces":
            _render_faces_in_blender(args[1])
        else:
            _export_in_blender(args[0], args[1].split(","))
    else:
        sys.exit(main())
