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

import math

DECK, TIMBER, SHEET, STEEL = "planks01", "was_scrpyd_rustmetal", "ws_corrugated1", "rustybolts"  # make_fort_kit's textures

# name -> (x, y, z, rz): where upstream's prop stood (deck: its top is at z)
PLACED = {
    "fort_labdeck": (2523.064, -1651.881, 17.86, 35.73),
    "fort_shelter": (2484.079, -1664.151, 12.31, 0.0),
    "fort_leanto": (2459.3, -1666.6, 12.48, 0.0),
}
LAB_FLOOR = 13.1  # the ground under the lab deck, read off Ariane (docs/reviews/2026-10-31-fort-defiance-spans.md)


def labdeck() -> tuple[list[tuple], list[tuple]]:
    """A 9.4 m plank deck whose top is the origin, on a 3 x 3 grid of posts to the ground."""
    drop = LAB_FLOOR - PLACED["fort_labdeck"][2]  # local z of the ground, negative
    parts = [(0.0, 0.0, -0.07, 9.4, 9.4, 0.14, DECK)]
    parts += [(0.0, y, -0.28, 9.4, 0.14, 0.4, TIMBER) for y in (-4.65, 4.65)]
    parts += [(x, 0.0, -0.28, 0.14, 9.4, 0.4, TIMBER) for x in (-4.65, 4.65)]
    parts += [(0.0, y, -0.4, 9.2, 0.25, 0.24, TIMBER) for y in (-3.0, 0.0, 3.0)]
    posts = [(x, y, (drop + -0.14) / 2, 0.3, 0.3, -0.14 - drop) for x in (-4.0, 0.0, 4.0) for y in (-4.0, 0.0, 4.0)]
    parts += [p + (TIMBER,) for p in posts]
    cols = [(0.0, 0.0, -0.07, 9.4, 9.4, 0.14)] + posts
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
