"""Port prop models for the prop_models resource (ids 20201+): one table row, one build function each.

    python -m tools.make_props [--gta DIR] [--blender EXE] [name ...]

Outside Blender it cuts each prop's vanilla TXD from gta3.img down to the textures the prop uses (as
tools/extract_samp_models.py trims vanilla TXDs), writes prop_models/props.lua (every row) and prop_models/meta.xml,
then runs itself in Blender (DragonFF) for each prop's dff and col.

    ls_hatch  20201  the Ganton ladder entrance's cast-iron hatch: a 1 m square plate, 4 cm thick, wearing pave_manhole1
                     (a square "BO-NESS IRON CO LTD / METER" cover from zombtest1.txd) on top and the cover's rim on
                     its edges, dim day/night prelight, one box of collision (world/puzzles/ranch.pwn "LS entrance").
    welder    20202  a portable welder: red body with a carry handle and louvres, yellow control panel on the +Y face
                     with the torch lead's plug (its end at WELDER_SOCKET), an earth lead with a clamp on the floor and
                     a holster collar on the -X side that welder_torch stands in at TORCH_STOWED.

    gas_bottle 20203 a propane bottle: the Airstream's own right-hand tank (the faces of the vanilla sm_airstrm_med_.dff
                     textured sm_airstreamside2 on the A-frame), stood on its base; one box of collision.

    generator 20204  a portable inverter generator after the Honda EU2200i: rounded red shell between black end caps, a
                     carry handle along X on top (centre at GENERATOR_HANDLE_Z), a fuel cap, a control panel with two
                     sockets on +Y, louvres on -Y; every surface a vanilla texture (GEN_TEXTURES, from five TXDs, merged);
                     0.52 x 0.32 x 0.45 m, one box of collision.

    welder_torch 20205  a hand-held MIG gun, 0.32 m: black grip with a trigger, rubber gooseneck, chrome collars, a
                     brass nozzle, a stub of lead (its end at TORCH_LEAD; the rest is drawn in game). Origin at the
                     grip's centre, the grip along Y, the nozzle forward (+Y) and bent down 50 degrees, trigger on -Z.

    grinder  20206   a cordless 115 mm angle grinder, 0.33 m: yellow motor housing (rubber grip band, paddle switch, vents),
                     a black battery under the tail, a cast gear head with the disc under it at GRINDER_DISC, a guard over
                     the disc's rear half and a side handle out of +X; every surface a vanilla texture (GRINDER_TEXTURES,
                     found with gta-scout). Origin at the grip's centre, the housing along Y, the disc forward (+Y) and
                     down (-Z); its lowest point at GRINDER_LOW.
    grind_disc 20207  a spare grinding disc for the grinder, lying flat: GRINDER_DISC's disc on its own.

    car_battery 20208 a 12 V lead-acid car battery, 0.26 x 0.17 m, 0.2 m with its strap: black case with ribs and a warning label,
                     a lid with a red (+) and a black (-) lead post, vent plugs and a carry strap along X (top at
                     BATTERY_HANDLE_Z); vanilla textures (BATTERY_TEXTURES, found with gta-scout). The Battery item.
    tool_battery 20209 a cordless tool's slide-on 18 V pack, the one under the grinder's tail (tool_pack), standing on its foot:
                     black body, yellow latch band, charge lamps on +Y; GRINDER_TEXTURES' subset (TOOL_BATTERY_TEXTURES).

    ratchet  20236   a socket ratchet, 0.25 m: a chrome handle along Y with a knurled rubber grip (the origin at the grip's
                     centre), a round head toward +Y, a reversing lever on the head and a square drive under it with a
                     socket fitted; vanilla textures (RATCHET_TEXTURES, found with gta-scout). One box of collision.

Origin (except welder_torch, grinder and ratchet): the centre of the base (x, y) with z = 0 at the lowest point; the front faces +Y.
"""
from __future__ import annotations

import math
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROP_MODELS = ROOT / "resources" / "[scavengesurvive]" / "prop_models"
FILES = PROP_MODELS / "files"
PROPS = PROP_MODELS / "props.lua"

SIZE, THICK, RIM = 1.0, 0.04, 0.04  # ls_hatch, metres; RIM: the share of the texture the edges show
DAY, NIGHT = (0.38, 0.38, 0.38, 1.0), (0.12, 0.12, 0.13, 1.0)


def build_ls_hatch(ctx):
    bm, h = ctx["bm"], SIZE / 2
    corners = [(-h, -h), (h, -h), (h, h), (-h, h)]
    top = [bm.verts.new((x, y, THICK)) for x, y in corners]
    low = [bm.verts.new((x, y, 0.0)) for x, y in corners]
    faces = [(bm.faces.new(top), [(0, 0), (1, 0), (1, 1), (0, 1)])]
    for i in range(4):
        j = (i + 1) % 4
        faces.append((bm.faces.new((low[i], low[j], top[j], top[i])), [(0, 0), (1, 0), (1, RIM), (0, RIM)]))
    for face, uvs in faces:
        ctx["paint"](face, uvs, DAY, NIGHT, 0)
    return [((0.0, 0.0, THICK / 2), (h, h, THICK / 2))]


WELDER_SOCKET = (-0.1, 0.195, 0.08)  # welder.dff: the end of the torch lead's plug on the +Y panel
TORCH_STOWED = (-0.27, -0.07, 0.18, -90, 0, 0)  # welder_torch in the welder's holster: x, y, z, rx, ry, rz (degrees)
TORCH_LEAD = (0.0, -0.155, 0.0)  # welder_torch.dff: the end of the lead stub out of the back of the grip
# (source TXD, texture) per welder_torch material: black grip, rubber neck and lead, chrome collars, brass nozzle
TORCH_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("cj_airprt.txd", "CJ_RUBBER"), ("industrialext.txd", "cj_chromepipe"), ("vgsedragon.txd", "buddha_gold")]


