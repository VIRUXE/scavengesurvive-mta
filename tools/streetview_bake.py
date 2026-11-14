"""Bake the GTA SA world into static files for the staff map's street view (ops/dashboard/web/streetview.js).

    python -m tools.streetview_bake [--gta DIR] [--out DIR] [--at X,Y --radius R] [--jobs N] [--cells-only]

Reads the game files the way tools/render_places.py does (IDE tables, text IPLs, binary stream IPLs in gta3.img, the port's own
map rows and removals) and writes, under --out (default /var/www/nasa/ssmta/streetview):

    index.json          cell size, bounds, sky, fog, counts, bake time
    models/<id>.bin     one merged mesh per model id (see write_model), GTA coordinates (Z up, metres)
    tex/<txd>/<name>.webp   textures, at most TEX_MAX px a side (RGB when opaque, RGBA when not)
    textures.json       {txd: {name: 1 if the texture has alpha else 0}}, so the browser can walk a model's txd chain
    cells/<cx>_<cy>.json    the full-detail layer of a 200 m cell: {model id: [x, y, z, qx, qy, qz, qw, ...]}
    lod/<cx>_<cy>.json      the far layer of a cell (the game's own LOD models, plus large scenery that has none)
    water.json          every water.dat quad: [[x, y, z] * 4]

Models and textures already on disk are kept, so a rerun only does what is missing; --cells-only rewrites just the cell, LOD,
water and index files (after a change to maps/data). No Blender needed: DragonFF's gtaLib is used as a plain Python library.
Not in the bake: interiors, night-only objects, the port's custom model ids (only vanilla ids are drawn) and the house-shell swaps.
"""

from __future__ import annotations

import argparse
import glob
import json
import math
import os
import re
import struct
import sys
import time
from multiprocessing import Pool
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import tools.render_places as rp  # noqa: E402
from tools.extract_samp_models import detect_gta, read_img_entry, read_img_index  # noqa: E402

OUT_DEFAULT = Path("/var/www/nasa/ssmta/streetview")
RES = ROOT / "resources" / "[scavengesurvive]"
CUSTOM_MANIFESTS = [("samp_models", "manifest.lua"), ("box_models", "boxes.lua")]
CUSTOM_ROW = re.compile(r"\[(\d+)\] = \{([^}]*)\}")
CUSTOM_FIELD = re.compile(r"(\w+) = (\"[^\"]*\"|\d+)")
WORLD = 3000
CELL = 200
CELLS = WORLD * 2 // CELL
TEX_MAX = 256
SKIP_FRAMES = ("_dam", "_vlo")  # damaged and very-low-detail twins sit in the same DFF as the intact atomic
HUGE = 1e9

GDFF = GTXD = None  # DragonFF gtaLib modules, loaded by load_gtalib() before the worker pool forks
GTA: Path = Path()
ARCH: list[tuple[Path, dict]] = []


# ---------------------------------------------------------------------------------------------------- setup


def find_dragonff() -> Path:
    env = os.environ.get("DRAGONFF")
    roots = [Path(env)] if env else []
    home = Path.home() / ".config" / "blender"
    roots += sorted(home.glob("*/scripts/addons/DragonFF"), reverse=True) + sorted(home.glob("*/extensions/*/DragonFF"), reverse=True)
    for root in roots:
        if (root / "gtaLib" / "dff.py").is_file():
            return root
    sys.exit("streetview_bake: DragonFF not found (set DRAGONFF to its addon folder, the one holding gtaLib/)")


def load_gtalib() -> None:
    global GDFF, GTXD
    sys.path.insert(0, str(find_dragonff()))
    from gtaLib import dff as gdff, txd as gtxd  # noqa: PLC0415

    GDFF, GTXD = gdff, gtxd


def open_archives() -> None:
    ARCH.clear()
    for name in ("gta3.img", "gta_int.img"):
        path = GTA / "models" / name
        if path.is_file():
            ARCH.append((path, read_img_index(path)))


