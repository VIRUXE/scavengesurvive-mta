"""Finds the loot points that sit on a rooftop, from the game's own collision, and writes sql/seed/0008_loot_rooftops.sql.

    python -m tools.loot_rooftops [--gta DIR] [--out FILE] [--report TSV] [--only ID,ID,...]

The world is the one tools/render_places.py builds (text and binary IPLs, no interiors, LOD twins or night-only
objects, the port's map objects and removals), but stamped from the collision models in gta3.img (COLL/COL2/COL3:
mesh faces and boxes; spheres are left out) instead of the render meshes. A point is tested with vertical rays only:
the "floor" at (x, y) is the highest surface no more than STEP_UP above the point (what a player standing there would
land on if they walked over). From the point, rays walk outward in DIRECTIONS directions in STEP metre steps out to
REACH metres, and each walk ends one of three ways: an edge (the floor falls by SUDDEN metres or more between two steps,
to more than DROP metres below the point), a wall (a floor higher than STEP_UP) or open (neither within REACH). A walk
skips the steps where nothing lies below (missing collision, the map's edge) or the floor lies under water
(data/water.dat), so piers and jetties are no roofs. A rooftop has a floor, nothing overhead (no surface within CEILING
metres above it), at least MIN_EDGES edges and at most OPEN_SHARE open walks per edge: a street ends mostly open, a roof
beside a taller part of its building ends in walls. The loot points are read from the live
DB (loot_spawns, ids as the seed 0002 lays them out) through the lib credentials in mods/deathmatch/settings.xml.
"""
from __future__ import annotations

import argparse
import math
import re
import struct
import subprocess
import sys
from pathlib import Path

import numpy as np

np.seterr(divide="ignore", invalid="ignore")

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from tools.extract_samp_models import read_img_entry, read_img_index  # noqa: E402
from tools.render_places import MAPS, PUZZLES, REMOVAL, ROW, binary_ipl, ide_tables, keep_world, text_ipl, water_quads  # noqa: E402

GTA = Path("/gta/sa/gamefiles/GTA San Andreas")
SETTINGS = ROOT.parent / "mods" / "deathmatch" / "settings.xml"
OUT = ROOT / "sql" / "seed" / "0008_loot_rooftops.sql"
CELL = 32.0
DIRECTIONS = 16
STEP = 1.0
REACH = 40.0
STEP_UP = 1.5
DROP = 3.0
SUDDEN = 2.0
MIN_EDGES = 4
OPEN_SHARE = 0.5
CEILING = 12.0
BOX_FACES = [(0, 1, 3), (0, 3, 2), (4, 6, 7), (4, 7, 5), (0, 4, 5), (0, 5, 1), (2, 3, 7), (2, 7, 6), (0, 2, 6), (0, 6, 4), (1, 5, 7), (1, 7, 3)]


def col_models(data: bytes) -> dict[str, np.ndarray]:
    """Every model of a .col archive: lowercase name -> (n, 3, 3) float32 local triangles (faces and boxes)."""
    out, pos = {}, 0
    while pos + 32 <= len(data):
        magic, size = struct.unpack_from("<4sI", data, pos)
        if magic not in (b"COLL", b"COL2", b"COL3", b"COL4"):
            break
        name = data[pos + 8 : pos + 30].split(b"\0")[0].decode("latin1").lower()
        tris: list = []
        boxes: list = []
        if magic == b"COLL":
            p = pos + 32 + 40
            (n,) = struct.unpack_from("<I", data, p)
            p += 4 + n * 20 + 4  # spheres, then the unknown count
            (n,) = struct.unpack_from("<I", data, p)
            p += 4
            for i in range(n):
                boxes.append(struct.unpack_from("<6f", data, p + i * 28))
            p += n * 28
            (nv,) = struct.unpack_from("<I", data, p)
            verts = np.frombuffer(data, "<f4", nv * 3, p + 4).reshape(-1, 3)
            p += 4 + nv * 12
            (nf,) = struct.unpack_from("<I", data, p)
            faces = np.frombuffer(data, "<u4", nf * 4, p + 4).reshape(-1, 4)[:, :3]
            if nf and nv:
                tris.append(verts[faces])
        else:
            hdr = pos + 32 + 40
            nsph, nbox, nface, _nline, flags, _osph, obox, _olin, overt, oface, _otri = struct.unpack_from("<HHHBxIIIIIII", data, hdr)
            for i in range(nbox):
                boxes.append(struct.unpack_from("<6f", data, pos + obox + 4 + i * 28))
            if nface:
                faces = np.frombuffer(data, "<u2", nface * 4, pos + oface + 4).reshape(-1, 4)[:, :3].astype(np.int64)
                nv = int(faces.max()) + 1
                verts = np.frombuffer(data, "<i2", nv * 3, pos + overt + 4).reshape(-1, 3).astype(np.float32) / 128.0
                tris.append(verts[faces])
        for x0, y0, z0, x1, y1, z1 in boxes:
            c = np.array([[x, y, z] for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)], np.float32)
            tris.append(c[np.array(BOX_FACES)])
        if tris:
            out.setdefault(name, np.concatenate(tris).astype(np.float32))
        pos += 8 + size
    return out


