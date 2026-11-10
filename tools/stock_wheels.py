"""Stock wheel items: the ten GTA SA meshes in models/generic/wheels.dff, inflated and flat.

    python -m tools.stock_wheels

Writes prop_models/files/wheel_<type>.dff and wheel_<type>_flat.dff (face up, origin on the
ground), one shared stock_wheels.txd, a box collision each, then props.lua and meta.xml.
Item rows go into data/generated/item_types.lua and sql/seed/0001_item_types.sql. The converter
is retired, so those two files are edited in place.

Ids 20237-20246 are the inflated wheels. 20247-20256 are the same meshes collapsed into a disc.
The generic Wheel item (20222) is unchanged. Both sets lie face-up: that is how a wheel item
rests, so rotx/roty/rotz stay 0 and modelz stays 0.
"""
from __future__ import annotations

import shutil
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
FILES = ROOT / "resources" / "[scavengesurvive]" / "prop_models" / "files"
ITEM_LUA = ROOT / "resources" / "[scavengesurvive]" / "data" / "generated" / "item_types.lua"
ITEM_SQL = ROOT / "sql" / "seed" / "0001_item_types.sql"
GTA = Path("/gta/sa/gamefiles/GTA San Andreas/models/generic")
DFF = GTA / "wheels.DFF"
TXD = GTA / "wheels.txd"
TXD_NAME = "stock_wheels"
FIRST_ID = 20237

# key in wheels.dff, display label, uname stem (Wheel + stem, Wheel + stem + Flat)
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

# The generic Wheel's hold, so these can be carried the same way until a studio pass retunes them.
HOLD = dict(attrx=258.455596, attry=346.618103, attrz=354.313049, attx=-0.098016, atty=0.356168, attz=-0.309851)


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


def _chunks(data: bytes):
    o = 0
    out = []
    while o + 12 <= len(data):
        kind, size, _ver = struct.unpack_from("<III", data, o)
        body = data[o + 12:o + 12 + size]
        out.append((kind, body))
        o += 12 + size
    return out


def parse_dff(data: bytes):
    """l0 atomics from wheels.dff. UVs are stored Blender-up (v flipped); DragonFF flips them back."""
    import numpy as np

    clump_parts = _chunks(_chunks(data)[0][1])
    frame_body = clump_parts[1][1]
    st = _chunks(frame_body)[0][1]
    nframes = struct.unpack_from("<i", st, 0)[0]
    o = 4
    frames = []
    for _ in range(nframes):
        vals = struct.unpack_from("<12fii", st, o)
        o += 56
        frames.append({
            "right": np.array(vals[0:3], np.float64),
            "up": np.array(vals[3:6], np.float64),
            "at": np.array(vals[6:9], np.float64),
            "pos": np.array(vals[9:12], np.float64),
            "parent": vals[12],
            "name": "",
        })
    fi = 0
    for t, b in _chunks(frame_body):
        if t != 0x03:
            continue
        for tt, bb in _chunks(b):
            if tt == 0x0253F2FE:
                frames[fi]["name"] = bb.split(b"\0", 1)[0].decode("latin1")
        fi += 1

    geos = []
    for t, b in _chunks(clump_parts[2][1]):
        if t != 0x0F:
            continue
        parts = _chunks(b)
        gst = parts[0][1]
        flags, ntri, nvert, _nm = struct.unpack_from("<IIII", gst, 0)
        o = 16
        if flags & 0x8:
            o += nvert * 4
        uvs = np.zeros((nvert, 2), np.float64)
        if flags & 0x84:
            sets = 2 if flags & 0x80 else 1
            for i in range(nvert):
                u, v = struct.unpack_from("<ff", gst, o)
                o += 8
                uvs[i] = (u, 1.0 - v)
                if sets == 2:
                    o += 8
        faces, mats = [], []
        for _ in range(ntri):
            v2, v1, mat, v3 = struct.unpack_from("<HHHH", gst, o)
            o += 8
            faces.append((v1, v2, v3))
            mats.append(mat)
        o += 24
        verts = np.zeros((nvert, 3), np.float64)
        for i in range(nvert):
            verts[i] = struct.unpack_from("<fff", gst, o)
            o += 12
        materials = []
        for mt, mb in parts:
            if mt != 0x08:
                continue
            for t2, b2 in _chunks(mb):
                if t2 != 0x07:
                    continue
                ms = _chunks(b2)[0][1]
                col = ms[4:8]
                tex = None
                for tt, bb in _chunks(b2):
                    if tt != 0x06:
                        continue
                    for t3, b3 in _chunks(bb):
                        if t3 == 0x02:
                            s = b3.split(b"\0", 1)[0].decode("latin1")
                            if s:
                                tex = s
                                break
                materials.append({"color": (col[0] / 255, col[1] / 255, col[2] / 255, 1), "texture": tex})
        geos.append({"verts": verts, "uvs": uvs, "faces": faces, "mat_index": mats, "materials": materials})

    atomics = []
    for t, b in clump_parts:
        if t != 0x14:
            continue
        ast = _chunks(b)[0][1]
        frame_i, geo_i = struct.unpack_from("<ii", ast, 0)
        atomics.append((frame_i, geo_i))
    return frames, geos, atomics