def init_worker(gta: str) -> None:
    """Pool initializer: Python 3.14 starts workers with forkserver, so nothing set up in main() is inherited."""
    global GTA
    GTA = Path(gta)
    load_gtalib()
    open_archives()


def fetch_dff(name: str) -> bytes | None:
    """A vanilla model by name, or a port model file by absolute path (custom_models)."""
    if name.startswith("/"):
        return Path(name).read_bytes() if Path(name).is_file() else None
    for path, index in ARCH:
        if name + ".dff" in index:
            return read_img_entry(path, index[name + ".dff"])
    for folder in (GTA / "models", GTA / "models" / "generic"):
        if (folder / (name + ".dff")).is_file():
            return (folder / (name + ".dff")).read_bytes()
    return None


def fetch_txd(key: str) -> bytes | None:
    """A vanilla txd by name, or a port one by its 'x-<resource>-<name>' key (custom_models)."""
    if key.startswith("x-"):
        _, res, name = key.split("-", 2)
        path = RES / res / "files" / (name + ".txd")
        return path.read_bytes() if path.is_file() else None
    return rp.fetch_txd(GTA, key)


def txd_chain(models: dict[int, dict], parents: dict[str, str], mid: int) -> list[str]:
    chain, txd = [], models[mid]["txd"]
    while txd and txd not in chain:
        chain.append(txd)
        txd = parents.get(txd)
    return chain


def custom_models(models: dict[int, dict], parents: dict[str, str]) -> dict[int, dict]:
    """Port model ids placed by maps/data: {id: {"dff": absolute path, "chain": txd keys}} from the samp_models and box_models manifests."""
    out = {}
    for res, manifest in CUSTOM_MANIFESTS:
        text = (RES / res / manifest).read_text(encoding="utf8")
        for mid, body in CUSTOM_ROW.findall(text):
            fields = dict(CUSTOM_FIELD.findall(body))
            if "dff" not in fields:
                continue
            if "txd" in fields:
                chain = [f"x-{res}-{fields['txd'].strip(chr(34))}"]
            elif "txdModel" in fields and int(fields["txdModel"]) in models:
                chain = txd_chain(models, parents, int(fields["txdModel"]))
            else:
                chain = []
            out[int(mid)] = {"dff": str(RES / res / "files" / (fields["dff"].strip('"') + ".dff")), "chain": chain}
    return out


# ---------------------------------------------------------------------------------------------------- placements


def classify(entries: list[tuple], models: dict[int, dict], twins: set[int]) -> tuple[list[tuple], list[tuple]]:
    """One IPL's exterior day entries as (full detail, far): LOD twins (indices in `twins`) and lod* models are far only;
    large scenery without a twin is both."""
    hi, far = [], []
    for i, e in enumerate(entries):
        m = models.get(e[0])
        if e[2] not in (0, 13) or not m or m["night"]:  # interior 13 is GTA's "visible everywhere" (Cranberry Station)
            continue
        name = (e[1] or m["dff"]).lower()
        if i in twins or name.startswith("lod"):
            far.append(e)
        else:
            hi.append(e)
            if e[10] < 0 and m["dist"] >= rp.BIG_DRAW_DISTANCE:
                far.append(e)
    return hi, far


def world_rows(models: dict[int, dict]) -> tuple[list[tuple], list[tuple]]:
    """Every text IPL with its binary streams from gta3.img (<name>_stream<n>.ipl). A stream entry's LOD index points into
    its text IPL, never into the stream, so the text file's twins are the indices referenced by itself and its streams."""
    texts = {Path(p).stem.lower(): rp.text_ipl(p) for p in sorted(glob.glob(str(GTA / "data" / "maps" / "**" / "*.ipl"), recursive=True))}
    streams: dict[str, list[tuple]] = {}
    img = GTA / "models" / "gta3.img"
    for name, entry in sorted(read_img_index(img).items()):
        if name.endswith(".ipl"):
            data = read_img_entry(img, entry)
            if data[:4] == b"bnry":
                streams.setdefault(name.rsplit("_stream", 1)[0], []).extend(rp.binary_ipl(data))
    hi, far = [], []
    for base in sorted(set(texts) | set(streams)):
        text, stream = texts.get(base, []), streams.get(base, [])
        h, f = classify(text, models, {e[10] for e in text + stream if e[10] >= 0})
        hi += h
        far += f
        h, f = classify(stream, models, set())
        hi += h
        far += f
    return hi, far


