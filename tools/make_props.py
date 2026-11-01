"""Port prop models for the prop_models resource (ids 20201+): one table row, one build function each.

    python -m tools.make_props [--gta DIR] [--blender EXE] [name ...]

Outside Blender it cuts each prop's vanilla TXD from gta3.img down to the textures the prop uses (as
tools/extract_samp_models.py trims vanilla TXDs), writes prop_models/props.lua (every row) and prop_models/meta.xml,
then runs itself in Blender (DragonFF) for each prop's dff and col.

    ls_hatch  20201  the Ganton ladder entrance's cast-iron hatch: a 1 m square plate, 4 cm thick, wearing pave_manhole1
                     (a square "BO-NESS IRON CO LTD / METER" cover from zombtest1.txd) on top and the cover's rim on
                     its edges, dim day/night prelight, one box of collision (world/puzzles/ranch.pwn "LS entrance").
    welder    20202  a portable arc welder: red body with a carry handle and louvres, yellow control panel on the +Y
                     face, a lead with a stinger hung on the -X side and an earth lead with a clamp on the floor.

    gas_bottle 20203 a propane bottle: the Airstream's own right-hand tank (the faces of the vanilla sm_airstrm_med_.dff
                     textured sm_airstreamside2 on the A-frame), stood on its base; one box of collision.

    generator 20204  a portable inverter generator (Honda EU2200i style): red rounded shell with black end caps, a carry
                     handle bar along X on top (centre at GENERATOR_HANDLE_Z), fuel cap beside it, black control panel
                     on the +Y face, louvres on -Y; 0.52 x 0.30 x 0.44 m, one box of collision.

Origin: the centre of the base (x, y) with z = 0 at the lowest point; the front faces +Y.
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROP_MODELS = ROOT / "resources" / "[scavengesurvive]" / "prop_models"
FILES = PROP_MODELS / "files"
PROPS = PROP_MODELS / "props.lua"

SIZE, THICK, RIM = 1.0, 0.04, 0.04  # ls_hatch, metres; RIM: the share of the texture the edges show
DAY, NIGHT = (0.38, 0.38, 0.38, 1.0), (0.12, 0.12, 0.13, 1.0)


def build_ls_hatch(ctx):
    bm, h = ctx["bm"], SIZE / 2
    corners = [(-h, -h), (h, -h), (h, h), (-h, h)]
    top = [bm.verts.new((x, y, THICK)) for x, y in corners]
    low = [bm.verts.new((x, y, 0.0)) for x, y in corners]
    faces = [(bm.faces.new(top), [(0, 0), (1, 0), (1, 1), (0, 1)])]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((bm.faces.new((low[i], low[j], top[j], top[i])), [(0, 0), (1, 0), (1, RIM), (0, RIM)]))
    for face, uvs in faces:
        ctx["paint"](face, uvs, DAY, NIGHT, 0)
    return [((0.0, 0.0, THICK / 2), (h, h, THICK / 2))]


def build_welder(ctx):
    box, tube, red, panel, alu = ctx["box"], ctx["tube"], 0, 1, 2
    dark, mid = (0.16, 0.16, 0.17, 1.0), (0.6, 0.6, 0.6, 1.0)
    for x in (-0.17, 0.17):
        box((x, 0.0, 0.015), (0.05, 0.25, 0.03), alu, mid)
    box((0.0, 0.0, 0.15), (0.45, 0.25, 0.24), red, None)
    for x in (-0.15, 0.15):
        box((x, 0.0, 0.31), (0.03, 0.03, 0.08), alu, mid)
    box((0.0, 0.0, 0.335), (0.33, 0.03, 0.03), alu, mid)
    for side in (-1, 1):
        for i in range(4):
            box((side * 0.2275, -0.03 + i * 0.025, 0.2), (0.005, 0.012, 0.1), alu, dark)
    box((0.0, 0.13, 0.15), (0.37, 0.01, 0.19), panel, None)
    tube((-0.08, 0.135, 0.19), (-0.08, 0.152, 0.19), 0.04, 10, alu, mid)
    tube((-0.08, 0.152, 0.19), (-0.08, 0.158, 0.19), 0.028, 10, alu, dark)
    tube((0.08, 0.135, 0.19), (0.08, 0.158, 0.19), 0.025, 8, alu, dark)
    tube((-0.1, 0.135, 0.08), (-0.1, 0.165, 0.08), 0.018, 8, alu, mid)
    tube((0.1, 0.135, 0.08), (0.1, 0.165, 0.08), 0.018, 8, alu, dark)
    lead = [(-0.1, 0.165, 0.08), (-0.1, 0.21, 0.06), (-0.14, 0.25, 0.018), (-0.25, 0.22, 0.018), (-0.31, 0.12, 0.14), (-0.275, 0.02, 0.25)]
    for a, b in zip(lead, lead[1:]):
        tube(a, b, 0.008, 6, alu, dark)
    earth = [(0.1, 0.165, 0.08), (0.1, 0.2, 0.05), (0.14, 0.26, 0.01), (0.24, 0.28, 0.01)]
    for a, b in zip(earth, earth[1:]):
        tube(a, b, 0.008, 6, alu, dark)
    box((0.28, 0.28, 0.012), (0.06, 0.035, 0.024), alu, mid)
    tube((-0.2275, 0.0, 0.26), (-0.27, 0.0, 0.26), 0.007, 6, alu, mid)
    tube((-0.275, 0.0, 0.14), (-0.275, 0.0, 0.27), 0.017, 8, panel, None)
    tube((-0.275, 0.0, 0.14), (-0.275, 0.0, 0.03), 0.005, 6, alu, mid)
    return [((0.0, 0.0, 0.15), (0.225, 0.125, 0.15))]


TANK_SHELL = ROOT / "tools" / "trailer_shells" / "build" / "vanilla" / "sm_airstrm_med_.dff"  # tools/trailer_shells/prep.py
TANK_TEXTURE = "sm_airstreamside2"


def tank_faces(texture_name, centre):
    """The Airstream's right-hand propane tank: the A-frame's faces in the tank texture, x > 0 (towable.py splits the same)."""
    return texture_name == TANK_TEXTURE and centre.y > 4.08 and centre.z < 1.4 and centre.x > 0


def build_gas_bottle(ctx):
    lo, hi = ctx["graft"](str(TANK_SHELL), "sm_airstrm_med_", tank_faces, 0)
    return [(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2), ((hi[0] - lo[0]) / 2, (hi[1] - lo[1]) / 2, (hi[2] - lo[2]) / 2))]


GENERATOR_HANDLE_Z = 0.42  # height of the carry bar's centre above the base (generator.dff, bar along X, x -0.14 .. 0.14, y 0)
GEN_HX, GEN_HY, GEN_Z0, GEN_Z1 = 0.25, 0.15, 0.09, 0.33  # the red shell's half length, half width, bottom and top


def gen_profile(scale):
    """The shell's rounded-rectangle section (y, z), 16 points: big top corners, small bottom ones, shrunk about its centre."""
    zc = (GEN_Z0 + GEN_Z1) / 2
    out = []
    for cy, cz, r, a0 in ((1, 1, 0.075, 0), (-1, 1, 0.075, 90), (-1, -1, 0.03, 180), (1, -1, 0.03, 270)):
        for k in range(4):
            a = math.radians(a0 + 30 * k)
            y = cy * (GEN_HY - r) + r * math.cos(a)
            z = (GEN_Z1 - r if cz > 0 else GEN_Z0 + r) + r * math.sin(a)
            out.append((y * scale, zc + (z - zc) * scale))
    return out