def all_collision(gta: Path) -> dict[str, np.ndarray]:
    img = gta / "models" / "gta3.img"
    cols: dict[str, np.ndarray] = {}
    for name, entry in sorted(read_img_index(img).items()):
        if name.endswith(".col"):
            for k, v in col_models(read_img_entry(img, entry)).items():
                cols.setdefault(k, v)
    return cols


def quat_matrix(qx: float, qy: float, qz: float, qw: float) -> np.ndarray:
    """IPL rotation, applied the way render_places does it: Quaternion((-qw, qx, qy, qz))."""
    w, x, y, z = -qw, qx, qy, qz
    n = math.sqrt(w * w + x * x + y * y + z * z) or 1.0
    w, x, y, z = w / n, x / n, y / n, z / n
    return np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )


def euler_matrix(rx: float, ry: float, rz: float) -> np.ndarray:
    """MTA object rotation as render_places applies it: Blender Euler order YXZ (Rz @ Rx @ Ry)."""
    a, b, c = (math.radians(v) for v in (rx, ry, rz))
    Rx = np.array([[1, 0, 0], [0, math.cos(a), -math.sin(a)], [0, math.sin(a), math.cos(a)]])
    Ry = np.array([[math.cos(b), 0, math.sin(b)], [0, 1, 0], [-math.sin(b), 0, math.cos(b)]])
    Rz = np.array([[math.cos(c), -math.sin(c), 0], [math.sin(c), math.cos(c), 0], [0, 0, 1]])
    return Rz @ Rx @ Ry


def world_placements(gta: Path, models: dict[int, dict]) -> list[tuple]:
    """render_places.world_placements, except the binary stream IPLs: their LOD field indexes the text IPL of the same
    area, not the stream itself, so keep_world would drop real terrain there. They hold no LODs; only interiors and
    night-only or lod-named models are left out."""
    import glob

    out = []
    for path in sorted(glob.glob(str(gta / "data" / "maps" / "**" / "*.ipl"), recursive=True)):
        out += keep_world(text_ipl(path), models)
    img = gta / "models" / "gta3.img"
    for name, entry in sorted(read_img_index(img).items()):
        if name.endswith(".ipl"):
            data = read_img_entry(img, entry)
            if data[:4] == b"bnry":
                for e in binary_ipl(data):
                    m = models.get(e[0])
                    if e[2] == 0 and m and not m["night"] and not m["dff"].startswith("lod"):
                        out.append(e)
    return out


def port_objects() -> tuple[list[tuple], list[tuple]]:
    objects, removals = [], []
    for path in sorted(MAPS.glob("*.lua")) + [PUZZLES]:
        text = path.read_text(encoding="utf8")
        for m, x, y, z, rx, ry, rz, world, interior in ROW.findall(text):
            if int(world) in (-1, 0) and int(interior) in (-1, 0):
                objects.append((int(m), *(float(v) for v in (x, y, z, rx, ry, rz))))
        if "removals = {" in text:
            for m, x, y, z, r in REMOVAL.findall(text[text.index("removals = {") :]):
                removals.append((int(m), float(x), float(y), float(z), float(r)))
    return objects, removals