def quat_from_ipl(qx: float, qy: float, qz: float, qw: float) -> tuple[float, float, float, float]:
    """render_places stamps Quaternion((-qw, qx, qy, qz)) (Blender w, x, y, z); as x, y, z, w that is (qx, qy, qz, -qw)."""
    return qx, qy, qz, -qw


def quat_mul(a: tuple, b: tuple) -> tuple:
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx, aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def quat_from_euler_yxz(rx: float, ry: float, rz: float) -> tuple[float, float, float, float]:
    """The port rows' degrees, Blender 'YXZ' (as render_places): matrix Rz * Rx * Ry, the same ZXY order MTA uses."""
    def axis(a: float, i: int) -> tuple:
        h = math.radians(a) / 2
        v = [0.0, 0.0, 0.0]
        v[i] = math.sin(h)
        return (*v, math.cos(h))

    return quat_mul(quat_mul(axis(rz, 2), axis(rx, 0)), axis(ry, 1))


def apply_removals(rows: list[tuple], removals: list[tuple]) -> list[tuple]:
    by_model: dict[int, list[tuple]] = {}
    for r in removals:
        by_model.setdefault(r[0], []).append(r)
    out = []
    for e in rows:
        if any(math.dist((e[3], e[4], e[5]), (r[1], r[2], r[3])) <= r[4] + 0.5 for r in by_model.get(e[0], ())):
            continue
        out.append(e)
    return out


def to_placements(rows: list[tuple]) -> list[tuple]:
    """(model, x, y, z, qx, qy, qz, qw) from IPL entries."""
    return [(e[0], e[3], e[4], e[5], *quat_from_ipl(e[6], e[7], e[8], e[9])) for e in rows]


# ---------------------------------------------------------------------------------------------------- models


def frame_matrices(frames: list) -> list[np.ndarray]:
    mats: list[np.ndarray | None] = [None] * len(frames)

    def get(i: int) -> np.ndarray:
        if mats[i] is not None:
            return mats[i]
        f = frames[i]
        r = f.rotation_matrix
        m = np.eye(4)
        m[:3, :3] = [[r.right.x, r.up.x, r.at.x], [r.right.y, r.up.y, r.at.y], [r.right.z, r.up.z, r.at.z]]
        m[:3, 3] = [f.position.x, f.position.y, f.position.z]
        if 0 <= f.parent != i:
            m = get(f.parent) @ m
        mats[i] = m
        return m

    return [get(i) for i in range(len(frames))]


