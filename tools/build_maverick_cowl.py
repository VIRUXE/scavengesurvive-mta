"""The Maverick (model 487) with an engine cowling, after the Bell 206 it is drawn from. The hump behind the rotor
mast keeps its top (the spine, which carries the two exhaust stacks) and its tail end; its two sides between the
firewalls become the cowl doors cowl_l and cowl_r, each its own frame hinged along the spine's edge, so the client
swings them up (setVehicleComponentRotation about the frame's Y) and their prop rods come down onto the sill. Behind
them sits the engine bay: the pan, two steel firewalls and an Allison 250 style turboshaft (compressor and intake at
the front, the accessory gearbox, the two compressor discharge tubes along its sides, the twin exhaust ducts up to
the stacks, the combustor can at the back), an oil tank on the right and the battery on the left of the pan.

    blender --factory-startup -b -t 4 --python tools/build_maverick_cowl.py

Inputs, from GTA Scout's ignored output directory (output/maverick-20261116): src/maverick.dff and src/maverick.txd
(gta3.img). Every texture is a vanilla one (the doors keep the body's primary paint), so maverick.txd ships
unchanged. Outputs: resources/[scavengesurvive]/vehicles/files/maverick.{dff,txd} and a .blend in Scout's directory.
"""

import math
import os
import shutil
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]
SCOUT = Path(os.environ.get("GTA_SCOUT_PATH", str(ROOT.parents[3] / "gta-scout")))
WORK = SCOUT / "output/maverick-20261116"
SRC = WORK / "src"
OUT = ROOT / "resources/[scavengesurvive]/vehicles/files"
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
sys.path.insert(0, str(SCOUT / "references"))
import DragonFF  # noqa: E402

DragonFF.register()

# the cowl doors: the hump's sides between the firewalls (rings of vertices at y -0.11 and -1.32), from the spine's edge
# (|x| 0.36) down to the sill (z 1.42). Aft of the rear firewall the hump runs into the boom and stays shut.
Y_FRONT, Y_REAR, Z_SILL = -0.10, -1.33, 1.41
SPINE_X = 0.355  # the spine's half width: the hinge line
HINGE = (0.365, (Y_FRONT + Y_REAR) / 2, 1.75)  # the right door's; the left one mirrors it
THICK = 0.02  # door skin
OPEN_DEG = 90  # the rods are cut for this angle: keep vehicles/shared/logic/vehicle.lua COWLS in step

bpy.ops.import_scene.dff(filepath=str(SRC / "maverick.dff"), read_mat_split=True, remove_doubles=False, load_images=False)
objs = {o.name: o for o in bpy.data.objects}
chassis = objs["chassis"]
clump = chassis.users_collection[0]
mats = {m.name: m for m in chassis.data.materials}


def fix_textures(mesh):
    """load_images=False leaves texture nodes empty; the exporter takes the texture name from the node's image."""
    for mat in mesh.materials:
        for node in mat.node_tree.nodes if mat and mat.node_tree else ():
            if node.type == "TEX_IMAGE" and node.image is None:
                name = (node.label or node.name).split(".")[0]
                node.image = bpy.data.images.get(name) or bpy.data.images.new(name, 4, 4)


for o in bpy.data.objects:
    if o.type == "MESH":
        fix_textures(o.data)

# vehiclegeneric256 areas (pixels x0, y0, x1, y1) and the tint over them
TEX = 256
WHITE, GRIME, STEEL, DETAIL, BLACK = (6, 6, 118, 70), (132, 132, 252, 188), (196, 196, 252, 222), (130, 2, 200, 60), (68, 132, 124, 188)
PARTS = {
    "bay_pan": (GRIME, (0.60, 0.60, 0.60)),  # the engine pan
    "bay_firewall": (STEEL, (0.80, 0.80, 0.82)),  # stainless firewalls
    "bay_liner": (WHITE, (0.38, 0.42, 0.22)),  # zinc chromate primer: inside of the skins
    "eng_case": (STEEL, (0.62, 0.64, 0.66)),  # compressor, gearbox
    "eng_detail": (DETAIL, (0.85, 0.85, 0.85)),
    "eng_hot": (STEEL, (0.50, 0.38, 0.28)),  # heat-stained turbine and combustor
    "eng_exhaust": (GRIME, (0.34, 0.30, 0.28)),
    "eng_tube": (STEEL, (0.95, 0.95, 0.95)),
    "bay_black": (BLACK, (0.55, 0.55, 0.55)),
    "bay_tank": (WHITE, (0.30, 0.34, 0.30)),
}
GENERIC = mats["generic"]
MAT = {}
for name, (_, rgb) in PARTS.items():
    m = GENERIC.copy()
    m.name = name
    next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED").inputs["Base Color"].default_value = (*rgb, 1.0)
    MAT[name] = m
