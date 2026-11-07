"""What the three Fort Carson weatherboard houses' Blender scripts (des_bighus01/02/03.py) share: the interior palette
out of house_shell/files/des_bighus0N.txd (tools/house_shells/prep.py), the open doorways through the partitions
and their lining, and the papered walls stretched once from floor to ceiling. The three are one house plan: 01 as
it stands, 02 turned a quarter about Z, 03 mirrored north to south and raised 0.9 m; each gets the same living room,
kitchen and bedroom.

Import after `common` (tools/trailer_shells/common.py), whose TRIM, door and texture-scale settings this sets.
"""
import common
from common import Opening

TRIM = "des_ghotwood1"
LIVING_WALL, LIVING_FLOOR, CEILING = "mp_burn_wall2", "ab_wood1", "mp_burn_ceiling"
KITCHEN_WALL, KITCHEN_FLOOR = "kitchen-wall1", "barbersflr1"
BED_WALL, BED_FLOOR = "mp_burn_wall4", "mp_burn_carpet1"
GARAGE_WALL, GARAGE_FLOOR = TRIM, "floor_tileone_256"
WALLS = {LIVING_WALL, KITCHEN_WALL, BED_WALL}  # stretched once floor to ceiling (they carry a skirting and a dado)
DOUBLE = [("v", 0.5), ("h", 0.5)]  # the wide windows are a pair of sashes
DOORWAY_HEIGHT = 2.05

common.TRIM = TRIM
common.DOOR_GAP = 0.004
common.DOOR_THICK = 0.06
common.SCALE.update({TRIM: 1.4, LIVING_FLOOR: 1.6, KITCHEN_FLOOR: 1.2, BED_FLOOR: 1.5, CEILING: 2.0, GARAGE_FLOOR: 2.5})


def drop_cols(s, *boxes):
    """Removes the vanilla collision boxes matching `boxes` (x0, y0, z0, x1, y1, z1, to 0.02) from shell `s`."""
    s.cols = [b for b in s.cols if not any(all(abs(b[i] - k[i]) < 0.02 for i in range(6)) for k in boxes)]


def paint_doors(s, texture):
    """Every door leaf of `s` wears `texture`, mapped as much of it as the faces cut out of the skin covered."""
    for o in s.openings:
        if not o.door:
            continue
        cut = [(lo, hi) for t, lo, hi in o.removed if t == texture]
        o.door["texture"] = texture
        o.door["uv"] = [[min(lo[i] for lo, _hi in cut) for i in (0, 1)], [max(hi[i] for _lo, hi in cut) for i in (0, 1)]]


def doorway(s, axis, u0, u1, near, far, floor):
    """An open doorway through a partition across `axis`, from the room whose wall is at `near` into the one whose
    wall is at `far`, `u0..u1` along it."""
    side = 1 if far > near else -1
    s.opening("pass", axis, side, u0, u1, floor, floor + DOORWAY_HEIGHT, near, outer=far, reveal=TRIM)
    s.openings.append(Opening("pass", axis, -side, u0, u1, floor, floor + DOORWAY_HEIGHT, far))


def line_doorways(s, doorways, floor, ceil):
    """An interior doorway is lined like the rooms, not with the outside trim the reveal gets: its jambs in plaster
    (the wall texture, stretched floor to ceiling like the walls), the floor running through it, ceiling over its
    head, all lit as inside. `doorways`: (axis, u0, u1, near, far, wall, floor texture)."""
    for axis, u0, u1, near, far, wall, flooring in doorways:
        n, a = (0, 1) if axis == "x" else (1, 0)  # the partition's normal and along-wall coordinates
        d0, d1 = min(near, far), max(near, far)
        for f in s.bm.faces:
            c = f.calc_center_median()
            if not (d0 - 0.01 < c[n] < d1 + 0.01 and u0 - 0.01 < c[a] < u1 + 0.01 and floor - 0.01 < c.z < floor + DOORWAY_HEIGHT + 0.01):
                continue
            if abs(f.normal[n]) > 0.5:
                continue  # not a lining face
            tex = flooring if f.normal.z > 0.5 else CEILING if f.normal.z < -0.5 else wall
            f.material_index = s.mat(tex)
            scale = common.SCALE.get(tex, 1.0)
            for loop in f.loops:
                co = loop.vert.co
                if tex == wall:
                    loop[s.uv].uv = (co[n] / scale, (co.z - floor) / (ceil - floor))
                else:
                    loop[s.uv].uv = (co.x / scale, co.y / scale)
                loop[s.day], loop[s.night] = common.IN_DAY, common.IN_NIGHT


def stretch_walls(s, faces, floor, ceil):
    """The papered walls among `faces`: one repeat from floor to ceiling, so the skirting and dado sit where they
    belong."""
    stretch = {s.mat(t) for t in WALLS}
    for f in faces:
        if f.material_index in stretch:
            for loop in f.loops:
                loop[s.uv].uv.y = (loop.vert.co.z - floor) / (ceil - floor)
