"""Renders item models in Blender (Workbench, textured) into docs/images/items/<set>/, one PNG per model.

    python -m tools.render_item_models --set scrap [--gta DIR] [--blender EXE] [--size 512]
    python -m tools.render_item_models --unames Wrench,Hammer --set tools

Outside Blender it resolves every item's model id to a dff and its texture dictionaries (SAMP.img, gta3.img, gta_int.img,
the port packs under resources/), stages them in a scratch folder and runs itself in Blender (DragonFF). Items that share
a model share one render. Every render stays in docs/images/items/<set>/<model>_<dff>.png, with index.json mapping each
item uname to its file; a contact sheet (sheet_N.png, labelled with item names) is written next to them.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

RES = ROOT / "resources" / "[scavengesurvive]"
OUT = ROOT / "docs" / "images" / "items"
SCRAP_SRC = RES / "items" / "shared" / "logic" / "machines.lua"
ITEM_TYPES = RES / "data" / "generated" / "item_types.lua"
SAMP_IDE = ROOT / "tools" / "data" / "samp.ide"
LUA_ENTRY = re.compile(r"\[(\d+)\]\s*=\s*\{([^}]*)\}")


def lua_fields(body: str) -> dict:
    out = {}
    for k, v in re.findall(r'(\w+)\s*=\s*("[^"]*"|[\w.]+)', body):
        out[k] = v.strip('"') if v.startswith('"') else (int(v) if v.isdigit() else v)
    return out


def scrap_unames() -> list[str]:
    src = SCRAP_SRC.read_text(encoding="utf8")
    blk = src[src.index("M.SCRAP = {") :]
    blk = blk[: blk.index("\n}")]
    return [u for u, _ in re.findall(r"(\w+) = (\d+),", blk)]


def item_models() -> dict[str, tuple[int, str]]:
    out = {}
    for line in ITEM_TYPES.read_text(encoding="utf8").splitlines():
        m = re.match(r"M\.byUname\.(\w+) = \{", line)
        if m:
            mod, name = re.search(r"\bmodel = (\d+)", line), re.search(r'\bname = "([^"]*)"', line)
            if mod:
                out[m.group(1)] = (int(mod.group(1)), name.group(1) if name else m.group(1))
    return out


def port_models() -> dict[int, dict]:
    """Port-made model ids -> lua fields, from every <pack>/*.lua table of [id] = { dff = ... } rows."""
    out = {}
    for pack in RES.glob("*_models"):
        for lua in list(pack.glob("*.lua")):
            for mid, body in LUA_ENTRY.findall(lua.read_text(encoding="utf8")):
                f = lua_fields(body)
                if "dff" in f and int(mid) >= 20001:
                    f["pack"] = pack.name
                    out[int(mid)] = f
    return out


def vanilla_ide(gta: Path) -> dict[int, tuple[str, str]]:
    """Every model id of the game's IDE files -> (dff, txd), lowercase (objs, tobj, weap, anim)."""
    out = {}
    paths = sorted(glob.glob(str(gta / "data" / "**" / "*.ide"), recursive=True))
    for p in paths:
        for line in open(p, encoding="latin1", errors="replace"):
            parts = [x.strip() for x in line.split(",")]
            if len(parts) >= 3 and parts[0].isdigit():
                out.setdefault(int(parts[0]), (parts[1].lower(), parts[2].lower()))
    return out


def samp_ide() -> dict[int, tuple[str, str]]:
    out = {}
    for line in SAMP_IDE.read_text(encoding="ascii").splitlines():
        parts = [x.strip() for x in line.split(",")]
        if len(parts) >= 3 and parts[0].isdigit():
            out[int(parts[0])] = (parts[1].lower(), parts[2].lower())
    return out


def stage(models: set[int], gta: Path, work: Path) -> tuple[list[dict], list[str]]:
    from tools.extract_samp_models import is_samp_model, read_img_entry, read_img_index

    archives = {n: gta / p for n, p in [("samp", "SAMP/SAMP.img"), ("gta3", "models/gta3.img"), ("gta_int", "models/gta_int.img"), ("cutscene", "models/cutscene.img")] if (gta / p).is_file()}
    indexes = {n: read_img_index(p) for n, p in archives.items()}
    loose = {p.stem.lower(): p for p in (gta / "models").glob("*.txd")}
    van, sam, port = vanilla_ide(gta), samp_ide(), port_models()

    def fetch(name: str, ext: str, dest: Path, order=("samp", "gta3", "gta_int", "cutscene")) -> bool:
        for arch in order:
            idx = indexes.get(arch, {})
            if name + ext in idx:
                dest.write_bytes(read_img_entry(archives[arch], idx[name + ext]))
                return True
        if ext == ".txd" and name in loose:
            dest.write_bytes(loose[name].read_bytes())
            return True
        return False

    jobs, problems = [], []
    for model in sorted(models):
        d = work / str(model)
        d.mkdir(parents=True, exist_ok=True)
        txds: list[str] = []
        if model in port:
            f = port[model]
            pack = RES / f["pack"] / "files"
            dff = f["dff"]
            if not (pack / (dff + ".dff")).is_file():
                pack = RES / "samp_models" / "files"
            if not (pack / (dff + ".dff")).is_file():
                problems.append(f"{model}: {dff}.dff not found in {f['pack']}")
                continue
            (d / (dff + ".dff")).write_bytes((pack / (dff + ".dff")).read_bytes())
            if "txd" in f and (pack / (f["txd"] + ".txd")).is_file():
                (d / (f["txd"] + ".txd")).write_bytes((pack / (f["txd"] + ".txd")).read_bytes())
                txds.append(f["txd"])
            elif "txdModel" in f and f["txdModel"] in van and fetch(van[f["txdModel"]][1], ".txd", d / (van[f["txdModel"]][1] + ".txd")):
                txds.append(van[f["txdModel"]][1])
        else:
            dff, txd = sam.get(model) if is_samp_model(model) and model in sam else van.get(model, (None, None))
            if not dff or not fetch(dff, ".dff", d / (dff + ".dff")):
                problems.append(f"{model}: dff {dff} not found")
                continue
            if fetch(txd, ".txd", d / (txd + ".txd")):
                txds.append(txd)
            else:
                problems.append(f"{model}: txd {txd} not found (untextured)")
        jobs.append({"model": model, "dir": str(d), "dff": dff, "txds": txds})
    return jobs, problems


EFFECT_TEXTURES = {"laserbeam64x64", "laserbeam64x64a"}


class CaseDict(dict):
    """TXD images by lowercase name; DFF materials ask for them in any case."""

    def __contains__(self, k):
        return dict.__contains__(self, k.lower())

    def __getitem__(self, k):
        return dict.__getitem__(self, k.lower())

    def get(self, k, default=None):
        return dict.get(self, k.lower(), default)


def build_in_blender(jobs_file: Path, out_dir: Path, size: int):
    import bmesh
    import bpy
    from mathutils import Vector

    jobs = json.loads(jobs_file.read_text())
    for job in jobs:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        from DragonFF.ops import dff_importer, txd_importer  # noqa: PLC0415

        scn = bpy.context.scene
        scn.render.engine = "BLENDER_WORKBENCH"
        scn.render.resolution_x = scn.render.resolution_y = size
        scn.render.film_transparent = False
        scn.display.shading.light = "STUDIO"
        scn.display.shading.color_type = "TEXTURE"
        scn.display.shading.show_cavity = False
        scn.display.shading.background_type = "VIEWPORT"
        scn.display.shading.background_color = (0.16, 0.17, 0.19)
        scn.view_settings.view_transform = "Standard"
        images = CaseDict()
        for t in job["txds"]:
            images.update({k.lower(): v for k, v in txd_importer.import_txd({"file_name": os.path.join(job["dir"], t + ".txd"), "skip_mipmaps": True, "pack": True}).images.items()})
        opts = {"file_name": os.path.join(job["dir"], job["dff"] + ".dff"), "txd_images": images, "image_ext": None, "connect_bones": False, "use_mat_split": True, "remove_doubles": False, "create_backfaces": False, "group_materials": False, "import_normals": False, "materials_naming": "DEFAULT", "hide_damage_parts": False}
        dff_importer.import_dff(opts)
        meshes = [o for o in scn.objects if o.type == "MESH" and not o.dff.type == "COL"]
        for o in meshes:
            for slot in o.material_slots:
                if slot.material and slot.material.node_tree:
                    for n in slot.material.node_tree.nodes:
                        if n.type == "TEX_IMAGE" and not n.image and n.label in images:
                            n.image = images[n.label][0]
        for o in meshes:  # effect geometry (a laser's beam) would shrink the item to a speck
            drop = [i for i, sl in enumerate(o.material_slots) if sl.material and sl.material.node_tree and any(n.type == "TEX_IMAGE" and n.label.lower() in EFFECT_TEXTURES for n in sl.material.node_tree.nodes)]
            if drop:
                bm = bmesh.new()
                bm.from_mesh(o.data)
                bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in drop], context="FACES")
                bm.to_mesh(o.data)
                bm.free()
        pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        if not pts:
            print("RENDER nothing", job["model"])
            continue
        lo = Vector([min(p[i] for p in pts) for i in range(3)])
        hi = Vector([max(p[i] for p in pts) for i in range(3)])
        mid, diag = (lo + hi) / 2, (hi - lo).length
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        scn.camera = cam
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = diag * 1.15
        cam.data.clip_start, cam.data.clip_end = 0.001, diag * 20
        direction = Vector((1.0, -1.0, 0.75)).normalized()
        cam.location = mid + direction * diag * 3
        cam.rotation_euler = (mid - cam.location).to_track_quat("-Z", "Y").to_euler()
        scn.render.filepath = str(out_dir / job["file"])
        bpy.ops.render.render(write_still=True)
        print("RENDER ok", job["model"], job["file"])


def sheets(items: list[dict], out: Path, cols=4, rows=3, cell=384):
    from PIL import Image, ImageDraw, ImageFont

    try:
        font = ImageFont.truetype("arial.ttf", 20)
    except OSError:
        font = ImageFont.load_default()
    per = cols * rows
    paths = []
    for n, start in enumerate(range(0, len(items), per), 1):
        chunk = items[start : start + per]
        sheet = Image.new("RGB", (cols * cell, rows * (cell + 40)), (40, 42, 48))
        d = ImageDraw.Draw(sheet)
        for i, it in enumerate(chunk):
            x, y = (i % cols) * cell, (i // cols) * (cell + 40)
            im = Image.open(out / it["file"]).convert("RGB").resize((cell, cell))
            sheet.paste(im, (x, y))
            d.text((x + 8, y + cell + 8), it["label"][:40], fill=(235, 235, 235), font=font)
        p = out / f"sheet_{n}.png"
        sheet.save(p)
        paths.append(p)
    return paths


def main(argv=None) -> int:
    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--set", default="scrap", help="folder name under docs/images/items/ (and the unames: scrap = machines.lua SCRAP)")
    ap.add_argument("--unames", help="comma-separated item unames instead of the set's own list")
    ap.add_argument("--gta", type=Path)
    ap.add_argument("--blender")
    ap.add_argument("--size", type=int, default=512)
    args = ap.parse_args(argv)
    unames = args.unames.split(",") if args.unames else scrap_unames()
    gta = args.gta or detect_gta()
    blender = find_blender(args.blender)
    if not gta or not blender:
        print("render_item_models: need GTA:SA (--gta) and Blender (--blender)", file=sys.stderr)
        return 2
    types = item_models()
    by_model: dict[int, list[str]] = {}
    for u in unames:
        if u in types:
            by_model.setdefault(types[u][0], []).append(u)
    out = OUT / args.set
    out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="render_items_"))
    jobs, problems = stage(set(by_model), gta, work)
    for j in jobs:
        j["file"] = f"{j['model']}_{j['dff']}.png"
    jobs_file = work / "jobs.json"
    jobs_file.write_text(json.dumps(jobs))
    cmd = [str(blender), "-b", "--python", __file__, "--", str(jobs_file), str(out), str(args.size)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    for line in (res.stdout + res.stderr).splitlines():
        if line.startswith("RENDER") or "Error" in line:
            print(line)
    index, listed = {}, []
    for j in jobs:
        if (out / j["file"]).is_file():
            names = [types[u][1] for u in by_model[j["model"]]]
            for u in by_model[j["model"]]:
                index[u] = j["file"]
            listed.append({"file": j["file"], "label": " / ".join(names)})
        else:
            problems.append(f"{j['model']}: no render written")
    (out / "index.json").write_text(json.dumps(index, indent=1, sort_keys=True) + "\n")
    for p in sheets(listed, out):
        print("sheet", p)
    for p in problems:
        print("problem:", p, file=sys.stderr)
    print(f"{len(listed)} models for {len(index)} items -> {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    if "bpy" in sys.modules:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        build_in_blender(Path(rest[0]), Path(rest[1]), int(rest[2]))
    else:
        sys.exit(main())
