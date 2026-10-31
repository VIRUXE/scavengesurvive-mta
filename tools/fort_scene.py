"""Fort Defiance's custom models inside the real Grove Street scenery, in Blender, with every collision reported.

    python -m tools.fort_scene [--radius 45] [--blend FILE] [--report FILE]

Reads every Rockstar placement within `radius` m of the cul-de-sac out of the game's IPLs, pulls their DFFs from the IMGs,
imports them in Blender (DragonFF) at their placements and stands the fort's custom models (tools/fort_walkways.py,
tools/fort_structures.py as exported to models/files) on top. Then every custom model is tested triangle against triangle
with each native mesh and the intersections are listed: model, native, how many triangles cross and where. Open the saved
.blend to see them and to build a piece against the scenery it has to clear.
"""
from __future__ import annotations

import argparse
import json
import math
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CENTRE = (2495.0, -1668.0)
THIN = re.compile(r"alpha|straps")  # wires, decals and street haze: planes nothing can collide with
REACH = 2.5  # natives higher than this above a span's design line are not something the span has to clear
FILES = ROOT / "resources" / "[scavengesurvive]" / "models" / "files"


def scene_spec(gta: Path, radius: float, out_dir: Path) -> dict:
    """The natives around CENTRE (DFFs extracted into out_dir) and the custom placements, as plain data for Blender."""
    from tools.convert.maps import port_rows
    from tools.extract_samp_models import read_img_entry, read_img_index
    from tools.fort_survey import ide_names, native_instances
    from tools.make_fort_kit import model_ids

    names = ide_names(gta)
    img = gta / "models" / "gta3.img"
    index = read_img_index(img)
    natives, used = [], set()
    for model, pos, rot in native_instances(gta):
        if math.hypot(pos[0] - CENTRE[0], pos[1] - CENTRE[1]) > radius or model not in names:
            continue
        dff = names[model][0]
        if dff.startswith("lod") or f"{dff}.dff" not in index:
            continue
        if dff not in used:
            (out_dir / f"{dff}.dff").write_bytes(read_img_entry(img, index[f"{dff}.dff"]))
            used.add(dff)
        natives.append({"dff": dff, "p": list(pos), "m": rot})
    from tools.fort_survey import matrix

    by_id = {v: k for k, v in model_ids().items()}
    custom = [{"name": by_id[r[0]], "dff": str(FILES / f"{by_id[r[0]]}.dff"), "p": r[1:4], "m": matrix(r[4], r[5], r[6])} for r in port_rows("LS/Fort Defiance.map")]
    from tools import fort_walkways

    spans = {}
    for name in fort_walkways.SPANS:
        spec = fort_walkways.layout(name)
        spans[name] = {"a": spec["a"], "b": spec["b"], "length": spec["length"], "width": fort_walkways.WIDTH}
    from tools.convert.maps import REPLACED_MODELS, parse_map
    from tools.fort_survey import UPSTREAM

    samp_img = gta / "SAMP" / "SAMP.img"
    samp_index = read_img_index(samp_img) if samp_img.exists() else {}
    props = []
    for row in parse_map((UPSTREAM / "LS" / "Fort Defiance.map").read_text(encoding="utf-8", errors="ignore"), "LS/Fort Defiance.map")["objects"]:
        if row[0] in REPLACED_MODELS["LS/Fort Defiance.map"] or row[0] not in names:
            continue
        dff = names[row[0]][0]
        if dff not in used:
            if f"{dff}.dff" in index:
                (out_dir / f"{dff}.dff").write_bytes(read_img_entry(img, index[f"{dff}.dff"]))
            elif f"{dff}.dff" in samp_index:
                (out_dir / f"{dff}.dff").write_bytes(read_img_entry(samp_img, samp_index[f"{dff}.dff"]))
            else:
                continue
            used.add(dff)
        props.append({"dff": dff, "row": row[:7], "m": matrix(row[4], row[5], row[6])})
    from tools import fort_structures

    areas = {name: {"at": list(fort_structures.PLACED[name]), "half": half} for name, half in fort_structures.AREAS.items()}
    return {"natives": natives, "custom": custom, "spans": spans, "areas": areas, "props": props, "dir": str(out_dir)}


