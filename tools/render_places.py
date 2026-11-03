"""Renders shots of real places of the game world in Blender for the wiki: the terrain, roads, trees and
buildings around a point, with item and vehicle placements dropped onto the ground there.

    python -m tools.render_places [--place NAME ...] [--at x,y,z --radius R] [--size WxH] [--samples N] [--stats]
    python -m tools.render_places --engine eevee  # faster draft; default: Cycles with daylight and indirect light
    python -m tools.render_places --list

The world comes from the game's own placements: the text IPLs under data/maps and the binary stream IPLs inside
gta3.img (read the way DragonFF's map importer does: 32-byte "bnry" header, 40-byte inst entries, the quaternion applied
as (w = -rw, x, y, z)), the IDEs for model -> dff/txd/draw distance (txdp parents honoured), plus the port's own world:
the buildings the maps resource creates (maps/data/<ZONE>.lua objects, with its removals and BOXES.lua applied), the
puzzle objects of world/data/puzzles.lua and the house shells that replace the vanilla houses (house_shell). Every
object within `radius` of the place is loaded, and the large models (IDE draw distance >= BIG_DRAW_DISTANCE) out to
`backdrop` so hills and skylines fill the horizon; interiors, LOD twins and night-only objects are skipped. The sea
and lakes come from data/water.dat. Models are staged once into a cache keyed by model id. A place may carry the same
item/vehicle placement spec as tools/render_scenes.py (positions relative to the place; every placement is dropped
onto the terrain by a ray cast). Writes docs/images/places/<name>.png plus index.json, and a 1200 px copy into the
wiki clone's images/places/. Cycles uses a physical sky with a sun direction fixed in world space, so shadows and
indirect skylight follow the surroundings rather than the camera. A supported GPU is used when available, otherwise
the CPU; --device cpu forces the latter. EEVEE is available for quick drafts.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import tools.render_scenes as rs  # noqa: E402

RES = ROOT / "resources" / "[scavengesurvive]"
OUT = ROOT / "docs" / "images" / "places"
WIKI_OUT = ROOT.parent / (ROOT.name + ".wiki") / "images" / "places"
CACHE = Path(tempfile.gettempdir()) / "render_places_cache"
MAPS = RES / "maps" / "data"
PUZZLES = RES / "world" / "data" / "puzzles.lua"
HOUSE_SHELL = RES / "house_shell"
BIG_DRAW_DISTANCE = 150.0  # IDE draw distance from which a model counts as large scenery (terrain chunks are 200)
DAYLIGHT = {
    "day": {"elevation": 42, "rotation": 225, "strength": 0.2, "sun": 1.0, "aerosol": 0.6},
    "overcast": {"elevation": 48, "rotation": 225, "strength": 0.3, "sun": 0.08, "aerosol": 3.0},
    "golden": {"elevation": 17, "rotation": 270, "strength": 0.3, "sun": 0.9, "aerosol": 1.0},
    "dusk": {"elevation": 5, "rotation": 275, "strength": 0.3, "sun": 0.4, "aerosol": 1.0},
}
ROW = re.compile(r"\{ (\d+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), (-?\d+), (-?\d+), [-\d.e]+ \}")
REMOVAL = re.compile(r"\{ (\d+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+), ([-\d.e]+) \}")
SECTIONS = {"inst", "cull", "path", "grge", "enex", "cars", "pick", "jump", "tcyc", "auzo", "mult", "occl", "zone", "objs", "tobj", "anim", "txdp", "peds", "weap", "hier", "2dfx"}

CAMP_ITEMS = rs.SCENES["camp"]["items"]
AIRSTREAM_ITEMS = rs.SCENES["airstream"]["items"]
SUPPLY_CRATE = [{"model": rs.SUPPLY_CRATE, "at": (0, 0, 0), "rot": (0, 0, 20), "name": "crate"}, {"model": rs.SUPPLY_CRATE, "at": (0.01, 0.01, 0), "rot": (0, 180, 20), "on": "crate"}]

PLACES = {
    "farm-silos": {"caption": "Storage tanks and towers at an industrial complex in Flint County", "at": (-1075.0, -672.0, 36.0), "camera": {"look_at": (-1065.0, -680.0, 38.0), "azimuth": -120, "elevation": 20, "distance": 230, "lens": 30}, "light": "day"},
    "area69-gate": {"caption": "The gate of Area 69", "at": (211.6, 1812.0, 19.0), "camera": {"look_at": (212.0, 1818.0, 19.0), "azimuth": -60, "elevation": 12, "distance": 55, "lens": 35}, "light": "day"},
    "chiliad-station": {"caption": "The Mount Chiliad summit station with the battery and fusebox puzzle", "at": (-2316.15, -1646.64, 483.43), "camera": {"look_at": (-2316.0, -1646.0, 485.0), "azimuth": -150, "elevation": 20, "distance": 45, "lens": 32}, "light": "golden", "items": [{"uname": "Battery", "at": (0.0, 0.0, 0.0), "yaw": 32.04}, {"uname": "Fusebox", "at": (0.48, 1.75, 0.0), "yaw": 262.98}]},
    "quarry-door": {"caption": "The quarry door's log cabin in the Whetstone woods", "at": (-2813.0, -1527.0, 140.0), "camera": {"look_at": (-2814.0, -1526.0, 141.5), "azimuth": -40, "elevation": 12, "distance": 36, "lens": 35}, "light": "overcast"},
    "scrapyard": {"caption": "The Whetstone machines in place: the Scrap Machine and the Refining Machine", "at": (-1868.0, -1661.0, 22.0), "camera": {"look_at": (-1868.0, -1661.0, 23.0), "azimuth": -70, "elevation": 22, "distance": 80, "lens": 30}, "light": "day", "items": [{"uname": "ScrapMachine", "at": (-20.26, 24.59, 0.0), "yaw": 0.0}, {"uname": "RefineMachine", "at": (19.44, -24.39, 0.0), "yaw": -54.0}]},
    "palisades-bbq": {"caption": "The BBQ on the Palisades", "at": (-2701.13, 845.74, 70.38), "camera": {"look_at": (-2704.0, 847.0, 71.2), "azimuth": 100, "elevation": 8, "distance": 9, "lens": 32}, "light": "golden", "items": [{"uname": "Barbecue", "at": (0.0, 0.0, 0.0), "yaw": 171.0}]},
    "queens-lockup": {"caption": "The code hunt's lockup entrance and keypad in Queens, San Fierro", "at": (-2497.0, 315.0, 29.5), "radius": 90.0, "backdrop": 300.0, "camera": {"look_at": (-2496.5, 314.7, 30.2), "azimuth": 180, "elevation": 15, "distance": 23.1, "lens": 35}, "light": "day"},
    "trailer-park": {"caption": "A trailer cluster in Las Barrancas, Bone County: the enterable shells", "at": (-890.0, 1541.0, 24.9), "radius": 300.0, "backdrop": 700.0, "camera": {"look_at": (-890.0, 1541.0, 26.0), "azimuth": -60, "elevation": 16, "distance": 60, "lens": 35}, "light": "day"},
    "townhouse-street": {"caption": "A Los Santos street of house shells (East Beach)", "at": (2663.0, -2005.0, 15.3), "camera": {"look_at": (2663.0, -2005.0, 16.5), "azimuth": 60, "elevation": 8, "distance": 50, "lens": 35}, "light": "day"},
    "fuel-station": {"caption": "A fuel station with eight outlets (San Fierro)", "at": (-1675.0, 413.0, 6.4), "camera": {"look_at": (-1675.0, 413.0, 7.5), "azimuth": 120, "elevation": 6, "distance": 40, "lens": 35}, "light": "day"},
    "spawn-beach": {"caption": "A spawn point on the beach, the sea behind", "at": (-228.79, -1719.81, 1.11), "camera": {"look_at": (-228.8, -1719.8, 2.2), "azimuth": 160, "elevation": 10, "distance": 40, "lens": 32}, "light": "golden"},
    "verdant-meadows": {"caption": "The Verdant Meadows airstrip drop point with a supply crate", "at": (373.17, 2511.17, 15.47), "camera": {"look_at": (373.0, 2511.0, 17.0), "azimuth": -40, "elevation": 12, "distance": 45, "lens": 35}, "light": "day", "items": SUPPLY_CRATE},
    "camp": {"caption": "A camp in a Flint County forest clearing at dusk", "at": (-1612.0, -2208.0, 35.0), "camera": {"look_at": (-1612.0, -2208.0, 1.0), "ground": True, "azimuth": -28, "elevation": 9, "distance": 16, "lens": 32}, "light": "dusk", "items": CAMP_ITEMS},
    "airstream-road": {"caption": "The towable Airstream on the Fort Carson road", "at": (-230.0, 1045.0, 19.7), "camera": {"look_at": (-230.0, 1042.0, 1.2), "ground": True, "azimuth": 60, "elevation": 12, "distance": 24, "lens": 35}, "light": "golden", "items": AIRSTREAM_ITEMS},
}


def visible_at_noon(on: int, off: int) -> bool:
    return (on <= 12 < off) if on <= off else (12 >= on or 12 < off)


def ide_tables(gta: Path) -> tuple[dict[int, dict], dict[str, str]]:
    """Model id -> dff, txd, draw distance, night-only flag (objs, tobj, anim) and txdp parents, lowercase."""
    models, parents = {}, {}
    for path in sorted(glob.glob(str(gta / "data" / "**" / "*.ide"), recursive=True)):
        section = None
        for raw in open(path, encoding="latin1", errors="replace"):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            low = line.lower()
            if section is None:
                section = low if low in SECTIONS else None
                continue
            if low == "end":
                section = None
                continue
            parts = [x.strip() for x in line.split(",")]
            if section == "txdp" and len(parts) >= 2:
                parents[parts[0].lower()] = parts[1].lower()
            elif section in ("objs", "tobj") and len(parts) >= 5 and parts[0].isdigit():
                extra = len(parts) - (5 if section == "objs" else 7)
                dist, flags = (parts[3], parts[4]) if extra <= 0 else (parts[4], parts[4 + extra])
                night = section == "tobj" and parts[-2].lstrip("-").isdigit() and not visible_at_noon(int(parts[-2]), int(parts[-1]))
                models.setdefault(int(parts[0]), {"dff": parts[1].lower(), "txd": parts[2].lower(), "dist": float(dist), "night": night})
            elif section == "anim" and len(parts) >= 6 and parts[0].isdigit():
                models.setdefault(int(parts[0]), {"dff": parts[1].lower(), "txd": parts[2].lower(), "dist": float(parts[4]), "night": False})
    return models, parents


def text_ipl(path: str) -> list[tuple]:
    entries, section = [], None
    for raw in open(path, encoding="latin1", errors="replace"):
        line = raw.strip()
        low = line.lower()
        if section is None:
            section = low if low in SECTIONS else None
            continue
        if low == "end":
            section = None
            continue
        if section != "inst":
            continue
        parts = [x.strip() for x in line.split(",")]
        if len(parts) >= 11 and parts[0].isdigit():
            entries.append((int(parts[0]), parts[1], int(parts[2]), *[float(v) for v in parts[3:10]], int(parts[10])))
    return entries


def binary_ipl(data: bytes) -> list[tuple]:
    """DragonFF gtaLib/map.py read_binary_ipl_from_stream: '4siiiiiii' header, 'fffffffiii' entries of 40 bytes."""
    _, count, _, _, _, _, _, offset = struct.unpack_from("<4siiiiiii", data, 0)
    entries = []
    for i in range(count):
        x, y, z, rx, ry, rz, rw, model, interior, lod = struct.unpack_from("<fffffffiii", data, offset + i * 40)
        entries.append((model, "", interior & 0xFF, x, y, z, rx, ry, rz, rw, lod))  # flags sit above the interior byte
    return entries


def keep_world(entries: list[tuple], models: dict[int, dict]) -> list[tuple]:
    """The entries of one IPL worth drawing by day in the open world: no interiors, no LOD twins, no night objects."""
    twins = {e[10] for e in entries if e[10] >= 0}
    out = []
    for i, e in enumerate(entries):
        if i in twins or e[2] != 0:
            continue
        m = models.get(e[0])
        name = (e[1] or (m["dff"] if m else "")).lower()
        if name.startswith("lod") or (m and m["night"]):
            continue
        out.append(e)
    return out


def world_placements(gta: Path, models: dict[int, dict]) -> list[tuple]:
    from tools.extract_samp_models import read_img_entry, read_img_index

    out = []
    for path in sorted(glob.glob(str(gta / "data" / "maps" / "**" / "*.ipl"), recursive=True)):
        out += keep_world(text_ipl(path), models)
    img = gta / "models" / "gta3.img"
    index = read_img_index(img)
    for name, entry in sorted(index.items()):
        if name.endswith(".ipl"):
            data = read_img_entry(img, entry)
            if data[:4] == b"bnry":
                out += keep_world(binary_ipl(data), models)
    return out


def port_rows(at: tuple, reach: float) -> tuple[list[tuple], list[tuple]]:
    """The port's own objects (maps/data/*.lua, puzzles.lua) and removals within reach of the place."""
    objects, removals = [], []
    for path in sorted(MAPS.glob("*.lua")) + [PUZZLES]:
        text = path.read_text(encoding="utf8")
        for m, x, y, z, rx, ry, rz, world, interior in ROW.findall(text):
            # Teleport interiors may share the same XY at z=1000; they must not shadow the street below.
            if int(world) in (-1, 0) and int(interior) in (-1, 0) and math.dist((float(x), float(y), float(z)), at) <= reach:
                objects.append((int(m), float(x), float(y), float(z), float(rx), float(ry), float(rz)))
        if "removals = {" in text:
            for m, x, y, z, r in REMOVAL.findall(text[text.index("removals = {") :]):
                if math.hypot(float(x) - at[0], float(y) - at[1]) <= reach + 50:
                    removals.append((int(m), float(x), float(y), float(z), float(r)))
    return objects, removals


