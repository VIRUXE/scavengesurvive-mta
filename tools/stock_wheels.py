"""Stock wheel items: one wheel per GTA SA wheel style, inflated and flat.

    python -m tools.stock_wheels

Models each wheel in Blender as a lathe (rounded tyre, dished rim, open barrel at the back) at the size of the
vehicles that drop it, and writes prop_models/files/wheel_<type>.dff and wheel_<type>_flat.dff (face up, origin on
the ground) with day and night vertex colours, one shared stock_wheels.txd holding the textures of
models/generic/wheels.txd, a box collision each, then props.lua and meta.xml. Item rows go into
data/generated/item_types.lua and sql/seed/0001_item_types.sql. The converter is retired, so those two files are
edited in place.

Ids 20237-20246 are the inflated wheels. 20247-20256 are the same wheels with the tyre caved in. The generic Wheel
item (20222) is unchanged. Both sets lie face-up: that is how a wheel item rests, so rotx/roty/rotz stay 0 and
modelz stays 0.

The reviewed HD PNGs in tools/data/wheel_hd/stock_wheels supersede the game's 64px textures.
write_stock_txd preserves those repaints on rebuild; python -m tools.wheel_hd build writes
only the two wheel TXDs, without changing models, collisions, item rows or registration.
"""
from __future__ import annotations

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
    """Inflated wheels first (20237+), then the flat discs."""
    rows = []
    n = 0
    for flat in (False, True):
        for key, label, stem in TYPES:
            rows.append({
                "key": key,
                "flat": flat,
                "id": FIRST_ID + n,
                "asset": f"wheel_{key}_flat" if flat else f"wheel_{key}",
                "uname": f"Wheel{stem}Flat" if flat else f"Wheel{stem}",
                "name": f"{label} Wheel (Flat)" if flat else f"{label} Wheel",
                "dist": 80,
                "txd": TXD_NAME,
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
}
SEGMENTS = 20
TYRE_TEX = "tyre64a"
BARREL_COLOUR = (0.3, 0.3, 0.31)
# The game draws a prelit prop at about 2.8 times texture x vertex colour (measured in game on the tread), so the
# near-black 2001 tyre texture wants nearly full light and the bright wheel faces about half of it.
SURFACE_LIGHT = {"barrel": 0.8, "tread": 1.0, "face": 0.55}


def face_texture(key: str) -> str:
    return "whee_rim64" if key == "rim" else f"wheel_{key}64"


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
    out = min((radius - rim) / (0.5 * (r - rim)), 1.0)  # 0 at the bead, 1 from mid-sidewall out
    up = height / w
    sag = 0.24 * w * (1.0 + 0.22 * math.sin(2 * angle + 1.0) + 0.14 * math.sin(5 * angle + 0.4))
    height = height - sag * out * up
    radius = radius + r * out * (0.045 * (1.0 - up) - 0.012 * up + 0.01 * math.sin(3 * angle + 2.0))
    return radius, max(height, 0.0)


def sync_items() -> None:
    """Insert the twenty item types if they are not already in the hand-edited generated files."""
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
        print("stock_wheels: item_types.lua already has the stock wheels")
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
        print("stock_wheels: item seed already has the stock wheels")


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


def register() -> None:
    from tools.make_props import PROPS, PROP_MODELS, render_props, write_meta

    PROPS.write_text(render_props(), encoding="ascii", newline="\n")
    write_meta(PROP_MODELS)
    write_stock_txd()
    sync_items()
    print("stock_wheels: wrote props.lua and meta.xml")


def _export_in_blender(out_dir: str) -> None:
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
        profile = wheel_profile(key)
        tread = [i for i, p in enumerate(profile) if p[2] == "tread"]
        first, last = tread[0], tread[-1] + 1
        # the tread texture spans the band once across, by distance, and repeats round it at the same scale
        along = [0.0]
        for i in range(first, last):
            along.append(along[-1] + math.dist(profile[i][:2], profile[i + 1][:2]))
        repeats = max(1, round(2 * math.pi * r / along[-1]))

        mesh = bpy.data.meshes.new(w["asset"])
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day = bm.loops.layers.color.new("Day")
        night = bm.loops.layers.color.new("Night")
        rings = []
        for radius, height, _surface, _light in profile:
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
        for i in range(len(profile) - 1):
            surface = profile[i][2]
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
                    radius = profile[pi][0]
                    angle = 2 * math.pi * si / SEGMENTS
                    if surface == "tread":
                        # the texture's ribs run up it, so v goes round the tyre and u across the tread
                        loop[uv].uv = (along[pi - first] / along[-1], turn * repeats / SEGMENTS)
                    else:
                        loop[uv].uv = (0.5 + 0.5 * radius * math.cos(angle) / r, 0.5 + 0.5 * radius * math.sin(angle) / r)
                    light = profile[pi][3] * SURFACE_LIGHT[surface]
                    if flat and surface != "barrel" and radius > SPECS[key][2] * r:
                        light *= 0.92
                    loop[day] = (light, light, light, 1.0)
                    loop[night] = (light * 0.3, light * 0.3, light * 0.32, 1.0)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        mesh.set_sharp_from_angle(angle=math.radians(50))
        mesh.materials.append(material("wheel_barrel", None, BARREL_COLOUR))
        mesh.materials.append(material(TYRE_TEX, TYRE_TEX, (1, 1, 1)))
        mesh.materials.append(material(face_texture(key), face_texture(key), (1, 1, 1)))
        ob = bpy.data.objects.new(w["asset"], mesh)
        ob.dff.type = "OBJ"
        ob.dff.day_cols = True
        ob.dff.night_cols = True
        bpy.context.scene.collection.objects.link(ob)
        return ob

    for w in catalog():
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


def export_models() -> None:
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
    cmd = [str(blender), "-b", "--python", str(Path(__file__).resolve()), "--", str(FILES)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    interesting = [ln for ln in (res.stdout + res.stderr).splitlines() if "stock_wheels" in ln or "Error" in ln or "Traceback" in ln]
    print("\n".join(interesting[-40:]))
    if res.returncode != 0:
        raise SystemExit(f"stock_wheels: blender export failed ({res.returncode})")
    for w in catalog():
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


def main() -> int:
    export_models()
    register()
    return 0


if __name__ == "__main__":
    if "bpy" in sys.modules:
        _export_in_blender(sys.argv[sys.argv.index("--") + 1])
    else:
        sys.exit(main())