def build_welder_torch(ctx):
    """A MIG welding gun, the grip along Y with the origin at its centre, the trigger under it (-Z), a gooseneck
    bending the nozzle down from +Y and a stub of lead out of the back (-Y, ending at TORCH_LEAD)."""
    box, tube = ctx["box"], ctx["tube"]
    grip, rubber, chrome, brass = 0, 1, 2, 3
    white, dim, dark = (0.9, 0.9, 0.9, 1.0), (0.55, 0.55, 0.55, 1.0), (0.12, 0.1, 0.08, 1.0)
    lead, neck = (0.35, 0.35, 0.36, 1.0), (0.7, 0.7, 0.72, 1.0)
    # the lead stub and its strain-relief boot behind the grip
    tube(TORCH_LEAD, (0.0, -0.118, 0.0), 0.008, 8, rubber, lead)
    tube((0.0, -0.118, 0.0), (0.0, -0.098, 0.0), 0.012, 10, rubber, lead)
    tube((0.0, -0.098, 0.0), (0.0, -0.08, 0.0), 0.016, 10, rubber, lead)
    # the grip, the trigger under its front half, the chrome collar the neck screws into
    tube((0.0, -0.075, 0.0), (0.0, 0.052, 0.0), 0.019, 12, grip, None)
    box((0.0, 0.018, -0.021), (0.009, 0.032, 0.016), grip, dim)
    tube((0.0, 0.052, 0.0), (0.0, 0.066, 0.0), 0.015, 12, chrome, white)
    # the gooseneck: a 50 degree arc of radius 0.08 bending down, then the nozzle along its end
    r, n, sweep = 0.08, 6, math.radians(50)
    arc = [(0.0, 0.066 + r * math.sin(sweep * i / n), -r + r * math.cos(sweep * i / n)) for i in range(n + 1)]
    for a, b in zip(arc, arc[1:]):
        tube(a, b, 0.009, 8, rubber, neck)
    d = (0.0, math.cos(sweep), -math.sin(sweep))
    at = lambda t: (arc[-1][0], arc[-1][1] + d[1] * t, arc[-1][2] + d[2] * t)
    tube(arc[-1], at(0.006), 0.011, 10, chrome, white)
    tube(at(0.006), at(0.034), 0.0125, 12, brass, None)
    tube(at(0.034), at(0.05), 0.0105, 12, brass, None)
    tube(at(0.05), at(0.052), 0.007, 8, brass, dark)
    return [((0.0, 0.0, -0.02), (0.02, 0.16, 0.05))]


def build_welder(ctx):
    box, tube, red, panel, alu = ctx["box"], ctx["tube"], 0, 1, 2
    dark, mid = (0.16, 0.16, 0.17, 1.0), (0.6, 0.6, 0.6, 1.0)
    for x in (-0.17, 0.17):
        box((x, 0.0, 0.015), (0.05, 0.25, 0.03), alu, mid)
    box((0.0, 0.0, 0.15), (0.45, 0.25, 0.24), red, None)
    for x in (-0.15, 0.15):
        box((x, 0.0, 0.31), (0.03, 0.03, 0.08), alu, mid)
    box((0.0, 0.0, 0.335), (0.33, 0.03, 0.03), alu, mid)
    for side in (-1, 1):
        for i in range(4):
            box((side * 0.2275, -0.03 + i * 0.025, 0.2), (0.005, 0.012, 0.1), alu, dark)
    box((0.0, 0.13, 0.15), (0.37, 0.01, 0.19), panel, None)
    tube((-0.08, 0.135, 0.19), (-0.08, 0.152, 0.19), 0.04, 10, alu, mid)
    tube((-0.08, 0.152, 0.19), (-0.08, 0.158, 0.19), 0.028, 10, alu, dark)
    tube((0.08, 0.135, 0.19), (0.08, 0.158, 0.19), 0.025, 8, alu, dark)
    tube((-0.1, 0.135, 0.08), (-0.1, 0.165, 0.08), 0.018, 8, alu, mid)
    tube((0.1, 0.135, 0.08), (0.1, 0.165, 0.08), 0.018, 8, alu, dark)
    # the torch lead's plug in the left socket; the lead itself is drawn in game from WELDER_SOCKET
    tube((-0.1, 0.165, 0.08), (-0.1, WELDER_SOCKET[1] - 0.006, 0.08), 0.012, 8, alu, dark)
    earth = [(0.1, 0.165, 0.08), (0.1, 0.2, 0.05), (0.14, 0.26, 0.01), (0.24, 0.28, 0.01)]
    for a, b in zip(earth, earth[1:]):
        tube(a, b, 0.008, 6, alu, dark)
    box((0.28, 0.28, 0.012), (0.06, 0.035, 0.024), alu, mid)
    # the torch holster on -X: a square collar the grip stands in (front down), on a bracket bolted to the side
    hx, hy, hz = TORCH_STOWED[0], TORCH_STOWED[1], 0.16
    inner, wall, tall = 0.021, 0.006, 0.04
    box((-0.234, hy, hz), (0.018, 0.05, tall), alu, mid)
    for s in (-1, 1):
        box((hx + s * (inner + wall / 2), hy, hz), (wall, 2 * (inner + wall), tall), alu, mid)
        box((hx, hy + s * (inner + wall / 2), hz), (2 * inner, wall, tall), alu, mid)
    return [((0.0, 0.0, 0.15), (0.225, 0.125, 0.15))]


TANK_SHELL = ROOT / "tools" / "trailer_shells" / "build" / "vanilla" / "sm_airstrm_med_.dff"  # tools/trailer_shells/prep.py
TANK_TEXTURE = "sm_airstreamside2"


def tank_faces(texture_name, centre):
    """The Airstream's right-hand propane tank: the A-frame's faces in the tank texture, x > 0 (towable.py splits the same)."""
    return texture_name == TANK_TEXTURE and centre.y > 4.08 and centre.z < 1.4 and centre.x > 0