ORDER = list(PARTS)


def area_uv(name, s, t):
    x0, y0, x1, y1 = PARTS[name][0]
    return ((x0 + (x1 - x0) * (s % 1.0001)) / TEX, 1 - (y0 + (y1 - y0) * (t % 1.0001)) / TEX)


body = chassis.data
assert chassis.matrix_world == Matrix.Identity(4)

# the hump's half section (|x|, z) at each ring, from the ridge down to the sill
rings = {}
for v in body.vertices:
    y = round(v.co.y, 2)
    if y in (-0.11, -0.67, -1.32) and v.co.z >= Z_SILL and abs(v.co.x) < 0.7:
        rings.setdefault(y, set()).add((round(abs(v.co.x), 3), round(v.co.z, 3)))
rings = {y: sorted(pts, key=lambda p: -p[1]) for y, pts in rings.items()}
# the rear ring has no vertex on the ridge: the ridge runs straight from y -0.67 (z 1.771) to y -1.97 (z 1.65)
rings[-1.32].insert(0, (0.0, 1.71))
ring_ys = sorted(rings, reverse=True)
for y in ring_ys:
    print("ring", y, rings[y])


def resample(poly, n):
    """n points evenly along a polyline of (x, z)."""
    seg = [math.dist(a, b) for a, b in zip(poly, poly[1:])]
    total, out = sum(seg), []
    for i in range(n):
        d, k = total * i / (n - 1), 0
        while k < len(seg) - 1 and d > seg[k]:
            d -= seg[k]
            k += 1
        t = d / seg[k] if seg[k] else 0
        out.append((poly[k][0] + (poly[k + 1][0] - poly[k][0]) * t, poly[k][1] + (poly[k + 1][1] - poly[k][1]) * t))
    return out


def section(y, door=False, n=7):
    """The half section at y between the rings; door: only from the spine's edge down."""
    def at(ry):
        pts = [p for p in rings[ry] if not door or p[0] >= SPINE_X - 0.01]
        return resample(pts, n)

    y = min(max(y, ring_ys[-1]), ring_ys[0])
    for a, b in zip(ring_ys, ring_ys[1:]):
        if a >= y >= b:
            t = (a - y) / (a - b)
            return [(pa[0] + (pb[0] - pa[0]) * t, pa[1] + (pb[1] - pa[1]) * t) for pa, pb in zip(at(a), at(b))]


def in_door(f, side):
    return all(Y_REAR <= v.co.y <= Y_FRONT and v.co.z >= Z_SILL and v.co.x * side >= SPINE_X - 0.01 for v in f.verts)


doors = {}
for side, name in ((-1, "cowl_l"), (1, "cowl_r")):
    part = body.copy()
    part.name = name
    bm = bmesh.new()
    bm.from_mesh(part)
    bmesh.ops.delete(bm, geom=[f for f in bm.faces if not in_door(f, side)], context="FACES")
    bm.to_mesh(part)
    bm.free()
    doors[name] = part
    print(f"{name}: {len(part.polygons)} skin faces")

bm = bmesh.new()
bm.from_mesh(body)
cut = [f for f in bm.faces if in_door(f, 1) or in_door(f, -1)]
bmesh.ops.delete(bm, geom=cut, context="FACES")
bm.to_mesh(body)
bm.free()
print(f"chassis: {len(cut)} faces cut, {len(body.polygons)} left")


