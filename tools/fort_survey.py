"""Measures an upstream fort's props against the Rockstar buildings around them and writes a survey to review.

    python -m tools.fort_survey "LS/Fort Defiance.map" [--gta DIR] [--out FILE] [--captures DIR]

Reads the .map from ../ScavengeSurvive/scriptfiles/maps, the model names and bounds from the GTA:SA folder (default
D:\\Games\\GTA San Andreas\\ariane-sa), and the native placements from its text and binary IPLs. Per row it builds the
world AABB of the prop's collision (its DFF when the model has none), groups rows whose boxes are within 1 m into
clusters, and flags `protrudes` (the box overlaps a native building's box by more than 0.05 m3, an upper bound: a
native's box is its full extent) and `floats` (the prop's bottom is above the highest native top it stands over).
The `proposal` column is pre-filled from the role and is meant to be edited by hand. With --captures it also takes
the fixed Ariane views (needs the editor running, window restored): see samp-house-shells/ariane/ctl.ps1.
"""
from __future__ import annotations

import argparse
import math
import re
import struct
import subprocess
import sys
from collections import Counter
from pathlib import Path

from tools.convert.maps import parse_map
from tools.extract_samp_models import read_img_index, read_img_entry
from tools.model_bounds import Box, load

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT.parent / "ScavengeSurvive" / "scriptfiles" / "maps"
DEFAULT_GTA = Path(r"D:\Games\GTA San Andreas\ariane-sa")
CTL = Path(r"C:\dev\gta\sa\samp-house-shells\ariane\ctl.ps1")
NATIVE_RADIUS = 60.0
NOT_BUILDINGS = re.compile(r"^lod|road|land|hub_|hubst|grnd|alpha|grass|veg_|bush|palm|tree|lamppost|telgrph|pole|hydrant")
CLUSTER_GAP, MIN_OVERLAP = 1.0, 0.05
VIEWS = {
    "east": (2536, -1642, 46, 2503, -1668, 14),
    "west": (2452, -1668, 34, 2503, -1668, 14),
    "north": (2503, -1618, 34, 2503, -1668, 14),
    "south": (2503, -1718, 34, 2503, -1668, 14),
    "top": (2503, -1668, 100, 2503, -1668.1, 13),
}
ROLES = {
    "perimeter": {974, 4100, 11474, 16370, 2060, 2061, 1413, 1447, 3260},
    "gate": {8167, 3095, 2929, 11327},
    "shelter": {17010, 16405, 3406, 1452, 1457, 16502, 11496},
    "tower": {8879, 8877, 1464, 3361},
    "junk": {849, 850, 851, 852, 854, 1362, 3569, 13591, 1358, 1431, 1685, 3577, 3576, 1230, 1299, 1264, 1265},
    "landmark": {3928, 7090, 1595, 1676, 3790, 3793, 3795, 3066, 11435},
}
PROPOSALS = {
    "perimeter": "kit wall / corner / barricade",
    "gate": "kit gate",
    "shelter": "kit lean-to",
    "tower": "kit tower",
    "junk": "keep (ground level)",
    "landmark": "keep helipad, drop the rest",
    "furniture/loot": "drop",
}


def role_of(model: int) -> str:
    for role, models in ROLES.items():
        if model in models:
            return role
    return "furniture/loot"


def ide_names(gta: Path) -> dict[int, tuple[str, str]]:
    """Object id -> (dff, txd) from the game's and SA-MP's IDE files."""
    names = {}
    for ide in list((gta / "data").rglob("*.ide")) + list((gta / "SAMP").glob("*.ide")):
        section = None
        for line in ide.read_text(errors="ignore").splitlines():
            line = line.split("#")[0].strip()
            low = line.lower()
            if not line:
                continue
            if low in ("objs", "tobj", "anim", "weap", "cars", "peds", "hier", "txdp", "2dfx", "path"):
                section = low
            elif low == "end":
                section = None
            elif section in ("objs", "tobj", "anim"):
                parts = [p.strip() for p in line.split(",")]
                if parts[0].isdigit() and len(parts) > 2:
                    names[int(parts[0])] = (parts[1].lower(), parts[2].lower())
    return names