def run_in_blender(spec: dict, blend: Path, report: Path, surfaces: Path, settle: Path, blender: Path) -> None:
    with tempfile.TemporaryDirectory() as tmp:
        spec_path = Path(tmp) / "spec.json"
        spec_path.write_text(json.dumps(spec), encoding="utf-8")
        cmd = [str(blender), "-b", "--python", __file__, "--", str(spec_path), str(blend), str(report), str(surfaces), str(settle)]
        res = subprocess.run(cmd, capture_output=True, text=True)
        if res.returncode:
            print(res.stdout[-2000:], res.stderr[-2000:], file=sys.stderr)
            raise SystemExit("fort_scene: Blender failed")


def build_in_blender(spec_path: str, blend: str, report: str, surfaces: str, settle_path: str) -> None:
    import bmesh
    import bpy
    from mathutils import Matrix, Vector
    from mathutils.bvhtree import BVHTree

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    spec = json.loads(Path(spec_path).read_text(encoding="utf-8"))
    scene = bpy.context.scene

    def load(path: str):
        """The DFF's triangles in model space as a mesh datablock."""
        before = set(bpy.data.objects)
        bpy.ops.import_scene.dff(filepath=path, load_images=False)
        new = [o for o in bpy.data.objects if o not in before]
        bm = bmesh.new()
        for o in new:
            if o.type == "MESH":
                tmp = o.data.copy()
                tmp.transform(o.matrix_world)
                bm.from_mesh(tmp)
                bpy.data.meshes.remove(tmp)
        for o in new:
            bpy.data.objects.remove(o, do_unlink=True)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
        mesh = bpy.data.meshes.new(Path(path).stem)
        bm.to_mesh(mesh)
        bm.free()
        return mesh

    def world(p, m) -> Matrix:
        return Matrix([[m[0][0], m[0][1], m[0][2], p[0]], [m[1][0], m[1][1], m[1][2], p[1]], [m[2][0], m[2][1], m[2][2], p[2]], [0, 0, 0, 1]])

    meshes, natives, custom = {}, [], []
    nat_col = bpy.data.collections.new("natives")
    cus_col = bpy.data.collections.new("custom")
    scene.collection.children.link(nat_col)
    scene.collection.children.link(cus_col)
    for n in spec["natives"]:
        if n["dff"] not in meshes:
            meshes[n["dff"]] = load(f"{spec['dir']}/{n['dff']}.dff")
        ob = bpy.data.objects.new(n["dff"], meshes[n["dff"]])
        ob.matrix_world = world(n["p"], n["m"])
        nat_col.objects.link(ob)
        natives.append(ob)
    for c in spec["custom"]:
        ob = bpy.data.objects.new(c["name"], load(c["dff"]))
        ob.matrix_world = world(c["p"], c["m"])
        cus_col.objects.link(ob)
        custom.append(ob)
    prop_col = bpy.data.collections.new("props")
    scene.collection.children.link(prop_col)
    props = []
    for pr in spec["props"]:
        if pr["dff"] not in meshes:
            meshes[pr["dff"]] = load(f"{spec['dir']}/{pr['dff']}.dff")
        ob = bpy.data.objects.new(pr["dff"], meshes[pr["dff"]])
        ob.matrix_world = world(pr["row"][1:4], pr["m"])
        prop_col.objects.link(ob)
        ob["row"] = pr["row"][:4]
        props.append(ob)
    bpy.context.view_layer.update()

    def tree(ob):
        bm = bmesh.new()
        bm.from_mesh(ob.data)
        bm.transform(ob.matrix_world)
        bm.faces.ensure_lookup_table()
        return BVHTree.FromBMesh(bm), bm

    def merge_bmesh(obs):
        bm = bmesh.new()
        for ob in obs:
            tmp = ob.data.copy()
            tmp.transform(ob.matrix_world)
            bm.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
        return bm

    native_trees = [(ob, *tree(ob)) for ob in natives]
    lines = ["# Fort Defiance: custom models against the Rockstar scenery", "",
             f"Generated by `python -m tools.fort_scene`: {len(natives)} native placements within the fort, each custom model tested "
             "triangle against triangle.", ""]
    total = 0
    for ob in custom:
        mine, mbm = tree(ob)
        hits = []
        for nat, nt, nbm in native_trees:
            if THIN.search(nat.name):
                continue
            pairs = mine.overlap(nt)
            if not pairs:
                continue
            pts = [mbm.faces[a].calc_center_median() for a, _b in pairs]
            lo = [min(p[i] for p in pts) for i in range(3)]
            hi = [max(p[i] for p in pts) for i in range(3)]
            hits.append((len(pairs), nat.name, lo, hi))
        total += len(hits)
        lines += [f"## {ob.name} at {ob.location.x:.1f}, {ob.location.y:.1f}, {ob.location.z:.1f}", ""]
        if not hits:
            lines += ["clear", ""]
            continue
        lines += ["| tris | native | from (x, y, z) | to (x, y, z) |", "| ---: | --- | --- | --- |"]
        for count, name, lo, hi in sorted(hits, reverse=True):
            lines.append(f"| {count} | {name} | {lo[0]:.1f}, {lo[1]:.1f}, {lo[2]:.1f} | {hi[0]:.1f}, {hi[1]:.1f}, {hi[2]:.1f} |")
        lines.append("")
    lines.insert(3, f"{total} model/native pairs intersect.")
    def clip_counts(obs, against):
        found = {}
        for ob in obs:
            mine, _bm = tree(ob)
            n = sum(len(mine.overlap(t)) for other, t, _b in against if other is not ob)
            if n:
                found[ob] = n
        return found

    solid_against = [(ob, *tree(ob)) for ob in natives + custom if not THIN.search(ob.name)]
    solid_against = [(ob, t, b) for ob, t, b in solid_against]
    clipping = clip_counts(props, solid_against)
    surface_tree = BVHTree.FromBMesh(merge_bmesh([ob for ob, _t, _b in solid_against]))
    settle = []
    for ob in props:
        pts = [ob.matrix_world @ v.co for v in ob.data.vertices]
        if not pts:
            continue
        bottom = min(p.z for p in pts)
        xs, ys = [p.x for p in pts], [p.y for p in pts]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        tops = []
        for fx, fy in ((0, 0), (0.3, 0.3), (-0.3, 0.3), (0.3, -0.3), (-0.3, -0.3)):
            x, y = cx + fx * (max(xs) - min(xs)), cy + fy * (max(ys) - min(ys))
            hit = surface_tree.ray_cast(Vector((x, y, bottom + 0.6)), Vector((0, 0, -1)), 2.0)
            if hit[0] is not None:
                tops.append(hit[0].z)
        if not tops:
            continue
        dz = max(tops) - bottom
        if 0.03 < abs(dz) <= 1.0 and ob in clipping or 0.15 < abs(dz) <= 1.0:
            ob.location.z += dz
            row = ob["row"]
            settle.append([row[0], row[1], row[2], row[3], round(row[3] + dz, 3)])
    bpy.context.view_layer.update()
    after = clip_counts(props, [(ob, *tree(ob)) for ob in natives + custom if not THIN.search(ob.name)])
    Path(settle_path).write_text(json.dumps(settle), encoding="utf-8", newline="\n")
    props_lines = ["", "## Upstream props that stay", "", f"{len(props)} props: {len(clipping)} intersected a native or custom mesh, {len(settle)} moved to rest on the "
                   f"surface below them, {len(after)} still intersect.", ""]
    if after:
        props_lines += ["| tris | prop | at (x, y, z) |", "| ---: | --- | --- |"]
        for ob, n in sorted(after.items(), key=lambda kv: -kv[1])[:40]:
            props_lines.append(f"| {n} | {ob.name} | {ob.location.x:.1f}, {ob.location.y:.1f}, {ob.location.z:.1f} |")
    lines += props_lines

    ground = re.compile(r"road|grnd|landhub|grass|hub_|bush|tree|palm|veg|^sm_|plant", re.I)
    solid = [ob for ob in natives if not ground.search(ob.name)]
    floor = [ob for ob in natives if ground.search(ob.name) and not re.search(r"bush|tree|palm|veg|^sm_|plant", ob.name, re.I)]

    def merged(obs):
        bm = bmesh.new()
        for ob in obs:
            tmp = ob.data.copy()
            tmp.transform(ob.matrix_world)
            bm.from_mesh(tmp)
            bpy.data.meshes.remove(tmp)
        return BVHTree.FromBMesh(bm)

    solid_tree, floor_tree = merged(solid), merged(floor)

    def down(bvh, x, y, top=40.0):
        hit = bvh.ray_cast(Vector((x, y, top)), Vector((0, 0, -1)), 60.0)
        return None if hit[0] is None else round(hit[0].z, 2)

    out = {}
    for name, sp in spec["spans"].items():
        ax, ay, bx, by, length = sp["a"][0], sp["a"][1], sp["b"][0], sp["b"][1], sp["length"]
        ux, uy = (bx - ax) / length, (by - ay) / length
        nx, ny = -uy, ux
        samples = []
        for i in range(int(length / 0.5) + 2):
            s = min(i * 0.5, length)
            tops, floors = [], []
            for off in (-sp["width"] / 2 - 0.1, -0.45, 0.0, 0.45, sp["width"] / 2 + 0.1):
                x, y = ax + ux * s + nx * off, ay + uy * s + ny * off
                tops.append(down(solid_tree, x, y, sp["a"][2] + (sp["b"][2] - sp["a"][2]) * s / length + REACH))
                floors.append(down(floor_tree, x, y))
            samples.append({"s": round(s, 2), "top": tops, "floor": floors})
            if s >= length:
                break
        out[name] = samples
    for name, area in spec["areas"].items():
        x0, y0, z0, rz = area["at"]
        c, sn = math.cos(math.radians(rz)), math.sin(math.radians(rz))
        hx, hy = area["half"]
        grid = []
        for ix in range(int(2 * hx) + 1):
            for iy in range(int(2 * hy) + 1):
                u, v = -hx + ix * (2 * hx / int(2 * hx)), -hy + iy * (2 * hy / int(2 * hy))
                x, y = x0 + u * c - v * sn, y0 + u * sn + v * c
                grid.append({"u": round(u, 2), "v": round(v, 2), "top": down(solid_tree, x, y, z0 + REACH + 1.5), "floor": down(floor_tree, x, y, z0 + REACH + 1.5)})
        out[name] = grid
    Path(surfaces).write_text(json.dumps(out, indent=1), encoding="utf-8", newline="\n")
    Path(report).write_text("\n".join(lines), encoding="utf-8", newline="\n")
    bpy.ops.wm.save_as_mainfile(filepath=blend)
    print(f"fort_scene: {total} intersecting pairs")


