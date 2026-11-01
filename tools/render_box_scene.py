"""Renders the box items (tools/world_boxes.py PARTS) as two Blender pictures with the game's own textures, for update posts.

    python -m tools.render_box_scene [--out DIR] [--gta DIR] [--blender EXE]

Writes lineup.png (every box item in rows on a plain ground) and scene.png (a warehouse corner: stacks of crates and
cartons, loose boxes and bin bags), 1920x1080, EEVEE. Outside Blender it stages each port box model (box_models) with
its TXD through tools/render_item_models.stage and runs itself in Blender (DragonFF). The default folder is
docs/images/items/box-scene/.
"""
from __future__ import annotations

import json
import math
import os
import random
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

MODELS = [m for m in range(20401, 20419) if m not in (20412, 20413)]
OUT = ROOT / "docs" / "images" / "items" / "box-scene"


def build_in_blender(jobs_file: Path, out_dir: Path) -> None:
    import bpy
    from mathutils import Vector

    from DragonFF.ops import dff_importer, txd_importer
    from tools.render_item_models import CaseDict

    jobs = json.loads(jobs_file.read_text())
    folder = str(out_dir)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")

    scn = bpy.context.scene
    protos = {}
    for job in jobs:
        images = CaseDict()
        for t in job["txds"]:
            images.update({k.lower(): v for k, v in txd_importer.import_txd({"file_name": os.path.join(job["dir"], t + ".txd"), "skip_mipmaps": True, "pack": True}).images.items()})
        before = set(bpy.data.objects)
        dff_importer.import_dff({"file_name": os.path.join(job["dir"], job["dff"] + ".dff"), "txd_images": images, "image_ext": None, "connect_bones": False, "use_mat_split": True, "remove_doubles": False, "create_backfaces": False, "group_materials": False, "import_normals": False, "materials_naming": "DEFAULT", "hide_damage_parts": False})
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == "MESH" and o.dff.type != "COL"]
        for o in new:
            if o not in meshes:
                bpy.data.objects.remove(o, do_unlink=True)
        for o in meshes:
            for slot in o.material_slots:
                if slot.material and slot.material.node_tree:
                    for n in slot.material.node_tree.nodes:
                        if n.type == "TEX_IMAGE" and not n.image and n.label in images:
                            n.image = images[n.label][0]
                        if n.type == "BSDF_PRINCIPLED":
                            n.inputs["Roughness"].default_value = 0.9
                            for k in ("Specular IOR Level", "Specular"):
                                if k in n.inputs: n.inputs[k].default_value = 0.1
        protos[job["model"]] = meshes
        for o in meshes:
            o.hide_render = True
            o.hide_viewport = True

    def put(model, x, y, yaw=0.0, z=0.0):
        root = bpy.data.objects.new("p%d" % model, None)
        scn.collection.objects.link(root)
        root.location = (x, y, z)
        root.rotation_euler = (0, 0, math.radians(yaw))
        for o in protos[model]:
            c = o.copy()
            c.data = o.data
            c.hide_render = False
            c.hide_viewport = False
            c.parent = root
            c.matrix_parent_inverse = root.matrix_world.inverted()
            scn.collection.objects.link(c)
        return root

    def dims(model):
        pts = [c for o in protos[model] for c in o.bound_box]
        return (max(p[0] for p in pts) - min(p[0] for p in pts), max(p[1] for p in pts) - min(p[1] for p in pts), max(p[2] for p in pts))

    def scene_common(cam_loc, target, lens=50):
        w = bpy.data.worlds.new("w"); w.use_nodes = True
        bg = w.node_tree.nodes["Background"]; bg.inputs[0].default_value = (0.55, 0.62, 0.72, 1); bg.inputs[1].default_value = 0.55
        scn.world = w
        bpy.ops.mesh.primitive_plane_add(size=400, location=(0, 0, 0))
        g = bpy.context.object; g.name = "ground"
        m = bpy.data.materials.new("gm"); m.use_nodes = True
        m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.24, 0.22, 0.19, 1)
        m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 1
        g.data.materials.append(m)
        sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); scn.collection.objects.link(sun)
        sun.data.energy = 3.2; sun.data.angle = math.radians(6); sun.rotation_euler = (math.radians(52), 0, math.radians(35))
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scn.collection.objects.link(cam); scn.camera = cam
        cam.data.lens = lens; cam.data.clip_end = 200
        cam.location = cam_loc
        cam.rotation_euler = (Vector(target) - Vector(cam_loc)).to_track_quat("-Z", "Y").to_euler()

    def render(name):
        scn.render.resolution_x, scn.render.resolution_y = 1920, 1080
        for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
            try:
                scn.render.engine = eng; break
            except TypeError:
                pass
        try: scn.eevee.taa_render_samples = 64
        except Exception: pass
        scn.view_settings.view_transform = "Standard"
        scn.render.filepath = os.path.join(folder, name)
        bpy.ops.render.render(write_still=True)
        print("SCENE wrote", name, scn.render.engine)

    # ---- lineup: three rows, each model on the ground, the doubles gone
    rows = [[20406, 20410, 20409, 20408, 20407, 20418], [20403, 20401, 20402, 20411, 20414, 20404, 20405], [20415, 20416, 20417]]
    y = 0.0
    for ri, row in enumerate(rows):
        widths = [dims(m)[0] for m in row]
        gap = 0.55
        total = sum(widths) + gap * (len(row) - 1)
        x = -total / 2
        for m, w in zip(row, widths):
            d = dims(m)
            put(m, x + w / 2 + 0.0, y - ri * 2.3, 0)
            x += w + gap
    scene_common((0.0, -14.2, 7.8), (0.0, -2.2, 0.4), 50)
    render("lineup.png")
    for o in list(bpy.data.objects):
        if o.name.startswith(("p", "ground", "sun", "cam")) and o.type in ("EMPTY", "LIGHT", "CAMERA", "MESH") and o not in [x for v in protos.values() for x in v]:
            bpy.data.objects.remove(o, do_unlink=True)

    # ---- scene: a warehouse corner, stacks and loose bags
    random.seed(5)
    def stack(model, x, y, nx, ny, nz, yaw=0.0, sx=None):
        d = dims(model)
        sx = sx or d[0] + 0.03
        for i in range(nx):
            for j in range(ny):
                for k in range(nz):
                    if random.random() < (0.12 if k else 0): continue
                    put(model, x + i * sx + random.uniform(-0.03, 0.03), y + j * (d[1] + 0.03), yaw + random.uniform(-4, 4), z=k * d[2])
    stack(20410, -3.4, 0.2, 1, 2, 2)      # the 1.44 m crates
    stack(20409, -1.4, 0.0, 2, 3, 2)      # the 0.93 m crates, no longer fused in pairs
    stack(20401, 1.8, 0.2, 3, 2, 2)       # cartons
    stack(20403, 1.5, -2.4, 2, 1, 2, 12)  # large cartons
    stack(20408, -3.6, -2.6, 2, 2, 2)
    put(20406, 4.9, 1.2, 20); put(20407, 5.0, -0.4, -10); put(20414, 4.1, -1.2, 35)
    put(20418, -5.3, 3.3, 12)
    put(20411, 3.1, -2.6, 8); put(20404, 0.0, -2.6, -20); put(20405, 0.9, -3.4, 30); put(20402, -1.4, -2.9, 5)
    put(20415, 0.3, 3.0, 0); put(20416, -0.6, 3.5, 40); put(20417, 0.9, 3.6, 120); put(20415, -4.6, 1.7, 0); put(20416, 3.9, 3.0, 70)
    scene_common((11.0, -10.2, 7.2), (0.5, -0.2, 0.7), 45)
    render("scene.png")