def matrix(rx: float, ry: float, rz: float) -> list[list[float]]:
    """Object rotation as a matrix: Rz * Rx * Ry, degrees (what make_ipl.quat_zxy encodes)."""
    ax, ay, az = (math.radians(a) for a in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    rzm = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    rxm = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rym = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    return mul(mul(rzm, rxm), rym)


def mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def quat_matrix(qx: float, qy: float, qz: float, qw: float) -> list[list[float]]:
    """Rotation matrix of an IPL quaternion; IPLs store the inverse, so the vector part is negated first."""
    qx, qy, qz = -qx, -qy, -qz
    return [
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
        [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
        [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)],
    ]


def world_box(box: Box, rot, pos) -> Box:
    """The world AABB of a model-space box turned by `rot` and moved to `pos`."""
    corners = [(x, y, z) for x in (box[0], box[3]) for y in (box[1], box[4]) for z in (box[2], box[5])]
    pts = [[sum(rot[i][k] * c[k] for k in range(3)) + pos[i] for i in range(3)] for c in corners]
    return (*(min(p[i] for p in pts) for i in range(3)), *(max(p[i] for p in pts) for i in range(3)))


def overlap(a: Box, b: Box) -> float:
    dims = [min(a[i + 3], b[i + 3]) - max(a[i], b[i]) for i in range(3)]
    return dims[0] * dims[1] * dims[2] if all(d > 0 for d in dims) else 0.0


def gap(a: Box, b: Box) -> float:
    return max(max(a[i] - b[i + 3], b[i] - a[i + 3], 0.0) for i in range(3))


def clusters(boxes: list[Box], max_gap: float = CLUSTER_GAP) -> list[list[int]]:
    """Single-linkage groups of box indices whose boxes are no more than `max_gap` apart."""
    parent = list(range(len(boxes)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            if gap(boxes[i], boxes[j]) <= max_gap:
                parent[find(i)] = find(j)
    groups: dict[int, list[int]] = {}
    for i in range(len(boxes)):
        groups.setdefault(find(i), []).append(i)
    return sorted(groups.values(), key=lambda g: (min(boxes[i][0] for i in g), min(boxes[i][1] for i in g)))


def native_instances(gta: Path) -> list[tuple[int, tuple[float, float, float], list[list[float]]]]:
    """(model, position, rotation matrix) of every vanilla placement: text IPLs plus the binary stream IPLs in gta3.img."""
    found = []
    for ipl in (gta / "data" / "maps").rglob("*.ipl"):
        section = None
        for line in ipl.read_text(errors="ignore").splitlines():
            line = line.split("#")[0].strip()
            low = line.lower()
            if low in ("inst", "cull", "grge", "enex", "pick", "jump", "tcyc", "auzo", "mult", "cars", "occl", "zone", "path"):
                section = low
            elif low == "end":
                section = None
            elif section == "inst" and line:
                p = [s.strip() for s in line.split(",")]
                if len(p) >= 10 and int(p[2]) == 0:
                    found.append((int(p[0]), (float(p[3]), float(p[4]), float(p[5])), quat_matrix(*(float(v) for v in p[6:10]))))
    img = gta / "models" / "gta3.img"
    for name, where in read_img_index(img).items():
        blob = read_img_entry(img, where)
        if not name.endswith(".ipl") or blob[:4] != b"bnry":
            continue
        count, at = struct.unpack_from("<I", blob, 4)[0], struct.unpack_from("<I", blob, 0x1C)[0]
        for k in range(count):
            x, y, z, qx, qy, qz, qw, model = struct.unpack_from("<7fi", blob, at + k * 40)
            found.append((model, (x, y, z), quat_matrix(qx, qy, qz, qw)))
    return found


def model_box(model: int, names, bounds) -> Box | None:
    """The collision box of a model (its DFF's when the COL has no geometry), in model space."""
    dff, _txd = names.get(model, (None, None))
    if dff is None:
        return None
    col = bounds["col"].get(dff)
    if col and col["has_geom"]:
        return tuple(col["box"])
    box = bounds["dff"].get(dff)
    return tuple(box) if box else None


def survey(rows, names, bounds, natives) -> list[dict]:
    """One dict per cluster of `rows`: its rows' boxes, models, roles and what they collide with."""
    placed = []
    for r in rows:
        box = model_box(r[0], names, bounds)
        if box is None:
            placed.append({"row": r, "box": (r[1], r[2], r[3], r[1], r[2], r[3]), "known": False})
            continue
        placed.append({"row": r, "box": world_box(box, matrix(r[4], r[5], r[6]), (r[1], r[2], r[3])), "known": True})
    cx = sum(p["row"][1] for p in placed) / len(placed)
    cy = sum(p["row"][2] for p in placed) / len(placed)
    near = []
    for model, pos, rot in natives:
        if math.hypot(pos[0] - cx, pos[1] - cy) > NATIVE_RADIUS + 60:
            continue
        box = model_box(model, names, bounds)
        if box and not NOT_BUILDINGS.search(names[model][0]):
            near.append((names[model][0], world_box(box, rot, pos)))
    for p in placed:
        hits = [(n, overlap(p["box"], b), b) for n, b in near if overlap(p["box"], b) > MIN_OVERLAP]
        p["protrudes"] = sorted({n for n, _v, _b in hits})
        under = [b[5] for _n, _v, b in hits if b[5] > p["box"][2]]
        below = [b[5] for n, b in near if b[3] > p["box"][0] and b[0] < p["box"][3] and b[4] > p["box"][1] and b[1] < p["box"][4] and b[5] <= p["box"][2]]
        top = max(below + under, default=None)
        p["floats"] = round(p["box"][2] - top, 1) if top is not None and p["box"][2] - top > 1.5 else 0.0
    out = []
    for group in clusters([p["box"] for p in placed]):
        members = [placed[i] for i in group]
        roles = Counter(role_of(m["row"][0]) for m in members)
        role = roles.most_common(1)[0][0]
        lo = [min(m["box"][i] for m in members) for i in range(3)]
        hi = [max(m["box"][i + 3] for m in members) for i in range(3)]
        out.append({
            "rows": len(members),
            "models": Counter(m["row"][0] for m in members),
            "bbox": (*lo, *hi),
            "role": role,
            "roles": roles,
            "protrudes": sorted({n for m in members for n in m["protrudes"]}),
            "floats": max(m["floats"] for m in members),
            "unknown": sum(1 for m in members if not m["known"]),
            "proposal": PROPOSALS[role],
        })
    return out


def render(name: str, rows, names, bounds, groups, shots: list[str]) -> str:
    lines = [f"# {name}: survey", "", f"Generated by `python -m tools.fort_survey \"{name}\"`; the `proposal` column is meant to be edited.", ""]
    lines += [f"{len(rows)} rows, {len(groups)} clusters (single linkage, gap {CLUSTER_GAP} m). `protrudes` = collision box overlaps a "
              "native building's box by more than 0.05 m3 (an upper bound; LODs, roads, ground, plants and poles are ignored); `floats` = metres above the highest native top below.", ""]
    lines += ["| cluster | rows | models | bbox (x0 y0 z0 .. x1 y1 z1) | role | protrudes | floats | proposal |", "| ---: | ---: | --- | --- | --- | --- | ---: | --- |"]
    for i, g in enumerate(groups, 1):
        models = " ".join(f"{m}x{n}" if n > 1 else str(m) for m, n in sorted(g["models"].items()))
        b = " ".join(f"{v:.0f}" for v in g["bbox"][:3]) + " .. " + " ".join(f"{v:.0f}" for v in g["bbox"][3:])
        hit = ", ".join(g["protrudes"]) or "-"
        lines.append(f"| {i} | {g['rows']} | {models} | {b} | {g['role']} | {hit} | {g['floats']} | {g['proposal']} |")
    lines += ["", "## Models", "", "| model | rows | dff | txd | collision box (m) |", "| ---: | ---: | --- | --- | --- |"]
    for model, n in sorted(Counter(r[0] for r in rows).items(), key=lambda kv: -kv[1]):
        dff, txd = names.get(model, ("?", "?"))
        box = model_box(model, names, bounds)
        size = " x ".join(f"{box[i + 3] - box[i]:.1f}" for i in range(3)) if box else "unknown"
        lines.append(f"| {model} | {n} | {dff} | {txd} | {size} |")
    if shots:
        lines += ["", "## Captures", ""] + [f"![{Path(s).stem}]({s})" for s in shots]
    return "\n".join(lines) + "\n"


def capture(out: Path) -> list[str]:
    out.mkdir(parents=True, exist_ok=True)
    shots = []
    for view, (px, py, pz, tx, ty, tz) in VIEWS.items():
        base = ["pwsh", "-ExecutionPolicy", "Bypass", "-File", str(CTL)]
        subprocess.run(base + ["camera", str(px), str(py), str(pz), str(tx), str(ty), str(tz), "60"], check=True, capture_output=True)
        subprocess.run(["pwsh", "-Command", "Start-Sleep 3"], check=True)
        path = out / f"{view}.png"
        subprocess.run(base + ["capture", str(path)], check=True, capture_output=True)
        shots.append(f"../images/fort-defiance/{out.name}/{path.name}")
    return shots


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("map", help='a .map under scriptfiles/maps, e.g. "LS/Fort Defiance.map"')
    ap.add_argument("--gta", type=Path, default=DEFAULT_GTA)
    ap.add_argument("--out", type=Path, help="markdown file (default: print)")
    ap.add_argument("--cache", type=Path, default=ROOT / ".cache" / "model_bounds.json")
    ap.add_argument("--captures", type=Path, help="docs/images/fort-defiance/<set> folder for the Ariane captures")
    args = ap.parse_args(argv)
    rows = parse_map((UPSTREAM / args.map).read_text(encoding="utf-8", errors="ignore"), args.map)["objects"]
    names, bounds = ide_names(args.gta), load(args.gta, args.cache)
    groups = survey(rows, names, bounds, native_instances(args.gta))
    shots = capture(args.captures) if args.captures else []
    text = render(re.sub(r"\.map$", "", args.map), rows, names, bounds, groups, shots)
    if args.out:
        args.out.write_text(text, encoding="utf-8", newline="\n")
        print(f"fort_survey: {len(rows)} rows -> {len(groups)} clusters, wrote {args.out}")
    else:
        print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
