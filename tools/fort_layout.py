"""Lays Fort Defiance out from the fort kit (tools/make_fort_kit.py) and writes maps/shared/forts.lua.

    python -m tools.fort_layout [--no-ground]

The fort is a ring of wall pieces on the sidewalk around the Grove Street cul-de-sac, a gate where the road enters from
the west, two watchtowers inside the ring, a lean-to where upstream's barn roof stood and two barricades that make the
gate a chicane. The ground-level pieces of upstream's Fort Defiance worth keeping (helipad, rubble, fire barrel) are copied from its .map. Heights come from the running Ariane editor (tools/ariane_ground.py), one ray
per footprint point; the lowest one is used so a piece's skirt covers the slope. With --no-ground z is 12.5.
Every number below was read off an Ariane top view of the cleared cul-de-sac (sand x 2468..2510, y -1684..-1654).
"""
from __future__ import annotations

import json
import math
import os
import subprocess
import sys
from pathlib import Path

from tools.convert.maps import parse_map
from tools.make_fort_kit import model_ids

ROOT = Path(__file__).resolve().parents[1]
FORTS = ROOT / "resources" / "[scavengesurvive]" / "maps" / "shared" / "forts.lua"
UPSTREAM_MAP = ROOT.parent / "ScavengeSurvive" / "scriptfiles" / "maps" / "LS" / "Fort Defiance.map"
VENV_PYTHON = Path(r"C:\dev\gta\sa\tools\ariane-agent\ariane-agent-windows-x64\.venv-agent\Scripts\python.exe")
GROUND_TOOL = ROOT / "tools" / "ariane_ground.py"

NAME = "Fort Defiance"
CENTER, SEMI = (2488.7, -1669.2), (24.6, 19.4)  # the sidewalk ring around the cul-de-sac
GATE_AT, GATE_GAP = (2467.0, -1659.5), 4.8  # where the road mouth meets the ring, and the opening incl. posts
WALL = 4.0  # length of fort_wall4
TOWERS = [(40.0, 3.2), (222.0, 3.2)]  # ring angle (degrees, from +x) and how far inside the ring they stand
LEANTO_AT, LEANTO_OPEN_TO = (2480.0, -1672.0), (1.0, 0.0)  # centre, and the direction its open side faces
BARRICADE_OFFSETS = [(-2.6, 3.4), (2.6, 3.4)]  # along the gate's tangent and inward from it
KEEP = {3928, 849, 850, 851, 852, 854, 1362}  # upstream models kept: helipad, rubble, fire barrel
DEFAULT_Z = 12.5

Row = list


def point(theta: float) -> tuple[float, float]:
    return (CENTER[0] + SEMI[0] * math.cos(theta), CENTER[1] + SEMI[1] * math.sin(theta))


def nearest_theta(target: tuple[float, float]) -> float:
    return min((t / 3600 * 2 * math.pi for t in range(3600)), key=lambda t: math.dist(point(t), target))


def arc_walk(a: float, b: float, n: int) -> list[float]:
    """n+1 angles from a to b (a < b) at equal arc length along the ellipse."""
    steps = 4000
    ts = [a + (b - a) * i / steps for i in range(steps + 1)]
    cum = [0.0]
    for i in range(steps):
        cum.append(cum[-1] + math.dist(point(ts[i]), point(ts[i + 1])))
    out = []
    for k in range(n + 1):
        want = cum[-1] * k / n
        i = min(range(steps), key=lambda j: abs(cum[j] - want))
        out.append(ts[i])
    return out


def heading(dx: float, dy: float) -> float:
    return math.degrees(math.atan2(dy, dx)) % 360


def ring(gate_gap: float = GATE_GAP, wall: float = WALL) -> tuple[list[tuple], tuple]:
    """([(mid x, mid y, heading, end a, end b), ...] wall segments, (gate x, gate y, heading)) around the ellipse."""
    tg = nearest_theta(GATE_AT)
    gate = point(tg)
    tangent = (-SEMI[0] * math.sin(tg), SEMI[1] * math.cos(tg))
    half = gate_gap / 2
    ta = next(tg - d / 2000 for d in range(1, 4000) if math.dist(point(tg - d / 2000), gate) >= half)
    tb = next(tg + d / 2000 for d in range(1, 4000) if math.dist(point(tg + d / 2000), gate) >= half)
    length = sum(math.dist(point(tb + (ta + 2 * math.pi - tb) * i / 2000), point(tb + (ta + 2 * math.pi - tb) * (i + 1) / 2000)) for i in range(2000))
    n = math.ceil(length / wall)
    angles = arc_walk(tb, ta + 2 * math.pi, n)
    segs = []
    for i in range(n):
        p, q = point(angles[i]), point(angles[i + 1])
        segs.append(((p[0] + q[0]) / 2, (p[1] + q[1]) / 2, heading(q[0] - p[0], q[1] - p[1]), p, q))
    return segs, (gate[0], gate[1], heading(*tangent))


def toward(frm: tuple[float, float], to: tuple[float, float]) -> float:
    """The heading that turns a piece's open (local -y) side from `frm` toward `to`."""
    return math.degrees(math.atan2(to[0] - frm[0], -(to[1] - frm[1]))) % 360


