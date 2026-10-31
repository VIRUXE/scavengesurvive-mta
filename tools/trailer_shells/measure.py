"""Prints a trailer's hull by raycast from a point inside, to pick room bounds and openings:

    blender -b --python tools/trailer_shells/measure.py -- <model> [x y]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from common import Shell, args  # noqa: E402

a = args()
s = Shell(a[0])
cx, cy = (float(a[1]), float(a[2])) if len(a) > 2 else (0.0, 0.0)
print("== hull of", a[0], "from", cx, cy)
for z in (0.3, 0.6, 1.0, 1.5, 2.0, 2.5, 2.8, 3.0):
    row = []
    for d in ((1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0)):
        r = s.ray((cx, cy, z), d)
        row.append("-" if r is None else "%.2f" % r)
    print("z=%.1f  +x %s  -x %s  +y %s  -y %s" % (z, *row))
for y in [cy + k * 0.5 for k in range(-14, 15)]:
    up, dn = s.ray((cx, y, 1.5), (0, 0, 1)), s.ray((cx, y, 1.5), (0, 0, -1))
    xs = s.ray((cx, y, 1.5), (1, 0, 0)), s.ray((cx, y, 1.5), (-1, 0, 0))
    print("y=%.1f roof %s floor %s +x %s -x %s" % (y, up and "%.2f" % (1.5 + up), dn and "%.2f" % (1.5 - dn), xs[0] and "%.2f" % (cx + xs[0]), xs[1] and "%.2f" % (cx - xs[1])))
for i in range(len(s.obj.data.materials)):
    print("material", i, s.texture_of(i))
print("cols", [[round(v, 2) for v in b] for b in s.cols])