def build_gas_bottle(ctx):
    lo, hi = ctx["graft"](str(TANK_SHELL), "sm_airstrm_med_", tank_faces, 0)
    return [(((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, (lo[2] + hi[2]) / 2), ((hi[0] - lo[0]) / 2, (hi[1] - lo[1]) / 2, (hi[2] - lo[2]) / 2))]


GENERATOR_HANDLE_Z = 0.42  # height of the carry bar's centre above the base (generator.dff, bar along X, x -0.15 .. 0.15, y 0)
GEN_HX, GEN_HY, GEN_Z0, GEN_Z1 = 0.25, 0.15, 0.06, 0.33  # the red shell's half length, half width, bottom and top
# (source TXD, texture) per material, all vanilla: glossy red plastic, black plastic, a louvred vent, a double socket, rubber
GEN_TEXTURES = [("cj_airprt.txd", "CJ_red_COUNTER"), ("ballys01.txd", "CJ_blackplastic"), ("a51.txd", "ventb64"), ("des_airfieldhus.txd", "cj_socket"), ("cj_airprt.txd", "CJ_RUBBER")]


def gen_profile(scale):
    """The shell's rounded-rectangle section (y, z), 16 points: big top corners, small bottom ones, shrunk about its centre."""
    zc = (GEN_Z0 + GEN_Z1) / 2
    out = []
    for cy, cz, r, a0 in ((1, 1, 0.08, 0), (-1, 1, 0.08, 90), (-1, -1, 0.03, 180), (1, -1, 0.03, 270)):
        for k in range(4):
            a = math.radians(a0 + 30 * k)
            y = cy * (GEN_HY - r) + r * math.cos(a)
            z = (GEN_Z1 - r if cz > 0 else GEN_Z0 + r) + r * math.sin(a)
            out.append((y * scale, zc + (z - zc) * scale))
    return out


def build_generator(ctx):
    """A portable inverter generator after the Honda EU2200i: a rounded red shell between black end caps on a black base,
    the carry handle moulded into the top, a flat fuel cap at one end, the control panel (two sockets, switch, lamps) on
    +Y, louvres on -Y and an exhaust grille on -X, the pull-start handle on +X."""
    bm, box, tube, paint = ctx["bm"], ctx["box"], ctx["tube"], ctx["paint"]
    red, black, vent, socket, rubber = 0, 1, 2, 3, 4
    white, grey = (0.95, 0.95, 0.95, 1.0), (0.7, 0.7, 0.7, 1.0)
    night = lambda c: (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    # the shell: the section lofted along X; the outer bands taper in and are the black end caps
    stations = ((-GEN_HX, 0.86), (-GEN_HX + 0.02, 0.96), (-0.215, 1.0), (0.215, 1.0), (GEN_HX - 0.02, 0.96), (GEN_HX, 0.86))
    rings = [[bm.verts.new((x, y, z)) for y, z in gen_profile(s)] for x, s in stations]
    n = len(rings[0])
    for i in range(len(rings) - 1):
        cap = i != 2
        for j in range(n):
            k = (j + 1) % n
            face = bm.faces.new((rings[i][j], rings[i][k], rings[i + 1][k], rings[i + 1][j]))
            u0, u1 = (stations[i][0] + GEN_HX) / (2 * GEN_HX), (stations[i + 1][0] + GEN_HX) / (2 * GEN_HX)
            paint(face, [(u0, j / n), (u0, (j + 1) / n), (u1, (j + 1) / n), (u1, j / n)], white, night(white), black if cap else red)
    for ring in (rings[0], rings[-1]):
        face = bm.faces.new(ring)
        paint(face, [(0.5 + 0.5 * math.cos(2 * math.pi * i / n), 0.5 + 0.5 * math.sin(2 * math.pi * i / n)) for i in range(n)], white, night(white), black)
    # the black base band under the shell, rubber feet
    box((0.0, 0.0, 0.045), (0.47, 0.27, 0.05), black, None)
    for x in (-0.19, 0.19):
        for y in (-0.1, 0.1):
            tube((x, y, 0.0), (x, y, 0.022), 0.022, 8, rubber, None)
    # the control panel on +Y: a black plate on the lower half with two sockets, the eco switch and three lamps
    box((0.03, GEN_HY + 0.002, 0.15), (0.3, 0.012, 0.13), black, None)
    for x in (-0.06, 0.07):
        box((x, GEN_HY + 0.01, 0.14), (0.09, 0.006, 0.07), socket, None)
    box((0.15, GEN_HY + 0.011, 0.18), (0.03, 0.008, 0.02), black, grey)
    for i, z in enumerate((0.2, 0.18, 0.16)):
        box((-0.13, GEN_HY + 0.01, z), (0.012, 0.006, 0.012), red if i else black, None)
    # louvres on -Y, the exhaust grille on the -X end, the pull-start handle on the +X end
    box((-0.03, -GEN_HY - 0.001, 0.19), (0.24, 0.006, 0.14), vent, None)
    box((-GEN_HX - 0.001, 0.0, 0.17), (0.006, 0.17, 0.1), vent, None)
    box((GEN_HX + 0.012, 0.03, 0.2), (0.016, 0.08, 0.02), black, None)
    # the fuel cap: a flat black disc on the top at the +X end; a fuel gauge window beside it
    tube((0.195, 0.0, GEN_Z1 - 0.004), (0.195, 0.0, GEN_Z1 + 0.012), 0.036, 12, black, None)
    tube((0.195, 0.0, GEN_Z1 + 0.012), (0.195, 0.0, GEN_Z1 + 0.022), 0.024, 12, black, grey)
    # the carry handle moulded into the top: two red posts and a black grip bar along X at GENERATOR_HANDLE_Z
    for x in (-0.12, 0.12):
        box((x, 0.0, (GEN_Z1 + GENERATOR_HANDLE_Z) / 2), (0.05, 0.07, GENERATOR_HANDLE_Z - GEN_Z1 + 0.02), red, None)
    tube((-0.145, 0.0, GENERATOR_HANDLE_Z), (0.145, 0.0, GENERATOR_HANDLE_Z), 0.022, 10, black, None)
    return [((0.0, 0.0, 0.22), (0.26, 0.16, 0.22))]


GRINDER_DISC = (0.0, 0.1, -0.0485)  # grinder.dff: the cutting disc's centre, the spindle along -Z
GRINDER_LOW = -0.058  # grinder.dff: the lowest point (the battery's foot and the guard's rim), its item type's modelz
# (source TXD, texture) per grinder material, all vanilla and found with gta-scout: yellow painted housing, black plastic,
# rubber grip, dark cast metal (gear head, guard), a dark wheel with a bright hub (the disc), chrome, louvred vent
GRINDER_TEXTURES = [("helixbarrier.txd", "yellow"), ("ballys01.txd", "CJ_blackplastic"), ("cj_airprt.txd", "CJ_RUBBER"), ("des_clifftown.txd", "drvin_metal"), ("trailers.txd", "trail_wheel"), ("industrialext.txd", "cj_chromepipe"), ("bistro.txd", "vent_64")]


def tool_pack(ctx, centre, black, yellow, dim):
    """The cordless tool's battery pack: a black body around `centre`, a wider foot under it (the pack's lowest point is
    TOOL_PACK_LOW below the centre) and a yellow latch band on top. Shared by the grinder and the loose Tool Battery."""
    box = ctx["box"]
    cx, cy, cz = centre
    box((cx, cy, cz), (0.058, 0.05, 0.05), black, None)
    box((cx, cy, cz - 0.034), (0.064, 0.056, 0.024), black, dim)
    box((cx, cy, cz + 0.027), (0.052, 0.044, 0.006), yellow, None)


TOOL_PACK_LOW = 0.046  # tool_pack: the body centre's height above the foot's underside
# UV rectangles (u0, v0, u1, v1; u0 > u1 mirrors) cut out of a texture: the "dude" brand logo on the right half of the garage
# welder's panel, the hazard triangle on the yellow barrel paint, the green swatch of the colour boxes
DUDE_LOGO = (1.0, 0.4, 0.5, 0.68)  # on a +Y face (its u runs along -X seen from the front)
HAZARD = (0.74, 0.81, 0.3, 0.37)  # on a top face, turned to read from +Y
GREEN = (0.4, 0.42, 0.6, 0.58)
# (source TXD, texture) per tool_battery material, all vanilla and found with gta-scout: black plastic, the grinder's yellow,
# the colour boxes (green charge lamps), chrome contacts, the "dude" label
TOOL_BATTERY_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("helixbarrier.txd", "yellow"), ("helixbarrier.txd", "colourboxes"), ("industrialext.txd", "cj_chromepipe"), ("hubprops2_sfse.txd", "welder")]
BATTERY_HANDLE_Z = 0.2  # car_battery.dff: the top of the carry strap
# (source TXD, texture) per car_battery material, all vanilla and found with gta-scout: black case, red cap, dull lead posts,
# rubber strap, the "dude" brand label (the garage welder's panel), the hazard triangle (the yellow barrels' paint)
BATTERY_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("cj_airprt.txd", "CJ_red_COUNTER"), ("hubprops2_sfse.txd", "Alumox64b"), ("cj_airprt.txd", "CJ_RUBBER"), ("hubprops2_sfse.txd", "welder"), ("dynbarrels.txd", "yellowmetal")]


