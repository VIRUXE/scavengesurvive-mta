"""The dev studio's camera, as a projection from the ped's Head bone space to the hatless reference grids (#89).

`tools/hatless_refs.py` shoots each skin in the studio and pastes the shots into 2x2 grids; `tools/hatless_rebuild.py`
measured the Head bone's world matrix of every skin in the studio (`tools/data/hatless_calib.json`). With both, a point
on a ped's head maps to the grid pixel that shows it, which is what carves the rebuilt skull out of the reference's
silhouettes and paints its hair (`tools/blender/rebuild_head.py`). Pure numpy: Blender's Python imports it too.

Facts measured on 2026-10-25: the client renders 1920x1080 with MTA's default horizontal field of view of 70 degrees;
`takePlayerScreenShot(p, 1280, 960)` squashes that whole screen to 1280x960; the grid crops 600x600 from each shot
(x 340..940, y from CROP_TOP) and scales it to a 512 cell.
"""
import math

import numpy as np

SCREEN = (1920, 1080)
SHOT = (1280, 960)
FOCAL = (SCREEN[0] / 2) / math.tan(math.radians(35))
PED = np.array([0.0, 0.0, 2500.0])  # studio.CENTRE: the ped's origin
# view -> (yaw, dist, height, lookZ), the studio verb's arguments (tools/hatless_refs.py CAMERAS)
CAMERAS = {
    "front": (0, 0.8, 0.68, 0.64),
    "three": (35, 0.8, 0.7, 0.64),
    "side": (270, 0.8, 0.68, 0.64),
    "back": (180, 0.8, 0.68, 0.64),
    "top": (0, 0.3, 1.45, 0.66),
    "topback": (180, 0.55, 1.2, 0.66),
}
CROP_TOP = {"top": 140, "topback": 40}
GRIDS = {"level": ("front", "three", "side", "back"), "top": ("top", "topback", "front", "side")}


def cell_origin(grid: str, view: str) -> tuple[int, int]:
    i = GRIDS[grid].index(view)
    return (i % 2) * 512, (i // 2) * 512


def camera(view: str):
    """World position, forward, right and up of the studio camera for `view`."""
    yaw, dist, height, look = CAMERAS[view]
    r = math.radians(yaw)
    c = PED + np.array([dist * math.sin(r), dist * math.cos(r), height])
    fwd = PED + np.array([0, 0, look]) - c
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 0, 1.0])
    right /= np.linalg.norm(right)
    return c, fwd, right, np.cross(right, fwd)


def to_world(bone_matrix, pts):
    """Head-bone-space points (n, 3) -> world, with MTA's getElementBoneMatrix rows (x, y, z axes, position)."""
    m = np.asarray(bone_matrix, dtype=np.float64)
    return np.asarray(pts, dtype=np.float64) @ m[:3, :3] + m[3, :3]


def to_shot(view: str, world):
    """World points -> screenshot pixels (1280x960)."""
    c, fwd, right, up = camera(view)
    d = np.asarray(world) - c
    z = d @ fwd
    sx = SCREEN[0] / 2 + FOCAL * (d @ right) / z
    sy = SCREEN[1] / 2 - FOCAL * (d @ up) / z
    return np.stack([sx * SHOT[0] / SCREEN[0], sy * SHOT[1] / SCREEN[1]], 1)


def to_grid(grid: str, view: str, shot_xy, offset=(0, 0)):
    """Screenshot pixels -> pixels of the 1024x1024 studio grid, plus a per-view registration offset."""
    ox, oy = cell_origin(grid, view)
    top = CROP_TOP.get(view, 0)
    xy = np.asarray(shot_xy, dtype=np.float64)
    return np.stack([(xy[:, 0] - 340) * 512 / 600 + ox + offset[0], (xy[:, 1] - top) * 512 / 600 + oy + offset[1]], 1)


def to_reference(grid: str, view: str, grid_xy, xform=(1.0, 0, 0)):
    """Studio-grid pixels -> pixels of the edited reference: the image model may scale and shift each view about its
    cell's centre (`xform` = scale, dx, dy, fitted by tools/hatless_rebuild.py prep)."""
    s, tx, ty = xform
    o = np.array(cell_origin(grid, view), dtype=np.float64)
    return (np.asarray(grid_xy) - o - 256) * s + 256 + [tx, ty] + o
