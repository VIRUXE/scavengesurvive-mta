"""conhoos2 (model 3241): the desert concrete house of Bone County, Red County and the Los Santos hills, a single-storey
rendered house 6 x 12 m under a hip-less gable roof, with a roofed porch on posts along its west (front) side. The
house gets three rooms along its length, joined by open doorways: a bedroom at the south end, a living room behind the
front door in the middle and a kitchen at the north end.

    blender -b --python tools/house_shells/conhoos2.py [-- --no-render]

Run tools/house_shells/prep_conhoos2.py first (headless Linux renders: SHELL_ENGINE=CYCLES). Vanilla skin: single
faces, the body the box x -3..3, y -6..6 from the floor (the door sill) at -0.54 to the eaves at about 2.5; the porch
roof reaches x -5.33 on four posts (x -4.97..-4.82); the door (des_adobedoor1, its twelve panes cut through and glazed like the farmhouse's) is painted 0.15 into the west skin, the
eleven windows (des_hooswin1) 0.1 into it. Rooms stand 0.2 inside the skin; partitions are 0.2 thick, placed in the
gaps between the windows (the vanilla windows decide where they can stand). The COL has no boxes, only a thin triangle
shell, so the shell's collision is all boxes. Writes house_shell/files/conhoos2.dff/.col and conhoos2_door.dff/.col,
build/conhoos2.json and build/conhoos2_doors.json (the leaf's hinge and heading).
"""
import json
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import common  # noqa: E402
from bighus import (  # noqa: E402
    BED_FLOOR, BED_WALL, CEILING, KITCHEN_FLOOR, KITCHEN_WALL, LIVING_FLOOR, LIVING_WALL, TRIM,
    doorway, line_doorways, stretch_walls,
)

common.CURTAINS["conhoos2"] = "ah_curtains1"
from common import BUILD, DOOR_THICK, GLASS, GLASS_DAY, GLASS_NIGHT, OUT_DAY, OUT_NIGHT, args  # noqa: E402

# the terrain lies at -0.52 here: the floor stands a hand above it, or the sand shows through
FLOOR, CEIL, ROOF = -0.42, 2.1, 2.58
WX0, WX1 = -2.8, 2.8
# bedroom | living room | kitchen along y; the partitions fall between the windows (see the module docstring)
AY0, AY1, BY0, BY1, CY0, CY1 = -5.8, -2.1, -1.9, 1.027, 1.227, 5.8

# the painted frame of des_hooswin1: its meeting stile, a patch of it stretched over every bar (texture, uv rect, v up)
SASH = ("des_hooswin1", (0.495, 0.15, 0.515, 0.85))
SLIDER = [("v", 0.5, 0.045)]

# the twelve small panes of the door (des_adobedoor1, 64 x 128): three across, four down, as uv ranges (v up)
DOOR_PANES_U = ((0.141, 0.359), (0.383, 0.594), (0.617, 0.828))
DOOR_PANES_V = ((0.398, 0.516), (0.531, 0.648), (0.664, 0.781), (0.797, 0.922))
MUNTIN_UV = (0.30, 0.06, 0.50, 0.10)  # a patch of the door's painted bottom rail, for the panes' linings


