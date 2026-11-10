"""A conical-seat lug nut for the wheel minigame (vehicles/files/lugnut.*).

Real M12 proportions: 19 mm across the flats, a 60-degree seat, a through-hole for the
stud. The mesh is the game model (DragonFF DFF + COL, one TXD). The top-down PNG is the
socket the minigame turns.

Run: python tools/make_lugnut.py
"""

from __future__ import annotations

import math
import struct
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FILES = ROOT / "resources" / "[scavengesurvive]" / "vehicles" / "files"
BLEND = ROOT / "tools" / "blender" / "lugnut.blend"
BEAUTY = ROOT / "tools" / "blender" / "lugnut_beauty.png"

AF = 0.019  # metres across the flats
HOLE = 0.00605
CONE_H = 0.0055
HEX_H = 0.0100
CHAMFER = 0.0014
SEGS = 24
HEIGHT = CONE_H + HEX_H + CHAMFER


def hex_radius(phi: float, af: float = AF) -> float:
    """Distance from the axis to a regular hexagon of the given across-flats size."""
    sector = math.pi / 3
    flat = math.pi / 6
    angle = (phi - flat) % sector
    if angle > sector / 2:
        angle -= sector
    return (af / 2) / math.cos(angle)


def chunk(kind: int, body: bytes) -> bytes:
    return struct.pack("<III", kind, len(body), 0x1803FFFF) + body


def write_txd(path: Path, name: str, w: int, h: int, bgra: bytes) -> None:
    head = struct.pack("<II", 9, 0x1106)
    head += name.encode()[:31].ljust(32, b"\0") + b"".ljust(32, b"\0")
    head += struct.pack("<II", 0x0600, 22)
    head += struct.pack("<HHBBBB", w, h, 32, 1, 4, 0x00)
    head += struct.pack("<I", len(bgra)) + bgra
    native = chunk(0x15, chunk(1, head) + chunk(3, b""))
    path.write_bytes(chunk(0x16, chunk(1, struct.pack("<HH", 1, 0)) + native + chunk(3, b"")))