def frame_matrix(frames, i, cache):
    import numpy as np

    if i in cache:
        return cache[i]
    f = frames[i]
    local = np.eye(4)
    local[:3, 0] = f["right"]
    local[:3, 1] = f["up"]
    local[:3, 2] = f["at"]
    local[:3, 3] = f["pos"]
    parent = f["parent"]
    world = local if parent < 0 else frame_matrix(frames, parent, cache) @ local
    cache[i] = world
    return world


def _kind(mi, materials):
    tex = ""
    if 0 <= mi < len(materials) and materials[mi]["texture"]:
        tex = materials[mi]["texture"].lower()
    if "tyre" in tex:
        return "tyre"
    if tex.startswith("wheel") or tex.startswith("whee"):
        return "rim"
    return "other"


def align_rim_out(verts, faces, mat_index, materials):
    """Axle along +Y, the textured rim facing +Y."""
    import numpy as np

    center = (verts.min(0) + verts.max(0)) * 0.5
    v = verts - center
    _evals, evecs = np.linalg.eigh(np.cov(v.T))
    normal = evecs[:, 0].copy()
    z_axis = evecs[:, 2].copy()
    x_axis = np.cross(z_axis, normal)
    x_axis /= np.linalg.norm(x_axis)
    z_axis = np.cross(normal, x_axis)
    src = np.stack([x_axis, normal, z_axis], axis=1)
    if np.linalg.det(src) < 0:
        x_axis *= -1
        src = np.stack([x_axis, normal, z_axis], axis=1)
    v = (src.T @ v.T).T
    pos = neg = 0
    for (a, b, c), mi in zip(faces, mat_index):
        if _kind(mi, materials) != "rim":
            continue
        cy = (v[a, 1] + v[b, 1] + v[c, 1]) / 3.0
        if cy > 0.02:
            pos += 1
        elif cy < -0.02:
            neg += 1
    if neg > pos:
        v[:, 1] *= -1
        faces = [(c, b, a) for a, b, c in faces]
    return v, faces