class Conhoos(common.Shell):
    def build_leaf(self):
        """The leaf with its twelve panes cut through and glazed: the door faces wear des_adobedoor1 around the
        holes (both faces mapped alike, so the holes line up), each hole is lined with the painted bar and holds a
        pane of house_window, seen from both sides."""
        d = next((o.door for o in self.openings if o.door), None)
        if not d:
            return None
        name = self.name + "_door"
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day, night = bm.loops.layers.color.new("Col"), bm.loops.layers.color.new("Col.001")
        for t in (d["texture"], TRIM, GLASS):
            m = bpy.data.materials.new(t)
            m.use_nodes = True
            bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = self._image(t) or bpy.data.images.new(t + ".png", 8, 8)
            m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            if t == GLASS:
                m.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
                if hasattr(m, "surface_render_method"):
                    m.surface_render_method = "BLENDED"
            mesh.materials.append(m)
        w, h, t = d["width"], d["height"], DOOR_THICK
        (ua, va), (ub, vb) = d["uv"]
        y0, y1 = -t / 2, t / 2

        def x_of(u):
            return w * (u - ua) / (ub - ua)

        def z_of(v):
            return h * (v - va) / (vb - va)

        def tex(x, z):
            return (ua + x / w * (ub - ua), va + z / h * (vb - va))

        def quad(vs, mi, uvs, light=(OUT_DAY, OUT_NIGHT)):
            f = bm.faces.new([bm.verts.new(v) for v in vs])
            f.material_index = mi
            for loop, c in zip(f.loops, uvs):
                loop[uv].uv = c
                loop[day], loop[night] = light

        panes = [(x_of(a), x_of(b), z_of(c), z_of(e)) for a, b in DOOR_PANES_U for c, e in DOOR_PANES_V]
        xs = sorted({0.0, w} | {v for p in panes for v in p[:2]})
        zs = sorted({0.0, h} | {v for p in panes for v in p[2:]})
        for i in range(len(xs) - 1):
            for j in range(len(zs) - 1):
                xa, xb, za, zb = xs[i], xs[i + 1], zs[j], zs[j + 1]
                cx, cz = (xa + xb) / 2, (za + zb) / 2
                if any(p[0] < cx < p[1] and p[2] < cz < p[3] for p in panes):
                    continue
                c = [tex(xa, za), tex(xb, za), tex(xb, zb), tex(xa, zb)]
                quad([(xa, y0, za), (xb, y0, za), (xb, y0, zb), (xa, y0, zb)], 0, c)
                quad([(xb, y1, za), (xa, y1, za), (xa, y1, zb), (xb, y1, zb)], 0, [c[1], c[0], c[3], c[2]])
        mu0, mv0, mu1, mv1 = MUNTIN_UV
        m = [(mu0, mv0), (mu1, mv0), (mu1, mv1), (mu0, mv1)]
        g = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for xa, xb, za, zb in panes:
            quad([(xa, y1, za), (xa, y0, za), (xa, y0, zb), (xa, y1, zb)], 0, m)  # facing +x
            quad([(xb, y0, za), (xb, y1, za), (xb, y1, zb), (xb, y0, zb)], 0, m)  # facing -x
            quad([(xa, y0, za), (xa, y1, za), (xb, y1, za), (xb, y0, za)], 0, m)  # facing +z
            quad([(xa, y1, zb), (xa, y0, zb), (xb, y0, zb), (xb, y1, zb)], 0, m)  # facing -z
        e = [(0, 0), (1, 0), (1, 0.1), (0, 0.1)]
        quad([(0, y1, 0), (0, y0, 0), (0, y0, h), (0, y1, h)], 1, e)
        quad([(w, y0, 0), (w, y1, 0), (w, y1, h), (w, y0, h)], 1, e)
        quad([(0, y0, h), (w, y0, h), (w, y1, h), (0, y1, h)], 1, e)
        quad([(0, y1, 0), (w, y1, 0), (w, y0, 0), (0, y0, 0)], 1, e)
        # the glass last, so the game draws it after the leaf around it
        lit = (GLASS_DAY, GLASS_NIGHT)
        for xa, xb, za, zb in panes:
            quad([(xa, 0, za), (xb, 0, za), (xb, 0, zb), (xa, 0, zb)], 2, g, lit)
            quad([(xb, 0, za), (xa, 0, za), (xa, 0, zb), (xb, 0, zb)], 2, [g[1], g[0], g[3], g[2]], lit)
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        self.leaf = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(self.leaf)
        return self.leaf


s = Conhoos("conhoos2")

# the door, on the porch (west) wall; the leaf wears as much of des_adobedoor1 as its cut covered
s.opening("door", "x", -1, -1.296, -0.294, FLOOR, 1.661, WX0, hinge="left", reveal=TRIM)

# windows: west (-x), east (+x), south (-y), north (+y); the pane rectangles of the vanilla skin
for u0, u1 in ((-3.594, -2.779), (1.428, 2.243), (3.663, 4.477)):
    s.opening("window", "x", -1, u0, u1, 0.555, 1.866, WX0, frame=SLIDER, reveal=TRIM, frame_skin=SASH)