def convert_model(job: tuple[int, str, list[str], Path]) -> tuple[int, str | None]:
    """DFF -> one merged mesh: shared vertices, indices sorted by material, one group per material."""
    mid, dffname, chain, path = job
    try:
        data = fetch_dff(dffname)
        if not data:
            return mid, "dff not found"
        d = GDFF.dff()
        d.load_memory(data)
        clump = d.clumps[0]
        mats = frame_matrices(clump.frame_list)
        pos, uv, col, tris, mat_keys, mat_list = [], [], [], [], {}, []
        for atomic in clump.atomic_list:
            if not atomic.flags & 4:
                continue
            frame = clump.frame_list[atomic.frame]
            if (frame.name or "").lower().endswith(SKIP_FRAMES):
                continue
            g = clump.geometry_list[atomic.geometry]
            if not g.vertices or not g.triangles:
                continue
            v = np.array(g.vertices, dtype=np.float64).reshape(-1, 3)
            m = mats[atomic.frame]
            v = v @ m[:3, :3].T + m[:3, 3]
            n = len(v)
            uvs = np.array(g.uv_layers[0], dtype=np.float32).reshape(-1, 2) if g.uv_layers else np.zeros((n, 2), np.float32)
            pre = np.array(g.prelit_colors, dtype=np.float32).reshape(-1, 4) if g.prelit_colors else np.full((n, 4), 255, np.float32)
            remap = {}
            for i, mat in enumerate(g.materials):
                tex = mat.textures[0].name.lower() if mat.textures and mat.is_textured else None
                c = (int(mat.color.r), int(mat.color.g), int(mat.color.b), int(mat.color.a))
                key = (tex, c)
                if key not in mat_keys:
                    mat_keys[key] = len(mat_list)
                    mat_list.append({"t": tex, "c": list(c)})
                remap[i] = mat_keys[key]
            base = sum(len(p) for p in pos)
            tri = np.array([[t.a, t.b, t.c, remap.get(t.material, 0)] for t in g.triangles], dtype=np.int64)
            tris.append(np.column_stack([tri[:, :3] + base, tri[:, 3]]))
            pos.append(v.astype(np.float32))
            uv.append(uvs)
            col.append(np.clip(pre, 0, 255).astype(np.uint8))
        if not pos:
            return mid, "empty"
        pos, uv, col, tri = np.concatenate(pos), np.concatenate(uv), np.concatenate(col), np.concatenate(tris)
        order = np.argsort(tri[:, 3], kind="stable")
        tri = tri[order]
        groups, start = [], 0
        for mi in np.unique(tri[:, 3]):
            count = int((tri[:, 3] == mi).sum()) * 3
            groups.append([start, count, int(mi)])
            start += count
        idx = tri[:, :3].reshape(-1)
        wide = len(pos) > 65535
        idx = idx.astype(np.uint32 if wide else np.uint16)
        header = json.dumps({"n": len(pos), "ni": len(idx), "wide": wide, "mats": mat_list, "groups": groups, "chain": chain}, separators=(",", ":")).encode()
        header += b" " * (-len(header) % 4)
        tmp = path.with_suffix(".tmp")
        with open(tmp, "wb") as f:
            f.write(b"SVM1" + struct.pack("<I", len(header)) + header)
            f.write(pos.astype("<f4").tobytes() + uv.astype("<f4").tobytes() + col.tobytes() + idx.astype("<u4" if wide else "<u2").tobytes())
        tmp.replace(path)
        return mid, None
    except Exception as e:  # noqa: BLE001 - one broken model must not stop the bake
        return mid, f"{type(e).__name__}: {e}"


def read_header(path: Path) -> dict:
    with open(path, "rb") as f:
        f.read(4)
        (n,) = struct.unpack("<I", f.read(4))
        return json.loads(f.read(n))


# ---------------------------------------------------------------------------------------------------- textures


def convert_txd(job: tuple[str, list[str], Path]) -> tuple[str, dict[str, int], str | None]:
    """Decode the wanted textures of one txd (lower-case names) at the smallest mip that fits TEX_MAX, into tex/<txd>/."""
    txd, wanted, out = job
    found: dict[str, int] = {}
    try:
        data = fetch_txd(txd)
        if not data:
            return txd, found, "txd not found"
        t = GTXD.txd()
        t.load_memory(data)
        folder = out / "tex" / txd
        for nt in t.native_textures:
            name = nt.name.lower()
            if name not in wanted:
                continue
            target = folder / (name + ".webp")
            if target.is_file():
                with Image.open(target) as im:
                    found[name] = int(im.mode == "RGBA")
                continue
            level = 0
            while nt.get_width(level) > TEX_MAX and level < nt.num_levels - 1:
                level += 1
            w, h = nt.get_width(level), nt.get_height(level)
            rgba = np.frombuffer(nt.to_rgba(level), dtype=np.uint8).reshape(h, w, 4)
            alpha = bool(rgba[:, :, 3].min() < 250)
            im = Image.fromarray(rgba if alpha else rgba[:, :, :3])
            if max(w, h) > TEX_MAX:
                im.thumbnail((TEX_MAX, TEX_MAX))
            folder.mkdir(parents=True, exist_ok=True)
            im.save(target, "WEBP", quality=80, method=4)
            found[name] = int(alpha)
        return txd, found, None
    except Exception as e:  # noqa: BLE001
        return txd, found, f"{type(e).__name__}: {e}"