def shell_jobs() -> dict[str, dict]:
    """The house shells that replace vanilla models for every client (house_shell/client/main.lua)."""
    files = str(HOUSE_SHELL / "files")
    jobs = {"3250": {"key": "3250", "model": 3250, "dir": files, "dff": "des_westrn9", "txds": ["des_westrn9"]}, "17067": {"key": "17067", "model": 17067, "dir": files, "dff": "cw2_logcabins", "txds": ["cw2_logcabins"]}}
    for mid, dff in re.findall(r"\[(\d+)\] = \{\s*dff = \"([^\"]+)\"", (HOUSE_SHELL / "trailers.lua").read_text(encoding="utf8")):
        jobs[mid] = {"key": mid, "model": int(mid), "dir": files, "dff": dff, "txds": ["trailers"]}
    return jobs


def water_quads(gta: Path, at: tuple, reach: float) -> list[list[list[float]]]:
    """water.dat: lines of three or four corners (x y z + four flow/wave values each) and a type; the ones near the place."""
    quads = []
    for line in (gta / "data" / "water.dat").read_text(encoding="latin1", errors="replace").splitlines():
        t = line.split()
        n = (len(t) - 1) // 7
        if n not in (3, 4) or len(t) != n * 7 + 1 or not t[0].lstrip("-").replace(".", "", 1).isdigit():
            continue
        pts = [[float(t[i * 7]), float(t[i * 7 + 1]), float(t[i * 7 + 2])] for i in range(n)]
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        if max(xs) < at[0] - reach or min(xs) > at[0] + reach or max(ys) < at[1] - reach or min(ys) > at[1] + reach:
            continue
        quads.append([pts[0], pts[1], pts[3], pts[2]] if n == 4 else pts)
    return quads