for u0, u1 in ((-4.794, -3.979), (0.012, 0.826), (3.663, 4.477)):
    s.opening("window", "x", 1, u0, u1, 0.555, 1.866, WX1, frame=SLIDER, reveal=TRIM, frame_skin=SASH)
s.opening("window", "y", -1, -0.904, 0.623, 0.484, 1.937, AY0, frame=SLIDER, reveal=TRIM, frame_skin=SASH)  # bedroom, south
s.opening("window", "y", 1, 0.421, 1.236, 0.555, 1.866, CY1, frame=SLIDER, reveal=TRIM, frame_skin=SASH)  # kitchen, north

DOORWAYS = (
    ("y", -0.5, 0.5, BY0, AY1, LIVING_WALL, LIVING_FLOOR),  # living room -> bedroom
    ("y", -0.5, 0.5, BY1, CY0, LIVING_WALL, LIVING_FLOOR),  # living room -> kitchen
)
for axis, u0, u1, near, far, _wall, _floor in DOORWAYS:
    doorway(s, axis, u0, u1, near, far, FLOOR)

before = set(s.bm.faces)
rooms = [
    s.room(WX0, WX1, AY0, AY1, FLOOR, CEIL, floor=BED_FLOOR, walls=BED_WALL, ceiling=CEILING),
    s.room(WX0, WX1, BY0, BY1, FLOOR, CEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING),
    s.room(WX0, WX1, CY0, CY1, FLOOR, CEIL, floor=KITCHEN_FLOOR, walls=KITCHEN_WALL, ceiling=CEILING),
]
stretch_walls(s, set(s.bm.faces) - before, FLOOR, CEIL)
line_doorways(s, DOORWAYS, FLOOR, CEIL)
for r in rooms:
    s.room_cols(r, wall=0.2, roof=ROOF)
# the porch: its roof over the four posts, and the east eaves
for y0, y1 in ((-6.03, -5.88), (-2.01, -1.86), (2.09, 2.24), (5.76, 5.91)):
    s.col_box((-4.97, y0, -0.55), (-4.82, y1, 2.2))
s.col_box((-5.33, -6.5, 1.98), (-3.0, 6.4, 2.5))
s.col_box((3.0, -6.5, 2.3), (3.5, 6.4, 2.55))

if "--no-render" not in args():
    s.render("v_top", (0.0, 0.0, 40.0), (0.0, 0.1, 0.0), lens=35, size=(700, 1000))
    bpy.data.objects["ground"].location.z = -0.53
    for name, eye in (
        ("lamp_bed", (0.0, -4.0, 1.5)),
        ("lamp_living", (0.0, -0.4, 1.5)),
        ("lamp_kitchen", (0.0, 3.5, 1.5)),
    ):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        lamp.data.energy = 120
        lamp.location = eye
        bpy.context.scene.collection.objects.link(lamp)
    s.render("outside_front", (-12.0, -9.0, 1.5), (-3.0, -1.0, 0.5))
    s.render("outside_back", (11.0, 9.0, 2.0), (2.0, 1.0, 0.5))
    s.render("door_open", (-6.0, -5.0, 1.0), (-3.0, -0.8, 0.4), door_open=100)
    s.render("door_shut", (-6.0, -3.5, 0.9), (-3.0, -0.8, 0.4), lens=30)
    s.render("window_west", (-6.0, 2.0, 0.9), (-3.0, 2.0, 0.9), lens=30)
    s.render("inside_living", (2.5, 0.8, 0.9), (-2.8, -1.2, 0.5), lens=16)
    s.render("inside_bedroom", (2.5, -2.4, 0.9), (-1.5, -5.8, 0.5), lens=16)
    s.render("inside_kitchen", (2.5, 1.5, 0.9), (-1.0, 5.8, 0.5), lens=16)
    s.render("inside_kitchen_south", (0.0, 5.5, 0.9), (0.0, 1.2, 0.5), lens=16)
s.export()
with open(os.path.join(BUILD, "conhoos2_doors.json"), "w") as f:
    json.dump({"doors": [{"hinge": [round(v, 4) for v in o.door["hinge"]], "rz": round(o.door["rz"], 1)} for o in s.openings if o.door]}, f, indent=2)