def build_generator(ctx):
    bm, box, tube, paint = ctx["bm"], ctx["box"], ctx["tube"], ctx["paint"]
    red, alu = 0, 1
    dark, mid, light = (0.12, 0.12, 0.13, 1.0), (0.55, 0.55, 0.57, 1.0), (0.8, 0.8, 0.82, 1.0)
    night = lambda c: (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    # the shell: a rounded section lofted along X, the two end rings tapering; the end bands are the black end caps
    stations = ((-GEN_HX, 0.84), (-GEN_HX + 0.015, 0.95), (-0.2, 1.0), (0.2, 1.0), (GEN_HX - 0.015, 0.95), (GEN_HX, 0.84))
    rings = [[bm.verts.new((x, y, z)) for y, z in gen_profile(s)] for x, s in stations]
    n = len(rings[0])
    for i in range(len(rings) - 1):
        cap = i in (0, len(rings) - 2)
        col = dark if cap else (0.9, 0.9, 0.9, 1.0)
        for j in range(n):
            k = (j + 1) % n
            face = bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
            u0, u1, v0, v1 = i * 0.4, i * 0.4 + 0.4, j / n, (j + 1) / n
            paint(face, [(u0, v0), (u0, v1), (u1, v1), (u1, v0)], col, night(col), alu if cap else red)
    for ring in (rings[0], rings[-1]):
        face = bm.faces.new(ring)
        paint(face, [(0.5 + 0.5 * math.cos(2 * math.pi * i / n), 0.5 + 0.5 * math.sin(2 * math.pi * i / n)) for i in range(n)], dark, night(dark), alu)
    # base: black skid, aluminium side rails, four rubber feet
    box((0.0, 0.0, 0.065), (0.46, 0.25, 0.07), alu, dark)
    for y in (-0.115, 0.115):
        tube((-0.235, y, 0.055), (0.235, y, 0.055), 0.013, 8, alu, mid)
    for x in (-0.19, 0.19):
        for y in (-0.095, 0.095):
            tube((x, y, 0.011), (x, y, 0.03), 0.022, 8, alu, dark)
    # the control panel on the +Y face: black plate, outlets, switch, indicator lights, sockets
    box((0.0, 0.151, 0.215), (0.42, 0.014, 0.15), alu, dark)
    box((-0.1, 0.16, 0.235), (0.11, 0.008, 0.075), alu, mid)
    for x in (-0.12, -0.08):
        box((x, 0.165, 0.235), (0.032, 0.004, 0.05), alu, dark)
    tube((0.07, 0.158, 0.245), (0.07, 0.163, 0.245), 0.026, 10, alu, light)
    box((0.07, 0.17, 0.245), (0.036, 0.006, 0.01), alu, dark)
    for x, z in ((0.0, 0.265), (0.0, 0.24), (0.0, 0.215)):
        box((x, 0.161, z), (0.014, 0.006, 0.014), red, None)
    for x in (0.1, 0.14):
        tube((x, 0.158, 0.19), (x, 0.162, 0.19), 0.014, 8, alu, mid)
    tube((-0.02, 0.158, 0.19), (-0.02, 0.163, 0.19), 0.011, 8, alu, light)
    # side louvres on -Y, an exhaust stub on -X
    for i in range(6):
        box((-0.06, -GEN_HY + 0.002, 0.14 + i * 0.03), (0.13, 0.012, 0.014), alu, dark)
    tube((-GEN_HX, 0.0, 0.17), (-GEN_HX - 0.003, 0.0, 0.17), 0.028, 10, alu, mid)
    # fuel cap and gauge on top, beside the handle on the panel side
    box((0.185, 0.06, 0.335), (0.085, 0.085, 0.02), alu, dark)
    tube((0.185, 0.06, 0.345), (0.185, 0.06, 0.382), 0.032, 10, alu, dark)
    tube((0.185, 0.06, 0.382), (0.185, 0.06, 0.39), 0.02, 10, alu, mid)
    box((0.1, 0.1, 0.331), (0.045, 0.03, 0.006), alu, light)
    # the carrying handle: two red moulded posts and a black grip bar along X at GENERATOR_HANDLE_Z
    for x in (-0.13, 0.13):
        box((x, 0.0, 0.38), (0.045, 0.06, 0.12), red, None)
    tube((-0.145, 0.0, GENERATOR_HANDLE_Z), (0.145, 0.0, GENERATOR_HANDLE_Z), 0.022, 10, alu, dark)
    return [((0.0, 0.0, 0.22), (0.26, 0.16, 0.22))]


PROPS_TABLE = [
    {"name": "ls_hatch", "id": 20201, "dist": 150, "source": "zombtest1.txd", "textures": ["pave_manhole1"], "build": build_ls_hatch},
    {"name": "welder", "id": 20202, "dist": 100, "source": "dynbarrels.txd", "textures": ["redmetal", "yellowmetal", "alumplat64"], "build": build_welder},
    {"name": "gas_bottle", "id": 20203, "dist": 100, "source": "trailers.txd", "textures": [TANK_TEXTURE], "build": build_gas_bottle},
    {"name": "generator", "id": 20204, "dist": 100, "source": "dynbarrels.txd", "textures": ["redmetal", "alumplat64"], "build": build_generator},
]


def render_props() -> str:
    lines = [
        "-- Generated by tools/make_props.py; do not edit. Port model id -> a prop the port adds to the world,",
        "-- in prop_models/files/ with its own TXD and collision.",
        "return {",
    ]
    lines += [f'    [{p["id"]}] = {{ dff = "{p["name"]}", txd = "{p["name"]}", dist = {p["dist"]} }},' for p in PROPS_TABLE]
    return "\n".join(lines + ["}", ""])


def render_meta(out_dir: Path) -> str:
    props_lua = out_dir / "props.lua"
    dffs = []
    if props_lua.is_file():
        dffs += [f"{name}.dff" for name in re.findall(r'dff = "([^"]+)"', props_lua.read_text(encoding="ascii"))]
    files = []
    for dff in sorted(dffs):
        stem = dff[:-4]
        files += [f"{stem}.col", f"{stem}.dff", f"{stem}.txd"]
    lines = [
        "<meta>",
        '    <info author="scavengesurvive-mta" type="script" name="prop_models" '
        'description="Port prop models added to the world" version="0.1.0"/>',
        '    <min_mta_version server="1.6.0" client="1.6.0-9.21695"/>',
        "    <download_priority_group>90</download_priority_group>",
        '    <include resource="lib"/>',
        '    <script src="client/main.lua" type="client"/>',
        '    <file src="props.lua"/>',
    ]
    lines += [f'    <file src="files/{name}"/>' for name in files]
    lines += [
        '    <export function="resolve" type="client"/>',
        '</meta>',
    ]
    return "\n".join(lines) + "\n"


def write_meta(out_dir: Path) -> None:
    (out_dir / "meta.xml").write_text(render_meta(out_dir), encoding="ascii", newline="\n")


def build_in_blender(out_dir: Path, names) -> None:
    import bmesh
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    for prop in PROPS_TABLE:
        if prop["name"] not in names:
            continue
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj)
        name, textures = prop["name"], prop["textures"]
        scene = bpy.context.scene
        model = bpy.data.collections.new(name)
        scene.collection.children.link(model)

        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day = bm.loops.layers.color.new("Day")
        night = bm.loops.layers.color.new("Night")

        def paint(face, uvs, day_col, night_col, material):
            face.material_index = material
            for loop, (u, v) in zip(face.loops, uvs):
                loop[uv].uv = (u, v)
                loop[day] = day_col
                loop[night] = night_col

        def quad(verts, material, col):
            face = bm.faces.new(verts)
            c = col if col else (0.9, 0.9, 0.9, 1.0)
            uvs = [(0, 0), (1, 0), (1, 1), (0, 1)][: len(verts)]
            if len(verts) > 4:
                uvs = [(0.5 + 0.5 * math.cos(2 * math.pi * i / len(verts)), 0.5 + 0.5 * math.sin(2 * math.pi * i / len(verts))) for i in range(len(verts))]
            paint(face, uvs, c, (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0), material)

        def box(centre, size, material, col):
            cx, cy, cz = centre
            hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
            v = [bm.verts.new((cx + sx * hx, cy + sy * hy, cz + sz * hz)) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
            for a, b, c, d in ((0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)):
                quad([v[a], v[b], v[c], v[d]], material, col)

        def tube(start, end, radius, segs, material, col):
            a, b = Vector(start), Vector(end)
            axis = b - a
            axis.normalize()
            a, b = a - axis * radius * 0.5, b + axis * radius * 0.5
            helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
            u = axis.cross(helper)
            u.normalize()
            w = axis.cross(u)
            rings = []
            for end_point in (a, b):
                ring = []
                for i in range(segs):
                    t = 2 * math.pi * i / segs
                    ring.append(bm.verts.new(end_point + (u * math.cos(t) + w * math.sin(t)) * radius))
                rings.append(ring)
            for i in range(segs):
                j = (i + 1) % segs
                quad([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], material, col)
            for ring in rings:
                quad(list(ring), material, col)

        def graft(path, mesh_name, keep, material):
            """Copies the faces `keep(texture, centre)` picks out of a vanilla DFF into the prop, centred on x and y with
            its lowest point at z 0, painted like the other props; returns the bounds (lo, hi) of the result."""
            bpy.ops.import_scene.dff(filepath=path, read_mat_split=True, remove_doubles=False, load_images=False)
            src = bpy.data.objects[mesh_name].data

            def texture_of(index):
                mat = src.materials[index]
                nodes = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"] if mat and mat.node_tree else []
                return ((nodes[0].image.name if nodes[0].image else nodes[0].label or nodes[0].name) if nodes else "").split(".")[0]

            polys = [p for p in src.polygons if keep(texture_of(p.material_index), p.center)]
            used = sorted({v for p in polys for v in p.vertices})
            co = [src.vertices[v].co for v in used]
            lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
            hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
            shift = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
            verts = {v: bm.verts.new(src.vertices[v].co - shift) for v in used}
            uv_layer = src.uv_layers[0].data
            for poly in polys:
                face = bm.faces.new([verts[v] for v in poly.vertices])
                uvs = [tuple(uv_layer[i].uv) for i in poly.loop_indices]
                paint(face, uvs, (0.9, 0.9, 0.9, 1.0), (0.27, 0.27, 0.29, 1.0), material)
            for obj in list(bpy.data.objects):
                bpy.data.objects.remove(obj)
            return (lo - shift, hi - shift)

        ctx = {"bm": bm, "paint": paint, "box": box, "tube": tube, "graft": graft}
        boxes = prop["build"](ctx)
        if name not in ("ls_hatch", "gas_bottle"):
            bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()

        for texture in textures:
            image = bpy.data.images.new(texture + ".png", 8, 8)  # DragonFF writes the name; the pixels are the TXD's
            material = bpy.data.materials.new(texture)
            material.use_nodes = True
            bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            node = material.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            material.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            mesh.materials.append(material)

        obj = bpy.data.objects.new(name, mesh)
        obj.dff.type = "OBJ"
        obj.dff.day_cols = True
        obj.dff.night_cols = True
        model.objects.link(obj)

        for i, (centre, half) in enumerate(boxes):
            col = bpy.data.objects.new(f"{name}_col" if i == 0 else f"{name}_col{i}", None)
            col.empty_display_type = "CUBE"
            col.location = centre
            col.scale = half
            col.dff.type = "COL"
            model.objects.link(col)

        dff_path, col_path = out_dir / f"{name}.dff", out_dir / f"{name}.col"
        bpy.ops.export_dff.scene(filepath=str(dff_path), export_coll=False, only_selected=False, export_version="0x36003")
        bpy.ops.export_col.scene(filepath=str(col_path), export_version="3", only_selected=False)
        print(f"make_props: wrote {dff_path.name} and {col_path.name}")
        bpy.data.collections.remove(model)


def main(argv=None) -> int:
    import argparse
    import subprocess

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta, read_img_entry, read_img_index, trim_txd

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("names", nargs="*", help="props to build (default: all)")
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender.exe (default: BLENDER or the newest install)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    img = gta / "models" / "gta3.img" if gta else None
    if not img or not img.is_file():
        print("make_props: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    blender = find_blender(args.blender)
    if not blender:
        print("make_props: no Blender found (pass --blender)", file=sys.stderr)
        return 2
    names = args.names or [p["name"] for p in PROPS_TABLE]
    index = read_img_index(img)
    for prop in PROPS_TABLE:
        if prop["name"] in names:
            txd = trim_txd(read_img_entry(img, index[prop["source"]]), {t.lower() for t in prop["textures"]})
            (FILES / f"{prop['name']}.txd").write_bytes(txd)
    PROPS.write_text(render_props(), encoding="ascii", newline="\n")
    write_meta(PROP_MODELS)
    cmd = [str(blender), "-b", "--python", __file__, "--", str(FILES)] + names
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    print("\n".join(line for line in out.splitlines() if "make_props" in line or "Error" in line))
    return 0 if res.returncode == 0 and all((FILES / f"{n}.dff").is_file() for n in names) else 1


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        build_in_blender(Path(rest[0]), set(rest[1:]))
    else:
        sys.exit(main())
