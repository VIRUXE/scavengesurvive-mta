"""Blender side of tools/car_parts.py: survey or cut out every car's ok/dam body panels (DragonFF).
Run by the driver: blender -b --factory-startup --python tools/car_parts_blender.py -- JOBS.json
"""
import json
import math
import re
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector

spec = json.loads(Path(sys.argv[sys.argv.index("--") + 1]).read_text())
MESHES = ["bonnet", "boot", "door_lf", "door_rf", "door_lr", "door_rr", "bump_front", "bump_rear"]
WHEELS = ["wheel_rf_dummy", "wheel_lf_dummy", "wheel_rb_dummy", "wheel_lb_dummy"]

bpy.ops.preferences.addon_enable(module="DragonFF")


def reset():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images, bpy.data.collections):
        for block in list(coll):
            coll.remove(block)


def base_name(obj):
    return re.sub(r"\.\d+$", "", obj.name).lower()


def objects_by_name():
    out = {}
    for obj in bpy.data.objects:
        out.setdefault(base_name(obj), obj)
    return out


def world_box(obj):
    pts = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector(tuple(min(p[k] for p in pts) for k in range(3)))
    hi = Vector(tuple(max(p[k] for p in pts) for k in range(3)))
    return lo, hi


def ground_drop(objs, wheel_scale):
    zs = [objs[w].matrix_world.translation.z for w in WHEELS if w in objs]
    if not zs:
        return 0.7
    # the wheels' rest height less the suspension's settle (0.2 m: the Bobcat measured 0.7 in game)
    return -(min(zs) - wheel_scale / 2) - 0.2


def slot_point(mesh, lo, hi):
    """Where a player works on the slot, in the vehicle's frame: offsets from the panel's box tuned so the Bobcat's
    come out where its hand-placed points were (tools/bobcat_parts.py era)."""
    cx, cy = (lo.x + hi.x) / 2, (lo.y + hi.y) / 2
    if mesh.startswith("door"):
        return (hi.x - 0.12 if cx > 0 else lo.x + 0.12), cy
    if mesh == "bump_front":
        return 0.0, hi.y - 0.15
    if mesh == "bump_rear":
        return 0.0, lo.y + 0.25
    if mesh == "boot":
        return 0.0, lo.y + 0.28
    return 0.0, cy - 0.23  # bonnet


def survey_model(job):
    reset()
    bpy.ops.import_scene.dff(filepath=job["dff"])
    objs = objects_by_name()
    parts, slots = {}, {}
    for mesh in MESHES:
        ok, dam = objs.get(mesh + "_ok"), objs.get(mesh + "_dam")
        if not ok or ok.type != "MESH" or not ok.data.vertices:
            continue
        if not dam or dam.type != "MESH" or not dam.data.vertices:
            dam = ok
        entry = {}
        for suffix, obj in (("ok", ok), ("dam", dam)):
            lo, hi = world_box(obj)
            entry[suffix] = dict(verts=len(obj.data.vertices), size=[round(v, 3) for v in hi - lo],
                                 centre=[round(v, 3) for v in (lo + hi) / 2], samemesh=obj is ok and suffix == "dam")
        parts[mesh] = entry
        lo, hi = world_box(ok)
        slots[mesh] = [round(v, 3) for v in slot_point(mesh, lo, hi)]
    return dict(name=job["name"], groundDrop=round(ground_drop(objs, job["wheel"]), 3), parts=parts, slots=slots,
                frames=sorted(objs))


PAINT_MARKERS = {(60, 255, 0): 0, (255, 0, 175): 1}


def rest_pose(mesh, size):
    """(rotx, roty, rotz), lift, and the footprint after the rotation: the thin side up; bumpers stand on their edge."""
    sx, sy, sz = size
    if mesh.startswith("bump"):
        return (0, 0, 0), sz / 2, (sx, sy, sz)
    thin = min(range(3), key=lambda k: size[k])
    if thin == 0:
        return (0, 90, 0), sx / 2, (sz, sy, sx)
    if thin == 1:
        return (90, 0, 0), sy / 2, (sx, sz, sy)
    return (0, 0, 0), sz / 2, (sx, sy, sz)