def build_world(gta: Path) -> tuple[np.ndarray, dict[tuple[int, int], np.ndarray], dict]:
    models, _ = ide_tables(gta)
    cols = all_collision(gta)
    objects, removals = port_objects()
    by_model: dict[int, list] = {}
    for r in removals:
        by_model.setdefault(r[0], []).append(r)
    placed, stats = [], {"world": 0, "removed": 0, "port": 0, "nocol": 0}
    for e in world_placements(gta, models):
        if any(math.dist((e[3], e[4], e[5]), r[1:4]) <= r[4] + 0.5 for r in by_model.get(e[0], ())):
            stats["removed"] += 1
            continue
        m = models.get(e[0])
        col = cols.get(m["dff"]) if m else None
        if col is None:
            stats["nocol"] += 1
            continue
        placed.append(col @ quat_matrix(*e[6:10]).T + np.array(e[3:6]))
        stats["world"] += 1
    for mid, x, y, z, rx, ry, rz in objects:
        m = models.get(mid)
        col = cols.get(m["dff"]) if m else None
        if col is None:
            stats["nocol"] += 1
            continue
        placed.append(col @ euler_matrix(rx, ry, rz).T + np.array((x, y, z)))
        stats["port"] += 1
    tris = np.concatenate(placed).astype(np.float64)
    # drop vertical and degenerate faces: a vertical ray never lands on them
    e1, e2 = tris[:, 1, :2] - tris[:, 0, :2], tris[:, 2, :2] - tris[:, 0, :2]
    tris = tris[np.abs(e1[:, 0] * e2[:, 1] - e1[:, 1] * e2[:, 0]) > 1e-6]
    lo, hi = tris[:, :, :2].min(axis=1), tris[:, :, :2].max(axis=1)
    grid: dict[tuple[int, int], list[int]] = {}
    for i, (a, b) in enumerate(zip(np.floor(lo / CELL).astype(int), np.floor(hi / CELL).astype(int))):
        for cx in range(a[0], b[0] + 1):
            for cy in range(a[1], b[1] + 1):
                grid.setdefault((cx, cy), []).append(i)
    stats["triangles"] = len(tris)
    water = []
    for q in water_quads(gta, (0.0, 0.0, 0.0), 1e6):
        water += [[q[0], q[1], q[2]]] + ([[q[0], q[2], q[3]]] if len(q) == 4 else [])
    stats["water"] = len(water)
    return tris, {k: np.array(v) for k, v in grid.items()}, stats, np.array(water, float)


def surfaces(tris: np.ndarray, px: np.ndarray, py: np.ndarray) -> np.ndarray:
    """Heights where vertical lines at (px, py) cross the triangles: (samples, triangles), NaN where they miss."""
    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    v0x, v0y, v1x, v1y = b[:, 0] - a[:, 0], b[:, 1] - a[:, 1], c[:, 0] - a[:, 0], c[:, 1] - a[:, 1]
    den = v0x * v1y - v1x * v0y
    wx, wy = px[:, None] - a[:, 0], py[:, None] - a[:, 1]
    u = (wx * v1y - v1x * wy) / den
    v = (v0x * wy - wx * v0y) / den
    inside = (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6)
    z = a[:, 2] + u * (b[:, 2] - a[:, 2]) + v * (c[:, 2] - a[:, 2])
    return np.where(inside, z, np.nan)


def classify(tris: np.ndarray, grid: dict, water: np.ndarray, x: float, y: float, z: float) -> dict:
    r = REACH + CELL
    cells = [grid.get((cx, cy)) for cx in range(int(math.floor((x - r) / CELL)), int(math.floor((x + r) / CELL)) + 1) for cy in range(int(math.floor((y - r) / CELL)), int(math.floor((y + r) / CELL)) + 1)]
    idx = np.unique(np.concatenate([c for c in cells if c is not None])) if any(c is not None for c in cells) else np.array([], int)
    near = tris[idx]
    if len(near):
        lo, hi = near[:, :, :2].min(axis=1), near[:, :, :2].max(axis=1)
        near = near[(hi[:, 0] >= x - REACH - 1) & (lo[:, 0] <= x + REACH + 1) & (hi[:, 1] >= y - REACH - 1) & (lo[:, 1] <= y + REACH + 1)]
    if not len(near):
        return {"roof": False, "edges": 0, "walls": 0, "open": DIRECTIONS, "ceiling": False, "floor": None}
    here = surfaces(near, np.array([x]), np.array([y]))[0]
    above = here[(here > z + 2.0) & (here < z + CEILING)]
    below = here[here <= z + STEP_UP]
    floor = float(np.nanmax(below)) if below.size else None
    steps = np.arange(STEP, REACH + 1e-9, STEP)
    ang = np.arange(DIRECTIONS) * (2 * math.pi / DIRECTIONS)
    sx = (x + np.cos(ang)[:, None] * steps[None, :]).ravel()
    sy = (y + np.sin(ang)[:, None] * steps[None, :]).ravel()
    zs = surfaces(near, sx, sy).reshape(DIRECTIONS, len(steps), -1)
    wall = np.any(zs > z + STEP_UP, axis=2) & np.any((zs > z + STEP_UP) & (zs < z + STEP_UP + 6.0), axis=2)
    landing = np.where(zs <= z + STEP_UP, zs, -np.inf).max(axis=2)  # -inf: nothing below at all
    wet = water[(water[:, :, 0].max(axis=1) >= x - REACH) & (water[:, :, 0].min(axis=1) <= x + REACH) & (water[:, :, 1].max(axis=1) >= y - REACH) & (water[:, :, 1].min(axis=1) <= y + REACH)]
    level = np.nanmax(surfaces(wet, sx, sy), axis=1, initial=-np.inf).reshape(DIRECTIONS, len(steps)) if len(wet) else np.full(landing.shape, -np.inf)
    # nothing below (missing collision, the map's edge) or a fall into water is no roof edge: piers and jetties stay out
    landing = np.where(np.isinf(landing) | (level > landing), np.nan, landing)
    edges = walls = 0
    for d in range(DIRECTIONS):
        prev = floor if floor is not None else z
        for s in range(len(steps)):
            if wall[d, s]:
                walls += 1
                break
            if np.isnan(landing[d, s]):
                continue
            # a roof edge is a sudden fall (a slope going down the same height is not one)
            if landing[d, s] < z - DROP and prev - landing[d, s] >= SUDDEN:
                edges += 1
                break
            prev = landing[d, s]
    opened = DIRECTIONS - edges - walls
    roof = floor is not None and not above.size and edges >= MIN_EDGES and opened <= OPEN_SHARE * edges
    return {"roof": roof, "edges": edges, "walls": walls, "open": opened, "ceiling": bool(above.size), "floor": floor}