def main(argv=None) -> int:
    import argparse

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta
    from tools.render_item_models import stage

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", type=Path, default=OUT, help="folder for lineup.png and scene.png")
    ap.add_argument("--gta", type=Path)
    ap.add_argument("--blender")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    blender = find_blender(args.blender)
    if not gta or not blender:
        print("render_box_scene: need GTA:SA (--gta) and Blender (--blender)", file=sys.stderr)
        return 2
    work = Path(tempfile.mkdtemp(prefix="box_scene_"))
    jobs, problems = stage(set(MODELS), gta, work)
    for p in problems:
        print("problem:", p, file=sys.stderr)
    if len(jobs) != len(MODELS):
        return 1
    jobs_file = work / "jobs.json"
    jobs_file.write_text(json.dumps(jobs))
    args.out.mkdir(parents=True, exist_ok=True)
    cmd = [str(blender), "-b", "--python", __file__, "--", str(jobs_file), str(args.out.resolve())]
    res = subprocess.run(cmd, capture_output=True, text=True)
    for line in (res.stdout + res.stderr).splitlines():
        if line.startswith("SCENE") or "Error" in line:
            print(line)
    return res.returncode


if __name__ == "__main__":
    if "bpy" in sys.modules:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        build_in_blender(Path(rest[0]), Path(rest[1]))
    else:
        sys.exit(main())
