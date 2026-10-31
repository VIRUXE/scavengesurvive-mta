"""Fort Defiance's rooftop walkways: stairs, ramps and bridges, one custom model per span, cut to its measured heights.

Upstream joins the houses around the Grove Street cul-de-sac with stock props (cxref_woodjetty, des_wjetty, cn2_jetty1,
cxref_woodstair, newramp, dyn_ramp, a garage door) laid across the roofs by eye. Each span here is one model built for
exactly one route: start and end world points and deck heights read off the props' own deck lines and the roofs under
them (tools/fort_spans.py, docs/reviews/2026-10-31-fort-defiance-spans.md), with a plank deck, rails on both sides, posts
down to whatever the span stands on and collision that follows the deck.

A model runs along its local +y with the deck's start at the origin; the map row puts it at the start point, turned to the
end point. `piece(name)` returns (parts, collision boxes) in tools/make_fort_kit.py's format, `placements()` the map rows.
"""
from __future__ import annotations

import math

GROUND = 12.5
WIDTH, THICK, RAIL = 1.8, 0.12, 1.0
STEP_RISE, RAMP_SEG, FLAT_SEG = 0.22, 0.5, 1.0
DECK, TIMBER, STEEL = "planks01", "was_scrpyd_rustmetal", "rustybolts"  # tools/make_fort_kit.py's texture names

# name -> (kind, start (x, y, z), end (x, y, z), floor segments (from m, to m, z) the span stands on; default the ground).
# z is the deck's top at that point; for stairs the start is the ground and the end the landing.
SPANS = {
    "fort_walk_n_stairs": ("stairs", (2492.5, -1655.9, 12.5), (2493.0, -1647.4, 16.6), []),
    "fort_walk_n_ramp": ("ramp", (2491.8, -1647.6, 16.6), (2492.9, -1632.0, 18.7), []),
    "fort_walk_n_bridge": ("bridge", (2496.6, -1641.4, 17.5), (2511.5, -1644.6, 17.5), [(0.0, 7.2, 16.4), (7.2, 13.2, GROUND), (13.2, 15.4, 16.8)]),
    "fort_walk_s_ridge": ("bridge", (2508.5, -1694.1, 17.0), (2514.0, -1693.4, 17.5), [(0.0, 5.6, 16.3)]),
    "fort_walk_s_rise": ("bridge", (2514.0, -1693.4, 17.5), (2519.3, -1692.3, 18.45), [(0.0, 5.4, 17.1)]),
    "fort_walk_s_bridge": ("bridge", (2519.3, -1692.3, 18.45), (2522.4, -1684.1, 18.6), [(0.0, 5.0, 17.0), (5.0, 8.0, 12.6), (8.0, 8.8, 18.4)]),
    "fort_walk_e_stairs": ("stairs", (2513.1, -1679.9, 12.6), (2521.0, -1679.7, 18.4), []),
    "fort_walk_e_bridge": ("bridge", (2526.8, -1671.0, 18.9), (2526.8, -1660.9, 18.6), [(0.0, 0.8, 18.5), (0.8, 7.0, 14.2), (7.0, 10.1, 17.9)]),
}


def layout(name: str) -> dict:
    kind, a, b, floors = SPANS[name]
    length = math.hypot(b[0] - a[0], b[1] - a[1])
    dz = b[2] - a[2]
    return {"kind": kind, "a": a, "b": b, "length": length, "dz": dz, "angle": math.degrees(math.atan2(dz, length)),
            "heading": math.degrees(math.atan2(-(b[0] - a[0]), b[1] - a[1])) % 360, "floors": floors}


def floor_at(spec: dict, s: float, start_z: float) -> float:
    """The z (local, relative to the deck's start) of whatever the span stands on at distance s."""
    for lo, hi, z in spec["floors"]:
        if lo <= s <= hi:
            return z - start_z
    return GROUND - start_z


def deck_z(spec: dict, s: float) -> float:
    return spec["dz"] * s / spec["length"]


def sloped(cx, cy, cz, sx, length, sz, tex, angle):
    """A box along y that follows the slope: `length` is the horizontal run it spans."""
    return (cx, cy, cz, sx, length / math.cos(math.radians(angle)), sz, tex, angle)


