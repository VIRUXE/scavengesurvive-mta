"""Fort Defiance's other rebuilt structures: the lab deck, the pole shelter and the lean-to that replaces the hut skeleton.

Same approach as tools/fort_walkways.py: each upstream prop that clipped or floated is replaced by a custom model cut to
the place it stands, at the position and rotation upstream gave it, and everything standing on or under it stays.

- fort_labdeck  replaces a51_jetdoor (3095): upstream used a 9 x 9 m Area 51 door as the floor of a log cabin (sw_logcover,
  3403, which stays) with nothing under it but air, 4.5 m above the ground. The deck is a plank slab with beams and posts
  down to the ground at 13.1.
- fort_shelter  replaces truth_barn03 (17010): a barn's exterior mesh on bare ground over the camp's beds. The shelter has
  the barn's 14.6 x 6.7 m footprint: ten posts, tie beams and a corrugated gable roof to 5.2 m. The beds stay.
- fort_leanto   (the kit's own piece, 20307) replaces desn2_hutskel03 (16405), a hut skeleton standing in the road verge.

`pieces()` returns {name: (parts, collision boxes)} in tools/make_fort_kit.py's format, `placements(ids)` the map rows.
"""
from __future__ import annotations

import json
import math
from pathlib import Path

DECK, TIMBER, SHEET, STEEL = "planks01", "was_scrpyd_rustmetal", "ws_corrugated1", "rustybolts"  # make_fort_kit's textures

# name -> (x, y, z, rz): where upstream's prop stood (deck: its top is at z)
PLACED = {
    "fort_labdeck": (2523.064, -1651.881, 17.86, 35.73),
    "fort_shelter": (2484.079, -1664.151, 12.31, 0.0),
    "fort_leanto": (2459.3, -1666.6, 12.48, 0.0),
}
SURFACES = Path(__file__).resolve().parent / "data" / "fort_surfaces.json"
LAB_CLEAR = 0.15  # a roof within this of the deck's top is a roof the deck gives way to
AREAS = {"fort_labdeck": (4.7, 4.7), "fort_shelter": (7.3, 3.35)}  # half extents tools/fort_scene.py samples under each
LAB_FLOOR = 13.1  # the ground under the lab deck, read off Ariane (docs/reviews/2026-10-31-fort-defiance-spans.md)


def surface_grid(name: str) -> list[dict]:
    """The scenery under a structure's footprint as tools/fort_scene.py sampled it: [{u, v, top, floor}] in model space."""
    data = json.loads(SURFACES.read_text(encoding="utf-8")) if SURFACES.exists() else {}
    return data.get(name, [])


def labdeck() -> tuple[list[tuple], list[tuple]]:
    """A plank deck whose top is the origin, over the alley between two houses: it is laid only where the scenery leaves
    room under it (a roof or ridge that reaches the deck takes its place), on posts that stand on the ground or the roof
    below, in one slab per row of the 1 m sampling grid."""
    grid = surface_grid("fort_labdeck")
    top_z = PLACED["fort_labdeck"][2]
    cell = 9.4 / 9
    rows: dict[float, list[dict]] = {}
    low = {(round((g["u"] + 4.7) / cell), round((g["v"] + 4.7) / cell)): g["top"] is None or g["top"] < top_z - LAB_CLEAR for g in grid}
    for g in grid:
        at = (round((g["u"] + 4.7) / cell), round((g["v"] + 4.7) / cell))
        if all(low.get((at[0] + du, at[1] + dv), True) for du in (-1, 0, 1) for dv in (-1, 0, 1)):  # and every neighbour: a slab is a cell wide
            rows.setdefault(g["v"], []).append(g)
    parts, cols = [], []
    for v, cells in sorted(rows.items()):
        cells.sort(key=lambda g: g["u"])
        run = [cells[0]]
        for g in cells[1:] + [None]:
            if g is not None and g["u"] - run[-1]["u"] < cell * 1.5:
                run.append(g)
                continue
            u0, u1 = run[0]["u"] - cell / 2, run[-1]["u"] + cell / 2
            parts.append(((u0 + u1) / 2, v, -0.07, u1 - u0, cell, 0.14, DECK))
            parts.append(((u0 + u1) / 2, v, -0.28, u1 - u0, 0.2, 0.28, TIMBER))
            cols.append(((u0 + u1) / 2, v, -0.07, u1 - u0, cell, 0.14))
            run = [g] if g is not None else []
    for tu in (-4.0, 0.0, 4.0):
        for tv in (-4.0, 0.0, 4.0):
            g = min(grid, key=lambda c: math.hypot(c["u"] - tu, c["v"] - tv))
            if g["top"] is not None and g["top"] >= top_z - LAB_CLEAR:
                continue
            ground = g["floor"] if g["floor"] is not None else LAB_FLOOR
            low = ground - top_z
            if -0.14 - low > 0.35:
                post = (g["u"], g["v"], (low - 0.14) / 2, 0.3, 0.3, -0.14 - low)
                parts.append(post + (TIMBER,))
                cols.append(post)
    return parts, cols


def shelter() -> tuple[list[tuple], list[tuple]]:
    """A pole shelter on the barn's footprint: ground at the origin, ridge along x at 5.2 m."""
    xs, ys, post_h, eave, ridge, run = (-6.8, -3.4, 0.0, 3.4, 6.8), (-3.1, 3.1), 3.3, 3.3, 5.2, 3.5
    parts = [(x, y, post_h / 2, 0.3, 0.3, post_h, TIMBER) for x in xs for y in ys]
    parts += [(0.0, y, post_h - 0.15, 14.6, 0.25, 0.25, TIMBER) for y in ys]
    parts += [(x, 0.0, post_h - 0.15, 0.25, 6.4, 0.25, TIMBER) for x in (-6.8, 0.0, 6.8)]
    angle = math.degrees(math.atan2(ridge - eave, run))
    plane = math.hypot(run, ridge - eave)
    mid = (ridge + eave) / 2 + 0.05
    parts += [(0.0, side * run / 2, mid, 14.8, plane, 0.1, SHEET, -side * angle) for side in (-1, 1)]
    parts += [(0.0, 0.0, ridge + 0.05, 14.8, 0.3, 0.12, STEEL)]
    cols = [(x, y, post_h / 2, 0.3, 0.3, post_h) for x in xs for y in ys]
    cols += [(0.0, 0.0, mid, 14.8, 7.0, 0.2)]
    return parts, cols


def piece(name: str) -> tuple[list[tuple], list[tuple]]:
    return {"fort_labdeck": labdeck, "fort_shelter": shelter}[name]()


def placements(ids: dict[str, int]) -> list[list]:
    """[model, x, y, z, rx, ry, rz, world, interior, range] rows for every structure above."""
    return [[ids[name], x, y, z, 0, 0, rz, -1, -1, 350.0] for name, (x, y, z, rz) in PLACED.items()]
