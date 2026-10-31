"""Shared Blender side of the trailer shells: each vanilla trailer (models 3167-3175) is rebuilt as an enterable shell
by its own script, tools/trailer_shells/<model>.py, which runs headless after tools/trailer_shells/prep.py:

    blender -b --python tools/trailer_shells/<model>.py

A script opens the vanilla model with `Shell(name)`, declares its door and windows with `opening(...)` (each cuts the
hole through the vanilla skin, lines it with a reveal and, for a window, glazes it with a framed see-through pane),
builds the rooms behind them with `room(...)` (panelled walls with those holes, carpet or lino floor, ceiling), edits
the collision boxes, then `render(...)`s views to check and `export()`s. Exterior geometry is the vanilla model, kept
as it is outside the openings, so the trailer looks the same from the street.

Coordinates are the model's own (metres, +Z up). An opening sits in a wall whose outward normal is an axis: `axis`
"x" or "y", `side` +1 or -1; `u0, u1` run along the wall (the other horizontal axis), `z0, z1` up it; `inner` is the
room-side face of that wall along `axis`. The door leaf is a model of its own (<name>_door), hinged at its origin.

Writes resources/[scavengesurvive]/house_shell/files/<name>.dff/.col and <name>_door.dff/.col, and
tools/trailer_shells/build/<name>.json (door hinge and size, rooms) for the house_shell resource's door placement.
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
BUILD = os.path.join(HERE, "build")
VANILLA = os.path.join(BUILD, "vanilla")
TEX = os.path.join(BUILD, "tex")
RENDERS = os.path.join(BUILD, "renders")
OUT = os.path.join(ROOT, "resources", "[scavengesurvive]", "house_shell", "files")

# interior palette, all in house_shell/files/trailers.txd (tools/trailer_shells/prep.py)
WALL, CEILING, CARPET, LINO, TRIM, CURTAIN, GLASS = "tr_wall2", "tr_wall3", "carp19s", "tr_floor2", "tr_wood1", "curtain_sink2", "house_window"
FRAME_RGB = (212, 214, 218)  # aluminium window frames: untextured, material colour only
SCALE = {WALL: 1.2, CEILING: 1.0, CARPET: 1.0, LINO: 0.8, TRIM: 0.6, CURTAIN: 1.0}  # metres per texture repeat
IN_DAY, IN_NIGHT = (0.60, 0.56, 0.50, 1.0), (0.20, 0.18, 0.16, 1.0)  # prelight inside: warm, dim at night
OUT_DAY, OUT_NIGHT = (0.70, 0.70, 0.70, 1.0), (0.16, 0.16, 0.19, 1.0)  # new faces seen from outside (reveals, frames)
GLASS_DAY, GLASS_NIGHT = (1.0, 1.0, 1.0, 1.0), (0.35, 0.35, 0.40, 1.0)
DOOR_GAP = 0.01  # clearance at the jambs and head, so the leaf swings free
DOOR_THICK = 0.04
EPS = 1e-4


def _axes(axis):
    """(normal index, along-wall index) for a wall facing `axis`."""
    return (0, 1) if axis == "x" else (1, 0)


def _point(axis, depth, u, z):
    n, a = _axes(axis)
    p = [0.0, 0.0, z]
    p[n], p[a] = depth, u
    return Vector(p)


class Opening:
    def __init__(self, kind, axis, side, u0, u1, z0, z1, inner):
        self.kind, self.axis, self.side = kind, axis, side
        self.u0, self.u1, self.z0, self.z1, self.inner = u0, u1, z0, z1, inner
        self.outer = {}  # corner (u, z) -> depth of the outer skin there
        self.removed = []  # (texture, uv min, uv max) of the vanilla faces cut away
        self.door = None

    @property
    def normal(self):
        n = [0.0, 0.0, 0.0]
        n[_axes(self.axis)[0]] = float(self.side)
        return Vector(n)


class Shell:
    def __init__(self, name):
        self.name = name
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.preferences.addon_enable(module="DragonFF")
        bpy.ops.import_scene.dff(filepath=os.path.join(VANILLA, name + ".dff"), read_mat_split=True, remove_doubles=False, load_images=False)
        for o in list(bpy.data.objects):
            if o.name.startswith("2dfx"):
                bpy.data.objects.remove(o)
        self.obj = next(o for o in bpy.data.objects if o.type == "MESH")
        mw = self.obj.matrix_world.copy()
        self.obj.data.transform(mw)  # bake the frame so model space == mesh space
        self.obj.parent = None
        self.obj.matrix_world = Matrix.Identity(4)
        for o in list(bpy.data.objects):
            if o is not self.obj:
                bpy.data.objects.remove(o)
        for mat in self.obj.data.materials:
            self._hook_texture(mat)
        mesh = self.obj.data
        self.bvh = BVHTree.FromPolygons([v.co.copy() for v in mesh.vertices], [p.vertices[:] for p in mesh.polygons])
        self.bm = bmesh.new()
        self.bm.from_mesh(mesh)
        self.uv = self.bm.loops.layers.uv.active or self.bm.loops.layers.uv.new("UVMap")
        attrs = list(mesh.color_attributes)
        layers = self.bm.loops.layers.float_color if attrs and attrs[0].data_type == "FLOAT_COLOR" else self.bm.loops.layers.color
        if len(attrs) < 2:
            raise RuntimeError(f"{name}: expected day and night prelight, found {[a.name for a in attrs]}")
        self.day, self.night = layers[attrs[0].name], layers[attrs[1].name]
        self.openings = []
        self.rooms = []
        self.cols = self._vanilla_cols()
        self.mats = {}
        self.leaf = None
        self._glass_faces = []
        self._finished = False

    # ---- materials -------------------------------------------------------------------------------------------
    @staticmethod
    def _image(texture):
        path = os.path.join(TEX, texture.lower() + ".png")
        img = bpy.data.images.get(texture.lower() + ".png")
        if img is None and os.path.exists(path):
            img = bpy.data.images.load(path)
            img.name = texture.lower() + ".png"
        return img

    def _hook_texture(self, mat):
        if not mat or not mat.node_tree:
            return
        for node in mat.node_tree.nodes:
            if node.type == "TEX_IMAGE":
                name = (node.image.name if node.image else node.label or node.name).split(".")[0]
                img = self._image(name)
                if img:
                    node.image = img

    def texture_of(self, index):
        mat = self.obj.data.materials[index] if index < len(self.obj.data.materials) else None
        if mat and mat.node_tree:
            for node in mat.node_tree.nodes:
                if node.type == "TEX_IMAGE" and node.image:
                    return node.image.name.rsplit(".", 1)[0].lower()
        return None

    def mat(self, texture=None, rgb=None):
        """Material index for a texture of trailers.txd, or an untextured colour."""
        key = texture or ("rgb", rgb)
        if key in self.mats:
            return self.mats[key]
        for i, m in enumerate(self.obj.data.materials):
            if texture and self.texture_of(i) == texture.lower():
                self.mats[key] = i
                return i
        m = bpy.data.materials.new(texture or "frame_%d_%d_%d" % rgb)
        m.use_nodes = True
        bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
        if texture:
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = self._image(texture) or bpy.data.images.new(texture.lower() + ".png", 8, 8)
            m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            if texture == GLASS:
                m.node_tree.links.new(node.outputs["Alpha"], bsdf.inputs["Alpha"])
                if hasattr(m, "surface_render_method"):
                    m.surface_render_method = "BLENDED"
        else:
            bsdf.inputs["Base Color"].default_value = (rgb[0] / 255, rgb[1] / 255, rgb[2] / 255, 1.0)
        self.obj.data.materials.append(m)
        self.mats[key] = len(self.obj.data.materials) - 1
        return self.mats[key]

    # ---- geometry --------------------------------------------------------------------------------------------
    def ray(self, origin, direction, dist=20.0):
        """Distance along `direction` to the vanilla skin (as loaded), or None."""
        hit = self.bvh.ray_cast(Vector(origin), Vector(direction).normalized(), dist)
        return None if hit[0] is None else (hit[0] - Vector(origin)).length

    def face(self, verts, material, uvs=None, light="in", scale=None):
        """One polygon; `uvs` per vertex, or planar from the face's own plane at the material's texture scale."""
        bm = self.bm
        f = bm.faces.new([bm.verts.new(Vector(v)) for v in verts])
        f.material_index = material
        f.normal_update()
        if uvs is None:
            s = scale or 1.0
            nrm = f.normal
            up = Vector((0, 0, 1)) if abs(nrm.z) < 0.9 else Vector((0, 1, 0))
            right = up.cross(nrm).normalized()
            up = nrm.cross(right).normalized()
            uvs = [(Vector(v).dot(right) / s, Vector(v).dot(up) / s) for v in verts]
        day, night = {"in": (IN_DAY, IN_NIGHT), "out": (OUT_DAY, OUT_NIGHT), "glass": (GLASS_DAY, GLASS_NIGHT)}[light]
        for loop, uv in zip(f.loops, uvs):
            loop[self.uv].uv = uv
            loop[self.day] = day
            loop[self.night] = night
        return f

    def box(self, lo, hi, material, light="in", scale=None, skip=()):
        """An axis-aligned box, faces outward; `skip` names faces to leave off ('-x', '+z', ...)."""
        x0, y0, z0 = lo
        x1, y1, z1 = hi
        quads = {
            "+x": [(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)],
            "-x": [(x0, y1, z0), (x0, y0, z0), (x0, y0, z1), (x0, y1, z1)],
            "+y": [(x1, y1, z0), (x0, y1, z0), (x0, y1, z1), (x1, y1, z1)],
            "-y": [(x0, y0, z0), (x1, y0, z0), (x1, y0, z1), (x0, y0, z1)],
            "+z": [(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)],
            "-z": [(x0, y1, z0), (x1, y1, z0), (x1, y0, z0), (x0, y0, z0)],
        }
        for k, q in quads.items():
            if k not in skip:
                self.face(q, material, light=light, scale=scale or SCALE.get(self._tex_name(material), 1.0))

    def _tex_name(self, material):
        return self.texture_of(material)

    def cut(self, o, back=0.02, front=0.25):
        """Deletes the vanilla faces filling opening `o`: faces facing along the wall normal whose centre lies in the
        rectangle, between `back` behind the inner face and `front` past the outer skin. Straddling faces are split
        at the rectangle's edges first, so the skin around the hole stays."""
        n, a = _axes(o.axis)
        ends = [o.inner - o.side * back] + [d + o.side * front for d in o.outer.values()]
        lo_d, hi_d = min(ends), max(ends)
        bm = self.bm

        def near(f):
            c = f.calc_center_median()
            return lo_d - EPS <= c[n] <= hi_d + EPS and o.u0 - 0.5 < c[a] < o.u1 + 0.5 and o.z0 - 0.5 < c.z < o.z1 + 0.5

        for co, no in ((o.u0, a), (o.u1, a), (o.z0, 2), (o.z1, 2)):
            faces = [f for f in bm.faces if near(f)]
            if not faces:
                continue
            geom = list({v for f in faces for v in f.verts}) + list({e for f in faces for e in f.edges}) + faces
            pn = [0.0, 0.0, 0.0]
            pn[no] = 1.0
            pc = [0.0, 0.0, 0.0]
            pc[no] = co
            bmesh.ops.bisect_plane(bm, geom=geom, plane_co=pc, plane_no=pn, dist=EPS)
        dead = []
        for f in bm.faces:
            c = f.calc_center_median()
            f.normal_update()
            if abs(f.normal[n]) < 0.5:
                continue
            if lo_d - EPS <= c[n] <= hi_d + EPS and o.u0 + EPS < c[a] < o.u1 - EPS and o.z0 + EPS < c.z < o.z1 - EPS:
                dead.append(f)
        for f in dead:
            uvs = [l[self.uv].uv.copy() for l in f.loops]
            o.removed.append((self.texture_of(f.material_index), (min(u.x for u in uvs), min(u.y for u in uvs)), (max(u.x for u in uvs), max(u.y for u in uvs))))
        bmesh.ops.delete(bm, geom=dead, context="FACES")
        return len(dead)

    def opening(self, kind, axis, side, u0, u1, z0, z1, inner, outer=None, frame="slider", glass_inset=0.04, hinge="left", reveal=TRIM):
        """Declares and builds a hole in a wall. kind: 'window' (glazed, framed, sill), 'door' (a leaf of its own,
        `hinge` 'left'/'right' as seen from outside) or 'pass' (a plain hole between two rooms: give `outer`, the
        other room's inner face). `outer`: depth of the outer skin, measured per corner by raycast when None.
        frame: 'slider' (vertical meeting stile), 'sash' (horizontal meeting rail), 'fixed', or a list of
        ('v'|'h', fraction) mullions."""
        o = Opening(kind, axis, side, u0, u1, z0, z1, inner)
        n, a = _axes(axis)
        corners = [(u0, z0), (u1, z0), (u1, z1), (u0, z1)]
        for u, z in corners:
            if outer is not None:
                o.outer[(u, z)] = outer
                continue
            iu = u + (0.02 if u == u0 else -0.02)
            iz = z + (0.02 if z == z0 else -0.02)
            d = self.ray(_point(axis, inner, iu, iz), o.normal, 3.0)
            if d is None:
                raise RuntimeError(f"{self.name}: no outer skin past {kind} corner u={u:.2f} z={z:.2f}")
            o.outer[(u, z)] = inner + side * d
        self.cut(o)
        trim = self.mat(reveal)
        # reveal: four faces lining the hole, facing its centre line
        ring_in = [_point(axis, inner, u, z) for u, z in corners]
        ring_out = [_point(axis, o.outer[(u, z)], u, z) for u, z in corners]
        for i in range(4):
            j = (i + 1) % 4
            quad = [ring_in[i], ring_in[j], ring_out[j], ring_out[i]]
            if side < 0:
                quad.reverse()
            if axis == "y":
                quad.reverse()
            self.face(quad, trim, light="out", scale=SCALE[TRIM])
        if kind == "window":
            self._glaze(o, frame, glass_inset)
            self._sill(o)
        elif kind == "door":
            o.door = self._door(o, hinge)
        self.openings.append(o)
        return o

    def _glaze(self, o, frame, inset):
        n, a = _axes(o.axis)
        depth = {k: v - o.side * inset for k, v in o.outer.items()}
        d0 = sum(depth.values()) / 4
        alu = self.mat(rgb=FRAME_RGB)
        u0, u1, z0, z1 = o.u0, o.u1, o.z0, o.z1
        bar = 0.045
        bars = [("v", 0.0), ("v", 1.0), ("h", 0.0), ("h", 1.0)]
        extra = {"slider": [("v", 0.5)], "sash": [("h", 0.5)], "fixed": []}[frame] if isinstance(frame, str) else frame
        bars += list(extra)
        # panes between the bars, both faces, so the glass is seen from inside and out
        us = sorted({u0 + bar, u1 - bar} | {u0 + f * (u1 - u0) + s * bar / 2 for k, f in extra if k == "v" for s in (-1, 1)})
        zs = sorted({z0 + bar, z1 - bar} | {z0 + f * (z1 - z0) + s * bar / 2 for k, f in extra if k == "h" for s in (-1, 1)})
        for i in range(0, len(us) - 1, 2):
            for j in range(0, len(zs) - 1, 2):
                pu0, pu1, pz0, pz1 = us[i], us[i + 1], zs[j], zs[j + 1]
                q = [_point(o.axis, d0, pu0, pz0), _point(o.axis, d0, pu1, pz0), _point(o.axis, d0, pu1, pz1), _point(o.axis, d0, pu0, pz1)]
                uv = [((pu0 - u0) / (u1 - u0), (pz0 - z0) / (z1 - z0)), ((pu1 - u0) / (u1 - u0), (pz0 - z0) / (z1 - z0)), ((pu1 - u0) / (u1 - u0), (pz1 - z0) / (z1 - z0)), ((pu0 - u0) / (u1 - u0), (pz1 - z0) / (z1 - z0))]
                outward = (o.side > 0) == (o.axis == "x")
                self._glass_faces.append((q, uv, outward))
        for k, f in bars:
            if k == "v":
                c = u0 + f * (u1 - u0)
                b0, b1 = max(u0, c - bar / 2) if f > 0 else u0, min(u1, c + bar / 2) if f < 1 else u1
                if f == 0:
                    b1 = u0 + bar
                if f == 1:
                    b0 = u1 - bar
                lo, hi = _point(o.axis, d0 - 0.03, b0, z0), _point(o.axis, d0 + 0.03, b1, z1)
            else:
                c = z0 + f * (z1 - z0)
                b0, b1 = (z0, z0 + bar) if f == 0 else (z1 - bar, z1) if f == 1 else (c - bar / 2, c + bar / 2)
                lo, hi = _point(o.axis, d0 - 0.03, u0, b0), _point(o.axis, d0 + 0.03, u1, b1)
            self.box([min(lo[i], hi[i]) for i in range(3)], [max(lo[i], hi[i]) for i in range(3)], alu, light="out")

    def _sill(self, o):
        """A trim ledge under the window on the room side."""
        n, a = _axes(o.axis)
        d_in, d_room = o.inner, o.inner - o.side * 0.06
        lo = _point(o.axis, min(d_in, d_room), o.u0 - 0.04, o.z0 - 0.03)
        hi = _point(o.axis, max(d_in, d_room), o.u1 + 0.04, o.z0)
        self.box([min(lo[i], hi[i]) for i in range(3)], [max(lo[i], hi[i]) for i in range(3)], self.mat(TRIM))

    def _door(self, o, hinge):
        """The opening's leaf, as its own model: origin at the hinge foot, leaf along local +X, thickness on Y."""
        # the door's own texture: the one covering the most UV area among the faces cut away (thin slivers of wall
        # split off at the jambs would otherwise win)
        area = {}
        for t, lo, hi in o.removed:
            if t:
                area[t] = area.get(t, 0.0) + (hi[0] - lo[0]) * (hi[1] - lo[1])
        tex = max(area, key=lambda t: ("door" in t, area[t])) if area else None
        uv_lo = [min(lo[i] for t, lo, _hi in o.removed if t == tex) for i in (0, 1)] if tex else [0.0, 0.0]
        uv_hi = [max(hi[i] for t, _lo, hi in o.removed if t == tex) for i in (0, 1)] if tex else [1.0, 1.0]
        outer = sum(o.outer.values()) / 4
        depth = outer - o.side * (0.02 + DOOR_THICK / 2)
        width = o.u1 - o.u0 - 2 * DOOR_GAP
        height = o.z1 - o.z0 - DOOR_GAP
        n, a = _axes(o.axis)
        # seen from outside (looking along -normal), 'left' is the hinge on the viewer's left
        out_n = o.normal
        right = Vector((0, 0, 1)).cross(-out_n)  # viewer's right, looking at the wall from outside
        hinge_u = o.u0 + DOOR_GAP if (right[a] > 0) == (hinge == "left") else o.u1 - DOOR_GAP
        direction = 1.0 if hinge_u < (o.u0 + o.u1) / 2 else -1.0
        along = Vector((0, 0, 0))
        along[a] = direction
        pos = _point(o.axis, depth, hinge_u, o.z0 + DOOR_GAP / 2)
        rz = math.degrees(math.atan2(along.y, along.x)) % 360
        return {"texture": tex, "uv": [uv_lo, uv_hi], "width": width, "height": height, "hinge": [pos.x, pos.y, pos.z], "rz": rz}

    def room(self, x0, x1, y0, y1, z0, z1, floor=CARPET, walls=WALL, ceiling=CEILING, open_sides=()):
        """A room's inside: four panelled walls (inward), floor and ceiling, with every declared opening whose inner
        face lies on one of these walls cut out of it. `open_sides` ('-x', '+y', ...) are left off."""
        self.rooms.append([x0, x1, y0, y1, z0, z1])
        wmat, fmat, cmat = self.mat(walls), self.mat(floor), self.mat(ceiling)
        self.face([(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0)], fmat, scale=SCALE.get(floor, 1.0))
        self.face([(x0, y1, z1), (x1, y1, z1), (x1, y0, z1), (x0, y0, z1)], cmat, scale=SCALE.get(ceiling, 1.0))
        sides = {"-x": ("x", -1, x0, y0, y1), "+x": ("x", 1, x1, y0, y1), "-y": ("y", -1, y0, x0, x1), "+y": ("y", 1, y1, x0, x1)}
        for key, (axis, side, d, ua, ub) in sides.items():
            if key in open_sides:
                continue
            holes = [o for o in self.openings if o.axis == axis and abs(o.inner - d) < 0.02 and o.u1 > ua and o.u0 < ub]
            us = sorted({ua, ub} | {max(ua, min(ub, v)) for o in holes for v in (o.u0, o.u1)})
            zs = sorted({z0, z1} | {max(z0, min(z1, v)) for o in holes for v in (o.z0, o.z1)})
            for i in range(len(us) - 1):
                for j in range(len(zs) - 1):
                    cu, cz = (us[i] + us[i + 1]) / 2, (zs[j] + zs[j + 1]) / 2
                    if any(o.u0 < cu < o.u1 and o.z0 < cz < o.z1 for o in holes):
                        continue
                    q = [_point(axis, d, us[i], zs[j]), _point(axis, d, us[i + 1], zs[j]), _point(axis, d, us[i + 1], zs[j + 1]), _point(axis, d, us[i], zs[j + 1])]
                    # wall faces point into the room (against `side`)
                    if (side > 0) == (axis == "x"):
                        q.reverse()
                    self.face(q, wmat, scale=SCALE.get(walls, 1.0))
            # skirting and cornice in trim
        return self.rooms[-1]

    # ---- collision -------------------------------------------------------------------------------------------
    def _vanilla_cols(self):
        path = os.path.join(VANILLA, self.name + ".col")
        before = set(bpy.data.objects)
        bpy.ops.import_scene.dff(filepath=path)
        boxes = []
        for o in [o for o in bpy.data.objects if o not in before]:
            if o.type == "EMPTY" and o.empty_display_type == "CUBE":
                c, s = o.matrix_world.translation, o.matrix_world.to_scale()
                boxes.append([c.x - s.x, c.y - s.y, c.z - s.z, c.x + s.x, c.y + s.y, c.z + s.z])
            bpy.data.objects.remove(o)
        return boxes

    def col_box(self, lo, hi):
        self.cols.append([lo[0], lo[1], lo[2], hi[0], hi[1], hi[2]])

    def room_cols(self, room, wall=0.12, roof=None, open_sides=()):
        """Collision for a room: floor slab under z0, roof slab over z1 (up to `roof`), and wall slabs outside its four
        sides, with a gap at every door and pass opening in them (windows stay solid)."""
        x0, x1, y0, y1, z0, z1 = room
        top = roof if roof is not None else z1 + 0.15
        self.col_box((x0 - wall, y0 - wall, z0 - 0.3), (x1 + wall, y1 + wall, z0))
        self.col_box((x0 - wall, y0 - wall, z1), (x1 + wall, y1 + wall, top))
        sides = {"-x": ("x", -1, x0, y0, y1), "+x": ("x", 1, x1, y0, y1), "-y": ("y", -1, y0, x0, x1), "+y": ("y", 1, y1, x0, x1)}
        for key, (axis, side, d, ua, ub) in sides.items():
            if key in open_sides:
                continue
            gaps = sorted((o.u0, o.u1, o.z1) for o in self.openings if o.kind != "window" and o.axis == axis and abs(o.inner - d) < 0.02)
            d0, d1 = (d, d + side * wall) if side > 0 else (d + side * wall, d)
            u = ua - wall
            segs = []
            for g0, g1, gz in gaps:
                segs.append((u, g0, z0, z1))
                segs.append((g0, g1, gz, z1))  # over the door
                u = g1
            segs.append((u, ub + wall, z0, z1))
            for s0, s1, sz0, sz1 in segs:
                if s1 - s0 < 0.01 or sz1 - sz0 < 0.01:
                    continue
                lo, hi = _point(axis, min(d0, d1), s0, sz0), _point(axis, max(d0, d1), s1, sz1)
                self.col_box([min(lo[i], hi[i]) for i in range(3)], [max(lo[i], hi[i]) for i in range(3)])

    # ---- output ----------------------------------------------------------------------------------------------
    def _finish_mesh(self):
        if self._finished:
            return
        self._finished = True
        # GTA draws a geometry's materials in order: the glass material is created here, last, so it is drawn after
        # everything it should show through to
        glass = self.mat(GLASS)
        for q, uv, outward in self._glass_faces or []:
            front = q if outward else list(reversed(q))
            fuv = uv if outward else list(reversed(uv))
            self.face(front, glass, uvs=fuv, light="glass")
            self.face(list(reversed(front)), glass, uvs=list(reversed(fuv)), light="glass")
        self._glass_faces = []
        for f in self.bm.faces:
            f.smooth = False
        self.bm.normal_update()
        self.bm.to_mesh(self.obj.data)
        # the imported custom normals no longer match the edited mesh: drop them, flat normals per face
        if "custom_normal" in self.obj.data.attributes:
            self.obj.data.attributes.remove(self.obj.data.attributes["custom_normal"])
        self.obj.data.update()

    def build_leaf(self):
        d = next((o.door for o in self.openings if o.door), None)
        if not d:
            return None
        name = self.name + "_door"
        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day, night = bm.loops.layers.color.new("Col"), bm.loops.layers.color.new("Col.001")
        mats = [d["texture"] or "trail_door", TRIM]
        for t in mats:
            m = bpy.data.materials.new(t)
            m.use_nodes = True
            bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            node = m.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = self._image(t) or bpy.data.images.new(t + ".png", 8, 8)
            m.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            mesh.materials.append(m)
        w, h, t = d["width"], d["height"], DOOR_THICK
        (ua, va), (ub, vb) = d["uv"]

        def quad(vs, mi, uvs):
            f = bm.faces.new([bm.verts.new(v) for v in vs])
            f.material_index = mi
            for loop, c in zip(f.loops, uvs):
                loop[uv].uv = c
                loop[day] = OUT_DAY
                loop[night] = OUT_NIGHT

        y0, y1 = -t / 2, t / 2
        quad([(0, y0, 0), (w, y0, 0), (w, y0, h), (0, y0, h)], 0, [(ua, va), (ub, va), (ub, vb), (ua, vb)])
        quad([(w, y1, 0), (0, y1, 0), (0, y1, h), (w, y1, h)], 0, [(ua, va), (ub, va), (ub, vb), (ua, vb)])
        e = [(0, 0), (1, 0), (1, 0.1), (0, 0.1)]
        quad([(0, y1, 0), (0, y0, 0), (0, y0, h), (0, y1, h)], 1, e)
        quad([(w, y0, 0), (w, y1, 0), (w, y1, h), (w, y0, h)], 1, e)
        quad([(0, y0, h), (w, y0, h), (w, y1, h), (0, y1, h)], 1, e)
        quad([(0, y1, 0), (w, y1, 0), (w, y0, 0), (0, y0, 0)], 1, e)
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()
        leaf = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(leaf)
        self.leaf = leaf
        return leaf

    def render(self, view, eye, target, lens=24, size=(960, 600), door_open=0.0):
        """Renders `view` to build/renders/<name>/<view>.png (EEVEE, sun and sky), the door leaf placed at its hinge,
        swung by `door_open` degrees. Look at the PNG to check the work."""
        self._finish_mesh()
        scene = bpy.context.scene
        if self.leaf is None:
            self.build_leaf()
        d = next((o.door for o in self.openings if o.door), None)
        if self.leaf and d:
            self.leaf.location = d["hinge"]
            self.leaf.rotation_euler = (0, 0, math.radians(d["rz"] + door_open))
        cam = bpy.data.objects.get("cam") or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        if cam.name not in scene.collection.objects:
            scene.collection.objects.link(cam)
        cam.data.lens = lens
        cam.data.clip_start = 0.02
        cam.location = eye
        cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()
        scene.camera = cam
        if not bpy.data.objects.get("sun"):
            sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
            sun.data.energy = 3.0
            sun.rotation_euler = (math.radians(50), 0, math.radians(30))
            scene.collection.objects.link(sun)
            lamp = bpy.data.objects.new("lamp", bpy.data.lights.new("lamp", "POINT"))
            lamp.data.energy = 150
            scene.collection.objects.link(lamp)
            if not scene.world:
                scene.world = bpy.data.worlds.new("w")
            scene.world.use_nodes = True
            bg = next(n for n in scene.world.node_tree.nodes if n.type == "BACKGROUND")
            bg.inputs["Color"].default_value = (0.55, 0.62, 0.7, 1)
            bg.inputs["Strength"].default_value = 0.8
            ground = bpy.data.meshes.new("ground")
            gbm = bmesh.new()
            bmesh.ops.create_grid(gbm, x_segments=1, y_segments=1, size=30)
            gbm.to_mesh(ground)
            gbm.free()
            g = bpy.data.objects.new("ground", ground)
            gm = bpy.data.materials.new("ground")
            gm.use_nodes = True
            next(n for n in gm.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (0.25, 0.22, 0.17, 1)
            ground.materials.append(gm)
            scene.collection.objects.link(g)
        if self.rooms:
            r = self.rooms[0]
            bpy.data.objects["lamp"].location = ((r[0] + r[1]) / 2, (r[2] + r[3]) / 2, r[5] - 0.3)
        for engine in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE", "BLENDER_WORKBENCH"):
            try:
                scene.render.engine = engine
                break
            except TypeError:
                continue
        scene.render.resolution_x, scene.render.resolution_y = size
        scene.render.film_transparent = False
        path = os.path.join(RENDERS, self.name, view + ".png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print(f"render: {path}")
        return path

    def export(self):
        """Writes <name>.dff/.col and <name>_door.dff/.col into house_shell/files and build/<name>.json."""
        self._finish_mesh()
        if self.leaf is None:
            self.build_leaf()
        for o in ("cam", "sun", "lamp", "ground"):
            if bpy.data.objects.get(o):
                bpy.data.objects.remove(bpy.data.objects[o])
        os.makedirs(OUT, exist_ok=True)
        d = next((o.door for o in self.openings if o.door), None)
        self._export_one(self.name, self.obj, self.cols)
        if self.leaf and d:
            self.leaf.location, self.leaf.rotation_euler = (0, 0, 0), (0, 0, 0)
            w, h, t = d["width"], d["height"], DOOR_THICK
            self._export_one(self.name + "_door", self.leaf, [[0, -t / 2, 0, w, t / 2, h]])
        meta = {
            "model": self.name,
            "rooms": [[round(v, 4) for v in r] for r in self.rooms],
            "door": {k: (round(v, 4) if isinstance(v, float) else v) for k, v in d.items()} if d else None,
            "openings": [{"kind": o.kind, "axis": o.axis, "side": o.side, "u": [o.u0, o.u1], "z": [o.z0, o.z1]} for o in self.openings],
        }
        if meta["door"]:
            meta["door"]["hinge"] = [round(v, 4) for v in d["hinge"]]
        with open(os.path.join(BUILD, self.name + ".json"), "w") as f:
            json.dump(meta, f, indent=2)
        print(f"export: {self.name} ({len(self.obj.data.polygons)} faces, {len(self.cols)} collision boxes)")

    def _export_one(self, name, obj, boxes):
        coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
        if coll.name not in bpy.context.scene.collection.children:
            bpy.context.scene.collection.children.link(coll)
        for c in obj.users_collection:
            c.objects.unlink(obj)
        coll.objects.link(obj)
        obj.name = name
        obj.dff.type = "OBJ"
        obj.dff.day_cols = True
        obj.dff.night_cols = True
        empties = []
        for i, (x0, y0, z0, x1, y1, z1) in enumerate(boxes):
            e = bpy.data.objects.new(f"{name}_col{i}", None)
            e.empty_display_type = "CUBE"
            e.location = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
            e.scale = ((x1 - x0) / 2, (y1 - y0) / 2, (z1 - z0) / 2)
            e.dff.type = "COL"
            coll.objects.link(e)
            empties.append(e)
        bpy.context.view_layer.update()
        for o in bpy.context.view_layer.objects:
            if o:
                o.select_set(False)
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        bpy.ops.export_dff.scene(filepath=os.path.join(OUT, name + ".dff"), export_coll=False, only_selected=True, export_version="0x36003")
        for o in bpy.context.view_layer.objects:
            if o:
                o.select_set(False)
        for e in empties:
            e.select_set(True)
        bpy.ops.export_col.scene(filepath=os.path.join(OUT, name + ".col"), export_version="3", only_selected=True)
        for e in empties:
            bpy.data.objects.remove(e)


def args():
    return sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