def db_points(ids: list[int] | None) -> list[tuple[int, float, float, float, str, str]]:
    text = SETTINGS.read_text(encoding="utf8")
    user = re.search(r'lib\.db_user" value="([^"]*)"', text).group(1)
    pw = re.search(r'lib\.db_pass" value="([^"]*)"', text).group(1)
    where = f" WHERE id IN ({','.join(str(i) for i in ids)})" if ids else ""
    sql = f"SELECT id, x, y, z, zone, table_name FROM loot_spawns{where} ORDER BY id"
    res = subprocess.run(["mariadb", "-h127.0.0.1", f"-u{user}", f"-p{pw}", "scavengesurvive", "-N", "-B", "-e", sql], capture_output=True, text=True, check=True)
    rows = []
    for line in res.stdout.splitlines():
        i, x, y, z, zone, tbl = line.split("\t")
        rows.append((int(i), float(x), float(y), float(z), zone, tbl))
    return rows


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--gta", type=Path, default=GTA)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--report", type=Path, help="TSV of every point: id, x, y, z, zone, table, edges, walls, open, ceiling, roof")
    ap.add_argument("--only", help="comma-separated loot_spawns ids to test (prints them, writes nothing)")
    args = ap.parse_args(argv)
    ids = [int(v) for v in args.only.split(",")] if args.only else None
    tris, grid, stats, water = build_world(args.gta)
    print(f"world: {stats}", file=sys.stderr)
    roofs, lines = [], []
    points = db_points(ids)
    for n, (i, x, y, z, zone, tbl) in enumerate(points):
        c = classify(tris, grid, water, x, y, z)
        if c["roof"]:
            roofs.append(i)
        lines.append(f"{i}\t{x:.2f}\t{y:.2f}\t{z:.2f}\t{zone}\t{tbl}\t{c['edges']}\t{c['walls']}\t{c['open']}\t{int(c['ceiling'])}\t{int(c['roof'])}")
        if ids:
            print(lines[-1], f"floor={c['floor']}")
        elif n % 500 == 0:
            print(f"{n}/{len(points)} points, {len(roofs)} rooftops", file=sys.stderr)
    if args.report:
        args.report.write_text("id\tx\ty\tz\tzone\ttable\tedges\twalls\topen\tceiling\troof\n" + "\n".join(lines) + "\n")
    if ids:
        return 0
    body = ",\n".join(", ".join(str(i) for i in roofs[k : k + 20]) for k in range(0, len(roofs), 20))
    args.out.write_text(
        "-- Loot points on a rooftop (loot_spawns ids as 0002 lays them out), found by python -m tools.loot_rooftops from\n"
        "-- the game's collision. The loot resource keeps the item types in roll.ROOF_BANNED (loot/shared/logic/roll.lua: wheels) off these points.\n"
        "UPDATE loot_spawns SET rooftop = 0;\n"
        f"UPDATE loot_spawns SET rooftop = 1 WHERE id IN (\n{body}\n);\n"
    )
    print(f"{len(roofs)} of {len(points)} points on a rooftop -> {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