# ---------------------------------------------------------------------------------------------------- sky


def noon_sky() -> dict:
    """Clear-weather noon from timecyc.dat (weather 0, the fifth of its eight time slots): sky, fog and water colours, 0..255 columns."""
    fallback = {"skyTop": [0.27, 0.46, 0.82], "skyBottom": [0.14, 0.46, 0.78], "farClip": 800, "fogStart": 10, "water": [0.35, 0.67, 0.67, 0.94]}
    try:
        rows = []
        for line in (GTA / "data" / "timecyc.dat").read_text(encoding="latin1").splitlines():
            line = line.split("//")[0].strip()
            if line and not line.startswith("#"):
                rows.append(line.split())
        noon = [float(v) for v in rows[4]]
        # PC layout: Amb, Amb_Obj, Dir, Sky top, Sky bot, SunCore, SunCorona (3 each), then SunSz .. PoleShd, FarClp, FogSt,
        # LightOnGround, LowClouds (3), BottomClouds (3), Water RGBA (4)
        top, bottom, far, fog, water = noon[9:12], noon[12:15], noon[27], noon[28], noon[36:40]
        if not all(0 <= v <= 255 for v in top + bottom + water) or not 200 <= far <= 5000:
            return fallback
        rgb = lambda c: [round(v / 255, 3) for v in c]  # noqa: E731
        return {"skyTop": rgb(top), "skyBottom": rgb(bottom), "farClip": far, "fogStart": fog, "water": rgb(water)}
    except Exception:  # noqa: BLE001
        return fallback


# ---------------------------------------------------------------------------------------------------- cells