def build() -> None:
    import bmesh
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    import addon_utils

    addon_utils.enable("DragonFF")

    # Brushed zinc. pixels[] is linear; the TXD stores the sRGB bytes GTA samples.
    size = 128
    srgb = bytearray(size * size * 4)
    linear = [0.0] * (size * size * 4)

    def to_lin(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    for y in range(size):
        for x in range(size):
            n = (
                math.sin(x * 0.85) * 0.5
                + math.sin(y * 1.7 + x * 0.15) * 0.35
                + math.sin((x + y) * 0.37) * 0.25
            )
            shade = 0.66 + n * 0.035
            # the right half is the machined hex face; a soft ring marks the seat
            if x >= 64:
                dx = (x - 96) / 28
                dy = (y - 64) / 28
                ring = abs(math.sqrt(dx * dx + dy * dy) - 0.72)
                shade += 0.04 - max(0, 0.08 - ring) * 0.35
            shade = max(0.45, min(0.82, shade))
            r = g = b = int(shade * 255)
            # blender is bottom-up; the TXD row 0 is the top
            bi = ((y * size) + x) * 4
            ti = (((size - 1 - y) * size) + x) * 4
            srgb[ti : ti + 4] = bytes((b, g, r, 255))
            linear[bi : bi + 4] = (to_lin(r / 255), to_lin(g / 255), to_lin(b / 255), 1.0)

    image = bpy.data.images.new("lugnut.png", size, size, alpha=True)
    image.colorspace_settings.name = "sRGB"
    image.pixels = linear
    FILES.mkdir(parents=True, exist_ok=True)
    # not the UI sprite path: a later render writes that file, and Blender would reload it as the albedo
    image.filepath_raw = str(BLEND.parent / "lugnut_albedo.png")
    image.file_format = "PNG"
    image.save()
    write_txd(FILES / "lugnut.txd", "lugnut", size, size, bytes(srgb))

    mesh = bpy.data.meshes.new("lugnut")
    bm = bmesh.new()
    uv_layer = bm.loops.layers.uv.new("UVMap")
    mid = HEIGHT / 2

    def ring(z: float, radius_at) -> list:
        verts = []
        for i in range(SEGS):
            phi = 2 * math.pi * i / SEGS
            radius = radius_at(phi)
            verts.append(bm.verts.new((math.cos(phi) * radius, math.sin(phi) * radius, z - mid)))
        return verts

    def hex_at(inset: float):
        return lambda phi: hex_radius(phi) - inset

    outer = [
        ring(0, lambda _phi: 0.0076),
        ring(CONE_H, hex_at(0)),
        ring(CONE_H + HEX_H, hex_at(0)),
        ring(HEIGHT, hex_at(0.00135)),
    ]
    inner = [ring(0, lambda _phi: HOLE), ring(HEIGHT, lambda _phi: HOLE)]

    def quad(verts, uvs):
        face = bm.faces.new(verts)
        for loop, uv in zip(face.loops, uvs):
            loop[uv_layer].uv = uv
        return face

    def band(ring_a, ring_b, v0, v1, outward=True):
        for i in range(SEGS):
            j = (i + 1) % SEGS
            u0, u1 = i / SEGS * 0.48, (i + 1) / SEGS * 0.48
            if outward:
                verts = [ring_a[i], ring_a[j], ring_b[j], ring_b[i]]
            else:
                verts = [ring_a[i], ring_b[i], ring_b[j], ring_a[j]]
            quad(verts, [(u0, v0), (u1, v0), (u1, v1), (u0, v1)])

    # cone, hex wall, chamfer
    band(outer[0], outer[1], 0.06, 0.34)
    band(outer[1], outer[2], 0.36, 0.78)
    band(outer[2], outer[3], 0.80, 0.96)
    # hole wall, normals toward the axis
    band(inner[1], inner[0], 0.84, 0.98, outward=False)
    for cap, z_ring_o, z_ring_i, center, radius in (
        ("top", outer[3], inner[1], (0.74, 0.38), 0.18),
        ("bottom", outer[0], inner[0], (0.74, 0.78), 0.08),
    ):
        for i in range(SEGS):
            j = (i + 1) % SEGS
            angles = [2 * math.pi * i / SEGS, 2 * math.pi * j / SEGS]

            def polar(index, scale):
                return (
                    center[0] + math.cos(angles[index]) * radius * scale,
                    center[1] + math.sin(angles[index]) * radius * scale,
                )

            if cap == "top":
                verts = [z_ring_o[i], z_ring_o[j], z_ring_i[j], z_ring_i[i]]
            else:
                verts = [z_ring_i[i], z_ring_i[j], z_ring_o[j], z_ring_o[i]]
            quad(verts, [polar(0, 1), polar(1, 1), polar(1, HOLE / 0.0076), polar(0, HOLE / 0.0076)])

    # hole-wall UVs: the fourth band of faces, retargeted so they do not share the side island
    hole_faces = [f for f in bm.faces if all(v in set(inner[0] + inner[1]) for v in f.verts)]
    for n, face in enumerate(hole_faces):
        u0, u1 = 0.52 + (n % SEGS) / SEGS * 0.44, 0.52 + ((n % SEGS) + 1) / SEGS * 0.44
        for loop, uv in zip(face.loops, ((u0, 0.90), (u0, 0.99), (u1, 0.99), (u1, 0.90))):
            loop[uv_layer].uv = uv

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    for edge in bm.edges:
        if len(edge.link_faces) == 2 and edge.calc_face_angle(0) > math.radians(28):
            edge.smooth = False
    bm.normal_update()
    bm.to_mesh(mesh)
    bm.free()

    material = bpy.data.materials.new("lugnut")
    material.use_nodes = True
    bsdf = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Metallic"].default_value = 1.0
    bsdf.inputs["Roughness"].default_value = 0.38
    tex = material.node_tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    material.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    mesh.materials.append(material)

    obj = bpy.data.objects.new("lugnut", mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.dff.type = "OBJ"
    obj.dff.day_cols = True
    obj.dff.night_cols = True
    with bpy.context.temp_override(object=obj, active_object=obj, selected_objects=[obj], selected_editable_objects=[obj]):
        bpy.ops.object.shade_smooth()

    # half-extents of the across-flats box; the nut spins about its centre
    col = bpy.data.objects.new("lugnut_col", None)
    col.empty_display_type = "CUBE"
    col.location = (0, 0, 0)
    col.scale = (AF / 2, AF / 2, HEIGHT / 2)
    col.dff.type = "COL"
    bpy.context.scene.collection.objects.link(col)

    dff_path = FILES / "lugnut.dff"
    col_path = FILES / "lugnut.col"
    bpy.ops.export_dff.scene(filepath=str(dff_path), export_coll=False, only_selected=False, export_version="0x36003")
    bpy.ops.export_col.scene(filepath=str(col_path), export_version="3", only_selected=False)

    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    dims = tuple(round(v, 5) for v in obj.dimensions)
    print(f"make_lugnut: tris={tris} dimensions={dims}")

    def render(path: Path, kind: str) -> None:
        scene = bpy.context.scene
        scene.render.engine = "CYCLES"
        scene.cycles.device = "CPU"
        scene.cycles.samples = 48
        scene.cycles.use_denoising = True
        scene.view_settings.view_transform = "AgX"
        scene.view_settings.exposure = 0.3
        scene.render.resolution_x = 512
        scene.render.resolution_y = 512
        scene.render.film_transparent = kind == "top"
        scene.render.filepath = str(path)
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA" if kind == "top" else "RGB"
        world = bpy.data.worlds.new("lugnut_world")
        scene.world = world
        world.use_nodes = True
        bg = next(node for node in world.node_tree.nodes if node.type == "BACKGROUND")
        bg.inputs["Color"].default_value = (0.16, 0.16, 0.17, 1)
        bg.inputs["Strength"].default_value = 0.4
        cam_data = bpy.data.cameras.new("cam")
        cam = bpy.data.objects.new("cam", cam_data)
        scene.collection.objects.link(cam)
        scene.camera = cam
        cam_data.type = "ORTHO"
        cam_data.clip_start = 0.001
        cam_data.clip_end = 10
        if kind == "top":
            cam.location = (0, 0, 0.12)
            cam.rotation_euler = (0, 0, 0)
            cam_data.ortho_scale = 0.030
        else:
            cam.location = (0.055, -0.06, 0.04)
            cam.rotation_euler = (Vector((0, 0, 0)) - Vector(cam.location)).to_track_quat("-Z", "Y").to_euler()
            cam_data.ortho_scale = 0.050
        for name, loc, energy, size in (
            ("key", (0.08, -0.06, 0.08), 8, 0.04),
            ("fill", (-0.07, -0.02, 0.05), 3, 0.06),
            ("rim", (0.0, 0.08, 0.04), 5, 0.03),
        ):
            light_data = bpy.data.lights.new(name, "AREA")
            light_data.energy = energy
            light_data.size = size
            light = bpy.data.objects.new(name, light_data)
            scene.collection.objects.link(light)
            light.location = loc
            direction = Vector((0, 0, 0)) - Vector(loc)
            light.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
        for name in ("key", "fill", "rim"):
            bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)

    render(FILES / "lugnut.png", "top")
    # the UI sprite replaced the texture png; keep the TXD on the brushed map already written
    render(BEAUTY, "beauty")
    BLEND.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))
    print(f"make_lugnut: wrote {dff_path.name} {col_path.name} lugnut.txd lugnut.png")


def main() -> int:
    blender = Path("/usr/local/bin/blender-5.2")
    cmd = [str(blender), "-b", "--python", str(Path(__file__).resolve())]
    res = subprocess.run(cmd, capture_output=True, text=True)
    lines = [line for line in (res.stdout + res.stderr).splitlines() if "make_lugnut" in line or "Error" in line or "Traceback" in line]
    print("\n".join(lines))
    if res.returncode != 0:
        print(res.stderr[-4000:])
    return res.returncode


if __name__ == "__main__":
    if "bpy" in sys.modules:
        build()
    else:
        sys.exit(main())