_archives: dict[str, tuple[Path, dict]] = {}


def fetch_txd(gta: Path, name: str) -> bytes | None:
    from tools.extract_samp_models import read_img_entry, read_img_index

    if not _archives:
        for n, p in [("gta3", "models/gta3.img"), ("gta_int", "models/gta_int.img"), ("samp", "SAMP/SAMP.img")]:
            if (gta / p).is_file():
                _archives[n] = (gta / p, read_img_index(gta / p))
    for path, index in _archives.values():
        if name + ".txd" in index:
            return read_img_entry(path, index[name + ".txd"])
    for folder in (gta / "models", gta / "models" / "generic"):
        if (folder / (name + ".txd")).is_file():
            return (folder / (name + ".txd")).read_bytes()
    return None


def stage_cached(ids: set[int], gta: Path, models: dict[int, dict], parents: dict[str, str]) -> tuple[dict[str, dict], list[str]]:
    """Jobs for the models, staged into the cache once (job.json per model; a failure is remembered too)."""
    from tools.render_item_models import stage

    CACHE.mkdir(parents=True, exist_ok=True)
    jobs, missing, problems = {}, [], []
    for m in sorted(ids):
        jf = CACHE / str(m) / "job.json"
        if jf.is_file():
            job = json.loads(jf.read_text())
            if job:
                jobs[str(m)] = job
        else:
            missing.append(m)
    if missing:
        new, problems = stage(set(missing), gta, CACHE)
        for j in new:
            j["key"] = str(j["model"])
            txd, seen = models.get(j["model"], {}).get("txd"), set(j["txds"])
            while txd and parents.get(txd) and parents[txd] not in seen:
                txd = parents[txd]
                data = fetch_txd(gta, txd)
                if data:
                    (Path(j["dir"]) / (txd + ".txd")).write_bytes(data)
                    j["txds"].append(txd)
                seen.add(txd)
            (Path(j["dir"]) / "job.json").write_text(json.dumps(j))
            jobs[j["key"]] = j
        for m in set(missing) - {j["model"] for j in new}:
            (CACHE / str(m)).mkdir(exist_ok=True)
            (CACHE / str(m) / "job.json").write_text("null")
    return jobs, problems


