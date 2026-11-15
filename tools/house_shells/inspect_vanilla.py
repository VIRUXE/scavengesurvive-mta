"""Dumps a vanilla house's skin and collision in model space, for planning a shell: python blender -b --python
tools/house_shells/inspect_vanilla.py -- <name> [--render]. Faces are grouped by texture, outward normal axis and plane."""
import os
import sys
from collections import defaultdict

import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
import common  # noqa: E402

name = common.args()[0]
s = common.Shell(name)
me = s.obj.data
xs = [v.co.x for v in me.vertices]
ys = [v.co.y for v in me.vertices]
zs = [v.co.z for v in me.vertices]
print("BBOX", [round(f(c), 2) for c in (xs, ys, zs) for f in (min, max)], "verts", len(xs), "faces", len(me.polygons))
print("MATS", [s.texture_of(i) for i in range(len(me.materials))])
print("COLS", len(s.cols))
for b in s.cols:
    print("  col", [round(v, 2) for v in b])
groups = defaultdict(list)
for p in me.polygons:
    n = p.normal
    ax = max(range(3), key=lambda i: abs(n[i]))
    sign = 1 if n[ax] > 0 else -1
    c = p.center
    groups[(s.texture_of(p.material_index), "xyz"[ax], sign, round(c[ax], 1))].append(p)
for k, ps in sorted(groups.items(), key=lambda kv: (kv[0][1], kv[0][3], kv[0][0])):
    vs = [me.vertices[i].co for p in ps for i in p.vertices]
    lo = [round(min(v[i] for v in vs), 2) for i in range(3)]
    hi = [round(max(v[i] for v in vs), 2) for i in range(3)]
    print("GROUP", k, len(ps), "faces", lo, hi)
if "--render" in common.args():
    for view, eye in (("v_front", (0, -25, 6)), ("v_back", (0, 25, 6)), ("v_east", (25, 0, 6)), ("v_west", (-25, 0, 6)), ("v_top", (0.01, 0, 45))):
        s.render(view, eye, (0, 0, 0), lens=35, size=(900, 700))
cm = s.keep_col_mesh()
if cm:
    cv = cm.data
    print("COLMESH verts", len(cv.vertices), "faces", len(cv.polygons))
    for p in cv.polygons:
        vs = [cv.vertices[i].co for i in p.vertices]
        print("  cface", [tuple(round(c, 2) for c in v) for v in vs])