def rails(spec: dict) -> list[tuple]:
    length, dz, angle = spec["length"], spec["dz"], spec["angle"]
    parts = []
    for side in (-1, 1):
        x = side * (WIDTH / 2 - 0.05)
        for h in (RAIL, RAIL / 2):
            parts.append(sloped(x, length / 2, dz / 2 + h, 0.05, length, 0.05, STEEL, angle))
        n = max(2, round(length / 2.0))
        for i in range(n + 1):
            s = length * i / n
            parts.append((x, s, deck_z(spec, s) + RAIL / 2, 0.07, 0.07, RAIL, TIMBER))
    return parts


def supports(spec: dict) -> list[tuple]:
    """Posts every 3 m from the floor to the deck's underside where there is room for them, and a beam across each pair."""
    length, start_z = spec["length"], spec["a"][2]
    parts = []
    n = max(1, int(length // 3.0))
    for i in range(n + 1):
        s = min(length, 0.4 + (length - 0.8) * i / n) if n else length / 2
        under = deck_z(spec, s) - THICK
        floor = floor_at(spec, s, start_z)
        if under - floor > 0.35:
            for x in (-0.65, 0.65):
                parts.append((x, s, (under + floor) / 2, 0.2, 0.2, under - floor, TIMBER))
            parts.append((0.0, s, under - 0.08, WIDTH + 0.2, 0.18, 0.16, TIMBER))
    return parts


def bridge_parts(spec: dict) -> tuple[list[tuple], list[tuple]]:
    length, dz, angle = spec["length"], spec["dz"], spec["angle"]
    parts = [sloped(0.0, length / 2, dz / 2 - THICK / 2, WIDTH, length, THICK, DECK, angle)] + rails(spec) + supports(spec)
    seg = RAMP_SEG if abs(dz) / length > 0.2 else FLAT_SEG
    n = max(1, math.ceil(length / seg))
    cols = []
    for i in range(n):
        lo, hi = length * i / n, length * (i + 1) / n
        z = deck_z(spec, (lo + hi) / 2)
        cols.append((0.0, (lo + hi) / 2, z - THICK / 2, WIDTH, hi - lo + 0.02, THICK))
        for side in (-1, 1):
            cols.append((side * (WIDTH / 2 - 0.05), (lo + hi) / 2, z + RAIL / 2, 0.08, hi - lo + 0.02, RAIL))
    return parts, cols


def stairs_parts(spec: dict) -> tuple[list[tuple], list[tuple]]:
    length, dz, angle = spec["length"], spec["dz"], spec["angle"]
    n = max(2, round(dz / STEP_RISE))
    run = length / n
    parts = [(0.0, run * (i + 0.5), dz * (i + 1) / n - 0.035, WIDTH, run + 0.02, 0.07, DECK) for i in range(n)]
    for side in (-1, 1):
        parts.append(sloped(side * (WIDTH / 2 - 0.05), length / 2, dz / 2 - 0.2, 0.1, length, 0.3, TIMBER, angle))
    parts += rails(spec)
    cols = [(0.0, run * (i + 0.5), (dz * (i + 1) / n) / 2, WIDTH, run + 0.02, dz * (i + 1) / n) for i in range(n)]
    for side in (-1, 1):
        cols += [(side * (WIDTH / 2 - 0.05), (length * (i + 0.5)) / n, dz * (i + 1) / n + RAIL / 2, 0.08, run + 0.02, RAIL) for i in range(n)]
    return parts, cols


def piece(name: str) -> tuple[list[tuple], list[tuple]]:
    spec = layout(name)
    return stairs_parts(spec) if spec["kind"] == "stairs" else bridge_parts(spec)


def placements(ids: dict[str, int]) -> list[list]:
    """The map rows that stand each walkway where it was measured: [model, x, y, z, rx, ry, rz, world, interior, range]."""
    rows = []
    for name in SPANS:
        spec = layout(name)
        x, y, z = spec["a"]
        rows.append([ids[name], round(x, 3), round(y, 3), round(z, 3), 0, 0, round(spec["heading"], 3), -1, -1, 350.0])
    return rows