def build_place(name: str, place: dict, gta: Path, models: dict, parents: dict, world: list[tuple], radius: float, backdrop: float, types: dict, vehicles: dict) -> tuple[dict, dict, list[str], dict]:
    at = tuple(float(v) for v in place["at"])
    near, far = [], []
    for e in world:
        d = math.hypot(e[3] - at[0], e[4] - at[1])
        if d <= radius:
            near.append(e)
        elif d <= backdrop and models.get(e[0], {}).get("dist", 0) >= BIG_DRAW_DISTANCE:
            far.append(e)
    objects, removals = port_rows(at, radius)
    kept = []
    for e in near + far:
        if not any(e[0] == r[0] and math.dist((e[3], e[4], e[5]), (r[1], r[2], r[3])) <= r[4] + 0.5 for r in removals):
            kept.append(e)
    removed = len(near) + len(far) - len(kept)
    shells = shell_jobs()
    ids = {e[0] for e in kept} | {o[0] for o in objects}
    resolved, item_models, txd_only = {"name": name, "items": [], "camera": {}, "light": place.get("light", "day")}, set(), set()
    if place.get("items"):
        resolved, item_models, txd_only = rs.resolve(name, {"items": place["items"], "light": place.get("light", "day"), "camera": {}}, types, vehicles)
    jobs, problems = stage_cached((ids | item_models | txd_only) - {int(k) for k in shells}, gta, models, parents)
    jobs.update(shells)
    for key in {it["key"] for it in resolved["items"] if it.get("vehicle")}:  # a vehicle needs the shared vehicle.txd
        if key in jobs and not jobs[key].get("vehicle"):
            txds = jobs[key]["txds"] + ([] if "vehicle" in jobs[key]["txds"] else ["vehicle"])
            jobs[key] = dict(jobs[key], vehicle=True, txds=txds)
            if not (Path(jobs[key]["dir"]) / "vehicle.txd").is_file():
                (Path(jobs[key]["dir"]) / "vehicle.txd").write_bytes(fetch_txd(gta, "vehicle") or b"")
    for key, f in rs.FILES.items():
        jobs[key] = dict(f, key=key, model=key)
    staged = set(jobs)
    world_rows = [[str(e[0]), e[3], e[4], e[5], e[6], e[7], e[8], e[9]] for e in kept if str(e[0]) in staged]
    port = [[str(o[0]), o[1], o[2], o[3], o[4], o[5], o[6]] for o in objects if str(o[0]) in staged]
    items = [it for it in resolved["items"] if it["key"] in staged and (not it.get("texture") or it["texture"][0] in staged)]
    spec = {"name": name, "at": list(at), "camera": place["camera"], "light": place.get("light", "day"), "ground": place.get("ground", "dirt"), "caption": place.get("caption", name), "world": world_rows, "port": port, "water": water_quads(gta, at, backdrop), "items": items}
    stats = {"near": len(near), "far": len(far), "removed": removed, "port": len(port), "models": len({r[0] for r in world_rows + port}), "unstaged": len({e[0] for e in kept} | {o[0] for o in objects}) - len({r[0] for r in world_rows + port}), "water": len(spec["water"])}
    return spec, jobs, problems, stats


# ---------------------------------------------------------------- inside Blender


