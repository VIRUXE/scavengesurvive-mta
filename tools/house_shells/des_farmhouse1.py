"""des_farmhouse1_ (model 16280): the Bone County farmhouse east of Fort Carson, a single-storey board house with a hip
roof, a lean-to annex on its front west corner and a porch beside it, standing in one model with its water tower and
barn (both left as they are). The house gets four rooms joined by open doorways: a living room behind the front door
on the porch and a kitchen behind it on the east side, a bedroom (taking in the annex, which the vanilla house leaves
open to the main room) and a back room behind the north door on the west side.

    blender -b --python tools/house_shells/des_farmhouse1.py [-- --no-render]

Run tools/house_shells/prep_farmhouse.py first (headless Linux renders: SHELL_ENGINE=CYCLES). Vanilla skin: single
faces, the main house the box x -11.65..-3.43, y -6.16..2.97 from the floor (the door sills, on the foundation slab's
top) at -3.17 to the eaves at -0.43; the annex x -11.65..-8.16, y -8.11..-6.16 under its own roof (collision to -0.84);
the porch x -8.16..-3.43 in front of the main house. The doors (des_adobedoor1 at the front, des_adobedoor3 at the back)
are painted 0.15 into the skin, the windows (des_ntwnwin2, des_whitewin1, trail_win2) up to 0.15 into it. Rooms stand 0.2
inside the skin; partitions are 0.2 thick. Both doors hang the same leaf, cut to the front door's 1.02 x 2.2 m. Writes
house_shell/files/des_farmhouse1.dff/.col and des_farmhouse1_door.dff/.col, build/des_farmhouse1.json and
build/des_farmhouse1_doors.json (every leaf's hinge and heading).
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
    doorway, drop_cols, line_doorways, stretch_walls,
)

common.CURTAINS["des_farmhouse1"] = "ah_curtains1"
from common import BUILD, DOOR_THICK, GLASS, GLASS_DAY, GLASS_NIGHT, OUT_DAY, OUT_NIGHT, args  # noqa: E402

FLOOR = -3.17
# west column (bedroom with the annex | back room), east column (living room | kitchen); y splits front | back
WX0, WX1, EX0, EX1 = -11.45, -8.36, -8.16, -3.63
FY0, AY0, FY1, BY0, BY1 = -5.96, -7.91, -1.10, -0.90, 2.77
WCEIL, ECEIL = -0.95, -0.60  # the west rooms stay under the annex's lower roof

# The windows are painted wooden sashes: each frame is cut from the vanilla window's own painted frame (texture, uv
# rect as Blender reads it, v up), with the vanilla pane pattern: des_ntwnwin2 brown, four by two lights a sash;
# des_whitewin1 white, two by two; trail_win2 white, two lights. Meeting rail 0.05 thick, glazing bars 0.022.
BROWN = ("des_ntwnwin2", (0.04, 0.375, 0.11, 0.53))
WHITE = ("des_whitewin1", (0.04, 0.53, 0.10, 0.77))
TRAILER = ("trail_win2", (0.02, 0.375, 0.09, 0.69))
RAIL, BAR = 0.05, 0.022
BROWN_SASH = [("h", 0.5, RAIL), ("v", 0.25, BAR), ("v", 0.5, BAR), ("v", 0.75, BAR), ("h", 0.25, BAR), ("h", 0.75, BAR)]
WHITE_SASH = [("h", 0.5, RAIL), ("v", 0.5, BAR), ("h", 0.25, BAR), ("h", 0.75, BAR)]
TRAILER_SASH = [("h", 0.5, 0.035)]
# the twelve small panes of the door (des_adobedoor1, 64 x 128): three across, four down, as uv ranges (v up)
DOOR_PANES_U = ((0.141, 0.359), (0.383, 0.594), (0.617, 0.828))
DOOR_PANES_V = ((0.398, 0.516), (0.531, 0.648), (0.664, 0.781), (0.797, 0.922))
MUNTIN_UV = (0.30, 0.06, 0.50, 0.10)  # a patch of the door's painted bottom rail, for the panes' linings


class Farmhouse(common.Shell):
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


s = Farmhouse("des_farmhouse1")
# the house's and the annex's solid boxes go; the foundation slab, porch posts, chimney, tower and barn stay
drop_cols(s, (-11.65, -6.16, -3.17, -3.43, 2.97, -0.43), (-11.65, -8.26, -3.17, -8.16, -6.16, -0.84))
s.keep_col_mesh()  # ground, porch deck, roofs (the annex's and porch's at -0.84 and up): all over the rooms

# doors, the front one first: its leaf is the model both hang
s.opening("door", "y", -1, -7.45, -6.43, FLOOR, -0.97, FY0, hinge="left", reveal=TRIM)  # front, on the porch
s.opening("door", "y", 1, -9.525, -8.505, FLOOR, -0.97, BY1, hinge="left", reveal=TRIM)  # back, north wall
# both leaves wear the front door, as much of des_adobedoor1 as its cut covered
front = s.openings[0].door
cut = [(lo, hi) for t, lo, hi in s.openings[0].removed if t == "des_adobedoor1"]
front["texture"] = "des_adobedoor1"
front["uv"] = [[min(lo[i] for lo, _hi in cut) for i in (0, 1)], [max(hi[i] for _lo, hi in cut) for i in (0, 1)]]
s.openings[1].door.update(texture=front["texture"], uv=front["uv"])

# windows
s.opening("window", "x", -1, -4.99, -3.67, -2.56, -0.99, WX0, frame=BROWN_SASH, reveal=TRIM, frame_skin=BROWN)  # bedroom, west
s.opening("window", "x", -1, -7.60, -6.82, -2.43, -1.17, WX0, frame=WHITE_SASH, reveal=TRIM, frame_skin=WHITE)  # annex, west
s.opening("window", "y", -1, -10.18, -9.58, -2.50, -1.50, AY0, frame=TRAILER_SASH, reveal=TRIM, frame_skin=TRAILER)  # annex, south
s.opening("window", "x", -1, 0.77, 1.57, -2.56, -0.99, WX0, frame=WHITE_SASH, reveal=TRIM, frame_skin=WHITE)  # back room, west
s.opening("window", "y", -1, -5.19, -4.40, -2.51, -0.94, FY0, frame=WHITE_SASH, reveal=TRIM, frame_skin=WHITE)  # living room, onto the porch
s.opening("window", "x", 1, -4.81, -3.49, -2.56, -0.99, EX1, frame=BROWN_SASH, reveal=TRIM, frame_skin=BROWN)  # living room, east
s.opening("window", "x", 1, -0.46, 0.86, -2.56, -0.99, EX1, frame=BROWN_SASH, reveal=TRIM, frame_skin=BROWN)  # kitchen, east

DOORWAYS = (
    ("x", -3.40, -2.40, EX0, WX1, LIVING_WALL, LIVING_FLOOR),  # living room -> bedroom
    ("y", -6.20, -5.20, FY1, BY0, LIVING_WALL, LIVING_FLOOR),  # living room -> kitchen
    ("x", 1.40, 2.40, EX0, WX1, KITCHEN_WALL, KITCHEN_FLOOR),  # kitchen -> back room
)
for axis, u0, u1, near, far, _wall, _floor in DOORWAYS:
    doorway(s, axis, u0, u1, near, far, FLOOR)

before = set(s.bm.faces)
rooms = [
    s.room(EX0, EX1, FY0, FY1, FLOOR, ECEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING),
    s.room(EX0, EX1, BY0, BY1, FLOOR, ECEIL, floor=KITCHEN_FLOOR, walls=KITCHEN_WALL, ceiling=CEILING),
]
east = set(s.bm.faces) - before
before = set(s.bm.faces)
rooms += [
    s.room(WX0, WX1, AY0, FY1, FLOOR, WCEIL, floor=BED_FLOOR, walls=BED_WALL, ceiling=CEILING),
    s.room(WX0, WX1, BY0, BY1, FLOOR, WCEIL, floor=LIVING_FLOOR, walls=LIVING_WALL, ceiling=CEILING),
]
stretch_walls(s, east, FLOOR, ECEIL)
stretch_walls(s, set(s.bm.faces) - before, FLOOR, WCEIL)
line_doorways(s, DOORWAYS, FLOOR, WCEIL)
for r in rooms[:2]:
    s.room_cols(r, wall=0.2, roof=-0.43)
for r in rooms[2:]:
    s.room_cols(r, wall=0.2, roof=-0.84)

if "--no-render" not in args():
    s.render("v_top", (-7.5, -2.5, 40.0), (-7.5, -2.4, 0.0), lens=35, size=(900, 900))
    bpy.data.objects["ground"].location.z = -3.77
    for name, eye in (
        ("lamp_living", (-5.9, -3.5, -1.0)),
        ("lamp_kitchen", (-5.9, 1.0, -1.0)),
        ("lamp_bed", (-9.9, -4.5, -1.3)),
        ("lamp_back", (-9.9, 1.0, -1.3)),
    ):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        lamp.data.energy = 120
        lamp.location = eye
        bpy.context.scene.collection.objects.link(lamp)
    s.render("outside_front", (-1.0, -17.0, -1.5), (-7.0, -6.0, -2.0))
    s.render("outside_back", (-14.0, 11.0, -1.0), (-8.0, 2.5, -2.0))
    s.render("door_open", (-6.2, -10.5, -1.6), (-6.9, -6.0, -2.1), door_open=100)
    s.render("door_shut", (-6.9, -8.6, -1.9), (-6.9, -6.0, -2.0), lens=30)
    s.render("window_east", (-1.4, -4.2, -1.8), (-3.5, -4.15, -1.8), lens=30)
    s.render("window_annex", (-14.0, -7.2, -1.8), (-11.6, -7.2, -1.8), lens=30)
    s.render("inside_living", (-3.9, -1.4, -1.3), (-8.0, -5.8, -2.3), lens=16)
    s.render("inside_kitchen", (-3.9, 2.5, -1.3), (-8.0, -0.8, -2.3), lens=16)
    s.render("inside_bedroom", (-8.6, -1.4, -1.5), (-11.2, -7.7, -2.3), lens=16)
    s.render("inside_back", (-8.6, -0.7, -1.5), (-11.2, 2.6, -2.3), lens=16)
s.export()
with open(os.path.join(BUILD, "des_farmhouse1_doors.json"), "w") as f:
    json.dump({"doors": [{"hinge": [round(v, 4) for v in o.door["hinge"]], "rz": round(o.door["rz"], 1)} for o in s.openings if o.door]}, f, indent=2)