def main(argv=None) -> int:
    from tools.extract_ped_models import find_blender
    from tools.fort_survey import DEFAULT_GTA

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--gta", type=Path, default=DEFAULT_GTA)
    ap.add_argument("--radius", type=float, default=45.0)
    ap.add_argument("--blend", type=Path, default=ROOT / ".cache" / "fort_scene.blend")
    ap.add_argument("--report", type=Path, default=ROOT / "docs" / "reviews" / "2026-10-31-fort-defiance-scene.md")
    ap.add_argument("--surfaces", type=Path, default=ROOT / "tools" / "data" / "fort_surfaces.json")
    ap.add_argument("--settle", type=Path, default=ROOT / "tools" / "data" / "fort_settle.json")
    ap.add_argument("--blender")
    args = ap.parse_args(argv)
    blender = find_blender(args.blender)
    if not blender:
        print("fort_scene: no Blender found (pass --blender)", file=sys.stderr)
        return 1
    args.blend.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        spec = scene_spec(args.gta, args.radius, Path(tmp))
        run_in_blender(spec, args.blend, args.report, args.surfaces, args.settle, blender)
    print(f"fort_scene: {len(spec['natives'])} natives, {len(spec['custom'])} custom -> {args.report}")
    return 0


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        build_in_blender(*sys.argv[sys.argv.index("--") + 1 :][:5])
    else:
        sys.exit(main())