# --- geometry helpers: everything is built into a bmesh with one UV layer and the PARTS materials ------------------
class Build:
    def __init__(self):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("Float2")

    def face(self, pts, mat, toward=None, uvs=None):
        """A face over pts; `toward` (a point the face looks at, or a direction with dir=True) fixes its winding."""
        pts = [Vector(p) for p in pts]
        n = (pts[1] - pts[0]).cross(pts[2] - pts[0])
        if toward is not None and n.dot(Vector(toward) - pts[0]) < 0:
            pts.reverse()
            uvs = list(reversed(uvs)) if uvs else None
        f = self.bm.faces.new([self.bm.verts.new(p) for p in pts])
        f.material_index = ORDER.index(mat)
        default = ((0, 0), (1, 0), (1, 1), (0, 1))
        for i, loop in enumerate(f.loops):
            s, t = uvs[i] if uvs else default[i % 4]
            loop[self.uv].uv = area_uv(mat, s, t)

    def box(self, lo, hi, mat, top=None):
        (x0, y0, z0), (x1, y1, z1) = lo, hi
        c = Vector(((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2))
        v = [(x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), (x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)]
        for idx in ((4, 5, 6, 7), (0, 3, 2, 1), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)):
            pts = [Vector(v[i]) for i in idx]
            out = sum(pts, Vector()) / 4
            self.face(pts, top if (top and idx == (4, 5, 6, 7)) else mat, toward=out + (out - c))

    def tube(self, p0, p1, r0, mat, sides=12, r1=None, cap0=True, cap1=True, cap_mat=None):
        """A (tapered) cylinder from p0 to p1, capped."""
        p0, p1 = Vector(p0), Vector(p1)
        r1 = r0 if r1 is None else r1
        axis = (p1 - p0).normalized()
        u = axis.orthogonal().normalized()
        w = axis.cross(u)
        ring = lambda p, r: [p + (u * math.cos(2 * math.pi * i / sides) + w * math.sin(2 * math.pi * i / sides)) * r for i in range(sides)]
        a, b = ring(p0, r0), ring(p1, r1)
        mid = (p0 + p1) / 2
        for i in range(sides):
            j = (i + 1) % sides
            quad = [a[i], a[j], b[j], b[i]]
            out = sum(quad, Vector()) / 4
            self.face(quad, mat, toward=out + (out - mid), uvs=[(i / sides, 0), ((i + 1) / sides, 0), ((i + 1) / sides, 1), (i / sides, 1)])
        fan = [(0.5 + 0.5 * math.cos(2 * math.pi * i / sides), 0.5 + 0.5 * math.sin(2 * math.pi * i / sides)) for i in range(sides)]
        if cap0:
            self.face(a, cap_mat or mat, toward=p0 - axis, uvs=fan)
        if cap1:
            self.face(b, cap_mat or mat, toward=p1 + axis, uvs=fan)

    def mesh(self, name):
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for n in ORDER:
            me.materials.append(MAT[n])
        me.validate()
        return me


def join(target, extra):
    """Appends `extra` (PARTS materials) to `target`, whose own materials stay first."""
    offset = len(target.materials)
    for m in extra.materials:
        target.materials.append(m)
    for p in extra.polygons:
        p.material_index += offset
    extra.materials.clear()
    for m in target.materials:
        extra.materials.append(m)
    bm = bmesh.new()
    bm.from_mesh(target)
    bm.from_mesh(extra)
    bm.to_mesh(target)
    bm.free()
    target.validate()