def plan() -> list[tuple]:
    """Every kit placement as (model, x, y, heading, footprint points): the points the ground is sampled at."""
    ids = model_ids()
    out = []
    segs, (gx, gy, gh) = ring()
    for i, (mx, my, mh, p, q) in enumerate(segs):
        nx, ny = math.sin(math.radians(mh)), -math.cos(math.radians(mh))  # the chord's right-hand side
        shift = 0.04 if i % 2 else -0.04  # neighbours overlap a little; offset every other one so the sheets don't fight
        mx, my = mx + nx * shift, my + ny * shift
        out.append((ids["fort_wall4"], mx, my, mh, [p, q, (mx, my)]))
    out.append((ids["fort_gate"], gx, gy, gh, [(gx, gy)] + [(gx + math.cos(math.radians(gh)) * d, gy + math.sin(math.radians(gh)) * d) for d in (-2.1, 2.1)]))
    for deg, inset in TOWERS:
        t = math.radians(deg)
        x, y = point(t)
        nx, ny = -SEMI[1] * math.cos(t), -SEMI[0] * math.sin(t)  # inward normal of the ellipse
        norm = math.hypot(nx, ny)
        x, y = x + nx / norm * (inset + 1.5), y + ny / norm * (inset + 1.5)
        out.append((ids["fort_tower"], x, y, toward((x, y), CENTER), [(x, y), (x - 1.4, y - 1.4), (x + 1.4, y + 1.4), (x - 1.4, y + 1.4), (x + 1.4, y - 1.4)]))
    lx, ly = LEANTO_AT
    lh = toward(LEANTO_AT, (lx + LEANTO_OPEN_TO[0], ly + LEANTO_OPEN_TO[1]))
    c, s = math.cos(math.radians(lh)), math.sin(math.radians(lh))
    corners = [(lx + c * a - s * b, ly + s * a + c * b) for a in (-3, 3) for b in (-2, 2)]
    out.append((ids["fort_leanto"], lx, ly, lh, [(lx, ly)] + corners))
    inward = (-math.sin(math.radians(gh)), math.cos(math.radians(gh)))
    inward = inward if math.dist((gx + inward[0], gy + inward[1]), CENTER) < math.dist((gx, gy), CENTER) else (-inward[0], -inward[1])
    along = (math.cos(math.radians(gh)), math.sin(math.radians(gh)))
    for off, depth in BARRICADE_OFFSETS:
        x, y = gx + along[0] * off + inward[0] * depth, gy + along[1] * off + inward[1] * depth
        out.append((ids["fort_barricade"], x, y, gh, [(x, y), (x - along[0] * 1.4, y - along[1] * 1.4), (x + along[0] * 1.4, y + along[1] * 1.4)]))
    return out


def sample_ground(points: list[tuple[float, float]]) -> list[float | None]:
    token = (Path(os.environ["LOCALAPPDATA"]) / "ariane-agent" / "token").read_text().strip()
    env = {**os.environ, "ARIANE_ENGINE_TCP_PORT": "48731", "ARIANE_ENGINE_TOKEN": token}
    res = subprocess.run([str(VENV_PYTHON), str(GROUND_TOOL), json.dumps([[round(x, 2), round(y, 2)] for x, y in points])], capture_output=True, text=True, env=env)
    if res.returncode:
        raise RuntimeError(f"ariane_ground.py failed (is Ariane running?): {res.stderr.strip()}")
    return json.loads(res.stdout)


def rows(ground=sample_ground) -> list[Row]:
    placements = plan()
    flat = [p for _m, _x, _y, _h, pts in placements for p in pts]
    heights = ground(flat) if ground else [None] * len(flat)
    out, at = [], 0
    for model, x, y, h, pts in placements:
        zs = [z for z in heights[at : at + len(pts)] if z is not None and 11.0 < z < 15.0]
        at += len(pts)
        out.append([model, round(x, 3), round(y, 3), round(min(zs) if zs else DEFAULT_Z, 3), 0, 0, round(h, 3), -1, -1, 350.0])
    upstream = parse_map(UPSTREAM_MAP.read_text(encoding="utf-8", errors="ignore"), "LS/Fort Defiance.map")["objects"]
    return out + [o for o in upstream if o[0] in KEEP]


def render(rows_: list[Row]) -> str:
    lines = [
        "-- Generated by tools/fort_layout.py; do not edit. The forts the port builds from its fort kit (models/fort.lua),",
        "-- in place of upstream's stock props: { model, x, y, z, rx, ry, rz, world, interior, range } per row, appended to the",
        "-- zone rows by placement.appendForts. Kept upstream ground pieces are copied as they were.",
        "return {",
        f'    ["{NAME}"] = {{',
    ]
    lines += ["        { " + ", ".join(str(v) for v in r) + " }," for r in rows_]
    return "\n".join(lines + ["    },", "}", ""])


def main(argv=None) -> int:
    no_ground = "--no-ground" in (sys.argv[1:] if argv is None else argv)
    table = rows(None if no_ground else sample_ground)
    FORTS.write_text(render(table), encoding="ascii", newline="\n")
    kit = sum(1 for r in table if r[0] in model_ids().values())
    print(f"fort_layout: {kit} kit pieces + {len(table) - kit} kept upstream props -> {FORTS}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