def build_car_battery(ctx):
    """A 12 V car battery: a black case 0.26 x 0.17 x 0.14 ribbed at the back, the blue "dude" label across the front (+Y),
    an inset lid with a hazard sticker, a row of vent plugs, a red (+) and a black (-) capped lead post at the front corners
    and a rubber strap along X with its top at BATTERY_HANDLE_Z. Origin at the base's centre."""
    box, tube = ctx["box"], ctx["tube"]
    black, red, lead, rubber, label, hazard = 0, 1, 2, 3, 4, 5
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    box((0.0, 0.0, 0.07), (0.26, 0.17, 0.14), black, dim)
    box((0.0, 0.0, 0.147), (0.25, 0.16, 0.014), black, None)  # the lid, inset
    for i in range(5):  # ribs down the back
        box((-0.09 + i * 0.045, -0.087, 0.07), (0.02, 0.004, 0.12), black, None)
    box((0.0, 0.0855, 0.072), (0.22, 0.002, 0.1), label, white, DUDE_LOGO)
    box((0.0, 0.02, 0.1545), (0.044, 0.044, 0.001), hazard, white, HAZARD)
    for x in (-0.06, -0.02, 0.02, 0.06):  # vent plugs behind the strap
        tube((x, -0.066, 0.154), (x, -0.066, 0.16), 0.01, 10, black, dim, False)
    for x, cap in ((-0.095, red), (0.095, black)):  # lead posts, capped
        tube((x, 0.052, 0.154), (x, 0.052, 0.172), 0.014, 10, lead, white, False)
        tube((x, 0.052, 0.172), (x, 0.052, 0.18), 0.019, 12, cap, None, False)
    for x in (-0.07, 0.07):  # the strap: two posts and the bar
        box((x, -0.035, 0.17), (0.02, 0.03, 0.05), rubber, None)
    tube((-0.07, -0.035, BATTERY_HANDLE_Z - 0.01), (0.07, -0.035, BATTERY_HANDLE_Z - 0.01), 0.011, 8, rubber, None)
    return [((0.0, 0.0, 0.1), (0.13, 0.085, 0.1))]


