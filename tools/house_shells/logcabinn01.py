"""logcabinn01 (model 18259): the Shady Cabin in the woods of Flint County, rebuilt from nothing on the vanilla footprint
(same floor level, door and windows where they were, the west porch and deck, the lean-to at the south end), so the
loot points and the vehicle spawn around it stay where they are. The vanilla model is a paper box: one face thick,
stretched textures, holes for the door and windows, and its log walls a second model (18258, removed by house_shell).

    blender -b --python tools/house_shells/logcabinn01.py [-- --no-render] [-- --prelit]

Run tools/house_shells/prep_logcabinn.py first (headless Linux renders: SHELL_ENGINE=CYCLES). What it builds, in the
cabin's own frame (x east, y north, floor top at z 0.08; turned 2.38 degrees and moved into the model's frame at the
end, as the vanilla cabin sits skewed in its model):

* a fieldstone foundation and four walls of round logs, saddle-notched (the courses of the end walls half a log
  above the long walls', every log running past the corner), chinked, the gables boarded;
* framed windows with a sash, a cross of glazing bars and glass, shutters outside, a sill; a framed doorway with a
  braced plank door that swings (its own model, logcabinn01_door);
* a roof with a thickness: rafters with tails at the eaves, a ridge beam, tie beams with king posts and struts,
  board sheathing seen from inside, mossy shakes on top, barge boards, fascias and a ridge cap;
* a stone chimney on the north gable with a fireplace, hearth and mantel inside; a board partition with a doorway
  making two rooms; a bunk and a shelf;
* the west porch under a tin roof on posts with knee braces, the open deck with pole railings, stairs down from it,
  the deck's framing, posts and braces underneath; firewood and a bench by the door;
* the lean-to at the south end: tin sheets on rafters and purlins, three posts, a rail fence.

Lighting is baked into the prelight: every face corner gets its share of open sky and of nearby occlusion, measured by
rays against the finished mesh. Collision is a triangle mesh built beside the geometry. Writes
house_shell/files/logcabinn01.dff/.col and logcabinn01_door.dff/.col, build/logcabinn01.json and
build/logcabinn01_doors.json (the leaf's hinge and heading, and the vanilla log walls to remove).
"""
import json
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "trailer_shells"))
import common  # noqa: E402
from common import BUILD, OUT, RENDERS, TEX, args  # noqa: E402

NAME = "logcabinn01"
LOG, LOGEND, BOARD, TIMBER, DECK, FLOOR = "cw2_logwall", "gen_log_end", "sw_cabinwall01", "des_ghotwood1", "planks01", "sw_woodflloor"
ROOF, TIN, TIN2, STONE, DOOR, SHUTTER, GLASS = "sw_cabinroof", "sw_corrug", "des_oldtinroof", "stonewall_la", "cj_wooddoor4", "sw_cabshut01", "house_window"
CHINK, SOOT = (176, 166, 146), (26, 24, 22)  # untextured: the mortar between the logs, the firebox

# the cabin's frame -> the model's (the vanilla cabin is skewed in its model; measured off its walls)
SKEW, SHIFT = 2.38, (0.02, -1.19, 0.0)
F = 0.08  # floor top: the loot points stand on it
GROUND = -2.45  # as deep as the vanilla posts reach
HX, HY = 5.25, 8.15  # centre lines of the long (east, west) and end (north, south) log walls
R, COURSE = 0.17, 0.32  # log radius, course height
LONG_Z = [0.17 + COURSE * i for i in range(10)]  # the long walls' courses; top at 3.22
END_Z = [0.01 + COURSE * i for i in range(10)]  # the end walls': half a course off; top at 3.06
PLATE = 3.27  # underside of the roof over the long walls' centre lines
PITCH = 0.5  # rise per metre
ROOF_T = 0.10
EAVE, VERGE = 6.0, HY + 0.7  # the roof reaches |x| 6.0 and |y| 8.85
# openings, on course joints: (u0, u1, z0, z1)
WIN_LONG_Z, WIN_END_Z = (0.97, 2.25), (1.13, 2.41)
DOOR_U, DOOR_Z = (0.32, 1.62), (F, 2.25)
WEST = [(-5.1, -4.0) + WIN_LONG_Z, DOOR_U + DOOR_Z, (5.05, 6.15) + WIN_LONG_Z]
EAST = [(-5.1, -4.0) + WIN_LONG_Z, (5.05, 6.15) + WIN_LONG_Z]
NORTH = [(-2.8, -1.7) + WIN_END_Z, (-0.6, 0.6, F, 1.45), (1.7, 2.8) + WIN_END_Z]  # the middle one is the firebox
SOUTH = [(-2.8, -1.7) + WIN_END_Z, (1.7, 2.8) + WIN_END_Z]
PART_Y, PART_DOOR = -1.8, (1.0, 2.1, F, 2.15)  # the partition and its doorway
# west porch (roofed) and open deck, stairs down from the deck's north edge
PORCH = (-9.15, -5.42, -4.0, 8.6)  # x0, x1, y0, y1
DECK_OPEN = (-11.6, -5.42, -9.3, -4.0)
STAIR = (-11.45, -10.1, -4.0, 0.18, 0.28)  # x0, x1, top y, rise, run (going north, as many risers as reach the ground)
CARPORT = (-4.45, 5.45, -8.36, -14.45, 3.30, 0.12)  # x0, x1, y at the wall, y at the eave, z at the wall, fall per metre

rnd = random.Random(18259)
Z = Vector((0, 0, 1))


# the ground round the cabin, in the model's frame, measured in game (getGroundPosition on a 2 m grid): heights along
# x = -10 by y, falling 0.015 per metre to the east. It lies level with the floor at the south end and 2 m under it
# at the north end of the porch.
GROUND_Y = [(-16, 0.5), (-14, 0.3), (-12, 0.1), (-10, -0.1), (-8, -0.35), (-6, -0.6), (-4, -0.8), (-2, -1.0), (0, -1.2), (2, -1.5), (4, -1.7), (6, -1.9), (8, -1.7), (10, -1.4)]


def ground(x, y):
    """Height of the terrain under a point of the cabin's frame."""
    a = math.radians(SKEW)
    mx = x * math.cos(a) - y * math.sin(a) + SHIFT[0]
    my = x * math.sin(a) + y * math.cos(a) + SHIFT[1]
    pts = GROUND_Y
    if my <= pts[0][0]:
        z = pts[0][1]
    elif my >= pts[-1][0]:
        z = pts[-1][1]
    else:
        z = next(z0 + (z1 - z0) * (my - y0) / (y1 - y0) for (y0, z0), (y1, z1) in zip(pts, pts[1:]) if y0 <= my <= y1)
    return z - 0.015 * (mx + 10)


def zu(x):
    """Underside of the main roof at x."""
    return PLATE + (HX - abs(x)) * PITCH


