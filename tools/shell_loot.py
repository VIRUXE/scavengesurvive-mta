"""Loot points inside the enterable trailers (house_shell models 3167-3175) and the log cabin row (17067).

Rooms come from tools/shell_rooms.json (written by Shell.export(): [x0, x1, y0, y1, floor z, ceiling z] per room, in
the model's frame). A point is (x, y, room index); its z is the room's floor + FLOOR_LIFT, so it follows the model.
Points sit at least MARGIN from every wall (loot rolls lay their items in a 0.6 m ring), clear of the door leaf's swing,
and off the wheel humps and the bed plinth; `points()` raises when one drifts out of its room. The converter
tools/convert/shellloot.py turns them into world points for every placement."""
from __future__ import annotations

import json
from pathlib import Path

SIZE, WEIGHT = 2, 20.0
TABLES = ("world_civilian", "world_survivor")
SURVIVOR_ONE_IN = 4  # a point rolls world_survivor when its position hash is divisible by this
FLOOR_LIFT, MARGIN = 0.02, 0.6

ROOMS = json.loads((Path(__file__).resolve().parent / "shell_rooms.json").read_text(encoding="utf-8"))

# model -> (shell, [(x, y, room)])
TRAILERS = {
    3167: ("trailer_large1_01", [(0.0, -3.2, 0), (0.0, 3.4, 0), (2.95, 0.3, 1)]),  # main room, annex with the door
    3168: ("trailer2_01", [(0.2, -2.8, 0), (0.0, 3.4, 1)]),  # lounge, bedroom past the wheel humps
    3169: ("trailer_large2_01", [(-0.2, -3.2, 0), (-0.2, 3.2, 0)]),
    3170: ("trailer_large3_01", [(-0.2, -3.2, 0), (-0.2, 3.2, 0)]),
    3171: ("trailer5_01", [(0.2, 0.9, 0)]),
    3172: ("trailer6_01", [(0.2, -2.8, 0), (0.0, 4.3, 1)]),  # lounge, bedroom (the bed plinth stops short of y 4.3)
    3173: ("trailer_large4_01", [(-0.2, -3.2, 0), (-0.2, 3.2, 0)]),
    3174: ("sm_airstrm_sml_", [(0.2, 0.5, 0)]),
    3175: ("sm_airstrm_med_", [(0.2, -0.6, 0), (0.2, 2.2, 0)]),
}

# Cabin points in a cabin's frame, about its room centre (room 3.0 x 2.0 half sizes 2.8 x 1.8, door slider at -Y).
CABIN_SHELL = "cw2_logcabins"
CABIN_POINTS = [(-1.5, 0.5), (1.5, -0.3)]


def inside(shell: str, room: int, x: float, y: float) -> tuple[float, float, float]:
    """The point as (x, y, z) in the model's frame, or ValueError when it is not MARGIN inside the room."""
    x0, x1, y0, y1, z0, _ = ROOMS[shell][room]
    if not (x0 + MARGIN <= x <= x1 - MARGIN and y0 + MARGIN <= y <= y1 - MARGIN):
        raise ValueError(f"{shell} room {room}: ({x}, {y}) is within {MARGIN} m of a wall")
    return x, y, round(z0 + FLOOR_LIFT, 4)


def trailer_points(model: int) -> list[tuple[float, float, float]]:
    shell, pts = TRAILERS[model]
    return [inside(shell, room, x, y) for x, y, room in pts]


def cabin_points() -> list[tuple[float, float, float]]:
    """Every point of the six cabins in the cabin model's frame."""
    out = []
    for i, (x0, x1, y0, y1, _, _) in enumerate(ROOMS[CABIN_SHELL]):
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        out += [inside(CABIN_SHELL, i, round(cx + dx, 4), round(cy + dy, 4)) for dx, dy in CABIN_POINTS]
    return out