def build_in_blender(spec_file: Path) -> None:
    import bpy
    from mathutils import Euler, Matrix, Quaternion, Vector

    from DragonFF.ops import dff_importer, txd_importer  # noqa: PLC0415
    import tools.render_item_models as rim  # noqa: PLC0415
    from tools.render_item_models import EFFECT_TEXTURES, CaseDict  # noqa: PLC0415

    spec = json.loads(Path(spec_file).read_text())
    jobs = spec["jobs"]
    width, height = spec["size"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    scn = bpy.context.scene
    use_cycles = spec.get("engine", "cycles") == "cycles"
    if use_cycles and spec.get("device", "auto") != "cpu":
        prefs = bpy.context.preferences.addons["cycles"].preferences
        for backend in ("CUDA", "OPTIX", "HIP", "ONEAPI", "METAL"):
            try:
                prefs.compute_device_type = backend
                prefs.get_devices()
            except (TypeError, RuntimeError):
                continue
            devices = [d for d in prefs.devices if d.type == backend]
            if devices:
                for d in prefs.devices:
                    d.use = d.type == backend
                scn.cycles.device = "GPU"
                print("PLACE device", backend, ", ".join(d.name for d in devices), flush=True)
                break

    def setattr_safe(obj, name, value):
        try:
            setattr(obj, name, value)
        except (AttributeError, TypeError) as e:
            print("PLACE note", name, "not set:", e)

    txd_cache: dict[str, CaseDict] = {}

    def images_for(key):
        """The images of a job's TXDs; each TXD file is imported once, however many models share it."""
        if key not in txd_cache:
            images = CaseDict()
            for t in jobs[key]["txds"]:
                path = os.path.join(jobs[key]["dir"], t + ".txd")
                if path not in txd_cache:
                    txd_cache[path] = CaseDict({k.lower(): v for k, v in txd_importer.import_txd({"file_name": path, "skip_mipmaps": True, "pack": True}).images.items()}) if os.path.isfile(path) else CaseDict()
                images.update(txd_cache[path])
            txd_cache[key] = images
        return txd_cache[key]

    def socket(node, ident, outputs=False):
        return next(s for s in (node.outputs if outputs else node.inputs) if s.identifier == ident)

    def fix_materials(meshes, images, override):
        lost = set()
        for o in meshes:
            for slot in o.material_slots:
                mat = slot.material
                if not mat or not mat.node_tree:
                    continue
                nodes = mat.node_tree.nodes
                for n in list(nodes):
                    if n.type == "TEX_IMAGE":
                        if override is not None:
                            n.image = override
                        elif not n.image and n.label in images:
                            n.image = images[n.label][0]
                        if not n.image:
                            if n.label.lower() not in EFFECT_TEXTURES:
                                lost.add(n.label)
                            nodes.remove(n)
                bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bsdf is not None:
                    bsdf.inputs["Roughness"].default_value = 0.8
                    if "Specular IOR Level" in bsdf.inputs:
                        bsdf.inputs["Specular IOR Level"].default_value = 0.2
                setattr_safe(mat, "surface_render_method", "DITHERED")
                mat.use_backface_culling = False
        return lost

    def drop_effects(meshes):
        import bmesh  # noqa: PLC0415

        for o in meshes:
            if any(k in o.name.lower() for k in rs.EFFECT_NAMES):
                o.hide_render = o.hide_viewport = True
                continue
            drop = [i for i, sl in enumerate(o.material_slots) if sl.material and sl.material.node_tree and any(n.type == "TEX_IMAGE" and any(k in n.label.lower() for k in rs.EFFECT_TEXTURE_KEYS) for n in sl.material.node_tree.nodes)]
            if drop:
                bm = bmesh.new()
                bm.from_mesh(o.data)
                bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in drop], context="FACES")
                bm.to_mesh(o.data)
                bm.free()

    protos: dict[tuple, dict] = {}

    def prototype(key, colour=None, texture=None):
        """One import of a job's model, kept in an unlinked collection: its visible meshes with their matrices."""
        pk = (key, colour, texture)
        if pk in protos:
            return protos[pk]
        job = jobs[key]
        images = images_for(key)
        override = None
        if texture is not None:
            txd_images = images_for(texture[0])
            override = txd_images[texture[1]][0] if texture[1] in txd_images else None
        before = set(bpy.data.objects)
        # GTA supplies vertex normals for its terrain, curved props and deliberately sharp building edges.
        dff_importer.import_dff({"file_name": os.path.join(job["dir"], job["dff"] + ".dff"), "txd_images": images, "image_ext": None, "connect_bones": False, "use_mat_split": True, "remove_doubles": False, "create_backfaces": False, "group_materials": False, "import_normals": True, "materials_naming": "DEFAULT", "hide_damage_parts": bool(job.get("vehicle"))})
        new = [o for o in bpy.data.objects if o not in before]
        for o in [o for o in new if o.type == "MESH" and o.dff.type == "COL" or o.type == "LIGHT"]:
            bpy.data.objects.remove(o, do_unlink=True)
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == "MESH"]
        lost = fix_materials(meshes, images, override)
        if lost:
            print("PLACE missing", key, ",".join(sorted(lost)))
        drop_effects(meshes)
        bpy.context.view_layer.update()
        if job.get("vehicle"):
            rim.BODY_COLOUR = tuple(colour or (0.62, 0.64, 0.66)) + (1.0,)
            rim.recolour_vehicle(meshes)
            hide = {h.lower() for h in job.get("hide", [])}
            for o in [o for o in bpy.data.objects if o not in before]:
                if o.parent is not None and o.parent.name.lower() in hide:
                    o.hide_render = o.hide_viewport = True
            bpy.context.view_layer.update()
        new = [o for o in bpy.data.objects if o not in before]
        parts = [(o, o.matrix_world.copy()) for o in new if o.type == "MESH" and not o.hide_render]
        pts = [m @ Vector(c) for o, m in parts for c in o.bound_box]
        coll = bpy.data.collections.new("proto_%s_%d" % (key, len(protos)))
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            coll.objects.link(o)
            o.name = "%s/%s" % (coll.name, o.name)
        for c in [c for c in scn.collection.children if not c.objects and not c.children and not c.get("keep")]:
            bpy.data.collections.remove(c)  # the importer's own, now empty, collection
        protos[pk] = {"coll": coll, "parts": parts, "corners": pts}
        return protos[pk]

    def clear_scene():
        for o in list(scn.collection.all_objects):
            bpy.data.objects.remove(o, do_unlink=True)
        for c in list(scn.collection.children):
            bpy.data.collections.remove(c)

    def stamp(proto, matrix, into):
        """Linked copies of a prototype's meshes placed by a world matrix (real objects, so rays can hit them)."""
        for o, local in proto["parts"]:
            c = o.copy()
            c.matrix_world = matrix @ local
            c.hide_render = c.hide_viewport = False
            into.objects.link(c)

    def place_world(place):
        world = bpy.data.collections.new("world")
        world["keep"] = True
        scn.collection.children.link(world)
        for key, x, y, z, qx, qy, qz, qw in place["world"]:
            proto = prototype(key)
            if proto["parts"]:
                stamp(proto, Matrix.LocRotScale((x, y, z), Quaternion((-qw, qx, qy, qz)), None), world)
        for key, x, y, z, rx, ry, rz in place["port"]:
            proto = prototype(key)
            if proto["parts"]:
                stamp(proto, Matrix.LocRotScale((x, y, z), Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "YXZ"), None), world)
        return world

    def make_water(quads):
        if not quads:
            return
        verts, faces = [], []
        for q in quads:
            faces.append(list(range(len(verts), len(verts) + len(q))))
            verts += [tuple(p) for p in q]
        me = bpy.data.meshes.new("water")
        me.from_pydata(verts, [], faces)
        o = bpy.data.objects.new("water", me)
        scn.collection.objects.link(o)
        m = bpy.data.materials.new("water")
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Base Color"].default_value = (0.02, 0.07, 0.09, 1.0)
        bsdf.inputs["Roughness"].default_value = 0.06
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.6
        me.materials.append(m)

    def terrain_z(depsgraph, x, y, hint):
        for start in (hint + 2.5, hint + 40.0):
            hit, loc, *_ = scn.ray_cast(depsgraph, Vector((x, y, start)), Vector((0.0, 0.0, -1.0)), distance=start - hint + 60.0)
            if hit:
                return loc.z
        return hint

    def place_items(place):
        """The render_scenes placement spec, positions relative to the place, every placement dropped onto the terrain."""
        ax, ay, az = place["at"]
        depsgraph = bpy.context.evaluated_depsgraph_get()
        named = {}
        for n, it in enumerate(place["items"]):
            proto = prototype(it["key"], tuple(it["colour"]) if it.get("colour") else None, tuple(it["texture"]) if it.get("texture") else None)
            rot = Euler([math.radians(a) for a in it["rot"]], "YXZ")
            s = float(it.get("scale", 1.0))
            m = Matrix.LocRotScale(None, rot, Vector((s, s, s)))
            pts = [m @ c for c in proto["corners"]]
            x, y, lz = ax + it["at"][0], ay + it["at"][1], it["at"][2]
            if it.get("on") and it["on"] in named:
                z = named[it["on"]] + lz
            else:
                z = terrain_z(depsgraph, x, y, az + lz) + lz if not it.get("drop", True) else terrain_z(depsgraph, x, y, az)
            if it.get("drop", True) and pts:
                z -= min(p.z for p in pts)
            e = bpy.data.objects.new("i%d_%s" % (n, it["label"]), None)
            e.instance_type = "COLLECTION"
            e.instance_collection = proto["coll"]
            e.location = (x, y, z)
            e.rotation_mode = "YXZ"
            e.rotation_euler = rot
            e.scale = (s, s, s)
            scn.collection.objects.link(e)
            if it.get("glow"):
                r, g, b, watts = it["glow"]
                data = bpy.data.lights.new("glow%d" % n, "POINT")
                data.color, data.energy, data.shadow_soft_size = (r, g, b), watts, 0.25
                lamp = bpy.data.objects.new("glow%d" % n, data)
                lamp.location = (x, y, z + it.get("glow_z", 0.35))
                scn.collection.objects.link(lamp)
            if it.get("name") and pts:
                named[it["name"]] = z + max(p.z for p in pts)

    def sky_dir(elevation, azimuth):
        el, az = math.radians(elevation), math.radians(azimuth)
        return Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))

    def make_world(light, sun_dir):
        w = bpy.data.worlds.new("sky")
        w.use_nodes = True
        nt = w.node_tree
        bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
        out = next(n for n in nt.nodes if n.type == "OUTPUT_WORLD")
        tc, sep, mr, ramp = nt.nodes.new("ShaderNodeTexCoord"), nt.nodes.new("ShaderNodeSeparateXYZ"), nt.nodes.new("ShaderNodeMapRange"), nt.nodes.new("ShaderNodeValToRGB")
        nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
        nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
        mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = -0.02, 0.45
        nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
        ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.0, tuple(light["horizon"]) + (1.0,)
        ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 1.0, tuple(light["zenith"]) + (1.0,)
        mid = ramp.color_ramp.elements.new(0.3)
        mid.color = tuple((a * 0.5 + b * 0.5) for a, b in zip(light["horizon"], light["zenith"])) + (1.0,)
        dot, power, glow = nt.nodes.new("ShaderNodeVectorMath"), nt.nodes.new("ShaderNodeMath"), nt.nodes.new("ShaderNodeMix")
        dot.operation, power.operation, glow.data_type = "DOT_PRODUCT", "POWER", "RGBA"
        dot.inputs[1].default_value = tuple(sun_dir)
        nt.links.new(tc.outputs["Generated"], dot.inputs[0])
        nt.links.new(dot.outputs["Value"], power.inputs[0])
        power.inputs[1].default_value = 12.0
        power.use_clamp = True
        nt.links.new(ramp.outputs["Color"], socket(glow, "A_Color"))
        socket(glow, "B_Color").default_value = tuple(min(1.0, c * 1.6) for c in light["sun_colour"]) + (1.0,)
        nt.links.new(power.outputs["Value"], socket(glow, "Factor_Float"))
        glow.clamp_factor = True
        nt.links.new(socket(glow, "Result_Color", True), bg.inputs["Color"])
        bg.inputs["Strength"].default_value = light["sky"]
        w.mist_settings.start, w.mist_settings.depth, w.mist_settings.falloff = 40.0, 1100.0, "LINEAR"
        scn.world = w

    def make_daylight(name):
        light = DAYLIGHT[name]
        w = bpy.data.worlds.new("daylight")
        w.use_nodes = True
        nt = w.node_tree
        bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
        sky = nt.nodes.new("ShaderNodeTexSky")
        sky_types = {i.identifier for i in sky.bl_rna.properties["sky_type"].enum_items}
        sky.sky_type = "MULTIPLE_SCATTERING" if "MULTIPLE_SCATTERING" in sky_types else "NISHITA"
        sky.sun_elevation, sky.sun_rotation = math.radians(light["elevation"]), math.radians(light["rotation"])
        sky.sun_disc, sky.sun_size, sky.sun_intensity = True, math.radians(0.526), light["sun"]
        sky.air_density, sky.ozone_density = 1.0, 1.0
        if hasattr(sky, "aerosol_density"):
            sky.aerosol_density = light["aerosol"]
        else:
            sky.dust_density = light["aerosol"]
        bg.inputs["Strength"].default_value = light["strength"]
        nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
        scn.world = w

    def make_haze(light):
        """Aerial perspective in the compositor: the mist pass fades the picture toward the sky's horizon colour, the
        sky itself (depth beyond the world) left alone. (An EEVEE world volume blacked the frame out instead.)"""
        vl = bpy.context.view_layer
        vl.use_pass_mist = vl.use_pass_z = True
        if hasattr(scn, "compositing_node_group"):  # Blender 5: the compositor is a node group ending in a group output
            nt = bpy.data.node_groups.new("haze", "CompositorNodeTree")
            nt.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
            scn.compositing_node_group = nt
            out = nt.nodes.new("NodeGroupOutput")
        else:
            scn.use_nodes = True
            nt = scn.node_tree
            nt.nodes.clear()
            out = nt.nodes.new("CompositorNodeComposite")
        scn.render.use_compositing = True
        rl = nt.nodes.new("CompositorNodeRLayers")
        rl.scene = scn
        depth = next(o for o in rl.outputs if o.name in ("Depth", "Z"))
        near = nt.nodes.new("ShaderNodeMath")
        near.operation = "LESS_THAN"
        near.inputs[1].default_value = 50000.0
        nt.links.new(depth, near.inputs[0])
        fac = nt.nodes.new("ShaderNodeMath")
        fac.operation = "MULTIPLY"
        nt.links.new(rl.outputs["Mist"], fac.inputs[0])
        nt.links.new(near.outputs[0], fac.inputs[1])
        strength = nt.nodes.new("ShaderNodeMath")
        strength.operation = "MULTIPLY"
        strength.inputs[1].default_value = light.get("haze", 0.6)
        nt.links.new(fac.outputs[0], strength.inputs[0])
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        socket(mix, "B_Color").default_value = tuple(c * light["sky"] for c in light["horizon"]) + (1.0,)
        nt.links.new(strength.outputs[0], socket(mix, "Factor_Float"))
        nt.links.new(rl.outputs["Image"], socket(mix, "A_Color"))
        nt.links.new(socket(mix, "Result_Color", True), out.inputs[0])

    def ground_material(name, preset, horizon, tint):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value, noise.inputs["Detail"].default_value, noise.inputs["Roughness"].default_value = preset["scale"], 12.0, 0.75
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.38, tuple(c * tint for c in preset["a"]) + (1.0,)
        ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 0.62, tuple(c * tint for c in preset["b"]) + (1.0,)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        cam, dist = nt.nodes.new("ShaderNodeCameraData"), nt.nodes.new("ShaderNodeMapRange")
        dist.inputs["From Min"].default_value, dist.inputs["From Max"].default_value = 100.0, 2500.0
        nt.links.new(cam.outputs["View Distance"], dist.inputs["Value"])
        fog = nt.nodes.new("ShaderNodeMix")
        fog.data_type = "RGBA"
        socket(fog, "B_Color").default_value = tuple(horizon) + (1.0,)
        nt.links.new(ramp.outputs["Color"], socket(fog, "A_Color"))
        nt.links.new(dist.outputs["Result"], socket(fog, "Factor_Float"))
        nt.links.new(socket(fog, "Result_Color", True), bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.95
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.2
        return m

    def make_floor(place, light, world):
        """A plane under everything loaded, so the land beyond the backdrop ring is not sky: below the lowest mesh."""
        zs = [(o.matrix_world @ Vector(c)).z for o in world.objects for c in o.bound_box]
        floor = (min(zs) if zs else place["at"][2]) - 2.0
        if os.environ.get("RENDER_PLACES_NO_FLOOR"):
            return
        bpy.ops.mesh.primitive_plane_add(size=8000, location=(place["at"][0], place["at"][1], floor))
        g = bpy.context.object
        g.name = "floor"
        g.data.materials.append(ground_material("floor", rs.GROUNDS[place["ground"]], light["horizon"], 0.8))

    def sun_at(name, direction, energy, colour, angle, shadow):
        data = bpy.data.lights.new(name, "SUN")
        data.energy, data.color, data.angle, data.use_shadow = energy, colour, math.radians(angle), shadow
        setattr_safe(data, "use_shadow_jitter", True)
        setattr_safe(data, "shadow_cascade_max_distance", 600.0)
        setattr_safe(data, "shadow_cascade_count", 4)
        o = bpy.data.objects.new(name, data)
        scn.collection.objects.link(o)
        o.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        return o

    def make_camera(spec, place_z):
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        scn.camera = cam
        look = Vector(spec["look_at"])
        if spec.get("ground"):  # look_at z is a height above the terrain there
            look.z += terrain_z(bpy.context.evaluated_depsgraph_get(), look.x, look.y, place_z)
        cam.location = look + sky_dir(spec.get("elevation", 12), spec.get("azimuth", -35)) * spec.get("distance", 40.0)
        cam.rotation_euler = (look - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.sensor_fit, cam.data.sensor_width, cam.data.lens = "HORIZONTAL", 36.0, spec.get("lens", 35)
        cam.data.clip_start, cam.data.clip_end = 0.1, 8000.0
        cam.data.shift_y = spec.get("shift_y", 0.0)
        if spec.get("fstop"):
            cam.data.dof.use_dof = True
            cam.data.dof.focus_distance = (look - cam.location).length
            cam.data.dof.aperture_fstop = spec["fstop"]
        return cam

    def setup_render(samples):
        engines = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
        scn.render.engine = "CYCLES" if use_cycles else ("BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE")
        scn.render.resolution_x, scn.render.resolution_y, scn.render.resolution_percentage = width, height, 100
        scn.render.film_transparent = False
        scn.render.image_settings.file_format, scn.render.image_settings.color_mode = "PNG", "RGB"
        ee = scn.eevee
        setattr_safe(ee, "taa_render_samples", samples)
        setattr_safe(ee, "use_shadows", True)
        setattr_safe(ee, "shadow_ray_count", 2)
        setattr_safe(ee, "shadow_step_count", 4)
        setattr_safe(ee, "use_raytracing", True)
        setattr_safe(ee, "ray_tracing_method", "SCREEN")
        setattr_safe(ee, "use_fast_gi", True)
        setattr_safe(ee, "fast_gi_method", "GLOBAL_ILLUMINATION")
        setattr_safe(ee, "fast_gi_distance", 10.0)
        setattr_safe(ee.ray_tracing_options, "use_denoise", True)
        for vt in ("AgX", "Filmic", "Standard"):
            try:
                scn.view_settings.view_transform = vt
                break
            except TypeError:
                continue
        for look in ("AgX - Medium High Contrast", "Medium High Contrast", "None"):
            try:
                scn.view_settings.look = look
                break
            except TypeError:
                continue
        scn.view_settings.exposure = -0.6 if use_cycles else 0.05
        if use_cycles:
            scn.cycles.samples, scn.cycles.use_denoising = samples, True
            scn.cycles.adaptive_threshold = 0.03
            scn.cycles.max_bounces = 6
            scn.cycles.diffuse_bounces, scn.cycles.glossy_bounces = 3, 3
            scn.cycles.transparent_max_bounces = 16
            scn.render.use_compositing = False

    for place in spec["places"]:
        clear_scene()
        light = rs.LIGHTS[place["light"]]
        world = place_world(place)
        make_water(place["water"])
        make_floor(place, light, world)
        bpy.context.view_layer.update()
        place_items(place)
        cam = make_camera(place["camera"], place["at"][2])
        cam_az = place["camera"].get("azimuth", -35)
        sun = sky_dir(light["sun_elevation"], cam_az + light["sun_offset"])
        if use_cycles:
            make_daylight(place["light"])
        else:
            make_world(light, sun)
            make_haze(light)
            sun_at("sun", sun, light["sun_energy"], light["sun_colour"], light["sun_angle"], True)
            sun_at("fill", sky_dir(35, cam_az + light["sun_offset"] + 180), light["fill"], light["fill_colour"], 60, False)
        setup_render(spec["samples"])
        bpy.context.view_layer.update()
        look = Vector(place["camera"]["look_at"])
        look.z = cam.location.z if place["camera"].get("ground") else look.z
        hit, loc, *_ = scn.ray_cast(bpy.context.evaluated_depsgraph_get(), cam.location, (look - cam.location).normalized(), distance=max((look - cam.location).length, 1.0))
        zs = [(o.matrix_world @ Vector(c)).z for o in world.objects for c in o.bound_box]
        print("PLACE stats %s: %d world objects, %d prototypes, camera %.1f %.1f %.1f, first hit toward the target %s, world z %.1f..%.1f" % (place["name"], len(world.objects), len(protos), *cam.location, ("%.1f m" % (loc - cam.location).length) if hit else "none", min(zs) if zs else 0, max(zs) if zs else 0), flush=True)
        path = os.path.join(spec["out"], place["name"] + ".png")
        scn.render.filepath = path
        try:
            bpy.ops.render.render(write_still=True)
        except RuntimeError:
            if not use_cycles or scn.cycles.device != "GPU":
                raise
            print("PLACE note GPU render failed; retrying with the CPU", flush=True)
            scn.cycles.device = "CPU"
            bpy.ops.render.render(write_still=True)
        print("PLACE ok", place["name"], path, flush=True)


# ---------------------------------------------------------------- outside Blender


def main(argv=None) -> int:
    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta
    from tools.render_item_models import find_txds, vehicle_models

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--place", action="append", help="place name (repeatable); default: every place")
    ap.add_argument("--at", help="x,y,z of an ad-hoc place (with --radius), named by its coordinates")
    ap.add_argument("--radius", type=float, default=150.0, help="metres around the place to load every object, default 150")
    ap.add_argument("--backdrop", type=float, default=550.0, help="metres to load the large models out to, default 550 (terrain chunks have far-off origins)")
    ap.add_argument("--list", action="store_true", help="list the places and exit")
    ap.add_argument("--gta", type=Path)
    ap.add_argument("--blender")
    ap.add_argument("--size", default="1920x1080", help="WxH, default 1920x1080")
    ap.add_argument("--samples", type=int, default=64, help="render samples, default 64")
    ap.add_argument("--engine", choices=("cycles", "eevee"), default="cycles", help="Cycles daylight and indirect lighting, or a fast EEVEE draft")
    ap.add_argument("--device", choices=("auto", "cpu"), default="auto", help="use a supported GPU when available, or force the CPU")
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--wiki", type=Path, default=WIKI_OUT, help="folder for the 1200 px copies; '-' to skip")
    ap.add_argument("--stats", action="store_true", help="print what each place loaded")
    ap.add_argument("--azimuth", type=float, help="with --at: camera azimuth (default -35)")
    ap.add_argument("--elevation", type=float, help="with --at: camera elevation (default 12)")
    ap.add_argument("--distance", type=float, help="with --at: camera distance (default 60)")
    args = ap.parse_args(argv)
    if args.list:
        for n, p in PLACES.items():
            print(f"{n:18s} {p['caption']}")
        return 0
    places = dict(PLACES)
    names = args.place or []
    if args.at:
        x, y, z = (float(v) for v in args.at.split(","))
        name = "at_%d_%d" % (round(x), round(y))
        places[name] = {"caption": name, "at": (x, y, z), "camera": {"look_at": (x, y, z + 1.5), "azimuth": args.azimuth if args.azimuth is not None else -35, "elevation": args.elevation if args.elevation is not None else 12, "distance": args.distance or 60, "lens": 35}, "light": "day"}
        names.append(name)
    names = names or list(PLACES)
    unknown = [n for n in names if n not in places]
    if unknown:
        print("render_places: unknown place(s):", ", ".join(unknown), file=sys.stderr)
        return 2
    gta = args.gta or detect_gta()
    blender = find_blender(args.blender)
    if not gta or not blender:
        print("render_places: need GTA:SA (--gta) and Blender (--blender)", file=sys.stderr)
        return 2
    m = re.fullmatch(r"(\d+)x(\d+)", args.size)
    if not m:
        print("render_places: --size wants WxH", file=sys.stderr)
        return 2
    size = [int(m.group(1)), int(m.group(2))]
    models, parents = ide_tables(gta)
    world = world_placements(gta, models)
    types, vehicles = rs.item_types(), vehicle_models()
    specs, jobs, problems = [], {}, []
    for n in names:
        radius = places[n].get("radius", args.radius)
        spec, pjobs, pproblems, stats = build_place(n, places[n], gta, models, parents, world, radius, places[n].get("backdrop", args.backdrop), types, vehicles)
        specs.append(spec)
        jobs.update(pjobs)
        problems += pproblems
        if args.stats:
            print("%s: %d near + %d backdrop objects (%d removed by the port), %d port objects, %d models (%d not staged), %d water quads" % (n, stats["near"], stats["far"], stats["removed"], stats["port"], stats["models"], stats["unstaged"], stats["water"]))
    args.out.mkdir(parents=True, exist_ok=True)
    work = Path(tempfile.mkdtemp(prefix="render_places_"))
    spec = {"out": str(args.out.resolve()), "size": size, "samples": args.samples, "engine": args.engine, "device": args.device, "jobs": jobs, "places": specs}
    spec_file = work / "spec.json"
    spec_file.write_text(json.dumps(spec))
    cmd = [str(blender), "-b", "--python-exit-code", "1", "--python", __file__, "--", str(spec_file)]

    def run_blender():
        lines = []
        with subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf8", errors="replace") as process:
            for line in process.stdout:
                line = line.rstrip("\r\n")
                lines.append(line)
                if line.startswith(("PLACE ok ", "PLACE device ")):
                    print(line, flush=True)
            return process.wait(), lines

    returncode, lines = run_blender()
    lost: dict[str, set[str]] = {}
    for line in lines:
        if line.startswith("PLACE missing"):
            _, _, key, names_ = line.split(" ", 3)
            lost.setdefault(key, set()).update(x.lower() for x in names_.split(",") if (key, x.lower()) not in rs.NO_FALLBACK)
    wanted = set().union(*lost.values()) if lost else set()
    if wanted and len(wanted) <= 60:  # textures a model's own TXD lacks: borrow from the game TXD that holds them, once
        where = find_txds(wanted, gta)
        again = False
        for key, names_ in lost.items():
            for t in sorted({where[n][0] for n in names_ if n in where}):
                if key in jobs and t not in jobs[key]["txds"]:
                    (Path(jobs[key]["dir"]) / (t + ".txd")).write_bytes(next(d for n, (x, d) in where.items() if x == t))
                    jobs[key]["txds"].append(t)
                    if (Path(jobs[key]["dir"]) / "job.json").is_file():
                        (Path(jobs[key]["dir"]) / "job.json").write_text(json.dumps(jobs[key]))
                    again = True
        for n in sorted(wanted - set(where)):
            problems.append(f"texture {n} is in no game TXD")
        if again:
            spec_file.write_text(json.dumps(spec))
            returncode, lines = run_blender()
    elif wanted:
        problems.append("%d textures not found in the models' own TXDs (too many to search)" % len(wanted))
    for line in lines:
        if line.startswith("PLACE stats") and args.stats or line.startswith("PLACE note") or "Error" in line or "Traceback" in line:
            print(line)
    index_file = args.out / "index.json"
    index = json.loads(index_file.read_text()) if index_file.is_file() else {}
    # An ad-hoc --at render or a removed place may leave metadata behind after its image is gone.
    index = {name: entry for name, entry in index.items() if (args.out / entry.get("file", "")).is_file()}
    done = []
    for s in specs:
        png = args.out / (s["name"] + ".png")
        if png.is_file() and any(line.startswith("PLACE ok " + s["name"] + " ") for line in lines):
            index[s["name"]] = {"file": png.name, "caption": s["caption"], "at": s["at"], "camera": s["camera"], "light": s["light"], "engine": args.engine}
            done.append(png)
            print("wrote", png, "->", rs.wiki_copy(png, args.wiki) if str(args.wiki) != "-" else "")
        else:
            problems.append(f"{s['name']}: no render written")
    index_file.write_text(json.dumps(index, indent=1, sort_keys=True) + "\n")
    for p in problems:
        print("problem:", p, file=sys.stderr)
    if returncode:
        print("\n".join(lines)[-3000:], file=sys.stderr)
    return 0 if len(done) == len(specs) else 1


if __name__ == "__main__":
    if "bpy" in sys.modules:
        build_in_blender(Path(sys.argv[sys.argv.index("--") + 1]))
    else:
        sys.exit(main())