# --- the doors: the skin, its primer inside with three ribs and a lip, and the prop rod -----------------------------
def rot_y(p, origin, deg):
    """p turned about the Y axis through origin, the way Blender (and the frame) turns it."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    x, z = p[0] - origin[0], p[2] - origin[2]
    return (origin[0] + x * c + z * s, p[1], origin[2] - x * s + z * c)


def thicken(mesh):
    """The single-sided skin with a primed inner face THICK inward and the rim between them, from the skin's own
    faces (anything rebuilt from sections strays from the skin and shows as slivers)."""
    liner = MAT["bay_liner"]
    ob = bpy.data.objects.new("tmp", mesh)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(liner)
    mod = ob.modifiers.new("solid", "SOLIDIFY")
    mod.thickness = THICK
    mod.offset = -1
    mod.use_even_offset = True
    mod.material_offset = len(ob.data.materials) - 1
    mod.material_offset_rim = len(ob.data.materials) - 1
    out = bpy.data.meshes.new_from_object(ob.evaluated_get(bpy.context.evaluated_depsgraph_get()))
    out.name = mesh.name
    bpy.data.objects.remove(ob)
    uv = out.uv_layers.active
    for p in out.polygons:
        if out.materials[p.material_index] is liner:
            for li in p.loop_indices:
                co = out.vertices[out.loops[li].vertex_index].co
                uv.data[li].uv = area_uv("bay_liner", (co.y + 1.4) / 1.4, (co.z - 1.38) / 0.42)
    return out


def inset(prof, side, y, d):
    """A half section's points moved d inward, each along its own normal in the section's plane."""
    out = []
    for i, (x, z) in enumerate(prof):
        (ax, az), (bx, bz) = prof[max(i - 1, 0)], prof[min(i + 1, len(prof) - 1)]
        tx, tz = bx - ax, bz - az
        length = math.hypot(tx, tz) or 1.0
        nx, nz = tz / length, -tx / length  # the profile runs from the spine down and out: this side faces in
        if nx * (0 - x) + nz * (1.5 - z) < 0:
            nx, nz = -nx, -nz
        out.append(Vector(((x + nx * d) * side, y, z + nz * d)))
    return out


for side, name in ((-1, "cowl_l"), (1, "cowl_r")):
    hinge = Vector((HINGE[0] * side, HINGE[1], HINGE[2]))
    doors[name] = thicken(doors[name])
    b = Build()
    ys = [Y_FRONT - 0.03 + (Y_REAR - Y_FRONT + 0.06) * i / 6 for i in range(7)]
    prof = [inset(section(y, door=True), side, y, THICK + 0.006) for y in ys]
    centre = Vector((0, HINGE[1], 1.5))
    for i in (1, 3, 5):  # hat-section ribs across the door, standing on the primer
        for k in range(1, len(prof[i]) - 2):
            p, q = prof[i][k], prof[i][k + 1]
            n = (centre - (p + q) / 2).normalized() * 0.016
            for dy in (-0.02, 0.02):
                o = Vector((0, dy, 0))
                b.face([p + o, q + o, q + o + n, p + o + n], "bay_liner", toward=(p + q) / 2 + Vector((0, dy * 50, 0)))
            o = Vector((0, 0.02, 0))
            b.face([p - o + n, q - o + n, q + o + n, p + o + n], "bay_liner", toward=centre)
    # the prop rod: from the door's lower rib end down to the sill when the door stands open, so it is built open
    # and turned back shut (where it lies inside the bay)
    for ry in (ys[1], ys[5]):
        low = prof[1][-2] if ry == ys[1] else prof[5][-2]
        top = Vector(rot_y(low, hinge, -side * OPEN_DEG))
        sx, sz = section(ry)[-1]
        foot = Vector((side * (sx - 0.03), ry, sz))
        b.tube(rot_y(top, hinge, side * OPEN_DEG), rot_y(foot, hinge, side * OPEN_DEG), 0.008, "eng_tube", sides=5)
    inner = b.mesh(name + "_inner")
    join(doors[name], inner)
    doors[name].transform(Matrix.Translation(-hinge))
    print(f"{name}: {len(doors[name].polygons)} faces, hinge {tuple(round(c, 3) for c in hinge)}")


# --- the engine bay ---------------------------------------------------------------------------------------------------
b = Build()
PAN = Z_SILL + 0.012
mid = Vector((0, HINGE[1], 1.58))
ys = [Y_FRONT + (Y_REAR - Y_FRONT) * i / 6 for i in range(7)]
for ya, yb in zip(ys, ys[1:]):  # the pan
    wa, wb = section(ya)[-1][0], section(yb)[-1][0]
    b.face([(-wa, ya, PAN), (wa, ya, PAN), (wb, yb, PAN), (-wb, yb, PAN)], "bay_pan", toward=mid)
    # the spine's underside, primed
    (ha, za0), (hb, zb0) = section(ya, door=True)[0], section(yb, door=True)[0]
    za, zb = section(ya)[0][1], section(yb)[0][1]
    for s in (-1, 1):
        b.face([(0, ya, za - 0.012), (s * ha, ya, za0 - 0.012), (s * hb, yb, zb0 - 0.012), (0, yb, zb - 0.012)], "bay_liner", toward=mid)
for y, look in ((Y_FRONT - 0.005, -1), (Y_REAR + 0.005, 1)):  # the firewalls
    half = section(y)
    prof = [(-x, z) for x, z in reversed(half)] + [(x, z) for x, z in half[1:]]
    for (xa, za), (xb, zb) in zip(prof, prof[1:]):
        b.face([(xa, y, PAN), (xa, y, za - 0.005), (xb, y, zb - 0.005), (xb, y, PAN)], "bay_firewall", toward=(0, y + look * -1, 1.6), uvs=[(xa + 0.6, 0), (xa + 0.6, 1), (xb + 0.6, 1), (xb + 0.6, 0)])

AX = 1.565  # the engine's centreline height
b.tube((0, -0.20, AX), (0, -0.27, AX), 0.135, "eng_case", 14, 0.105, cap_mat="bay_black")  # intake bellmouth
b.tube((0, -0.27, AX), (0, -0.56, AX), 0.105, "eng_case", 14)  # compressor
for y in (-0.33, -0.41, -0.49):  # its stator bands
    b.tube((0, y, AX), (0, y - 0.015, AX), 0.112, "eng_tube", 14)
b.box((-0.13, -0.80, PAN + 0.02), (0.13, -0.56, AX + 0.07), "eng_case", "eng_detail")  # accessory gearbox
b.tube((0, -0.80, AX), (0, -0.98, AX), 0.118, "eng_hot", 14)  # turbine
b.tube((0, -0.98, AX), (0, -1.20, AX), 0.128, "eng_hot", 14)  # combustor can
b.tube((0, -1.20, AX), (0, -1.26, AX), 0.128, "eng_hot", 14, 0.05)  # its dome
for s in (-1, 1):
    # compressor discharge tubes: from the compressor's scroll back along the sides into the combustor
    b.tube((s * 0.10, -0.54, AX + 0.02), (s * 0.175, -0.62, AX + 0.03), 0.028, "eng_tube", 8)
    b.tube((s * 0.175, -0.62, AX + 0.03), (s * 0.175, -1.08, AX + 0.03), 0.028, "eng_tube", 8)
    b.tube((s * 0.175, -1.08, AX + 0.03), (s * 0.11, -1.16, AX + 0.02), 0.028, "eng_tube", 8)
    # exhaust ducts up through the spine to the stacks
    top = section(-0.86)[0][1]
    b.tube((s * 0.07, -0.86, AX + 0.05), (s * 0.115, -0.86, top + 0.02), 0.055, "eng_exhaust", 10, 0.062)
    b.tube((s * 0.115, -0.86, top + 0.02), (s * 0.15, -0.88, top + 0.13), 0.062, "eng_exhaust", 10, 0.066, cap_mat="bay_black")
    # engine mounts: a bipod each side from the gearbox to the pan
    for y in (-0.60, -0.76):
        b.tube((s * 0.13, y, AX - 0.02), (s * 0.30, y - s * 0 - 0.0, PAN), 0.012, "eng_tube", 5)
b.box((0.26, -1.27, PAN), (0.42, -1.07, PAN + 0.17), "bay_tank")  # oil tank
b.tube((0.34, -1.17, PAN + 0.17), (0.34, -1.17, PAN + 0.20), 0.03, "bay_black", 8)  # its filler cap
BATTERY = ((-0.44, -1.27, PAN), (-0.24, -1.05, PAN + 0.17))
b.box(*BATTERY, "bay_black")
for y in (-1.22, -1.10):
    b.tube((-0.34, y, PAN + 0.17), (-0.34, y, PAN + 0.195), 0.014, "eng_tube", 6)  # terminals
bay = b.mesh("engine_bay")
n_bay = len(bay.polygons)
join(body, bay)
print(f"chassis with bay: {len(body.polygons)} faces (bay {n_bay})")

# --- the door frames ---------------------------------------------------------------------------------------------------
for side, name in ((-1, "cowl_l"), (1, "cowl_r")):
    ob = bpy.data.objects.new(name, doors[name])
    ob.dff.type = "OBJ"
    ob.dff.is_frame = True
    clump.objects.link(ob)
    ob.parent = objs["chassis_dummy"]
    ob.matrix_world = Matrix.Translation((HINGE[0] * side, HINGE[1], HINGE[2]))
bpy.context.view_layer.update()

for o in bpy.data.objects:
    o.select_set(False)
out = OUT / "maverick.dff"
bpy.ops.export_dff.scene(filepath=str(out), export_coll=True, only_selected=False, export_version="0x36003")
shutil.copyfile(SRC / "maverick.txd", OUT / "maverick.txd")
bpy.ops.wm.save_as_mainfile(filepath=str(WORK / "maverick_cowl.blend"))
print(f"maverick: {out} ({out.stat().st_size} bytes), open {OPEN_DEG}")
