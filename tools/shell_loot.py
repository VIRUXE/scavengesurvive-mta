"""Loot points inside the enterable trailers (house_shell models 3167-3175) and the log cabin row (17067).

Every point is in the model's own frame, z at the room floor + 0.02. They sit well inside the room boxes written by
tools/trailer_shells/<name>.py (build/<name>.json "rooms", gitignored): at least 0.6 m from every wall (loot rolls lay
their items in a 0.6 m ring), clear of the door leaf's swing, and off the wheel humps and the bed plinth. The converter
tools/convert/shellloot.py turns them into world points for every placement."""
from __future__ import annotations

SIZE, WEIGHT = 2, 20.0
TABLES = ("world_civilian", "world_survivor")
SURVIVOR_ONE_IN = 4  # a point rolls world_survivor when its position hash is divisible by this

# model -> [(x, y, z)]
TRAILER_POINTS = {
    3167: [(0.0, -3.2, 0.47), (0.0, 3.4, 0.47), (2.95, 0.3, 0.47)],  # trailer_large1_01: floor 0.45, annex entry room
    3168: [(0.2, -2.8, 0.42), (0.0, 3.4, 0.42)],  # trailer2_01: lounge and bedroom past the wheel humps
    3169: [(-0.2, -3.2, 0.47), (-0.2, 3.2, 0.47)],  # trailer_large2_01
    3170: [(-0.2, -3.2, 0.47), (-0.2, 3.2, 0.47)],  # trailer_large3_01
    3171: [(0.2, 0.9, 0.42)],  # trailer5_01
    3172: [(0.2, -2.8, 0.42), (0.0, 4.3, 0.42)],  # trailer6_01: lounge, bedroom (bed plinth stops short of y 4.3)
    3173: [(-0.2, -3.2, 0.47), (-0.2, 3.2, 0.47)],  # trailer_large4_01
    3174: [(0.2, 0.5, 0.48)],  # sm_airstrm_sml_
    3175: [(0.2, -0.6, 0.47), (0.2, 2.2, 0.47)],  # sm_airstrm_med_
}

# Each cabin's room centre (dx, dy, dz) from the model origin: cabin_shells/cw2_logcabins.py OFFSETS, floor 0.06 + dz.
CABIN_OFFSETS = [(-18.855, -25.366, 0.0), (-12.434, -16.851, 0.0), (-6.02, -8.348, 0.0), (0.0, 0.0, 0.0), (6.142, 8.33, 0.257), (12.017, 16.667, 0.496)]
# in a cabin's frame (room X 2.8, Y 1.8 about its centre, door slider at -Y, u -0.48..0.48)
CABIN_POINTS = [(-1.5, 0.5, 0.08), (1.5, -0.3, 0.08)]