def build_tool_battery(ctx):
    """The grinder's slide-on 18 V pack standing on its foot: the "dude" label and four green charge lamps on +Y, slide rails
    and a chrome contact block on the yellow latch band. Origin at the foot's centre."""
    box = ctx["box"]
    black, yellow, lamp, chrome, label = 0, 1, 2, 3, 4
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    tool_pack(ctx, (0.0, 0.0, TOOL_PACK_LOW), black, yellow, dim)
    box((0.0, 0.0255, 0.039), (0.048, 0.001, 0.02), label, white, DUDE_LOGO)
    for i in range(4):
        box((-0.0135 + i * 0.009, 0.0255, 0.061), (0.006, 0.0012, 0.004), lamp, white, GREEN)
    for x in (-0.021, 0.021):
        box((x, 0.0, 0.0755), (0.004, 0.044, 0.003), black, None)
    box((0.0, 0.006, 0.0755), (0.02, 0.02, 0.003), chrome, None)
    return [((0.0, 0.0, 0.0385), (0.032, 0.028, 0.0385))]


def build_grinder(ctx):
    """A cordless 115 mm angle grinder, 0.33 m: the yellow motor housing along Y with a rubber grip band and a paddle
    switch under it, a black battery pack under the tail, the cast gear head in front with the spindle down (-Z), the
    disc under it at GRINDER_DISC, a guard over its rear half and a side handle out of +X. Origin at the grip's centre."""
    bm, box, tube, paint = ctx["bm"], ctx["box"], ctx["tube"], ctx["paint"]
    yellow, black, rubber, cast, disc, chrome, vent = 0, 1, 2, 3, 4, 5, 6
    white, dim, dark = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0), (0.3, 0.3, 0.32, 1.0)
    night = lambda c: (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)

    def sector(r0, r1, z0, z1, a0, a1, n, material, col):
        """A closed ring sector about the disc's axis: radii r0..r1, heights z0..z1, angles a0..a1 (degrees)."""
        cx, cy = GRINDER_DISC[0], GRINDER_DISC[1]
        at = lambda r, a, z: bm.verts.new((cx + r * math.cos(math.radians(a)), cy + r * math.sin(math.radians(a)), z))
        cols = [[at(r, a0 + (a1 - a0) * i / n, z) for r, z in ((r0, z0), (r1, z0), (r1, z1), (r0, z1))] for i in range(n + 1)]
        uvs = [(0, 0), (1, 0), (1, 1), (0, 1)]
        for i in range(n):
            for k in range(4):
                face = bm.faces.new((cols[i][k], cols[i][(k + 1) % 4], cols[i + 1][(k + 1) % 4], cols[i + 1][k]))
                paint(face, uvs, col, night(col), material)
        for end in (cols[0], cols[-1]):
            paint(bm.faces.new(end), uvs, col, night(col), material)

    # the tail: a black end cap with vents, the battery pack hanging under it (yellow latch band on top)
    tube((0.0, -0.105, 0.0), (0.0, -0.088, 0.0), 0.028, 12, black, None, False)
    tool_pack(ctx, (0.0, -0.124, -0.012), black, yellow, dim)
    # the motor housing: yellow, a rubber grip band round its rear half, vents on both sides, the paddle switch underneath
    tube((0.0, -0.088, 0.0), (0.0, 0.055, 0.0), 0.03, 14, yellow, None)
    tube((0.0, -0.072, 0.0), (0.0, -0.018, 0.0), 0.0315, 14, rubber, None, False)
    for x in (-0.0285, 0.0285):
        box((x, 0.024, 0.004), (0.004, 0.032, 0.024), vent, None)
    box((0.0, -0.04, -0.031), (0.018, 0.075, 0.008), black, None)
    box((0.0, 0.012, 0.03), (0.012, 0.018, 0.006), black, dim)  # the spindle lock button
    # the gear head: a cast neck, a squat drum round the spindle, the spindle and the flange nut under the disc
    tube((0.0, 0.05, 0.0), (0.0, 0.075, 0.0), 0.027, 12, cast, None)
    tube((0.0, GRINDER_DISC[1], -0.03), (0.0, GRINDER_DISC[1], 0.016), 0.031, 14, cast, None, False)
    tube((0.0, GRINDER_DISC[1], -0.03), (0.0, GRINDER_DISC[1], -0.044), 0.018, 12, cast, dim, False)
    tube((0.0, GRINDER_DISC[1], -0.044), (0.0, GRINDER_DISC[1], -0.054), 0.007, 8, chrome, white)
    # the disc, 115 mm, and its flange nut
    dz = GRINDER_DISC[2]
    tube((0.0, GRINDER_DISC[1], dz - 0.0015), (0.0, GRINDER_DISC[1], dz + 0.0015), 0.0575, 24, disc, None, False)
    tube((0.0, GRINDER_DISC[1], dz - 0.0045), (0.0, GRINDER_DISC[1], dz - 0.0015), 0.013, 12, chrome, white, False)
    # the guard over the rear half: a plate above the disc and a rim down past it, clamped to the drum by a collar
    sector(0.03, 0.065, -0.044, -0.041, 180, 360, 12, cast, dark)
    sector(0.062, 0.065, GRINDER_LOW, -0.041, 180, 360, 12, cast, dark)
    sector(0.033, 0.037, -0.044, -0.024, 150, 390, 12, cast, dim)
    # the side handle screwed into +X of the gear head: a stud and a black grip with a rubber end
    tube((0.03, GRINDER_DISC[1], -0.004), (0.05, GRINDER_DISC[1], -0.004), 0.007, 8, chrome, dim)
    tube((0.05, GRINDER_DISC[1], -0.004), (0.13, GRINDER_DISC[1], -0.004), 0.014, 10, black, None)
    tube((0.13, GRINDER_DISC[1], -0.004), (0.14, GRINDER_DISC[1], -0.004), 0.016, 10, rubber, None, False)
    return [((0.04, 0.0, -0.01), (0.105, 0.165, 0.048))]


GRIND_DISC_TEXTURES = [("trailers.txd", "trail_wheel")]