def lay_flat(verts):
    """Turn the rim from +Y onto +Z so the wheel lies face-up."""
    import numpy as np

    x, y, z = verts[:, 0], verts[:, 1], verts[:, 2]
    return np.stack([x, -z, y], axis=1)


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
                    **w, **HOLD
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
    """wheels.txd is D3D8 DXT1. MTA's engineLoadTXD rejects that; the port's other TXDs are D3D9 BGRA."""
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
    import numpy as np
    from mathutils import Vector

    out = Path(out_dir)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    frames, geos, atomics = parse_dff(DFF.read_bytes())
    cache = {}
    by_name = {frames[i]["name"]: (i, g) for i, g in atomics}

    def placeholder(tex):
        name = tex + ".png"
        img = bpy.data.images.get(name)
        if img is None:
            img = bpy.data.images.new(name, 4, 4)
        return img

    def make_material(tex, color):
        mat = bpy.data.materials.new(tex or "untextured")
        mat.use_nodes = True
        bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (color[0], color[1], color[2], 1)
        if tex:
            node = mat.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = placeholder(tex)
            mat.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
        return mat

    def build(name, verts, uvs, faces, mat_index, materials):
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata(verts.tolist(), [], [tuple(f) for f in faces])
        mesh.validate()
        mesh.update()
        uv_layer = mesh.uv_layers.new(name="UV")
        for poly in mesh.polygons:
            for li, vi in zip(poly.loop_indices, poly.vertices):
                uv_layer.data[li].uv = uvs[vi]
        built = []
        for m in materials:
            built.append(make_material(m["texture"], m["color"]))
        if not built:
            built.append(make_material(None, (0.7, 0.7, 0.7, 1)))
        for m in built:
            mesh.materials.append(m)
        for poly, mi in zip(mesh.polygons, mat_index):
            poly.material_index = mi if mi < len(built) else 0
        bm = bmesh.new()
        bm.from_mesh(mesh)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(mesh)
        bm.free()
        mesh.update()
        ob = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(ob)
        return ob

    def deflate(ob):
        me = ob.data
        coords = np.empty(len(me.vertices) * 3, dtype=np.float64)
        me.vertices.foreach_get("co", coords)
        coords = coords.reshape(-1, 3)
        radii = np.hypot(coords[:, 0], coords[:, 1])
        outer = float(np.percentile(radii, 98)) or 1.0
        group = ob.vertex_groups.new(name="Tyre")
        for i, r in enumerate(radii):
            group.add([i], 0.55 + 0.45 * min(float(r) / outer, 1.0), "REPLACE")
        bpy.context.view_layer.update()
        corners = [Vector(c) for c in ob.bound_box]
        lo = Vector((min(c.x for c in corners), min(c.y for c in corners), min(c.z for c in corners)))
        hi = Vector((max(c.x for c in corners), max(c.y for c in corners), max(c.z for c in corners)))
        centre = (lo + hi) * 0.5
        size = hi - lo
        lat = bpy.data.lattices.new(ob.name + "_lattice")
        lat.points_u = lat.points_v = 4
        lat.points_w = 3
        lat.interpolation_type_u = lat.interpolation_type_v = lat.interpolation_type_w = "KEY_LINEAR"
        lat_ob = bpy.data.objects.new(lat.name, lat)
        bpy.context.scene.collection.objects.link(lat_ob)
        lat_ob.location = ob.matrix_world @ centre
        lat_ob.scale = (size.x * 0.55, size.y * 0.55, size.z * 0.7)
        for point in lat.points:
            co = point.co_deform
            radial = math.hypot(co.x, co.y)
            co.z = -0.5 + (co.z + 0.5) * 0.42
            if radial > 1e-5:
                spread = 1.0 + 0.06 * min(radial / 0.5, 1.0)
                co.x *= spread
                co.y *= spread
            point.co_deform = co
        mod = ob.modifiers.new("Deflate", "LATTICE")
        mod.object = lat_ob
        mod.vertex_group = "Tyre"
        with bpy.context.temp_override(object=ob, active_object=ob, selected_objects=[ob], selected_editable_objects=[ob]):
            result = bpy.ops.object.modifier_apply(modifier=mod.name)
        if result != {"FINISHED"}:
            raise RuntimeError(f"lattice apply failed on {ob.name}: {result}")
        bpy.data.objects.remove(lat_ob, do_unlink=True)
        bpy.data.lattices.remove(lat)
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()

    def seat(ob):
        me = ob.data
        verts = np.empty(len(me.vertices) * 3, dtype=np.float64)
        me.vertices.foreach_get("co", verts)
        verts = verts.reshape(-1, 3)
        centre_xy = (verts[:, :2].min(0) + verts[:, :2].max(0)) * 0.5
        verts[:, 0] -= centre_xy[0]
        verts[:, 1] -= centre_xy[1]
        verts[:, 2] -= verts[:, 2].min()
        me.vertices.foreach_set("co", verts.reshape(-1))
        me.update()

    for w in catalog():
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj, do_unlink=True)
        frame_i, geo_i = by_name[f"wheel_{w['key']}_l0"]
        g = geos[geo_i]
        matrix = frame_matrix(frames, frame_i, cache)
        verts = (matrix[:3, :3] @ g["verts"].T).T + matrix[:3, 3]
        faces = list(g["faces"])
        verts, faces = align_rim_out(verts, faces, g["mat_index"], g["materials"])
        verts = lay_flat(verts)
        ob = build(w["asset"], verts, g["uvs"], faces, g["mat_index"], g["materials"])
        if w["flat"]:
            deflate(ob)
        seat(ob)
        ob.location = (0, 0, 0)
        ob.rotation_euler = (0, 0, 0)
        ob.scale = (1, 1, 1)
        bpy.ops.export_dff.scene(
            filepath=str(out / f"{w['asset']}.dff"),
            export_coll=False,
            only_selected=False,
            export_version="0x36003",
        )
        dims = tuple(round(v, 3) for v in ob.dimensions)
        print(f"stock_wheels: {w['asset']} tris={len(ob.data.polygons)} size={dims}")
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