def cell_of(x: float, y: float) -> tuple[int, int]:
    return min(max(int((x + WORLD) // CELL), 0), CELLS - 1), min(max(int((y + WORLD) // CELL), 0), CELLS - 1)


def write_cells(folder: Path, placements: list[tuple], ids: set[int]) -> int:
    cells: dict[tuple[int, int], dict[int, list[float]]] = {}
    for m, x, y, z, qx, qy, qz, qw in placements:
        if m not in ids:
            continue
        rows = cells.setdefault(cell_of(x, y), {}).setdefault(m, [])
        rows += [round(x, 2), round(y, 2), round(z, 2), round(qx, 4), round(qy, 4), round(qz, 4), round(qw, 4)]
    folder.mkdir(parents=True, exist_ok=True)
    for old in folder.glob("*.json"):
        old.unlink()
    for (cx, cy), by_model in cells.items():
        (folder / f"{cx}_{cy}.json").write_text(json.dumps({str(k): v for k, v in by_model.items()}, separators=(",", ":")))
    return len(cells)


# ---------------------------------------------------------------------------------------------------- main


def main() -> None:
    global GTA
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--gta", help="GTA San Andreas folder (default: detected)")
    ap.add_argument("--out", default=str(OUT_DEFAULT))
    ap.add_argument("--at", help="x,y: bake only around this point")
    ap.add_argument("--radius", type=float, default=400.0)
    ap.add_argument("--jobs", type=int, default=3)
    ap.add_argument("--cells-only", action="store_true", help="rewrite only cells, lod, water and index")
    args = ap.parse_args()

    gta = Path(args.gta) if args.gta else detect_gta()
    if not gta or not (gta / "models" / "gta3.img").is_file():
        sys.exit("streetview_bake: no GTA San Andreas install found; pass --gta DIR")
    GTA = gta
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    (out / "models").mkdir(exist_ok=True)
    load_gtalib()
    open_archives()
    t0 = time.time()

    models, parents = rp.ide_tables(gta)
    hi_rows, far_rows = world_rows(models)
    objects, removals = rp.port_rows((0.0, 0.0, 0.0), HUGE)
    custom = custom_models(models, parents)
    port_vanilla = [o for o in objects if o[0] in models or o[0] in custom]
    print(f"world: {len(hi_rows)} full detail, {len(far_rows)} far; port: {len(objects)} objects ({len(objects) - len(port_vanilla)} unknown ids skipped), {len(removals)} removals")
    hi = apply_removals(hi_rows, removals)
    far = apply_removals(far_rows, removals)
    place_hi = to_placements(hi) + [(o[0], o[1], o[2], o[3], *quat_from_euler_yxz(o[4], o[5], o[6])) for o in port_vanilla]
    place_far = to_placements(far)
    if args.at:
        ax, ay = (float(v) for v in args.at.split(","))
        keep = lambda p: math.hypot(p[1] - ax, p[2] - ay) <= args.radius  # noqa: E731
        place_hi, place_far = [p for p in place_hi if keep(p)], [p for p in place_far if keep(p)]
    ids = {p[0] for p in place_hi} | {p[0] for p in place_far}
    print(f"{len(ids)} models in use ({len(place_hi)} + {len(place_far)} placements)")

    if not args.cells_only:
        def job(m: int) -> tuple:
            if m in custom:
                return m, custom[m]["dff"], custom[m]["chain"], out / "models" / f"{m}.bin"
            return m, models[m]["dff"], txd_chain(models, parents, m), out / "models" / f"{m}.bin"

        todo = [job(m) for m in sorted(ids) if not (out / "models" / f"{m}.bin").is_file()]
        failed = {}
        print(f"models to convert: {len(todo)}")
        with Pool(args.jobs, initializer=init_worker, initargs=(str(gta),)) as pool:
            for i, (m, err) in enumerate(pool.imap_unordered(convert_model, todo, chunksize=8), 1):
                if err:
                    failed[m] = err
                if i % 500 == 0:
                    print(f"  models {i}/{len(todo)} ({time.time() - t0:.0f}s)")
        for m, err in sorted(failed.items())[:20]:
            print(f"  model {m} ({custom[m]['dff'] if m in custom else models[m]['dff']}): {err}")
        ids = {m for m in ids if (out / "models" / f"{m}.bin").is_file()}
        print(f"{len(failed)} models failed, {len(ids)} usable")

        wanted: dict[str, set[str]] = {}
        for m in ids:
            h = read_header(out / "models" / f"{m}.bin")
            names = {mat["t"] for mat in h["mats"] if mat["t"]}
            for txd in h["chain"]:
                wanted.setdefault(txd, set()).update(names)
        jobs = [(txd, sorted(names), out) for txd, names in sorted(wanted.items())]
        print(f"txds to read: {len(jobs)}")
        manifest, problems = {}, []
        with Pool(args.jobs, initializer=init_worker, initargs=(str(gta),)) as pool:
            for i, (txd, found, err) in enumerate(pool.imap_unordered(convert_txd, jobs, chunksize=4), 1):
                manifest[txd] = found
                if err:
                    problems.append(f"{txd}: {err}")
                if i % 200 == 0:
                    print(f"  txds {i}/{len(jobs)} ({time.time() - t0:.0f}s)")
        for p in problems[:20]:
            print("  txd", p)
        (out / "textures.json").write_text(json.dumps({k: v for k, v in sorted(manifest.items()) if v}, separators=(",", ":")))
    else:
        ids = {m for m in ids if (out / "models" / f"{m}.bin").is_file()}

    n_hi = write_cells(out / "cells", place_hi, ids)
    n_far = write_cells(out / "lod", place_far, ids)
    water = rp.water_quads(gta, (0.0, 0.0), HUGE)
    (out / "water.json").write_text(json.dumps([[[round(c, 1) for c in p] for p in q] for q in water], separators=(",", ":")))
    index = {"world": WORLD, "cell": CELL, "cells": CELLS, "sky": noon_sky(), "models": len(ids), "cellFiles": n_hi, "lodFiles": n_far, "water": len(water), "partial": bool(args.at), "baked": int(time.time())}
    (out / "index.json").write_text(json.dumps(index, separators=(",", ":")))
    print(f"done in {time.time() - t0:.0f}s: {n_hi} cells, {n_far} lod cells, {len(water)} water quads -> {out}")


if __name__ == "__main__":
    main()