def build_model(job, out, used):
    reset()
    bpy.ops.import_scene.dff(filepath=job["dff"])
    objs = objects_by_name()
    coll = bpy.data.collections.new(job["name"])
    bpy.context.scene.collection.children.link(coll)
    paint = [tuple(c / 255 for c in rgb) for rgb in job["paint"]]
    result = {}
    textures = set()
    for mesh in MESHES:
        ok = objs.get(mesh + "_ok")
        if not ok or ok.type != "MESH" or not ok.data.vertices:
            continue
        dam = objs.get(mesh + "_dam")
        if not dam or dam.type != "MESH" or not dam.data.vertices:
            dam = ok
        entry = {}
        for suffix, src in (("ok", ok), ("dam", dam)):
            asset = f"{job['name']}_{mesh}_{suffix}"
            obj = bpy.data.objects.new(asset + "_part", src.data.copy())
            coll.objects.link(obj)
            obj.data.transform(src.matrix_world)
            pts = [v.co for v in obj.data.vertices]
            lo = Vector(tuple(min(v[k] for v in pts) for k in range(3)))
            hi = Vector(tuple(max(v[k] for v in pts) for k in range(3)))
            shift = (lo + hi) / 2
            for v in obj.data.vertices:
                v.co -= shift
            if mesh == "bonnet" or mesh == "boot":
                # a vehicle panel is a single skin: a loose one needs a textured underside as well
                bm = bmesh.new()
                bm.from_mesh(obj.data)
                back = bmesh.ops.duplicate(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces))
                bmesh.ops.reverse_faces(bm, faces=[f for f in back["geom"] if isinstance(f, bmesh.types.BMFace)])
                bm.normal_update()
                bm.to_mesh(obj.data)
                bm.free()
            obj.dff.type = "OBJ"
            for name, color in [("Day", (0.9, 0.9, 0.9, 1.0)), ("Night", (0.27, 0.27, 0.288, 1.0))]:
                layer = obj.data.color_attributes.new(name=name, type="BYTE_COLOR", domain="CORNER")
                for loop in layer.data:
                    loop.color = color
            obj.dff.day_cols = True
            obj.dff.night_cols = True
            for slot in obj.material_slots:
                if not slot.material:
                    continue
                mat = slot.material.copy()
                slot.material = mat
                rgba = tuple(mat.diffuse_color)
                marker = tuple(round(c * 255) for c in rgba[:3])
                if marker in PAINT_MARKERS:
                    rgba = (*paint[PAINT_MARKERS[marker]], rgba[3])
                mat.diffuse_color = rgba
                node = next((n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
                if node:
                    node.inputs["Base Color"].default_value = rgba
                mat.dff.export_env_map = False
                mat.dff.export_specular = False
                mat.dff.export_reflection = False
                for tex in mat.node_tree.nodes:
                    if tex.type == "TEX_IMAGE" and tex.image:
                        key = re.split(r"\.png", tex.image.name, flags=re.I)[0].lower()
                        key = re.sub(r"\.\d+$", "", key)
                        key = job.get("rename", {}).get(key, key)  # a name another car's TXD also uses
                        image = bpy.data.images.get(key + ".png") or bpy.data.images.new(key + ".png", 8, 8)
                        tex.image = image
                        textures.add(key)
            size = hi - lo
            col = bpy.data.objects.new(asset + "_col", None)
            col.empty_display_type = "CUBE"
            col.scale = tuple(max(size[k] / 2, 0.025) for k in range(3))
            col.dff.type = "COL"
            coll.objects.link(col)
            bpy.ops.object.select_all(action="DESELECT")
            obj.select_set(True)
            col.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.export_dff.scene(filepath=str(Path(out) / (asset + ".dff")), export_coll=False,
                                     only_selected=True, export_version="0x36003")
            bpy.ops.export_col.scene(filepath=str(Path(out) / (asset + ".col")), export_version="3",
                                     only_selected=True)
            bpy.data.objects.remove(col, do_unlink=True)
            rot, lift, foot = rest_pose(mesh, tuple(size))
            fx, fy, fz = foot
            big = max(fx, fy)
            cls = 4 if big > 0.9 else 3 if big > 0.5 else 2
            entry[suffix] = dict(
                rest=list(rot),
                modelz=round(lift, 4),
                restRow=[round(lift, 4), 0.0, 0.0, cls, 1 if fx >= fy else 0, round(fx, 3), round(fy, 3), round(fz, 3)],
                size=[round(v, 3) for v in size],
                samemesh=src is ok and suffix == "dam",
            )
            print("EXPORTED", asset, len(obj.data.polygons))
        result[mesh] = entry
        lo, hi = world_box(ok)
    used[str(job["model"])] = sorted(textures)
    surveyed = survey_slots(objs, job)
    return dict(name=job["name"], groundDrop=surveyed[0], slots=surveyed[1], parts=result)


def survey_slots(objs, job):
    slots = {}
    for mesh in MESHES:
        ok = objs.get(mesh + "_ok")
        if ok and ok.type == "MESH" and ok.data.vertices:
            lo, hi = world_box(ok)
            slots[mesh] = [round(v, 3) for v in slot_point(mesh, lo, hi)]
    return round(ground_drop(objs, job["wheel"]), 3), slots


models, used = {}, {}
for job in spec["jobs"]:
    try:
        if spec["mode"] == "survey":
            models[str(job["model"])] = survey_model(job)
        else:
            models[str(job["model"])] = build_model(job, spec["out"], used)
    except Exception as exc:  # noqa: BLE001 - report and go on with the next car
        print("FAILED", job["model"], repr(exc))
        models[str(job["model"])] = dict(name=job["name"], error=repr(exc), groundDrop=0, parts={}, slots={})
Path(spec["result"]).write_text(json.dumps(dict(models=models, textures=used)))
_ = math