def build_grind_disc(ctx):
    """A spare 115 mm grinding disc lying flat: the grinder's disc (trail_wheel on both faces), 3 mm thick, its centre
    hole's bright hub up. Origin at the centre of its underside."""
    ctx["tube"]((0.0, 0.0, 0.0), (0.0, 0.0, 0.003), 0.0575, 24, 0, None, False)
    return [((0.0, 0.0, 0.0015), (0.0575, 0.0575, 0.0015))]


# 0.25 m overall: the butt face at y = -0.132, the head's front face at y = +0.118. The head's axis is Z (the drive).
RATCHET_HEAD_Y, RATCHET_HEAD_R = 0.094, 0.024
# (source TXD, texture) per ratchet material, all vanilla and found with gta-scout: chrome pipe (handle, head, drive
# and socket), the airport's bumpy black rubber (the knurled grip), smooth black plastic (the reversing lever)
RATCHET_TEXTURES = [("cj_airprt.txd", "cj_chromepipe"), ("cj_airprt.txd", "CJ_BLACK_RUB2"), ("ballys01.txd", "CJ_blackplastic")]


def build_ratchet(ctx):
    """A 1/2 inch socket ratchet, 0.25 m: the chrome handle along Y, a knurled rubber grip centred on the origin, a round
    head toward +Y with the reversing lever on top (+Z) and the square drive under it (-Z) holding a hex socket."""
    bm, box, paint = ctx["bm"], ctx["box"], ctx["paint"]
    chrome, rubber, lever = 0, 1, 2
    white, dim = (0.92, 0.92, 0.93, 1.0), (0.55, 0.55, 0.56, 1.0)
    night = lambda c: (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    hy, hr = RATCHET_HEAD_Y, RATCHET_HEAD_R

    def y_tube(y0, y1, radius, segs, material, col, u_rep=1.0, v_rep=1.0):
        """A closed cylinder along Y. `u_rep` / `v_rep` tile the texture around it and along it."""
        rings = []
        for y in (y0, y1):
            ring = [bm.verts.new((radius * math.cos(2 * math.pi * i / segs), y, radius * math.sin(2 * math.pi * i / segs))) for i in range(segs)]
            rings.append(ring)
        for i in range(segs):
            j = (i + 1) % segs
            u0, u1 = u_rep * i / segs, u_rep * (i + 1) / segs
            paint(bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i])), [(u0, 0), (u1, 0), (u1, v_rep), (u0, v_rep)], col, night(col), material)
        for ring, flip in ((rings[0], True), (rings[1], False)):
            order = list(reversed(ring)) if flip else ring
            uvs = [(0.5 + 0.5 * math.cos(2 * math.pi * i / segs), 0.5 + 0.5 * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
            paint(bm.faces.new(order), uvs, col, night(col), material)

    def z_tube(z0, z1, radius, segs, material, col):
        """A closed cylinder along Z at the head. The chrome wraps once, so the rim is not a stack of stripes."""
        rings = [[bm.verts.new((radius * math.cos(2 * math.pi * i / segs), hy + radius * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)] for z in (z0, z1)]
        for i in range(segs):
            j = (i + 1) % segs
            u0, u1 = i / segs, (i + 1) / segs
            paint(bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i])), [(u0, 0), (u1, 0), (u1, 1), (u0, 1)], col, night(col), material)
        for ring, flip in ((rings[0], True), (rings[1], False)):
            order = list(reversed(ring)) if flip else ring
            uvs = [(0.5 + 0.5 * math.cos(2 * math.pi * i / segs), 0.5 + 0.5 * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
            paint(bm.faces.new(order), uvs, col, night(col), material)

    # the handle, a rounded butt past the grip, and the grip itself (its centre is the origin) with a collar each end
    y_tube(-0.118, 0.076, 0.010, 12, chrome, white)
    y_tube(-0.132, -0.112, 0.013, 12, chrome, white)
    y_tube(-0.046, 0.046, 0.0155, 16, rubber, dim, 4.0, 2.0)
    y_tube(-0.054, -0.040, 0.0175, 16, chrome, white)
    y_tube(0.040, 0.054, 0.0175, 16, chrome, white)
    # the head: a round housing the handle runs into, and a smaller cover the lever sits on.
    # overlapping shells stay more than 1 mm off any parallel face so the caps do not z-fight
    z_tube(-0.010, 0.009, hr, 20, chrome, white)
    z_tube(0.006, 0.015, 0.020, 16, chrome, white)
    z_tube(0.011, 0.021, 0.0025, 8, chrome, dim)  # the lever's pivot, inside the lever's width
    box((0.007, hy, 0.016), (0.026, 0.010, 0.006), lever, dim)  # flipped toward +X
    # the square drive (its top buried in the head), then the socket stepped down over it
    box((0.0, hy, -0.017), (0.0127, 0.0127, 0.020), chrome, white)
    z_tube(-0.050, -0.022, 0.014, 6, chrome, white)
    z_tube(-0.060, -0.046, 0.012, 6, chrome, dim)
    # butt y=-0.132 to head front y=0.118; the socket's nose is the low point, the pivot the high one
    return [((0.0, -0.007, -0.0195), (0.026, 0.125, 0.0405))]


PROPS_TABLE = [
    {"name": "ls_hatch", "id": 20201, "dist": 150, "source": "zombtest1.txd", "textures": ["pave_manhole1"], "build": build_ls_hatch},
    {"name": "welder", "id": 20202, "dist": 100, "source": "dynbarrels.txd", "textures": ["redmetal", "yellowmetal", "alumplat64"], "build": build_welder},
    {"name": "gas_bottle", "id": 20203, "dist": 100, "source": "trailers.txd", "textures": [TANK_TEXTURE], "build": build_gas_bottle},
    {"name": "generator", "id": 20204, "dist": 100, "sources": GEN_TEXTURES, "build": build_generator},
    {"name": "welder_torch", "id": 20205, "dist": 60, "sources": TORCH_TEXTURES, "build": build_welder_torch},
    {"name": "grinder", "id": 20206, "dist": 60, "sources": GRINDER_TEXTURES, "build": build_grinder},
    {"name": "grind_disc", "id": 20207, "dist": 40, "sources": GRIND_DISC_TEXTURES, "build": build_grind_disc},
    {"name": "car_battery", "id": 20208, "dist": 60, "sources": BATTERY_TEXTURES, "build": build_car_battery},
    {"name": "tool_battery", "id": 20209, "dist": 40, "sources": TOOL_BATTERY_TEXTURES, "build": build_tool_battery},
    {"name": "ratchet", "id": 20236, "dist": 40, "sources": RATCHET_TEXTURES, "build": build_ratchet},
]


def prop_sources(prop):
    """(source TXD, texture) per material: a row's `sources`, or its one `source` with each of its `textures`."""
    return prop.get("sources") or [(prop["source"], t) for t in prop["textures"]]


def prop_textures(prop):
    return [t for _, t in prop_sources(prop)]


def render_props() -> str:
    lines = [
        "-- Generated by tools/make_props.py; do not edit. Port model id -> a prop the port adds to the world,",
        "-- in prop_models/files/ with its own TXD and collision.",
        "return {",
    ]
    from tools.bobcat_parts import PARTS
    from tools.make_vending import props_rows
    from tools.vanilla_props import COPIES
    entries = PROPS_TABLE + [dict(id=p["model"], name=p["asset"], dist=80) for p in PARTS] + COPIES + props_rows()
    def extra(p):  # a vanilla model whose physical properties it takes, IDE flags it is drawn with
        return "".join(f", {k} = {p[k]}" for k in ("parent", "ideFlags") if p.get(k) is not None)

    lines += [f'    [{p["id"]}] = {{ dff = "{p["name"]}", txd = "{p["name"]}", dist = {p["dist"]}{extra(p)} }},' for p in entries]
    return "\n".join(lines + ["}", ""])


def render_meta(out_dir: Path) -> str:
    props_lua = out_dir / "props.lua"
    dffs = []
    if props_lua.is_file():
        dffs += [f"{name}.dff" for name in re.findall(r'dff = "([^"]+)"', props_lua.read_text(encoding="ascii"))]
    files = []
    for dff in sorted(dffs):
        stem = dff[:-4]
        files += [f"{stem}.col", f"{stem}.dff", f"{stem}.txd"]
    lines = [
        "<meta>",
        '    <info author="scavengesurvive-mta" type="script" name="prop_models" '
        'description="Port prop models added to the world" version="0.1.0"/>',
        '    <min_mta_version server="1.6.0" client="1.6.0-9.21695"/>',
        "    <download_priority_group>90</download_priority_group>",
        '    <include resource="lib"/>',
        '    <script src="client/main.lua" type="client"/>',
        '    <file src="props.lua"/>',
    ]
    lines += [f'    <file src="files/{name}"/>' for name in files]
    lines += [
        '    <export function="resolve" type="client"/>',
        '</meta>',
    ]
    return "\n".join(lines) + "\n"


def write_meta(out_dir: Path) -> None:
    (out_dir / "meta.xml").write_text(render_meta(out_dir), encoding="ascii", newline="\n")


def build_in_blender(out_dir: Path, names) -> None:
    import bmesh
    import bpy
    from mathutils import Vector

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    for prop in PROPS_TABLE:
        if prop["name"] not in names:
            continue
        for obj in list(bpy.data.objects):
            bpy.data.objects.remove(obj)
        # a texture an earlier prop used would come back as "name.png.001", and DragonFF writes "name.png" into the DFF
        for block in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
            for item in list(block):
                block.remove(item)
        name, textures = prop["name"], prop_textures(prop)
        scene = bpy.context.scene
        model = bpy.data.collections.new(name)
        scene.collection.children.link(model)

        mesh = bpy.data.meshes.new(name)
        bm = bmesh.new()
        uv = bm.loops.layers.uv.new("UVMap")
        day = bm.loops.layers.color.new("Day")
        night = bm.loops.layers.color.new("Night")

        def paint(face, uvs, day_col, night_col, material):
            face.material_index = material
            for loop, (u, v) in zip(face.loops, uvs):
                loop[uv].uv = (u, v)
                loop[day] = day_col
                loop[night] = night_col

        def quad(verts, material, col, rect=None):
            face = bm.faces.new(verts)
            c = col if col else (0.9, 0.9, 0.9, 1.0)
            u0, v0, u1, v1 = rect or (0, 0, 1, 1)
            uvs = [(u0, v0), (u1, v0), (u1, v1), (u0, v1)][: len(verts)]
            if len(verts) > 4:
                uvs = [(0.5 + 0.5 * math.cos(2 * math.pi * i / len(verts)), 0.5 + 0.5 * math.sin(2 * math.pi * i / len(verts))) for i in range(len(verts))]
            paint(face, uvs, c, (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0), material)

        def box(centre, size, material, col, rect=None):
            """An axis-aligned box; `rect` (u0, v0, u1, v1) maps every face to that part of the texture."""
            cx, cy, cz = centre
            hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
            v = [bm.verts.new((cx + sx * hx, cy + sy * hy, cz + sz * hz)) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
            for a, b, c, d in ((0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)):
                quad([v[a], v[b], v[c], v[d]], material, col, rect)

        def tube(start, end, radius, segs, material, col, extend=True):
            """A closed cylinder; `extend` runs each end on by half the radius so joined tubes leave no gap."""
            a, b = Vector(start), Vector(end)
            axis = b - a
            axis.normalize()
            if extend:
                a, b = a - axis * radius * 0.5, b + axis * radius * 0.5
            helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
            u = axis.cross(helper)
            u.normalize()
            w = axis.cross(u)
            rings = []
            for end_point in (a, b):
                ring = []
                for i in range(segs):
                    t = 2 * math.pi * i / segs
                    ring.append(bm.verts.new(end_point + (u * math.cos(t) + w * math.sin(t)) * radius))
                rings.append(ring)
            for i in range(segs):
                j = (i + 1) % segs
                quad([rings[0][i], rings[0][j], rings[1][j], rings[1][i]], material, col)
            for ring in rings:
                quad(list(ring), material, col)

        def graft(path, mesh_name, keep, material, place=None):
            """Copies the faces `keep(texture, centre)` picks out of a vanilla DFF into the prop, centred on x and y with
            its lowest point at z 0, then moved by `place(co) -> (x, y, z)` if given, painted like the other props;
            `material` is the prop's material index, or a {texture: index} map. Returns the bounds (lo, hi) before
            `place`."""
            bpy.ops.import_scene.dff(filepath=path, read_mat_split=True, remove_doubles=False, load_images=False)
            src = bpy.data.objects[mesh_name].data

            def texture_of(index):
                mat = src.materials[index]
                nodes = [n for n in mat.node_tree.nodes if n.type == "TEX_IMAGE"] if mat and mat.node_tree else []
                return ((nodes[0].image.name if nodes[0].image else nodes[0].label or nodes[0].name) if nodes else "").split(".")[0]

            polys = [p for p in src.polygons if keep(texture_of(p.material_index), p.center)]
            used = sorted({v for p in polys for v in p.vertices})
            co = [src.vertices[v].co for v in used]
            lo = Vector((min(c.x for c in co), min(c.y for c in co), min(c.z for c in co)))
            hi = Vector((max(c.x for c in co), max(c.y for c in co), max(c.z for c in co)))
            shift = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
            move = place or (lambda co: co)
            verts = {v: bm.verts.new(move(src.vertices[v].co - shift)) for v in used}
            uv_layer = src.uv_layers[0].data
            for poly in polys:
                face = bm.faces.new([verts[v] for v in poly.vertices])
                uvs = [tuple(uv_layer[i].uv) for i in poly.loop_indices]
                index = material[texture_of(poly.material_index).lower()] if isinstance(material, dict) else material
                paint(face, uvs, (0.9, 0.9, 0.9, 1.0), (0.27, 0.27, 0.29, 1.0), index)
                grafted.add(face)
            for obj in list(bpy.data.objects):
                bpy.data.objects.remove(obj)
            return (lo - shift, hi - shift)

        grafted = set()  # vanilla faces keep their own winding
        ctx = {"bm": bm, "paint": paint, "box": box, "tube": tube, "graft": graft}
        boxes = prop["build"](ctx)
        if name != "ls_hatch":
            bmesh.ops.recalc_face_normals(bm, faces=[f for f in bm.faces if f not in grafted])
        bm.normal_update()
        bm.to_mesh(mesh)
        bm.free()

        for texture in textures:
            image = bpy.data.images.new(texture + ".png", 8, 8)  # DragonFF writes the name; the pixels are the TXD's
            material = bpy.data.materials.new(texture)
            material.use_nodes = True
            bsdf = next(n for n in material.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            node = material.node_tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            material.node_tree.links.new(node.outputs["Color"], bsdf.inputs["Base Color"])
            mesh.materials.append(material)

        obj = bpy.data.objects.new(name, mesh)
        obj.dff.type = "OBJ"
        obj.dff.day_cols = True
        obj.dff.night_cols = True
        model.objects.link(obj)

        for i, (centre, half) in enumerate(boxes):
            col = bpy.data.objects.new(f"{name}_col" if i == 0 else f"{name}_col{i}", None)
            col.empty_display_type = "CUBE"
            col.location = centre
            col.scale = half
            col.dff.type = "COL"
            model.objects.link(col)

        dff_path, col_path = out_dir / f"{name}.dff", out_dir / f"{name}.col"
        bpy.ops.export_dff.scene(filepath=str(dff_path), export_coll=False, only_selected=False, export_version="0x36003")
        bpy.ops.export_col.scene(filepath=str(col_path), export_version="3", only_selected=False)
        print(f"make_props: wrote {dff_path.name} and {col_path.name}")
        bpy.data.collections.remove(model)


def main(argv=None) -> int:
    import argparse
    import subprocess

    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta, merge_txd, read_img_entry, read_img_index, trim_txd

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("names", nargs="*", help="props to build (default: all)")
    ap.add_argument("--gta", type=Path, help="GTA:SA folder (default: from the registry)")
    ap.add_argument("--blender", help="blender.exe (default: BLENDER or the newest install)")
    args = ap.parse_args(argv)
    gta = args.gta or detect_gta()
    img = gta / "models" / "gta3.img" if gta else None
    if not img or not img.is_file():
        print("make_props: no GTA:SA models/gta3.img (pass --gta)", file=sys.stderr)
        return 2
    blender = find_blender(args.blender)
    if not blender:
        print("make_props: no Blender found (pass --blender)", file=sys.stderr)
        return 2
    names = args.names or [p["name"] for p in PROPS_TABLE]
    index = read_img_index(img)
    for prop in PROPS_TABLE:
        if prop["name"] in names:
            parts = {}
            for source, texture in prop_sources(prop):
                parts.setdefault(source, set()).add(texture.lower())
            txds = [trim_txd(read_img_entry(img, index[source]), keep) for source, keep in parts.items()]
            (FILES / f"{prop['name']}.txd").write_bytes(txds[0] if len(txds) == 1 else merge_txd(txds))
    PROPS.write_text(render_props(), encoding="ascii", newline="\n")
    write_meta(PROP_MODELS)
    cmd = [str(blender), "-b", "--python", __file__, "--", str(FILES)] + names
    res = subprocess.run(cmd, capture_output=True, text=True)
    out = res.stdout + res.stderr
    print("\n".join(line for line in out.splitlines() if "make_props" in line or "Error" in line))
    return 0 if res.returncode == 0 and all((FILES / f"{n}.dff").is_file() for n in names) else 1


if __name__ == "__main__":
    if "bpy" in sys.modules or "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1 :]
        build_in_blender(Path(rest[0]), set(rest[1:]))
    else:
        sys.exit(main())