class Cabin:
    def __init__(self):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        self.mesh = bpy.data.meshes.new(NAME)
        self.obj = bpy.data.objects.new(NAME, self.mesh)
        bpy.context.scene.collection.objects.link(self.obj)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.day, self.night = self.bm.loops.layers.color.new("Col"), self.bm.loops.layers.color.new("Col.001")
        self.mats = {}
        self.glass = []  # (verts, uvs), made last so the game draws the panes after what shows through them
        self.col = bmesh.new()
        self.col_mats = {}
        self.col_mesh = bpy.data.meshes.new(NAME + "_col")

    # ---- materials -------------------------------------------------------------------------------------------
    def mat(self, key):
        if key in self.mats:
            return self.mats[key]
        textured = isinstance(key, str)
        m = bpy.data.materials.new(key if textured else "rgb_%d_%d_%d" % key)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        bsdf.inputs["Roughness"].default_value = 0.85
        if textured:
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            path = os.path.join(TEX, key.lower() + ".png")
            node.image = bpy.data.images.load(path) if os.path.exists(path) else bpy.data.images.new(key + ".png", 8, 8)
            node.image.name = key.lower() + ".png"
            m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            if key == GLASS:
                m.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
                if hasattr(m, "surface_render_method"):
                    m.surface_render_method = "BLENDED"
        else:
            bsdf.inputs["Base Color"].default_value = (key[0] / 255, key[1] / 255, key[2] / 255, 1.0)
        self.mesh.materials.append(m)
        self.mats[key] = len(self.mesh.materials) - 1
        return self.mats[key]

    # ---- faces -----------------------------------------------------------------------------------------------
    def poly(self, vs, tex, uvs=None, scale=1.0, udir=None, vdir=None, facing=None, off=(0.0, 0.0)):
        """One polygon. `facing`: a direction its normal must agree with (the vertex order is turned if not). UVs are
        given per vertex, or planar at `scale` metres per repeat: `udir` or `vdir` names the direction the texture's
        u or v runs along (v is the grain of boards, the fall of roof sheets)."""
        vs = [Vector(v) for v in vs]
        n = (vs[1] - vs[0]).cross(vs[2] - vs[1])
        if n.length < 1e-9 and len(vs) > 3:
            n = (vs[2] - vs[1]).cross(vs[3] - vs[2])
        if facing is not None and n.dot(Vector(facing)) < 0:
            vs.reverse()
            if uvs is not None:
                uvs = list(reversed(uvs))
            n = -n
        if uvs is None:
            n.normalize()
            if vdir is not None:
                v = Vector(vdir) - n * n.dot(Vector(vdir))
                v.normalize()
                u = v.cross(n)
            else:
                if udir is not None:
                    u = Vector(udir) - n * n.dot(Vector(udir))
                elif abs(n.z) < 0.9:
                    u = Z.cross(n)
                else:
                    u = Vector((1, 0, 0)) - n * n.x
                u.normalize()
                v = n.cross(u)
            uvs = [(p.dot(u) / scale + off[0], p.dot(v) / scale + off[1]) for p in vs]
        f = self.bm.faces.new([self.bm.verts.new(p) for p in vs])
        f.material_index = self.mat(tex)
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
        return f

    def grid(self, o, du, dv, nu, nv, tex, facing, two=None, **kw):
        """A parallelogram o + s*du + t*dv in nu x nv cells (so the baked light has corners to vary over), facing
        `facing`; `two`: the texture of its other side, if it has one."""
        o, du, dv = Vector(o), Vector(du), Vector(dv)
        faces = []
        for i in range(nu):
            for j in range(nv):
                q = [o + du * (a / nu) + dv * (b / nv) for a, b in ((i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1))]
                faces.append(self.poly(q, tex, facing=facing, **kw))
                if two:
                    self.poly(q, two, facing=-Vector(facing), **kw)
        return faces

    def box(self, lo, hi, tex, scale=1.0, skip=(), **kw):
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        quads = {
            "+x": ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], (1, 0, 0)),
            "-x": ([(x0, y0, z0), (x0, y1, z0), (x0, y1, z1), (x0, y0, z1)], (-1, 0, 0)),
            "+y": ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], (0, 1, 0)),
            "-y": ([(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)], (0, -1, 0)),
            "+z": ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], (0, 0, 1)),
            "-z": ([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], (0, 0, -1)),
        }
        return [self.poly(q, tex, scale=scale, facing=n, **kw) for k, (q, n) in quads.items() if k not in skip]

    def beam(self, p0, p1, w, h, tex=TIMBER, up=Z, caps=(True, True)):
        """A squared timber from p0 to p1, `w` across and `h` deep (along `up`, squared off against its run); each
        face wears one board of the timber texture along its length."""
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        side = d.cross(Vector(up))
        if side.length < 1e-6:
            side = d.cross(Vector((1, 0, 0)))
        side.normalize()
        upv = side.cross(d)
        length = (p1 - p0).length
        corners = [side * (sx * w / 2) + upv * (sz * h / 2) for sx, sz in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
        u0 = rnd.random()
        faces = []
        for i in range(4):
            a, b = corners[i], corners[(i + 1) % 4]
            band = rnd.randrange(5) * 0.2
            width = (b - a).length
            v0, v1 = band + 0.02, band + min(0.18, 0.02 + width / 0.9)
            uvs = [(u0, v0), (u0 + length / 1.4, v0), (u0 + length / 1.4, v1), (u0, v1)]
            faces.append(self.poly([p0 + a, p1 + a, p1 + b, p0 + b], tex, uvs=uvs, facing=a + b))
        for end, p, n in ((0, p0, -d), (1, p1, d)):
            if caps[end]:
                faces.append(self.poly([p + c for c in corners], tex, uvs=[(0.1, 0.02), (0.2, 0.02), (0.2, 0.12), (0.1, 0.12)], facing=n))
        return faces

    def cyl(self, p0, p1, r, out, sides=8, mode="log", caps=(True, True), r1=None):
        """A round timber from p0 to p1. mode 'log': the half turned to `out` wears one log of the log-wall texture
        (its own shading running from the joint below to the joint above), the other half the next one; 'pole': one
        board of the timber texture wrapped round."""
        p0, p1 = Vector(p0), Vector(p1)
        d = (p1 - p0).normalized()
        out = Vector(out) - d * d.dot(Vector(out))
        out.normalize()
        upv = d.cross(out)
        if upv.z < 0 and abs(upv.z) > 1e-6:
            upv = -upv
        length = (p1 - p0).length
        r1 = r if r1 is None else r1
        ring = [(math.cos(2 * math.pi * k / sides), math.sin(2 * math.pi * k / sides)) for k in range(sides)]
        u0 = rnd.random()
        band = rnd.randrange(8)
        pole = rnd.randrange(5) * 0.2
        faces = []
        for k in range(sides):
            (c0, s0), (c1, s1) = ring[k], ring[(k + 1) % sides]
            a0, a1 = 360.0 * k / sides, 360.0 * (k + 1) / sides
            if mode == "log":
                mid = (a0 + a1) / 2
                if mid < 90 or mid > 270:  # outer half, joint below (-90) to joint above (+90)
                    f0, f1 = (((a0 + 90) % 360) / 180, ((a1 + 90) % 360) / 180 or 1.0)
                    b = band
                else:
                    f0, f1 = (270 - a0) / 180, (270 - a1) / 180
                    b = band + 1
                v0, v1 = 1 - (b + 1) * 0.1 + f0 * 0.1, 1 - (b + 1) * 0.1 + f1 * 0.1
                ul = length / 3.4
            else:
                v0, v1 = pole + 0.02 + 0.16 * k / sides, pole + 0.02 + 0.16 * (k + 1) / sides
                ul = length / 1.4
            q = [p0 + (out * c0 + upv * s0) * r, p1 + (out * c0 + upv * s0) * r1, p1 + (out * c1 + upv * s1) * r1, p0 + (out * c1 + upv * s1) * r]
            faces.append(self.poly(q, LOG if mode == "log" else TIMBER, uvs=[(u0, v0), (u0 + ul, v0), (u0 + ul, v1), (u0, v1)], facing=out * (c0 + c1) + upv * (s0 + s1)))
        for end, p, n, rr in ((0, p0, -d, r), (1, p1, d, r1)):
            if caps[end]:
                vs = [p + (out * c + upv * s) * rr for c, s in ring]
                uvs = [(0.5 + 0.47 * c, 0.5 + 0.47 * s) for c, s in ring]
                faces.append(self.poly(vs, LOGEND, uvs=uvs, facing=n))
        return faces

    @staticmethod
    def turn(faces, pivot, axis, degrees):
        m = Matrix.Translation(Vector(pivot)) @ Matrix.Rotation(math.radians(degrees), 4, Vector(axis)) @ Matrix.Translation(-Vector(pivot))
        for v in {v for f in faces for v in f.verts}:
            v.co = m @ v.co

    # ---- collision -------------------------------------------------------------------------------------------
    def col_mat(self, kind):
        """kind: (surface, outside): wood, stone or tin; outside faces light a ped standing on them as daylight."""
        if kind not in self.col_mats:
            surface, outside = kind
            m = bpy.data.materials.new("col_%s_%s" % (surface, "out" if outside else "in"))
            m.dff.col_mat_index = {"wood": 43, "stone": 35, "tin": 167}[surface]
            m.dff.col_brightness = 1
            m.dff.col_day_light, m.dff.col_night_light = (13, 2) if outside else (8, 1)
            self.col_mesh.materials.append(m)
            self.col_mats[kind] = len(self.col_mesh.materials) - 1
        return self.col_mats[kind]

    def ctri(self, vs, surface="wood", outside=True):
        vs = [Vector(v) for v in vs]
        mi = self.col_mat((surface, outside))
        for tri in ([vs[0], vs[1], vs[2]],) if len(vs) == 3 else ([vs[0], vs[1], vs[2]], [vs[0], vs[2], vs[3]]):
            f = self.col.faces.new([self.col.verts.new(p) for p in tri])
            f.material_index = mi

    def cbox(self, lo, hi, surface="wood", outside=True):
        x0, y0, z0 = (min(a, b) for a, b in zip(lo, hi))
        x1, y1, z1 = (max(a, b) for a, b in zip(lo, hi))
        for q in (
            [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
            [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)], [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],
        ):
            self.ctri(q, surface, outside)

    # ---- walls -----------------------------------------------------------------------------------------------
    @staticmethod
    def wp(axis, depth, u, z):
        """A point of a wall facing `axis`: `depth` along it, `u` along the wall."""
        return Vector((depth, u, z)) if axis == "x" else Vector((u, depth, z))

    def wbox(self, axis, d0, d1, u0, u1, z0, z1, tex, **kw):
        a, b = self.wp(axis, d0, u0, z0), self.wp(axis, d1, u1, z1)
        return self.box([min(a[i], b[i]) for i in range(3)], [max(a[i], b[i]) for i in range(3)], tex, **kw)

    def log_wall(self, axis, c, half, zs, holes):
        """A wall of logs on the line `c` of `axis`, from -half to half along it and past both corners, less the
        holes; then the chinking, a mortar slab either side of the centre line that shows between the logs."""
        s = 1 if c > 0 else -1
        out = self.wp(axis, s, 0, 0)
        for zc in zs:
            cuts = sorted((h[0], h[1]) for h in holes if h[2] < zc < h[3])
            a = -half - rnd.uniform(0.3, 0.46)
            spans = []
            for h0, h1 in cuts:
                spans.append((a, h0, a < -half, False))
                a = h1
            spans.append((a, half + rnd.uniform(0.3, 0.46), a < -half, True))
            for u0, u1, cap0, cap1 in spans:
                r = R + rnd.uniform(-0.008, 0.012)
                d = c + rnd.uniform(-0.012, 0.012)
                self.cyl(self.wp(axis, d, u0, zc), self.wp(axis, d, u1, zc), r, out, sides=12, caps=(cap0, cap1))
        z0, z1 = zs[0] - R, zs[-1] + R
        us = sorted({-half, half} | {v for h in holes for v in h[:2]})
        zz = sorted({z0, z1} | {min(z1, max(z0, v)) for h in holes for v in h[2:]})
        for i in range(len(us) - 1):
            for j in range(len(zz) - 1):
                cu, cz = (us[i] + us[i + 1]) / 2, (zz[j] + zz[j + 1]) / 2
                if any(h[0] < cu < h[1] and h[2] < cz < h[3] for h in holes):
                    continue
                for side in (1, -1):
                    d = c + side * 0.078
                    q = [self.wp(axis, d, us[i], zz[j]), self.wp(axis, d, us[i + 1], zz[j]), self.wp(axis, d, us[i + 1], zz[j + 1]), self.wp(axis, d, us[i], zz[j + 1])]
                    self.poly(q, CHINK, facing=out * side * s)

    def lining(self, axis, c, u0, u1, z0, z1, sill=True, depth=0.2):
        """The boards lining a hole through a log wall: jambs and head (and sill), facing the hole."""
        mid = self.wp(axis, c, (u0 + u1) / 2, (z0 + z1) / 2)
        ring = [(u0, z0), (u1, z0), (u1, z1), (u0, z1)]
        for i in range(4):
            if i == 0 and not sill:
                continue
            (ua, za), (ub, zb) = ring[i], ring[(i + 1) % 4]
            q = [self.wp(axis, c - depth, ua, za), self.wp(axis, c - depth, ub, zb), self.wp(axis, c + depth, ub, zb), self.wp(axis, c + depth, ua, za)]
            centre = sum(q, Vector()) / 4
            band = rnd.randrange(5) * 0.2
            length = math.hypot(ub - ua, zb - za)
            self.poly(q, TIMBER, uvs=[(0, band + 0.02), (length / 1.4, band + 0.02), (length / 1.4, band + 0.18), (0, band + 0.18)], facing=mid - centre)

    def casing(self, axis, c, s, u0, u1, z0, z1, sill=True):
        """Boards round a hole on one face of a wall (s: +1 the outer face of a wall at positive c)."""
        d0, d1 = c + s * 0.165, c + s * 0.215
        w = 0.11
        self.beam(self.wp(axis, (d0 + d1) / 2, u0 - w, z1 + w / 2), self.wp(axis, (d0 + d1) / 2, u1 + w, z1 + w / 2), 0.05, w, up=self.wp(axis, 0, 0, 1))
        for u in (u0 - w / 2, u1 + w / 2):
            self.beam(self.wp(axis, (d0 + d1) / 2, u, z0 - (w if sill else 0)), self.wp(axis, (d0 + d1) / 2, u, z1), w, 0.05, up=self.wp(axis, 1, 0, 0), caps=(sill, False))
        if sill:
            self.beam(self.wp(axis, c + s * 0.2, u0 - 0.16, z0 - 0.03), self.wp(axis, c + s * 0.2, u1 + 0.16, z0 - 0.03), 0.17, 0.06, up=self.wp(axis, 0, 0, 1))

    def window(self, axis, c, hole, shutters=("open", "open")):
        u0, u1, z0, z1 = hole
        s = 1 if c > 0 else -1
        self.lining(axis, c, u0, u1, z0, z1)
        self.casing(axis, c, s, u0, u1, z0, z1)
        self.casing(axis, c, -s, u0, u1, z0, z1)
        bar, t = 0.05, 0.025
        for a, b in ((u0, u0 + bar), (u1 - bar, u1)):  # stiles
            self.wbox(axis, c - t, c + t, a, b, z0, z1, TIMBER, scale=0.5, vdir=Z)
        for a, b in ((z0, z0 + bar), (z1 - bar, z1)):  # rails
            self.wbox(axis, c - t * 0.9, c + t * 0.9, u0 + bar, u1 - bar, a, b, TIMBER, scale=0.5)
        um, zm = (u0 + u1) / 2, (z0 + z1) / 2
        self.wbox(axis, c - t * 0.7, c + t * 0.7, um - 0.016, um + 0.016, z0 + bar, z1 - bar, TIMBER, scale=0.5, vdir=Z)
        self.wbox(axis, c - t * 0.6, c + t * 0.6, u0 + bar, u1 - bar, zm - 0.016, zm + 0.016, TIMBER, scale=0.5)
        q = [self.wp(axis, c, u0 + bar, z0 + bar), self.wp(axis, c, u1 - bar, z0 + bar), self.wp(axis, c, u1 - bar, z1 - bar), self.wp(axis, c, u0 + bar, z1 - bar)]
        self.glass.append((q, [(0, 0), (1, 0), (1, 1), (0, 1)]))
        out = self.wp(axis, s, 0, 0)
        d0, d1 = c + s * 0.218, c + s * 0.25
        w = (u1 - u0) / 2 + 0.03
        for k, state in enumerate(shutters):
            if not state:
                continue
            a, b = (u0 - 0.13 - w, u0 - 0.13) if k == 0 else (u1 + 0.13, u1 + 0.13 + w)
            faces = []
            za, zb = z0 - 0.03, z1 + 0.03
            uv = [(0, 0), (1, 0), (1, 1), (0, 1)] if k == 0 else [(1, 0), (0, 0), (0, 1), (1, 1)]
            front = [self.wp(axis, d1, a, za), self.wp(axis, d1, b, za), self.wp(axis, d1, b, zb), self.wp(axis, d1, a, zb)]
            back = [self.wp(axis, d0, a, za), self.wp(axis, d0, b, za), self.wp(axis, d0, b, zb), self.wp(axis, d0, a, zb)]
            faces.append(self.poly(front, SHUTTER, uvs=uv, facing=out))
            faces.append(self.poly(back, SHUTTER, uvs=uv, facing=-out))
            for i in range(4):
                j = (i + 1) % 4
                e = [back[i], back[j], front[j], front[i]]
                faces.append(self.poly(e, TIMBER, uvs=[(0, 0.02), (0.3, 0.02), (0.3, 0.06), (0, 0.06)], facing=sum(e, Vector()) / 4 - sum(front + back, Vector()) / 8))
            if state == "askew":  # hanging by its upper hinge
                hinge = self.wp(axis, d0, b if k == 0 else a, zb)
                self.turn(faces, hinge, out, 11 if (k == 0) == (s > 0) == (axis == "x") else -11)

    # ---- the parts -------------------------------------------------------------------------------------------
    def foundation(self):
        x, y = HX + 0.27, HY + 0.27
        for lo, hi, facing in (
            ((-x, -y, GROUND), (-x, y, -0.03), (-1, 0, 0)), ((x, -y, GROUND), (x, y, -0.03), (1, 0, 0)),
            ((-x, -y, GROUND), (x, -y, -0.03), (0, -1, 0)), ((-x, y, GROUND), (x, y, -0.03), (0, 1, 0)),
        ):
            du = Vector((hi[0] - lo[0], hi[1] - lo[1], 0))
            self.grid(lo, du, (0, 0, hi[2] - lo[2]), max(1, round(du.length / 1.8)), 2, STONE, facing, scale=1.25)
        self.grid((-x, -y, -0.03), (2 * x, 0, 0), (0, 2 * y, 0), 1, 1, STONE, (0, 0, 1), scale=1.25)  # the ledge under the sill logs
        self.cbox((-x, -y, GROUND), (x, y, F), "wood", False)  # foundation and floor in one block

    def floor(self):
        x, y = HX - 0.1, HY - 0.1
        self.grid((-x, -y, F), (2 * x, 0, 0), (0, 2 * y, 0), 9, 14, FLOOR, (0, 0, 1), scale=2.6, vdir=(0, 1, 0))

    def walls(self):
        self.log_wall("x", -HX, HY, LONG_Z, WEST)
        self.log_wall("x", HX, HY, LONG_Z, EAST)
        self.log_wall("y", HY, HX, END_Z, NORTH)
        self.log_wall("y", -HY, HX, END_Z, SOUTH)
        for i, h in enumerate(WEST):
            if h[:2] == DOOR_U:
                self.lining("x", -HX, *h, sill=False)
                self.casing("x", -HX, -1, *h, sill=False)
                self.casing("x", -HX, 1, *h, sill=False)
                self.wbox("x", -HX - 0.2, -HX + 0.2, h[0], h[1], F - 0.02, F + 0.025, TIMBER, scale=0.6)  # threshold
            else:
                self.window("x", -HX, h, shutters=("open", "askew") if i == 0 else ("open", "open"))
        self.window("x", HX, EAST[0], shutters=("open", None))
        self.window("x", HX, EAST[1], shutters=("askew", "open"))
        self.window("y", HY, NORTH[0], shutters=(None, None))
        self.window("y", HY, NORTH[2], shutters=(None, None))
        self.window("y", -HY, SOUTH[0], shutters=("open", "open"))
        self.window("y", -HY, SOUTH[1], shutters=("open", None))
        # gables: boards outside and inside, from the top log to the roof
        base = END_Z[-1] + R - 0.04
        for s in (1, -1):
            for face, tex in ((s * (HY + 0.07), BOARD), (s * (HY - 0.07), BOARD)):
                n = 10
                xe = HX + 0.2
                for i in range(n):
                    xa, xb = -xe + 2 * xe * i / n, -xe + 2 * xe * (i + 1) / n
                    q = [(xa, face, base), (xb, face, base), (xb, face, zu(xb) + 0.02), (xa, face, zu(xa) + 0.02)]
                    self.poly(q, tex, scale=2.2, facing=(0, s if abs(face) > HY else -s, 0))
            self.beam((-HX - 0.2, s * (HY + 0.1), base + 0.05), (HX + 0.2, s * (HY + 0.1), base + 0.05), 0.04, 0.14)  # drip board
            self.ctri([(-HX - 0.2, s * HY, base), (HX + 0.2, s * HY, base), (0, s * HY, zu(0))], "wood", True)
        top = LONG_Z[-1] + R
        t = 0.2
        (d0, d1) = DOOR_U
        self.cbox((-HX - t, -HY - t, F), (-HX + t, d0, top))
        self.cbox((-HX - t, d1, F), (-HX + t, HY + t, top))
        self.cbox((-HX - t, d0, DOOR_Z[1]), (-HX + t, d1, top))
        self.cbox((HX - t, -HY - t, F), (HX + t, HY + t, top))
        self.cbox((-HX, HY - t, F), (HX, HY + t, top))
        self.cbox((-HX, -HY - t, F), (HX, -HY + t, top))

    def roof(self):
        ridge_t = zu(0) + ROOF_T
        for s in (1, -1):
            run = Vector((s * EAVE, 0, -EAVE * PITCH))
            up = -run.normalized()
            n = Vector((s * PITCH, 0, 1))
            for f in self.grid((0, -VERGE, ridge_t), (0, 2 * VERGE, 0), run, 9, 4, ROOF, n):  # the shakes run up the slope: v along it
                for loop in f.loops:
                    p = loop.vert.co
                    loop[self.uv].uv = (p.y / 1.7, (p - Vector((0, 0, ridge_t))).dot(up) / 1.7)
            self.grid((0, -VERGE, zu(0)), (0, 2 * VERGE, 0), run, 9, 4, BOARD, -n, scale=2.2, vdir=(0, 1, 0))
            ex, ez = s * EAVE, zu(EAVE)
            self.poly([(ex, -VERGE, ez), (ex, VERGE, ez), (ex, VERGE, ez + ROOF_T), (ex, -VERGE, ez + ROOF_T)], TIMBER, uvs=[(0, 0.02), (12, 0.02), (12, 0.1), (0, 0.1)], facing=(s, 0, 0))
            self.beam((ex + s * 0.02, -VERGE, ez - 0.03), (ex + s * 0.02, VERGE, ez - 0.03), 0.035, 0.19)  # fascia
            for y in (-VERGE - 0.02, VERGE + 0.02):  # barge boards
                self.beam((0, y, zu(0) + 0.0), (ex, y, ez + 0.0), 0.045, 0.24)
            for i in range(17):  # rafters, their tails out under the eave
                y = -8.45 + 16.9 * i / 16
                self.beam((s * 0.06, y, zu(0.06) - 0.085), (s * (EAVE - 0.06), y, zu(EAVE - 0.06) - 0.085), 0.07, 0.17, caps=(False, True))
            # ridge cap: a tin strip either side
            a, b = Vector((0, 0, ridge_t + 0.035)), Vector((s * 0.3, 0, ridge_t + 0.035 - 0.3 * PITCH + 0.012))
            self.grid(a + Vector((0, -VERGE - 0.03, 0)), (0, 2 * VERGE + 0.06, 0), b - a, 6, 1, TIN, n, scale=1.6, vdir=(0, 1, 0))
            self.ctri([(0, -VERGE, ridge_t), (0, VERGE, ridge_t), (ex, VERGE, ez + ROOF_T), (ex, -VERGE, ez + ROOF_T)], "wood", True)
        self.beam((0, -8.6, zu(0) - 0.2), (0, 8.6, zu(0) - 0.2), 0.12, 0.26)  # ridge beam
        for y in (-5.2, PART_Y, 1.6, 5.0):  # tie beams, king posts and struts
            zt = LONG_Z[-1] - 0.02  # let into the top logs, so the ends stay under the roof
            self.cyl((-HX + 0.08, y, zt), (HX - 0.08, y, zt), 0.125, (0, 1, 0), caps=(False, False))
            self.beam((0, y, zt + 0.1), (0, y, zu(0) - 0.3), 0.14, 0.14, up=(0, 1, 0), caps=(False, False))
            for s in (1, -1):
                self.beam((s * 0.12, y, zt + 0.35), (s * 2.7, y, zu(2.7) - 0.22), 0.09, 0.12, up=(0, 1, 0), caps=(False, False))

    def chimney(self):
        y0, y1 = HY + 0.12, HY + 1.0
        grid = dict(scale=1.25)
        self.box((-0.95, y0, GROUND), (0.95, y1, 3.5), STONE, skip=("-z", "+z"), **grid)
        # shoulders in to the stack
        base = [(-0.95, y0, 3.5), (0.95, y0, 3.5), (0.95, y1, 3.5), (-0.95, y1, 3.5)]
        neck = [(-0.48, y0 + 0.08, 4.25), (0.48, y0 + 0.08, 4.25), (0.48, y1 - 0.04, 4.25), (-0.48, y1 - 0.04, 4.25)]
        mid = Vector((0, (y0 + y1) / 2, 3.9))
        for i in range(4):
            j = (i + 1) % 4
            q = [base[i], base[j], neck[j], neck[i]]
            self.poly(q, STONE, scale=1.25, facing=sum((Vector(p) for p in q), Vector()) / 4 - mid)
        self.box(neck[0], (0.48, y1 - 0.04, 6.85), STONE, skip=("-z", "+z"), **grid)
        self.box((-0.56, y0 + 0.0, 6.85), (0.56, y1 + 0.04, 6.98), STONE, **grid)  # cap
        self.box((-0.3, y0 + 0.24, 6.98), (0.3, y1 - 0.2, 7.0), SOOT, skip=("-z",))  # the flue's mouth
        self.cbox((-0.95, y0, GROUND), (0.95, y1, 3.5), "stone")
        self.cbox((-0.56, y0, 3.5), (0.56, y1, 6.98), "stone")
        # inside: the surround round the firebox, the breast above it, hearth and mantel
        f0, f1 = HY - 0.55, HY - 0.12
        (a, b, za, zb) = NORTH[1]
        za, zb = F + 0.12, zb - 0.2
        us, zs = [-1.15, a + 0.05, b - 0.05, 1.15], [F, za, zb, 2.45]
        for i in range(3):
            for j in range(3):
                if i == 1 and j == 1:
                    continue
                self.poly([(us[i], f0, zs[j]), (us[i + 1], f0, zs[j]), (us[i + 1], f0, zs[j + 1]), (us[i], f0, zs[j + 1])], STONE, scale=1.25, facing=(0, -1, 0))
        for x, n in ((-1.15, (-1, 0, 0)), (1.15, (1, 0, 0))):
            self.poly([(x, f0, F), (x, f1, F), (x, f1, 2.45), (x, f0, 2.45)], STONE, scale=1.25, facing=n)
        self.poly([(-1.15, f0, 2.45), (1.15, f0, 2.45), (0.7, f0 + 0.1, 2.9), (-0.7, f0 + 0.1, 2.9)], STONE, scale=1.25, facing=(0, -1, 0.3))
        for x, n in ((-1, (-1, 0, 0.3)), (1, (1, 0, 0.3))):
            self.poly([(x * 1.15, f0, 2.45), (x * 1.15, f1, 2.45), (x * 0.7, f1, 2.9), (x * 0.7, f0 + 0.1, 2.9)], STONE, scale=1.25, facing=n)
        top = zu(0.7) + 0.02
        self.box((-0.7, f0 + 0.1, 2.9), (0.7, f1, top), STONE, skip=("+y", "-z", "+z"), **grid)
        back = HY + 0.5
        fb = [(a + 0.05, f0, za), (b - 0.05, f0, za), (b - 0.05, f0, zb), (a + 0.05, f0, zb)]
        bk = [(a + 0.18, back, za), (b - 0.18, back, za), (b - 0.18, back, zb - 0.15), (a + 0.18, back, zb - 0.15)]
        centre = Vector((0, (f0 + back) / 2, (za + zb) / 2))
        for i in range(4):
            j = (i + 1) % 4
            q = [fb[i], fb[j], bk[j], bk[i]]
            self.poly(q, SOOT, facing=centre - sum((Vector(p) for p in q), Vector()) / 4)
        self.poly(bk, SOOT, facing=(0, -1, 0))
        self.box((-1.3, f0 - 0.6, F), (1.3, f0, F + 0.12), STONE, skip=("-z", "+y"), **grid)  # hearth
        self.beam((-1.35, f0 - 0.09, 1.56), (1.35, f0 - 0.09, 1.56), 0.2, 0.13)  # mantel
        self.cbox((-1.15, f0, F), (a + 0.05, HY, 2.45), "stone", False)
        self.cbox((b - 0.05, f0, F), (1.15, HY, 2.45), "stone", False)
        self.cbox((a, f0, zb), (b, HY, 2.45), "stone", False)
        self.cbox((-0.7, f0 + 0.1, 2.45), (0.7, HY, top), "stone", False)
        self.cbox((-1.3, f0 - 0.6, F), (1.3, f0, F + 0.12), "stone", False)

    def partition(self):
        x0, x1, top = -HX + 0.17, HX - 0.17, LONG_Z[-1] + R
        (a, b, za, zb) = PART_DOOR
        us, zs = [x0, a, b, x1], [F, zb, top]
        for side in (1, -1):
            y = PART_Y + side * 0.05
            for i in range(3):
                for j in range(2):
                    if i == 1 and j == 0:
                        continue
                    n = max(1, round((us[i + 1] - us[i]) / 1.6))
                    self.grid((us[i], y, zs[j]), (us[i + 1] - us[i], 0, 0), (0, 0, zs[j + 1] - zs[j]), n, 1, BOARD, (0, side, 0), scale=2.2)
        self.lining("y", PART_Y, a, b, za, zb, sill=False, depth=0.07)
        for side in (1, -1):
            d = PART_Y + side * 0.075
            self.beam((a - 0.05, d, F), (a - 0.05, d, zb + 0.1), 0.1, 0.04, up=(0, 1, 0), caps=(False, False))
            self.beam((b + 0.05, d, F), (b + 0.05, d, zb + 0.1), 0.1, 0.04, up=(0, 1, 0), caps=(False, False))
            self.beam((a - 0.1, d, zb + 0.05), (b + 0.1, d, zb + 0.05), 0.04, 0.1)
            self.beam((x0, d, F + 0.06), (a - 0.1, d, F + 0.06), 0.03, 0.12)  # skirting
            self.beam((b + 0.1, d, F + 0.06), (x1, d, F + 0.06), 0.03, 0.12)
        self.cbox((x0, PART_Y - 0.06, F), (a, PART_Y + 0.06, top), "wood", False)
        self.cbox((b, PART_Y - 0.06, F), (x1, PART_Y + 0.06, top), "wood", False)
        self.cbox((a, PART_Y - 0.06, zb), (b, PART_Y + 0.06, top), "wood", False)

    def furniture(self):
        # a bunk in the back room's south-east corner
        x0, x1, y0, y1 = HX - 0.2 - 1.0, HX - 0.2, -HY + 0.25, -HY + 0.25 + 2.05
        for x in (x0 + 0.04, x1 - 0.04):
            for y in (y0 + 0.04, y1 - 0.04):
                self.beam((x, y, F), (x, y, F + 1.75), 0.08, 0.08, up=(0, 1, 0), caps=(False, True))
        for z in (F + 0.45, F + 1.35):
            self.grid((x0, y0, z), (x1 - x0, 0, 0), (0, y1 - y0, 0), 1, 2, DECK, (0, 0, 1), two=DECK, scale=0.75, udir=(1, 0, 0))
            for y in (y0 + 0.02, y1 - 0.02):
                self.beam((x0, y, z - 0.07), (x1, y, z - 0.07), 0.03, 0.16)
            for x in (x0 + 0.02, x1 - 0.02):
                self.beam((x, y0, z - 0.07), (x, y1, z - 0.07), 0.03, 0.16)
        self.cbox((x0, y0, F), (x1, y1, F + 0.47), "wood", False)
        self.cbox((x0, y0, F + 1.25), (x1, y1, F + 1.37), "wood", False)
        # a shelf on brackets along the main room's east wall
        xs = HX - 0.19
        self.grid((xs - 0.3, 1.0, F + 1.55), (0.3, 0, 0), (0, 3.4, 0), 1, 2, DECK, (0, 0, 1), two=DECK, scale=0.75, udir=(0, 1, 0))
        self.beam((xs - 0.3, 1.0, F + 1.53), (xs - 0.3, 4.4, F + 1.53), 0.025, 0.05)
        for y in (1.25, 2.7, 4.15):
            self.beam((xs - 0.02, y, F + 1.2), (xs - 0.27, y, F + 1.52), 0.04, 0.05, up=(0, 1, 0), caps=(False, False))

    def pole_rail(self, p0, p1, posts=True):
        """A railing of peeled poles from p0 to p1 (points on the deck): posts no more than 1.5 m apart, three rails."""
        p0, p1 = Vector(p0), Vector(p1)
        length = (p1 - p0).length
        n = max(1, math.ceil(length / 1.5))
        side = (p1 - p0).normalized().cross(Z)
        if posts:
            for i in range(n + 1):
                p = p0 + (p1 - p0) * (i / n)
                self.cyl(p - Z * 0.2, p + Z * 1.06, 0.06, side, sides=6, mode="pole", caps=(False, True))
        for h, r in ((1.0, 0.05), (0.58, 0.04), (0.18, 0.04)):
            self.cyl(p0 + Z * h, p1 + Z * h, r, side, sides=6, mode="pole", caps=(False, False))
        a, b = p0 - side * 0.05, p1 + side * 0.05 + Z * 1.05
        self.cbox(a, b)

    def porch(self):
        px0, px1, py0, py1 = PORCH
        dx0, dx1, dy0, dy1 = DECK_OPEN
        top, t = F, 0.05
        for x0, x1, y0, y1 in ((px0, px1, py0, py1), (dx0, dx1, dy0, dy1)):
            nx, ny = max(1, round((x1 - x0) / 1.3)), max(1, round((y1 - y0) / 1.3))
            self.grid((x0, y0, top), (x1 - x0, 0, 0), (0, y1 - y0, 0), nx, ny, DECK, (0, 0, 1), scale=0.74, udir=(1, 0, 0))
            self.grid((x0, y0, top - t), (x1 - x0, 0, 0), (0, y1 - y0, 0), nx, ny, DECK, (0, 0, -1), scale=0.74, udir=(1, 0, 0))
            self.cbox((x0, y0, top - 0.28), (x1, y1, top), "wood", True)
        # rim boards round the L
        outline = [(dx0, dy0), (dx1, dy0), None, (px1, py1), (px0, py1), (px0, dy1), (dx0, dy1), (dx0, dy0)]
        for a, b in zip(outline, outline[1:]):
            if a and b:
                self.beam((a[0], a[1], top - 0.135), (b[0], b[1], top - 0.135), 0.04, 0.27)
        # beams along y under the boards, posts under the beams, braces between the posts of the outer rows
        rows = [(-5.75, py0 - 5.2, py1 - 0.1), (-7.35, dy0 + 0.1, py1 - 0.1), (px0 + 0.12, dy0 + 0.1, py1 - 0.1), (-10.35, dy0 + 0.1, dy1 - 0.1), (dx0 + 0.12, dy0 + 0.1, dy1 - 0.1)]
        ys = [dy0 + 0.15, -6.65, dy1 - 0.1, -0.95, 2.2, 5.35, py1 - 0.15]
        for x, y0, y1 in rows:
            self.beam((x, y0, top - t - 0.11), (x, y1, top - t - 0.11), 0.11, 0.22)
            mine = [y for y in ys if y0 - 0.2 <= y <= y1 + 0.2]
            for y in mine:
                self.beam((x, y, GROUND), (x, y, top - t - 0.22), 0.16, 0.16, up=(0, 1, 0), caps=(False, False))
                self.cbox((x - 0.08, y - 0.08, GROUND), (x + 0.08, y + 0.08, top - 0.2))
            if x in (px0 + 0.12, dx0 + 0.12):
                for k, (ya, yb) in enumerate(zip(mine, mine[1:])):  # a brace per bay, from a post's foot to the next one's head
                    lo, hi = (ya, yb) if k % 2 == 0 else (yb, ya)
                    foot = ground(x, lo) + 0.2
                    if -0.35 - foot > 0.6:  # none where the deck lies close to the ground
                        self.beam((x - 0.1, lo, foot), (x - 0.1, hi, -0.35), 0.035, 0.13, caps=(True, True))
        for x0, x1 in ((px0 + 0.12, -7.35), (-7.35, -5.75)):  # and under the porch's north end
            self.beam((x0, py1 - 0.05, -0.35), (x1, py1 - 0.05, ground(x1, py1) + 0.2), 0.13, 0.035, up=(0, 1, 0))
        # railings: the deck's south and west edges, its north edge beside the stairs, the porch's west edge and north end
        e = 0.09
        sx1 = STAIR[1]
        self.pole_rail((dx1 - 0.25, dy0 + e, top), (dx0 + e, dy0 + e, top))
        self.pole_rail((dx0 + e, dy0 + e, top), (dx0 + e, dy1 - e, top))
        self.pole_rail((sx1 + 0.1, dy1 - e, top), (px0 + e, dy1 - e, top))
        self.pole_rail((px0 + e, dy1 - e, top), (px0 + e, py1 - e, top))
        self.pole_rail((px0 + e, py1 - e, top), (px1 - 0.25, py1 - e, top))
        # the porch roof: posts, beam, knee braces, ledger on the wall, rafters, purlins, tin sheets
        rx0, rx1, rz0, fall = -5.72, -9.42, 2.9, 0.14
        ry0, ry1 = py0 - 0.3, py1 + 0.2

        def rz(x):
            return rz0 - (rx0 - x) * fall

        bx = px0 + 0.12
        bz = rz(bx) - 0.19 - 0.1
        post_ys = [py0 + 0.1, -0.95, 2.2, 5.35, py1 - 0.15]
        for y in post_ys:
            self.beam((bx, y, top), (bx, y, bz - 0.1), 0.15, 0.15, up=(0, 1, 0), caps=(False, False))
            self.cbox((bx - 0.075, y - 0.075, top), (bx + 0.075, y + 0.075, bz))
            for s in (1, -1):
                if ry0 < y + s * 0.6 < ry1:
                    self.beam((bx, y, bz - 0.7), (bx, y + s * 0.6, bz - 0.1), 0.07, 0.09, caps=(False, False))
        self.beam((bx, ry0, bz), (bx, ry1, bz), 0.15, 0.2)
        self.beam((-HX - 0.2, ry0, rz(-5.45) - 0.24), (-HX - 0.2, ry1, rz(-5.45) - 0.24), 0.05, 0.2)  # ledger
        n = 11
        for i in range(n):
            y = ry0 + 0.12 + (ry1 - ry0 - 0.24) * i / (n - 1)
            self.beam((-HX - 0.17, y, rz(-HX - 0.17) - 0.13), (rx1 + 0.06, y, rz(rx1 + 0.06) - 0.13), 0.06, 0.13, caps=(False, True))
        for x in (-6.2, -7.5, -8.75):
            self.beam((x, ry0, rz(x) - 0.035), (x, ry1, rz(x) - 0.035), 0.06, 0.05)
        self.tin_roof((rx0, ry0, rz0), (0, 1, 0), ry1 - ry0, (rx1 - rx0, 0, rz(rx1) - rz0), missing=(9,))
        self.ctri([(rx0, ry0, rz0), (rx0, ry1, rz0), (rx1, ry1, rz(rx1)), (rx1, ry0, rz(rx1))], "tin", True)
        # firewood stacked on the porch between the door and the north window, a bench south of the door
        fx = -HX - 0.24
        for row in range(4):
            y = 2.05 + (0.07 if row % 2 else 0.0)
            while y < 4.55:
                r = rnd.uniform(0.07, 0.1)
                z = top + 0.09 + row * 0.165 + rnd.uniform(-0.01, 0.01)
                x1 = fx - 0.42 + rnd.uniform(-0.05, 0.05)
                self.cyl((fx, y + r, z), (x1, y + r, z), r, (0, 1, 0), sides=8, caps=(False, True))
                y += 2 * r + 0.004
        self.cbox((fx - 0.45, 2.05, top), (fx, 4.6, top + 0.72))
        by0, by1, bxa, bxb = -2.6, -0.9, -HX - 0.28, -HX - 0.68
        self.grid((bxb, by0, top + 0.45), (bxa - bxb, 0, 0), (0, by1 - by0, 0), 1, 1, DECK, (0, 0, 1), two=DECK, scale=0.74, udir=(0, 1, 0))
        self.beam((bxb, by0, top + 0.425), (bxb, by1, top + 0.425), 0.03, 0.05)
        for y in (by0 + 0.12, by1 - 0.12):
            self.box((bxb + 0.03, y - 0.02, top), (bxa - 0.03, y + 0.02, top + 0.45), TIMBER, scale=0.6, skip=("+z", "-z"))
        self.cbox((bxb, by0, top), (bxa, by1, top + 0.46))

    def extras(self):
        # a rain barrel at the porch's north end, under the eave
        bx, by, z0 = -HX - 0.75, PORCH[3] - 0.75, F
        rings = [(0.0, 0.27), (0.45, 0.33), (0.9, 0.27)]
        for (za, ra), (zb, rb) in zip(rings, rings[1:]):
            self.cyl((bx, by, z0 + za), (bx, by, z0 + zb), ra, (1, 0, 0), sides=10, mode="pole", caps=(False, False), r1=rb)
        ring = [(bx + 0.25 * math.cos(2 * math.pi * k / 10), by + 0.25 * math.sin(2 * math.pi * k / 10), z0 + 0.84) for k in range(10)]
        self.poly(ring, SOOT, facing=(0, 0, 1))  # the water, dark under the eave
        for z in (0.12, 0.45, 0.78):
            r = 0.335 if z == 0.45 else 0.29
            self.cyl((bx, by, z0 + z - 0.02), (bx, by, z0 + z + 0.02), r, (1, 0, 0), sides=10, mode="pole", caps=(False, False))
        self.cbox((bx - 0.3, by - 0.3, z0), (bx + 0.3, by + 0.3, z0 + 0.9))
        # a louvred vent high in each gable
        for s in (1, -1):
            y = s * (HY + 0.075)
            self.beam((-0.4, y + s * 0.02, 4.55), (0.4, y + s * 0.02, 4.55), 0.05, 0.07)
            self.beam((-0.4, y + s * 0.02, 5.15), (0.4, y + s * 0.02, 5.15), 0.05, 0.07)
            for x in (-0.37, 0.37):
                self.beam((x, y + s * 0.02, 4.55), (x, y + s * 0.02, 5.15), 0.07, 0.05, up=(0, 1, 0), caps=(False, False))
            for i in range(6):
                z = 4.62 + i * 0.09
                self.poly([(-0.34, y + s * 0.005, z), (0.34, y + s * 0.005, z), (0.34, y + s * 0.05, z + 0.07), (-0.34, y + s * 0.05, z + 0.07)], TIMBER, uvs=[(0, 0.42), (0.5, 0.42), (0.5, 0.58), (0, 0.58)], facing=(0, s, 0.6))
            self.poly([(-0.34, y + s * 0.004, 4.58), (0.34, y + s * 0.004, 4.58), (0.34, y + s * 0.004, 5.12), (-0.34, y + s * 0.004, 5.12)], SOOT, facing=(0, s, 0))

    def tin_roof(self, origin, along, width, run, missing=(), sheet=0.92):
        """Corrugated sheets side by side along `along` from `origin`, each running down `run`; every sheet sits a
        little off its neighbours, some are the older rustier tin, the `missing` ones have gone."""
        origin, along, run = Vector(origin), Vector(along).normalized(), Vector(run)
        n = max(1, round(width / sheet))
        w = width / n
        normal = along.cross(run).normalized()
        if normal.z < 0:
            normal = -normal
        down = run.normalized()
        for i in range(n):
            if i in missing:
                continue
            tex = TIN2 if rnd.random() < 0.45 else TIN
            lift = normal * rnd.uniform(0.0, 0.02)
            a = origin + along * (i * w - 0.02) + lift + down * rnd.uniform(-0.04, 0.04)
            u0 = rnd.random()
            for j in range(2):
                q = [a + run * (j / 2), a + along * (w + 0.04) + run * (j / 2), a + along * (w + 0.04) + run * ((j + 1) / 2), a + run * ((j + 1) / 2)]
                rl = run.length
                uvs = [(u0, 1 - j * rl / 4.4), (u0 + w / 2.2, 1 - j * rl / 4.4), (u0 + w / 2.2, 1 - (j + 1) * rl / 4.4), (u0, 1 - (j + 1) * rl / 4.4)]
                self.poly(q, tex, uvs=uvs, facing=normal)
                self.poly(q, tex, uvs=uvs, facing=-normal)

    def stairs(self):
        x0, x1, y0, rise, run = STAIR
        xm = (x0 + x1) / 2
        n = next(i for i in range(2, 14) if F - i * rise <= ground(xm, y0 + (i - 1) * run) + 0.04)  # the last riser lands on the ground
        for i in range(1, n):
            z, y = F - i * rise, y0 + (i - 1) * run
            self.box((x0, y - 0.02, z - 0.045), (x1, y + run + 0.02, z), DECK, scale=0.74, udir=(1, 0, 0))
        length = (n - 1) * run
        bottom = F - n * rise
        for x in (x0 + 0.04, x1 - 0.04):
            self.beam((x, y0 - 0.05, F - 0.2), (x, y0 + length + 0.25, bottom - 0.1), 0.06, 0.3, caps=(False, True))
            for y, z in ((y0 + 0.12, F - rise), (y0 + length - 0.1, bottom + rise)):
                self.cyl((x, y, z - 0.3), (x, y, z + 1.0), 0.055, (1, 0, 0), sides=6, mode="pole", caps=(False, True))
            self.cyl((x, y0 + 0.12, F - rise + 0.95), (x, y0 + length - 0.1, bottom + rise + 0.95), 0.045, (1, 0, 0), sides=6, mode="pole")
            self.cyl((x, y0 + 0.12, F - rise + 0.5), (x, y0 + length - 0.1, bottom + rise + 0.5), 0.035, (1, 0, 0), sides=6, mode="pole", caps=(False, False))
        for y in (y0 + length, ):
            for x in (x0 + 0.04, x1 - 0.04):
                self.beam((x, y, GROUND), (x, y, bottom + 0.1), 0.12, 0.12, up=(0, 1, 0), caps=(False, False))
        self.ctri([(x0, y0, F), (x1, y0, F), (x1, y0 + length + run, bottom), (x0, y0 + length + run, bottom)], "wood", True)
        for x in (x0, x1):
            self.ctri([(x, y0, F - 0.3), (x, y0 + length + run, bottom - 0.3), (x, y0 + length + run, bottom + 0.95), (x, y0, F + 0.95)], "wood", True)

    def carport(self):
        x0, x1, yw, ye, zw, fall = CARPORT

        def rz(y):
            return zw - (yw - y) * fall

        by = ye + 0.45
        bz = rz(by) - 0.2 - 0.11
        posts = (x0 + 0.25, (x0 + x1) / 2, x1 - 0.25)
        for x in posts:
            self.beam((x, by, GROUND), (x, by, bz - 0.11), 0.18, 0.18, up=(0, 1, 0), caps=(False, False))
            self.cbox((x - 0.09, by - 0.09, GROUND), (x + 0.09, by + 0.09, bz))
            for s in (1, -1):
                if x0 < x + s * 0.8 < x1:
                    self.beam((x, by, bz - 0.95), (x + s * 0.8, by, bz - 0.11), 0.08, 0.1, up=(0, 1, 0), caps=(False, False))
        self.beam((x0, by, bz), (x1, by, bz), 0.16, 0.22, up=Z)
        self.beam((x0, -HY - 0.22, rz(-HY - 0.22) - 0.3), (x1, -HY - 0.22, rz(-HY - 0.22) - 0.3), 0.06, 0.22)  # ledger
        n = 8
        for i in range(n):
            x = x0 + 0.12 + (x1 - x0 - 0.24) * i / (n - 1)
            self.beam((x, -HY - 0.2, rz(-HY - 0.2) - 0.16), (x, ye + 0.06, rz(ye + 0.06) - 0.16), 0.07, 0.16, caps=(False, True))
        for y in (-9.3, -10.9, -12.5, -14.1):
            self.beam((x0, y, rz(y) - 0.045), (x1, y, rz(y) - 0.045), 0.06, 0.07)
        self.tin_roof((x0, yw, zw), (1, 0, 0), x1 - x0, (0, ye - yw, rz(ye) - zw), missing=(), sheet=0.95)
        self.ctri([(x0, yw, zw), (x1, yw, zw), (x1, ye, rz(ye)), (x0, ye, rz(ye))], "tin", True)
        # the rail fence along the south side and up the east side to the cabin
        fence = [((x0 + 0.25, by), (x1 - 0.25, by)), ((x1 - 0.25, by), (x1 - 0.25, -HY - 0.45))]
        for (ax, ay), (bx, by2) in fence:
            ga, gb = ground(ax, ay), ground(bx, by2)
            for h in (0.25, 0.6, 0.95, 1.3):  # the rails follow the ground
                off = 0.1 if ax != bx else 0.0
                self.beam((ax + (0.1 if ax == bx else 0), ay - off, ga + h + rnd.uniform(-0.03, 0.03)), (bx + (0.1 if ax == bx else 0), by2 - off, gb + h + rnd.uniform(-0.03, 0.03)), 0.035, 0.15, up=Z)
            a, b = Vector((ax, ay, -1.75)), Vector((bx, by2, max(ga, gb) + 1.4))
            self.cbox((min(a.x, b.x) - 0.06, min(a.y, b.y) - 0.12, -1.75), (max(a.x, b.x) + 0.12, max(a.y, b.y) + 0.06, b.z))
        xm = x1 - 0.25
        for y in (-11.2, -HY - 0.5):
            self.beam((xm, y, GROUND), (xm, y, ground(xm, y) + 1.5), 0.14, 0.14, up=(0, 1, 0), caps=(False, True))

    # ---- light -----------------------------------------------------------------------------------------------
    def bake(self):
        """Prelight: for every face corner, rays over the hemisphere of its face tell how much open sky it sees and
        how closely it is hemmed in; day and night colours follow (the game shows a building's prelight about
        doubled, so open ground stays near 0.5)."""
        self.bm.normal_update()
        self.bm.faces.ensure_lookup_table()
        bvh = BVHTree.FromBMesh(self.bm)
        r2 = random.Random(5)
        dirs = []
        for _ in range(28):
            u, v = r2.random(), r2.random()
            rad, phi = math.sqrt(u), 2 * math.pi * v
            dirs.append((rad * math.cos(phi), rad * math.sin(phi), math.sqrt(max(0.0, 1 - u))))
        cache = {}
        ends = self.mat(LOGEND)
        for f in self.bm.faces:
            n = f.normal
            t = n.cross(Z) if abs(n.z) < 0.95 else n.cross(Vector((1, 0, 0)))
            t.normalize()
            b = n.cross(t)
            c = f.calc_center_median()
            tint = 0.6 if f.material_index == ends else 1.0  # the sawn ends have weathered as dark as the logs
            for loop in f.loops:
                p = loop.vert.co + (c - loop.vert.co) * 0.18 + n * 0.02
                key = (round(p.x, 2), round(p.y, 2), round(p.z, 2), round(n.x, 1), round(n.y, 1), round(n.z, 1))
                if key not in cache:
                    sky = near = 0.0
                    for dx, dy, dz in dirs:
                        d = t * dx + b * dy + n * dz
                        hit = bvh.ray_cast(p, d, 14.0)
                        if hit[0] is None:
                            sky += 1.0 if d.z > -0.2 else 0.45  # rays leaving downwards meet the ground
                        elif hit[3] < 0.9:
                            near += 1.0 - hit[3] / 0.9
                    cache[key] = (sky / len(dirs), 1.0 - near / len(dirs))
                sky, open_ = cache[key]
                warm = 1.0 - min(1.0, sky * 3.0)  # indoors: warmer, lifted a little, and not as dark at night as the sums say
                lit = (0.30 + 0.07 * warm + 0.24 * sky ** 0.7) * (0.42 + 0.58 * open_ ** 1.5) * (1.0 + 0.1 * n.z) * tint
                day = (lit, lit * (1 - 0.05 * warm), lit * (1 - 0.14 * warm), 1.0)
                nl = lit * (0.34 + 0.1 * warm)
                night = (nl * (0.92 + 0.08 * warm), nl * 0.96, nl * (1.1 - 0.22 * warm), 1.0)
                loop[self.day], loop[self.night] = day, night

    # ---- output ----------------------------------------------------------------------------------------------
    def finish(self):
        for q, uv in self.glass:
            for vs, uvs in ((q, uv), (list(reversed(q)), list(reversed(uv)))):
                f = self.poly(vs, GLASS, uvs=uvs)
        self.bake()
        glass = self.mat(GLASS)
        for f in self.bm.faces:
            f.smooth = False
            if f.material_index == glass:
                for loop in f.loops:
                    loop[self.day], loop[self.night] = common.GLASS_DAY, common.GLASS_NIGHT
        m = Matrix.Translation(Vector(SHIFT)) @ Matrix.Rotation(math.radians(SKEW), 4, "Z")
        self.matrix = m
        bmesh.ops.transform(self.bm, matrix=m, verts=self.bm.verts)
        bmesh.ops.transform(self.col, matrix=m, verts=self.col.verts)
        self.bm.normal_update()
        self.bm.to_mesh(self.mesh)
        self.col.to_mesh(self.col_mesh)
        self.mesh.update()
        self.colobj = bpy.data.objects.new(NAME + "_colmesh", self.col_mesh)
        bpy.context.scene.collection.objects.link(self.colobj)
        self.colobj.dff.type = "COL"
        self.colobj.hide_render = True
        # the leaf: hinged on the doorway's south jamb, closed along +y
        w, h, t = DOOR_U[1] - DOOR_U[0] - 0.03, DOOR_Z[1] - DOOR_Z[0] - 0.03, 0.06
        mesh = bpy.data.meshes.new(NAME + "_door")
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day, night = bm.loops.layers.color.new("Col"), bm.loops.layers.color.new("Col.001")
        for tex in (DOOR, TIMBER):
            mesh.materials.append(self.mesh.materials[self.mat(tex)])
        lit = ((0.4, 0.39, 0.37, 1.0), (0.15, 0.15, 0.16, 1.0))

        def quad(vs, mi, uvs):
            f = bm.faces.new([bm.verts.new(v) for v in vs])
            f.material_index = mi
            for loop, c in zip(f.loops, uvs):
                loop[uv].uv = c
                loop[day], loop[night] = lit

        y0, y1 = -t / 2, t / 2
        full = [(0.02, 0.01), (0.98, 0.01), (0.98, 0.99), (0.02, 0.99)]
        quad([(0, y0, 0), (w, y0, 0), (w, y0, h), (0, y0, h)], 0, full)
        quad([(w, y1, 0), (0, y1, 0), (0, y1, h), (w, y1, h)], 0, full)
        e = [(0, 0.02), (1, 0.02), (1, 0.08), (0, 0.08)]
        quad([(0, y1, 0), (0, y0, 0), (0, y0, h), (0, y1, h)], 1, e)
        quad([(w, y0, 0), (w, y1, 0), (w, y1, h), (w, y0, h)], 1, e)
        quad([(0, y0, h), (w, y0, h), (w, y1, h), (0, y1, h)], 1, e)
        quad([(0, y1, 0), (w, y1, 0), (w, y0, 0), (0, y0, 0)], 1, e)
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        self.leaf = bpy.data.objects.new(NAME + "_door", mesh)
        bpy.context.scene.collection.objects.link(self.leaf)
        self.leaf_size = (w, h, t)
        hinge = m @ Vector((-HX, DOOR_U[0] + 0.015, F + 0.015))
        self.door = {"hinge": [round(v, 4) for v in hinge], "rz": round(90.0 + SKEW, 2)}

    def prelit_materials(self):
        """Shows the model as the game does: texture times the baked day prelight, doubled, no other light."""
        for m in list(self.mesh.materials):
            nt = m.node_tree
            out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
            tex = next((n for n in nt.nodes if n.type == "TEX_IMAGE"), None)
            bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
            col = nt.nodes.new("ShaderNodeVertexColor")
            col.layer_name = "Col"
            mix = nt.nodes.new("ShaderNodeMixRGB")
            mix.blend_type = "MULTIPLY"
            mix.inputs[0].default_value = 1.0
            if tex:
                nt.links.new(tex.outputs["Color"], mix.inputs[1])
            else:
                mix.inputs[1].default_value = bsdf.inputs["Base Color"].default_value
            nt.links.new(col.outputs["Color"], mix.inputs[2])
            em = nt.nodes.new("ShaderNodeEmission")
            em.inputs["Strength"].default_value = 2.0
            nt.links.new(mix.outputs["Color"], em.inputs["Color"])
            if m.name == GLASS:
                continue
            nt.links.new(em.outputs["Emission"], out.inputs["Surface"])

    def render(self, view, eye, target, lens=24, size=(1280, 800), door_open=0.0):
        scene = bpy.context.scene
        self.leaf.location = self.door["hinge"]
        self.leaf.rotation_euler = (0, 0, math.radians(self.door["rz"] + door_open))
        cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        if cam.name not in scene.collection.objects:
            scene.collection.objects.link(cam)
        cam.data.lens, cam.data.clip_start = lens, 0.03
        cam.location = eye
        cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        if not bpy.data.objects.get("sun"):
            sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
            sun.data.energy, sun.data.angle = 3.2, math.radians(3)
            sun.rotation_euler = (math.radians(52), 0, math.radians(-128))
            scene.collection.objects.link(sun)
            scene.world = bpy.data.worlds.new("w")
            scene.world.use_nodes = True
            bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
            bg.inputs["Color"].default_value = (0.5, 0.6, 0.72, 1)
            bg.inputs["Strength"].default_value = 1.0
            ground = bpy.data.meshes.new("ground")
            gbm = bmesh.new()
            bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=60)
            gbm.to_mesh(ground)
            gbm.free()
            g = bpy.data.objects.new("ground", ground)
            g.location.z = -1.25  # the measured slope: level with the floor at the south end, falling north
            g.rotation_euler.x = -math.atan(0.1)
            gm = bpy.data.materials.new("ground")
            gm.use_nodes = True
            next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.13, 0.12, 0.07, 1)
            ground.materials.append(gm)
            scene.collection.objects.link(g)
        engines = (os.environ["SHELL_ENGINE"],) if os.environ.get("SHELL_ENGINE") else ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH")
        for engine in engines:
            try:
                scene.render.engine = engine
                break
            except TypeError:
                continue
        if scene.render.engine == "CYCLES":
            scene.cycles.device, scene.cycles.samples = "CPU", int(os.environ.get("SHELL_SAMPLES", "24"))
            scene.cycles.use_denoising = True
        scene.render.resolution_x, scene.render.resolution_y = size
        path = os.path.join(RENDERS, NAME, view + ".png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"render: {path}")

    def export(self):
        for o in ("cam", "sun", "ground"):
            if bpy.data.objects.get(o):
                bpy.data.objects.remove(bpy.data.objects[o])
        os.makedirs(OUT, exist_ok=True)
        one = common.Shell._export_one
        one(None, NAME, self.obj, [], self.colobj)
        self.leaf.location, self.leaf.rotation_euler = (0, 0, 0), (0, 0, 0)
        w, h, t = self.leaf_size
        one(None, NAME + "_door", self.leaf, [[0, -t / 2, 0, w, t / 2, h]])
        with open(os.path.join(BUILD, NAME + "_doors.json"), "w") as f:
            # the vanilla log walls are a model of their own (18258, logcabinnlogs01), placed beside this one
            json.dump({"doors": [self.door], "remove": [{"model": 18258, "pos": [-5.13, -0.59, 0.36], "radius": 3.0}]}, f, indent=2)
        print(f"export: {NAME} ({len(self.mesh.polygons)} faces, {len(self.mesh.loops)} corners, {len(self.col_mesh.polygons)} collision triangles)")


c = Cabin()
c.foundation()
c.floor()
c.walls()
c.roof()
c.chimney()
c.partition()
c.furniture()
c.porch()
c.stairs()
c.carport()
c.extras()
c.finish()

if "--no-render" not in args():
    only = [a.split("=", 1)[1] for a in args() if a.startswith("--views=")]
    only = only[0].split(",") if only else None
    if "--prelit" in args():
        c.prelit_materials()
    views = {
        "front_sw": ((-21.0, -19.0, 2.6), (-3.0, -3.0, 1.2), 28, 0),
        "porch_w": ((-17.0, 4.5, 1.6), (-5.0, 1.0, 1.4), 30, 0),
        "back_ne": ((16.0, 19.0, 3.2), (0.0, 1.0, 2.0), 28, 0),
        "carport_se": ((14.0, -22.0, 1.2), (0.0, -7.0, 1.2), 28, 0),
        "door": ((-8.9, -1.6, 1.75), (-5.3, 1.6, 1.25), 24, 55),
        "window": ((-7.6, 4.2, 1.6), (-5.3, 5.6, 1.6), 35, 0),
        "deck": ((-10.9, -8.6, 1.8), (-6.0, 3.0, 1.0), 20, 0),
        "inside_main": ((3.6, -0.9, 1.7), (-1.5, 8.0, 1.5), 16, 0),
        "inside_back": ((-3.8, -2.6, 1.7), (3.5, -8.0, 1.2), 16, 0),
        "roof_frame": ((-3.8, 6.4, 0.9), (2.5, -3.0, 5.0), 16, 0),
    }
    lamps = []
    for name, eye in (("lamp_main", (0.0, 3.0, 2.6)), ("lamp_back", (0.0, -5.0, 2.6))):
        lamp = bpy.data.objects.new(name, bpy.data.lights.new(name, "POINT"))
        lamp.data.energy, lamp.data.color = 260, (1.0, 0.82, 0.6)
        lamp.location = eye
        bpy.context.scene.collection.objects.link(lamp)
        lamps.append(lamp)
    for view, (eye, target, lens, door_open) in views.items():
        if only is None or view in only:
            c.render(view + ("_prelit" if "--prelit" in args() else ""), eye, target, lens=lens, door_open=door_open)
    for lamp in lamps:
        bpy.data.objects.remove(lamp)
if "--prelit" not in args():
    c.export()
