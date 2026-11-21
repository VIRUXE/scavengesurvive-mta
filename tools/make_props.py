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

    locksmith_kit 20257  a lock-pick case, 0.26 x 0.18 x 0.045 m, its lid open on a hinge along +Y: picks, tension wrenches,
                     a brass practice padlock and key blanks in the base's foam, two spare picks under a strap on the lid's
                     red lining, latches on the front (-Y); vanilla textures (KIT_TEXTURES, found with gta-scout). Two
                     boxes of collision, the base and the open lid. The Locksmith Kit item.

    chain    20258   about 0.6 m of steel chain lying in a loose S: oval links of 8 mm wire, 46 x 28 mm, flat and upright by
                     turns, chrome pipe wrapped round the wire. The Chain item.
    padlock  20259   a laminated steel padlock, 0.05 x 0.026 x 0.042 m body standing on its base: seven galvanised plates
                     with grooves between them, rivets, a brass key cylinder and keyway underneath, a chrome shackle on
                     top. The Padlock item.
    lock_chain 20260 the chain closed into a 0.25 m loop by the padlock, which lies on its back with the shackle through the
                     two end links. The Lock and Chain item (WheelLock).
    combo_padlock 20261  a four-dial combination padlock, 0.046 x 0.024 x 0.05 m red die-cast body standing on its base:
                     four steel dials across the front in a chrome bezel, a digit on each (the motel's door numbers from
                     gta_int.img, alpha, so the prop is drawn last), a chrome shackle on top, open: raised and turned out
                     on its long leg. The Combination Padlock item; combo_padlock_shut (20263) is the same lock shut.
    combo_padlock_body 20264, combo_shackle 20265  the two parts of combo_padlock_shut apart, for the close-up the
                     items client shows while the dials are set (it raises and turns the shackle).
    combo_lock_chain 20262  the chain closed into a loop by the combination padlock lying dials up. The Combination
                     Lock and Chain item (ComboLockChain).

    tow_bar  20266   a ball-type receiver hitch, 0.45 m long: a 50 mm chrome ball on a galvanised ball mount, its shank in
                     a black square receiver tube with a chrome hitch pin, and a mounting bar rising into the car. Origin
                     at the ball's centre, the bar forward (+Y) from it: vehicles fit it at a model's trailer_attach
                     dummy. Vanilla textures (TOWBAR_TEXTURES, found with gta-scout). The Tow Bar item.
    rope_coil 20267  about 5 m of twisted hemp rope (gta_int.img's Gym_rope) in a 0.27 m coil lying on the ground, six
                     hand-wound turns, the free end trailing out to +Y and a tie round the bundle. The Rope item.

    Crafting parts and gadgets (20268-20283), every surface a vanilla texture found with gta-scout, cylinders through _tube
    (the texture wrapped once round): motor (blue finned induction motor), starter_motor (car starter with solenoid),
    power_supply (ATX box with its loom), fluctuator (coil and rod on a project box), tnt (seven taped sticks), ied (pipe
    bomb with clock and battery), fireworks (open carton of rockets and cakes), emp (pancake coil, capacitor bank and
    tool battery on a board), storage_unit (3.5 inch hard drive), io_unit (phone keypad in a project box), flux_cap (three
    can capacitors in a tray), hack_device (rugged netbook with clip leads), advanced_keypad (access-control keypad, face
    +Y), lockpick (electric pick gun, origin at the grip's foot), clothes (three folded garments), pills (pharmacy vial).

    flood_light 20300  a halogen site work light on a tripod, 1.57 m tall: black legs and lower mast, a chrome upper mast,
                     a yellow lamp head on a black yoke, its face (the SF light tower's ws_floodlight reflector) toward +Y
                     and FLOOD_TILT degrees down; the light comes from FLOOD_LAMP along FLOOD_AIM. The Flood Light item.

Origin (except welder_torch, grinder, ratchet and tow_bar): the centre of the base (x, y) with z = 0 at the lowest point; the front faces +Y.
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


KIT_W, KIT_D, KIT_H = 0.26, 0.18, 0.04  # locksmith_kit: the base shell (x, y, z)
KIT_LID_H = 0.016  # the lid: the base's footprint, this deep, hinged along the back
KIT_FOAM_Z = 0.031  # the top of the base's foam insert
KIT_LID_OPEN = 100  # degrees the lid stands open from shut
# (source TXD, texture) per locksmith_kit material, all vanilla and found with gta-scout: black plastic shell, the airport's
# dark rubber (the foam), the counter's red (the lid lining), chrome pipe (picks and wrenches), a brass bullet casing (the
# practice padlock and key blanks), dull aluminium (latches and hinge)
KIT_TEXTURES = [
    ("ballys01.txd", "CJ_blackplastic"),
    ("cj_airprt.txd", "CJ_RUBBER"),
    ("cj_airprt.txd", "CJ_red_COUNTER"),
    ("cj_airprt.txd", "cj_chromepipe"),
    ("light_fit_ext.txd", "CJ_BULLETBRASS"),
    ("hubprops2_sfse.txd", "Alumox64b"),
]


def build_locksmith_kit(ctx):
    """A lock-pick case, 0.26 x 0.18 m, 0.056 deep shut: a black shell with its lid open KIT_LID_OPEN degrees on a hinge along
    the back edge. In the base's dark foam lie a fan of picks (black handles toward the front), two tension wrenches, a
    brass practice padlock with its chrome shackle and three brass key blanks; the lid's red lining holds two more picks
    under a black strap. Two latches on the front. Built with the front toward +Y, then turned so it faces -Y. Origin at
    the base's centre, z = 0 underneath."""
    bm, box = ctx["bm"], ctx["box"]
    shell, foam, lining, chrome, brass, alum = 0, 1, 2, 3, 4, 5
    white, dim, dark = (0.92, 0.92, 0.93, 1.0), (0.62, 0.62, 0.64, 1.0), (0.4, 0.4, 0.42, 1.0)
    w, d, h, wall = KIT_W, KIT_D, KIT_H, 0.005
    fz = KIT_FOAM_Z

    def tray(z0, z1, floor_z):
        """A shell half between z0 and z1: four walls and a floor `wall` thick centred on floor_z."""
        box((0.0, 0.0, floor_z), (w, d, wall), shell, dim)
        cz, hz = (z0 + z1) / 2, z1 - z0
        for y in (d / 2 - wall / 2, -d / 2 + wall / 2):
            box((0.0, y, cz), (w, wall, hz), shell, dim)
        for x in (w / 2 - wall / 2, -w / 2 + wall / 2):
            box((x, 0.0, cz), (wall, d - 2 * wall, hz), shell, dim)

    def pick(x, y0, length, tip, mat=chrome, z=fz, handle=True):
        """A pick lying along Y on the foam: a flat shaft from y0 toward -Y, a black handle at y0 and a `tip` at the far
        end ("hook", "diamond", "rake", "ball")."""
        t = 0.0014
        y1 = y0 - length
        box((x, (y0 + y1) / 2, z + t / 2), (0.0028, length, t), mat, white)
        if handle:
            box((x, y0 - 0.025, z + 0.0025), (0.008, 0.055, 0.005), shell, dark)
        if tip == "hook":
            box((x, y1 + 0.001, z + 0.0035), (0.0028, 0.0024, 0.006), mat, white)
        elif tip == "diamond":
            box((x, y1 + 0.003, z + t / 2), (0.006, 0.006, t), mat, white)
        elif tip == "rake":
            for i in range(3):
                box((x, y1 + 0.003 + i * 0.006, z + 0.0025), (0.0028, 0.0022, 0.004), mat, white)
        elif tip == "ball":
            box((x, y1 + 0.002, z + 0.002), (0.005, 0.005, 0.004), mat, white)

    # the base: shell, a foam insert inside its walls and two latches on the front
    tray(0.0, h, wall / 2)
    box((0.0, 0.0, (wall + fz) / 2), (w - 2 * wall - 0.001, d - 2 * wall - 0.001, fz - wall), foam, white)
    for x in (-0.075, 0.075):
        box((x, d / 2 + 0.003, h - 0.008), (0.026, 0.006, 0.016), alum, white)
        box((x, d / 2 + 0.0065, h - 0.004), (0.012, 0.002, 0.01), shell, dark)
    # picks fanned across the left of the foam, handles toward the front
    tips = ["hook", "hook", "diamond", "rake", "rake", "ball", "diamond", "hook"]
    for i, tip in enumerate(tips):
        pick(-0.112 + i * 0.0125, 0.068, 0.105, tip)
    # two tension wrenches: an L of flat chrome each, in front of the padlock
    for i in range(2):
        y = 0.052 - i * 0.014
        box((0.035, y, fz + 0.0008), (0.07, 0.003, 0.0016), chrome, white)
        box((0.0015, y - 0.006, fz + 0.0008), (0.003, 0.012, 0.0016), chrome, white)
    # the practice padlock lying on its back: a brass body, its chrome shackle and a keyway, right of centre
    px, py = 0.035, -0.025
    box((px, py, fz + 0.009), (0.05, 0.04, 0.018), brass, white)
    box((px, py + 0.0205, fz + 0.011), (0.006, 0.001, 0.012), shell, dark)  # the keyway on the +Y face
    for sx in (-0.016, 0.016):
        box((px + sx, py - 0.032, fz + 0.009), (0.007, 0.026, 0.007), chrome, white)
    box((px, py - 0.0485, fz + 0.009), (0.039, 0.007, 0.007), chrome, white)
    # three cut keys along the right edge: a round brass bow, a blade toward -X and its bitting on the +Y edge
    for i in range(3):
        kx, ky = 0.103, -0.058 + i * 0.03
        ctx["tube"]((kx, ky, fz), (kx, ky, fz + 0.002), 0.0115, 12, brass, white, False)
        box((kx - 0.03, ky - 0.001, fz + 0.001), (0.04, 0.006, 0.002), brass, white)
        for j in range(4):
            box((kx - 0.044 + j * 0.008, ky + 0.0028, fz + 0.001), (0.004, 0.003 + 0.0015 * ((i + j) % 3), 0.002), brass, white)

    # the lid, built shut over the base (its outside up), then swung open on the hinge
    before = set(bm.verts)
    lz = h + KIT_LID_H  # the lid's outer face when shut
    tray(h, lz, lz - wall / 2)
    lining_z = lz - wall - 0.004
    box((0.0, 0.0, lining_z), (w - 2 * wall - 0.001, d - 2 * wall - 0.001, 0.008), lining, white)
    for i, tip in enumerate(("rake", "hook")):  # two spare picks on the lining, face down while shut
        pick(-0.03 + i * 0.06, 0.06, 0.1, tip, z=lining_z - 0.004 - 0.0014, handle=False)
        box((-0.03 + i * 0.06, 0.035, lining_z - 0.006), (0.008, 0.055, 0.004), shell, dark)
    box((0.0, -0.01, lining_z - 0.0055), (w - 2 * wall - 0.02, 0.018, 0.003), shell, dark)  # the strap
    lid = [v for v in bm.verts if v not in before]
    # the hinge: rotate about the X axis through the back edge at the rim (y = -d/2, z = h)
    a = math.radians(KIT_LID_OPEN)
    ca, sa = math.cos(a), math.sin(a)
    for v in lid:
        y, z = v.co.y + d / 2, v.co.z - h
        v.co.y, v.co.z = -d / 2 + y * ca - z * sa, h + y * sa + z * ca
    # the hinge barrel along the back edge
    ctx["tube"]((-w / 2 + 0.02, -d / 2 - 0.002, h), (w / 2 - 0.02, -d / 2 - 0.002, h), 0.004, 8, alum, white)
    # turned half round so the open side faces -Y, toward the item renders' camera (tools/render_item_models.py)
    for v in bm.verts:
        v.co.x, v.co.y = -v.co.x, -v.co.y
    # collision: the base, and the open lid as a slab standing behind the hinge (+Y)
    lid_top, lid_y = h + d * sa, d / 2 - min(d * ca, 0.0) + KIT_LID_H * sa
    return [
        ((0.0, 0.0, h / 2), (w / 2, d / 2, h / 2)),
        ((0.0, (lid_y + d / 2) / 2, (h + lid_top) / 2), (w / 2, (lid_y - d / 2) / 2, (lid_top - h) / 2)),
    ]


CHAIN_WIRE = 0.004  # chain, lock_chain: the links' wire radius
CHAIN_LINK = (0.046, 0.028)  # a link's outside length and width; links interlock one inside length apart
CHAIN_PITCH = CHAIN_LINK[0] - 4 * CHAIN_WIRE
PAD_W, PAD_D, PAD_H = 0.05, 0.026, 0.042  # padlock: the laminated body (x, y, z)
PAD_SHACKLE = (0.0042, 0.0155, 0.02)  # the shackle's wire radius, half its centre-line span and its legs' height above the body
# (source TXD, texture) per chain / padlock material, all vanilla: chrome pipe (the links and the shackle), galvanised
# steel (the padlock's plates), a brass bullet casing (its key cylinder), black plastic (the keyway)
LOCK_TEXTURES = [
    ("industrialext.txd", "cj_chromepipe"),
    ("metalbarrier_cj.txd", "CJ_GALVANISED"),
    ("light_fit_ext.txd", "CJ_BULLETBRASS"),
    ("ballys01.txd", "CJ_blackplastic"),
]
CHAIN_TEXTURES = LOCK_TEXTURES[:1]


def _sweep(ctx, path, radius, sides, material, col, closed=False, frames=None):
    """A tube of `sides` round a centre-line `path` (Vectors), closed into a ring or capped at both ends; u runs round
    the wire, so a striped chrome texture lights one side of it. `frames` gives each point's (normal, binormal)."""
    from mathutils import Vector

    bm, paint = ctx["bm"], ctx["paint"]
    n = len(path)
    rings = []
    nrm = None
    for i, p in enumerate(path):
        if frames:
            nrm, bin_ = frames[i]
        else:  # parallel transport: each ring keeps the last one's turn, so a bend never twists the wire
            a, b = path[(i - 1) % n if closed else max(i - 1, 0)], path[(i + 1) % n if closed else min(i + 1, n - 1)]
            t = (b - a).normalized()
            if nrm is None:
                helper = Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))
                nrm = t.cross(helper).normalized()
            else:
                nrm = (nrm - t * nrm.dot(t)).normalized()
            bin_ = t.cross(nrm).normalized()
        rings.append([bm.verts.new(p + (nrm * math.cos(2 * math.pi * k / sides) + bin_ * math.sin(2 * math.pi * k / sides)) * radius) for k in range(sides)])
    c = col or (0.9, 0.9, 0.9, 1.0)
    night = (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    segs = n if closed else n - 1
    for i in range(segs):
        r0, r1 = rings[i], rings[(i + 1) % n]
        for k in range(sides):
            j = (k + 1) % sides
            face = bm.faces.new((r0[k], r0[j], r1[j], r1[k]))
            v0, v1 = i / segs * 2, (i + 1) / segs * 2
            paint(face, [(k / sides, v0), ((k + 1) / sides, v0), ((k + 1) / sides, v1), (k / sides, v1)], c, night, material)
    if not closed:
        for ring in (rings[0], rings[-1]):
            face = bm.faces.new(ring)
            paint(face, [(0.5 + 0.5 * math.cos(2 * math.pi * k / sides), 0.5 + 0.5 * math.sin(2 * math.pi * k / sides)) for k in range(sides)], c, night, material)


def _link(ctx, centre, along, normal, material=0, col=None):
    """One oval chain link round `centre`: its long axis `along`, its plane's normal `normal` (unit Vectors)."""
    r = CHAIN_WIRE
    length, width = CHAIN_LINK[0] - 2 * r, CHAIN_LINK[1] - 2 * r  # the wire's centre line
    a, straight = width / 2, length - width
    side = normal.cross(along).normalized()
    pts, frames = [], []
    per_end, per_side = 4, 0
    for end in (1, -1):  # a half circle round each end, then the straight side back
        cy = end * straight / 2
        for k in range(per_end + 1):
            t = math.pi * k / per_end
            dx, dy = a * math.cos(t) * end, a * math.sin(t) * end
            pts.append((dx, cy + dy))
        for k in range(1, per_side + 1):
            pts.append((-a * end, cy - end * straight * k / (per_side + 1)))
    # (x across, y along) -> world; the frame's normal points out of the oval in its plane, the binormal along `normal`
    path = [centre + side * x + along * y for x, y in pts]
    n = len(path)
    for i in range(n):
        t = (path[(i + 1) % n] - path[i - 1]).normalized()
        frames.append((t.cross(normal).normalized(), normal))
    _sweep(ctx, path, r, 6, material, col, closed=True, frames=frames)


def _chain(ctx, centres, first_flat=True, ends=None):
    """Links through `centres` (Vectors), each pointing at its neighbours, lying flat and standing upright by turns; a
    flat one rests on z = wire radius, an upright one on its edge. `ends` {index: (along, normal)} fixes a link's frame."""
    from mathutils import Vector

    up = Vector((0, 0, 1))
    n = len(centres)
    for i, c in enumerate(centres):
        if ends and i in ends:
            along, normal = ends[i]
        else:
            along = (centres[min(i + 1, n - 1)] - centres[max(i - 1, 0)]).normalized()
            flat = (i % 2 == 0) == first_flat
            normal = (up - along * along.dot(up)).normalized() if flat else along.cross(up).normalized()
            if not flat:
                c = Vector((c.x, c.y, CHAIN_LINK[1] / 2))
        _link(ctx, c, along, normal, 0, (0.88, 0.88, 0.9, 1.0) if i % 2 else (0.78, 0.78, 0.8, 1.0))


def _spaced(points, step, count=None):
    """Points along the polyline `points` `step` apart (or `count` of them spread over its whole length)."""
    seg = [(points[i + 1] - points[i]).length for i in range(len(points) - 1)]
    total = sum(seg)
    if count:
        step = total / (count - 1)
    out, want, run = [], 0.0, 0.0
    for i, s in enumerate(seg):
        while want <= run + s + 1e-9 and (not count or len(out) < count):
            f = (want - run) / s if s else 0.0
            out.append(points[i].lerp(points[i + 1], f))
            want += step
        run += s
    if count and len(out) < count:
        out.append(points[-1].copy())
    return out


def _padlock(ctx, xf):
    """The padlock in its own frame, mapped through xf(Vector) -> Vector: a laminated steel body PAD_W x PAD_D x PAD_H
    with z = 0 underneath, a brass key cylinder and a black keyway in the bottom, four rivets on each face, and a
    chrome shackle standing on the top, its arc in the x-z plane. Returns the shackle's centre line (local)."""
    from mathutils import Vector

    bm, paint = ctx["bm"], ctx["paint"]
    chrome, steel, brass, black = 0, 1, 2, 3

    def block(c, s, mat, col):
        cx, cy, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        p = [bm.verts.new(xf(Vector((cx + sx * hx, cy + sy * hy, cz + sz * hz)))) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        night = (col[0] * 0.3, col[1] * 0.3, col[2] * 0.32, 1.0)
        for a, b, cc, d in ((0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)):
            paint(bm.faces.new((p[a], p[b], p[cc], p[d])), [(0, 0), (1, 0), (1, 1), (0, 1)], col, night, mat)

    def cyl(c0, c1, r, sides, mat, col):
        _sweep(ctx, [xf(Vector(c0)), xf(Vector(c1))], r, sides, mat, col)

    # seven plates, every other one a hair narrower: the grooves of a laminated lock
    plates = 7
    ph = PAD_H / plates
    for i in range(plates):
        inset = 0.0006 if i % 2 else 0.0
        shade = (0.86, 0.86, 0.88, 1.0) if i % 2 else (0.7, 0.7, 0.72, 1.0)
        block((0.0, 0.0, ph * (i + 0.5)), (PAD_W - 2 * inset, PAD_D - 2 * inset, ph), steel, shade)
    for x in (-PAD_W / 2 + 0.006, PAD_W / 2 - 0.006):  # rivets through the plates
        for z in (0.007, PAD_H - 0.007):
            cyl((x, -PAD_D / 2 - 0.0008, z), (x, PAD_D / 2 + 0.0008, z), 0.0024, 8, chrome, (0.95, 0.95, 0.95, 1.0))
    # the key cylinder and its keyway in the bottom face
    cyl((0.0, 0.0, -0.0004), (0.0, 0.0, 0.0006), 0.0075, 12, brass, (0.92, 0.9, 0.86, 1.0))
    block((0.0, 0.0, -0.0006), (0.0015, 0.0085, 0.0008), black, (0.25, 0.25, 0.26, 1.0))
    # the shackle: two legs out of the top, joined by a half circle
    r, a, legs = PAD_SHACKLE
    top = PAD_H + legs
    line = [Vector((-a, 0.0, PAD_H - 0.004)), Vector((-a, 0.0, PAD_H)), Vector((-a, 0.0, top))]
    line += [Vector((-a * math.cos(math.pi * k / 10), 0.0, top + a * math.sin(math.pi * k / 10))) for k in range(1, 10)]
    line += [Vector((a, 0.0, top)), Vector((a, 0.0, PAD_H)), Vector((a, 0.0, PAD_H - 0.004))]
    _sweep(ctx, [xf(p) for p in line], r, 8, chrome, (0.95, 0.95, 0.96, 1.0))
    return line


def _ground(ctx):
    """Moves the model so its base is centred on x and y with z = 0 at the lowest point; returns its half extents."""
    vs = ctx["bm"].verts
    lo = [min(v.co[i] for v in vs) for i in range(3)]
    hi = [max(v.co[i] for v in vs) for i in range(3)]
    shift = ((lo[0] + hi[0]) / 2, (lo[1] + hi[1]) / 2, lo[2])
    for v in vs:
        v.co.x, v.co.y, v.co.z = v.co.x - shift[0], v.co.y - shift[1], v.co.z - shift[2]
    return [(hi[i] - lo[i]) / 2 for i in range(3)]


def build_chain(ctx):
    """About 0.6 m of steel chain lying in a loose S on the ground: 20 links, flat and upright by turns."""
    from mathutils import Vector

    curve = [Vector((-0.24 + 0.48 * t / 40, 0.07 * math.sin(t / 40 * 2 * math.pi) * (0.6 + 0.4 * t / 40), 0.0)) for t in range(41)]
    centres = [Vector((p.x, p.y, CHAIN_WIRE)) for p in _spaced(curve, CHAIN_PITCH)][:20]
    _chain(ctx, centres)
    hx, hy, hz = _ground(ctx)
    return [((0.0, 0.0, hz), (hx, hy, hz))]


def build_padlock(ctx):
    """A laminated steel padlock standing on its base, 0.05 x 0.026 m, 0.078 m to the top of its shackle."""
    _padlock(ctx, lambda v: v)
    _ground(ctx)
    r, a, legs = PAD_SHACKLE
    return [((0.0, 0.0, PAD_H / 2), (PAD_W / 2, PAD_D / 2, PAD_H / 2)), ((0.0, 0.0, PAD_H + (legs + a + r) / 2), (a + r, r, (legs + a + r) / 2))]


def _lock_chain(ctx, padlock, depth):
    """The chain closed into a loop on the ground by a padlock lying on its back (its front face up), the shackle through
    the two end links. `padlock(ctx, xf)` builds the lock through xf and returns its shackle's centre line (two legs of
    three points, a nine-point arc) and wire radius; `depth` is its body's front-to-back size."""
    from mathutils import Vector

    # the padlock on its back: local z (up the lock) -> world +y, its front (-y) -> world up
    lift = depth / 2
    base = Vector((0.0, -0.17, 0.0))
    xf = lambda v: base + Vector((v.x, v.z, -v.y + lift))  # noqa: E731
    line, r = padlock(ctx, xf)
    # the end links sit on the shackle's arc either side of its crown, their holes round the wire
    picks = (5, 9)  # 54 degrees round the arc from each leg
    shackle = [xf(p) for p in line]
    anchors = []
    for k in picks:
        p = shackle[k]
        tangent = (shackle[k + 1] - shackle[k - 1]).normalized()
        along = Vector((0, 0, 1)).cross(tangent).normalized()  # flat on the ground, square to the wire
        if along.y < 0:
            along = -along
        anchors.append((p, along, tangent))
    # the loop: from one end link out round a circle and back to the other
    (p0, al0, t0), (p1, al1, t1) = anchors
    centre, radius = Vector((0.0, 0.03, 0.0)), 0.12
    ang0, ang1 = math.atan2(p0.y - centre.y, p0.x - centre.x), math.atan2(p1.y - centre.y, p1.x - centre.x)
    if ang1 > ang0:
        ang1 -= 2 * math.pi
    # an end link hangs on the wire by its inner end, so its centre sits out from the shackle
    hang = (CHAIN_LINK[0] - 4 * CHAIN_WIRE) / 2 - r
    s0, s1 = p0 + al0 * hang, p1 + al1 * hang
    steps = 48
    arc = [s0]
    for s in range(1, steps):
        ang = ang0 + (ang1 - ang0) * s / steps
        arc.append(Vector((centre.x + radius * math.cos(ang), centre.y + radius * math.sin(ang), 0.0)))
    arc.append(s1)
    total = sum((arc[i + 1] - arc[i]).length for i in range(len(arc) - 1))
    count = max(3, round(total / CHAIN_PITCH) + 1)
    if count % 2 == 0:
        count += 1  # both end links stand upright on the shackle, so the count is odd
    centres = [Vector((c.x, c.y, CHAIN_WIRE)) for c in _spaced(arc, 0, count)]
    centres[0], centres[-1] = s0, s1
    ends = {0: (al0, t0), count - 1: (al1, t1)}
    _chain(ctx, centres, first_flat=False, ends=ends)
    hx, hy, hz = _ground(ctx)
    return [((0.0, 0.0, hz), (hx, hy, hz))]


def build_lock_chain(ctx):
    """The chain closed into a loop by the keyed padlock."""
    return _lock_chain(ctx, lambda c, xf: (_padlock(c, xf), PAD_SHACKLE[0]), PAD_D)


COMBO_W, COMBO_D, COMBO_H = 0.046, 0.024, 0.05  # combo_padlock: the die-cast body (x, y, z)
COMBO_DIAL = (0.009, 0.0096, 0.0108, 0.018)  # a dial wheel's radius and width, the wheels' spacing and their axis' height
COMBO_SHOWN = (2, 7, 4, 9)  # the digits the four wheels show to the front
# (source TXD, texture) per combo_padlock material, all vanilla: chrome pipe (shackle, bezel), the counter's red (the
# body), galvanised steel (the dials' cores), the motel's door numbers (black 1 to 9 over alpha, round the dials)
COMBO_TEXTURES = [
    ("industrialext.txd", "cj_chromepipe"),
    ("cj_airprt.txd", "CJ_red_COUNTER"),
    ("metalbarrier_cj.txd", "CJ_GALVANISED"),
    ("imy_motel.txd", "mp_motel_numbers"),
]


COMBO_SHACKLE = (0.004, 0.0145, 0.022)  # the shackle's wire radius, half its span and its legs' height above the body
# the shackle's long leg (-X) reaches COMBO_LONG_LEG into the body and turns there; the short one (+X) goes
# COMBO_SHORT_LEG into its hole when shut. Open, the shackle stands COMBO_RAISE higher (the short leg clear of the body)
# and has turned COMBO_TURN degrees on the long leg. items/client/combo.lua moves combo_shackle by the same numbers.
COMBO_LONG_LEG, COMBO_SHORT_LEG, COMBO_RAISE, COMBO_TURN = 0.016, 0.004, 0.01, 90.0


def _combo_padlock(ctx, xf, body=True, shackle=True, raise_=0.0, turn=0.0, shift=0.0):
    """The four-dial combination padlock in its own frame, mapped through xf(Vector) -> Vector: a red die-cast body
    COMBO_W x COMBO_D x COMBO_H with z = 0 underneath, its four dials across the front (-Y) in a chrome bezel, each a
    nine-sided steel drum with its COMBO_SHOWN digit on the facet that faces the front, and a chrome shackle on top, its
    arc in the x-z plane when shut. `body` / `shackle` leave either part out; the shackle stands `raise_` higher and has
    turned `turn` degrees on its long leg, and moves `shift` along X (the shackle alone, its long leg on the origin).
    Returns the shackle's centre line (local, shut) and its wire radius."""
    from mathutils import Vector

    bm, paint = ctx["bm"], ctx["paint"]
    chrome, red, steel, digits = 0, 1, 2, 3
    white = (0.92, 0.92, 0.92, 1.0)
    night = (0.28, 0.28, 0.29, 1.0)
    w, d, h = COMBO_W, COMBO_D, COMBO_H
    r, dw, pitch, az = COMBO_DIAL

    def block(c, s, mat, rect=(0, 0, 1, 1)):
        cx, cy_, cz = c
        hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
        v = [bm.verts.new(xf(Vector((cx + sx * hx, cy_ + sy * hy, cz + sz * hz)))) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
        u0, v0, u1, v1 = rect
        for a, b, cc, e in ((0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)):
            paint(bm.faces.new((v[a], v[b], v[cc], v[e])), [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], white, night, mat)

    sr, sa, legs = COMBO_SHACKLE
    top = h + legs
    line = [Vector((-sa, 0.0, h - COMBO_LONG_LEG)), Vector((-sa, 0.0, h)), Vector((-sa, 0.0, top))]
    line += [Vector((-sa * math.cos(math.pi * k / 10), 0.0, top + sa * math.sin(math.pi * k / 10))) for k in range(1, 10)]
    line += [Vector((sa, 0.0, top)), Vector((sa, 0.0, h)), Vector((sa, 0.0, h - COMBO_SHORT_LEG))]
    if shackle:
        ca, sn = math.cos(math.radians(turn)), math.sin(math.radians(turn))

        def moved(p):  # turned on the long leg's axis (x = -sa, y = 0), raised, shifted
            x, y = p.x + sa, p.y
            return Vector((-sa + x * ca - y * sn + shift, x * sn + y * ca, p.z + raise_))

        _sweep(ctx, [xf(moved(p)) for p in line], sr, 8, chrome, (0.95, 0.95, 0.96, 1.0))
    if not body:
        return line, sr
    block((0.0, 0.0, h / 2), (w, d, h), red)
    sides = 9
    step = 2 * math.pi / sides
    # the dials: a wheel's axis along X, set into the body so the facet facing the front stands just proud of it
    front = -d / 2
    cy = front + r * math.cos(step / 2) - 0.0015
    # the bezel: a chrome window round that row of facets, flatter than the dials stand out so it hides no digit
    half = r * math.sin(step / 2)
    for z in (az + half + 0.0016, az - half - 0.0016):
        block((0.0, front - 0.0005, z), (4 * pitch + 0.004, 0.001, 0.0018), chrome)
    for x in (-2 * pitch - 0.0008, 2 * pitch + 0.0008):
        block((x, front - 0.0005, az), (0.0024, 0.001, 2 * half + 0.005), chrome)

    def at(x, a, rad):  # a = 0 faces the front (-Y), growing upward
        return xf(Vector((x, cy - rad * math.cos(a), az + rad * math.sin(a))))

    for i, shown in enumerate(COMBO_SHOWN):
        xc = (i - 1.5) * pitch
        x0, x1 = xc - dw / 2, xc + dw / 2
        # the wheel, a closed nine-sided steel drum with a facet square to the front
        rings = [[bm.verts.new(at(x, (k - 0.5) * step, r)) for k in range(sides)] for x in (x0, x1)]
        for k in range(sides):
            j = (k + 1) % sides
            face = bm.faces.new((rings[0][k], rings[1][k], rings[1][j], rings[0][j]))
            paint(face, [(0, 0), (1, 0), (1, 0.25), (0, 0.25)], white, night, steel)
        for ring in rings:
            paint(bm.faces.new(ring), [(0.5, 0.5)] * sides, white, night, steel)
        # its shown digit on that facet: one cell of the motel numbers (a 3 x 3 grid, each cell twice as tall as wide)
        col, row = (shown - 1) % 3, (shown - 1) // 3
        rect = (col / 3, 1 - (row + 1) / 3, (col + 1) / 3, 1 - row / 3)
        facet_y = cy - r * math.cos(step / 2)
        block((xc, facet_y - 0.0002, az), (half, 0.0003, 2 * half), digits, rect)
    return line, sr


def _combo_boxes(raise_=0.0):
    w, d, h = COMBO_W, COMBO_D, COMBO_H
    sr, sa, legs = COMBO_SHACKLE
    tall = legs + sa + sr
    return [((0.0, 0.0, h / 2), (w / 2, d / 2, h / 2)), ((0.0, 0.0, h + raise_ + tall / 2), (sa + sr, sa + sr, tall / 2))]


def build_combo_padlock(ctx):
    """The four-dial combination padlock standing on its base, its dials to the front (-Y), open: the shackle up and
    turned out on its long leg. The item model; a shut one is combo_padlock_shut."""
    _combo_padlock(ctx, lambda v: v, raise_=COMBO_RAISE, turn=COMBO_TURN)
    return _combo_boxes(COMBO_RAISE)


def build_combo_padlock_shut(ctx):
    """The combination padlock shut: the shackle down, its short leg in its hole."""
    _combo_padlock(ctx, lambda v: v)
    return _combo_boxes()


def build_combo_padlock_body(ctx):
    """The combination padlock without its shackle, for the close-up that moves combo_shackle (items client)."""
    _combo_padlock(ctx, lambda v: v, shackle=False)
    return _combo_boxes()[:1]


def build_combo_shackle(ctx):
    """The combination padlock's shackle alone, shut, its long leg's axis on the origin (x = 0, y = 0) and z as the
    body's: the close-up turns it about Z and raises it."""
    _combo_padlock(ctx, lambda v: v, body=False, shift=COMBO_SHACKLE[1])
    sr, sa, legs = COMBO_SHACKLE
    tall = legs + sa + sr + COMBO_LONG_LEG
    return [((sa, 0.0, COMBO_H - COMBO_LONG_LEG + tall / 2), (sa + sr, sr, tall / 2))]


def build_combo_lock_chain(ctx):
    """The chain closed into a loop by the combination padlock, its dials up."""
    return _lock_chain(ctx, _combo_padlock, COMBO_D)


# (source TXD, texture) per tow_bar material, all vanilla (found with gta-scout): black steel (the receiver and its
# mounting bar), galvanised steel (the ball mount), chrome pipe (the ball, its nut and the hitch pin)
TOWBAR_TEXTURES = [("fences.txd", "blackmetal"), ("metalbarrier_cj.txd", "CJ_GALVANISED"), ("industrialext.txd", "cj_chromepipe")]
TOWBAR_BALL = 0.025  # tow_bar: the ball's radius; its centre is the model's origin
# rope_coil: a twisted hemp rope (gta_int.img's gym rope, its strands along u), wound into a coil
ROPE_TEXTURES = [("dogsgym.txd", "Gym_rope")]
ROPE_R = 0.012  # the rope's radius
ROPE_BAND = (0.16, 0.84)  # the part of Gym_rope's height the rope fills (black above and below it)


def _sphere(ctx, centre, radius, rings, sides, material, col):
    """A UV sphere; its texture wraps once round it."""
    bm, paint = ctx["bm"], ctx["paint"]
    cx, cy, cz = centre
    night = (col[0] * 0.3, col[1] * 0.3, col[2] * 0.32, 1.0)
    grid = []
    for i in range(rings + 1):
        phi = math.pi * i / rings
        z, r = -math.cos(phi) * radius, math.sin(phi) * radius
        grid.append([bm.verts.new((cx + r * math.cos(2 * math.pi * k / sides), cy + r * math.sin(2 * math.pi * k / sides), cz + z)) for k in range(sides)])
    for i in range(rings):
        for k in range(sides):
            j = (k + 1) % sides
            quad = [grid[i][k], grid[i][j], grid[i + 1][j], grid[i + 1][k]]
            uvs = [(k / sides, i / rings), ((k + 1) / sides, i / rings), ((k + 1) / sides, (i + 1) / rings), (k / sides, (i + 1) / rings)]
            if i == 0:  # the poles' rings collapse to one point: drop the duplicate corner
                quad, uvs = quad[1:], uvs[1:]
            elif i == rings - 1:
                quad, uvs = quad[:2] + quad[3:], uvs[:2] + uvs[3:]
            paint(bm.faces.new(quad), uvs, col, night, material)
    # the collapsed pole rings left duplicate vertices: merge them
    import bmesh

    bmesh.ops.remove_doubles(bm, verts=grid[0] + grid[-1], dist=1e-6)


def build_tow_bar(ctx):
    """A ball-type tow bar (class II receiver hitch), the ball at the origin and the bar running forward (+Y) under the
    car from it: a 50 mm chrome ball on a neck and nut, a galvanised ball mount whose shank slides into a black square
    receiver tube, a chrome hitch pin through the tube, and the receiver's mounting bar rising into the car's underside.
    Fitted at a vehicle's trailer_attach dummy, so a hitched trailer's coupler lands on the ball."""
    box, tube = ctx["box"], ctx["tube"]
    black, galv, chrome = 0, 1, 2
    white, dim = (0.95, 0.95, 0.96, 1.0), (0.62, 0.62, 0.64, 1.0)
    _sphere(ctx, (0.0, 0.0, 0.0), TOWBAR_BALL, 8, 16, chrome, white)
    tube((0.0, 0.0, -0.05), (0.0, 0.0, -0.012), 0.012, 12, chrome, white)  # the neck
    tube((0.0, 0.0, -0.075), (0.0, 0.0, -0.062), 0.022, 6, chrome, dim)  # the nut under the mount
    # the ball mount: a plate under the ball, dropping to a shank that runs forward into the receiver
    box((0.0, 0.015, -0.056), (0.075, 0.11, 0.012), galv, None)
    box((0.0, 0.08, -0.04), (0.05, 0.035, 0.045), galv, None)
    box((0.0, 0.2, -0.04), (0.044, 0.25, 0.044), galv, None)
    # the receiver tube round the shank, its square mouth a little bigger, the pin across it
    box((0.0, 0.25, -0.04), (0.062, 0.24, 0.062), black, None)
    box((0.0, 0.135, -0.04), (0.07, 0.012, 0.07), black, None)
    tube((-0.05, 0.2, -0.04), (0.05, 0.2, -0.04), 0.007, 8, chrome, white)
    tube((0.05, 0.2, -0.04), (0.05, 0.2, -0.06), 0.003, 6, chrome, dim)  # the pin's clip
    # the mounting bar: up from the receiver's back end into the car, then across under the bumper
    box((0.0, 0.39, 0.0), (0.06, 0.05, 0.14), black, None)
    box((0.0, 0.39, 0.085), (0.34, 0.04, 0.04), black, None)
    for x in (-0.15, 0.15):  # the brackets that bolt it to the chassis
        box((x, 0.39, 0.125), (0.04, 0.07, 0.04), galv, None)
    return [((0.0, 0.2, -0.02), (0.04, 0.22, 0.06))]


def _rope_sweep(ctx, path, radius, sides, col):
    """The rope along `path` (Vectors), capped at both ends: Gym_rope's strands run along it (u by arc length, one
    tile per 2.8 radii) and its band of rope wraps once round it."""
    from mathutils import Vector

    bm, paint = ctx["bm"], ctx["paint"]
    night = (col[0] * 0.3, col[1] * 0.3, col[2] * 0.32, 1.0)
    rings, nrm, run, us = [], None, 0.0, []
    for i, p in enumerate(path):
        a, b = path[max(i - 1, 0)], path[min(i + 1, len(path) - 1)]
        t = (b - a).normalized()
        if nrm is None:
            nrm = t.cross(Vector((0, 0, 1)) if abs(t.z) < 0.9 else Vector((1, 0, 0))).normalized()
        else:
            nrm = (nrm - t * nrm.dot(t)).normalized()
        bin_ = t.cross(nrm).normalized()
        rings.append([bm.verts.new(p + (nrm * math.cos(2 * math.pi * k / sides) + bin_ * math.sin(2 * math.pi * k / sides)) * radius) for k in range(sides)])
        if i:
            run += (p - path[i - 1]).length
        us.append(run / (radius * 2.8))
    v0, v1 = ROPE_BAND
    for i in range(len(path) - 1):
        for k in range(sides):
            j = k + 1
            va, vb = v0 + (v1 - v0) * k / sides, v0 + (v1 - v0) * j / sides
            face = bm.faces.new((rings[i][k], rings[i][j % sides], rings[i + 1][j % sides], rings[i + 1][k]))
            paint(face, [(us[i], va), (us[i], vb), (us[i + 1], vb), (us[i + 1], va)], col, night, 0)
    for ring in (rings[0], rings[-1]):
        face = bm.faces.new(ring)
        paint(face, [(0.5 + 0.1 * math.cos(2 * math.pi * k / sides), 0.5 + 0.1 * math.sin(2 * math.pi * k / sides)) for k in range(sides)], col, night, 0)


def build_rope_coil(ctx):
    """About 5 m of hemp rope wound into a coil lying on the ground: six turns of 0.13 m, each one a little higher and
    wider where it crosses the last, the outer end trailing out and its tail tied round the coil."""
    from mathutils import Vector

    turns, per_turn, r0 = 6, 24, 0.13
    pts = []
    for s in range(turns * per_turn + 1):
        a = 2 * math.pi * s / per_turn
        lap = s / per_turn
        r = r0 + 0.011 * lap + 0.006 * math.sin(a * 2 + lap * 1.7)  # hand-wound: not quite round, turns apart
        z = ROPE_R + 0.004 * lap + 0.014 * (0.5 + 0.5 * math.sin(a + lap * 2.1))  # each turn rides over the last somewhere
        pts.append(Vector((r * math.cos(a), r * math.sin(a), z)))
    # the free end runs out across the floor in a lazy curve
    end = pts[-1]
    for s in range(1, 13):
        f = s / 12
        pts.append(Vector((end.x + 0.03 * f, end.y + 0.22 * f, ROPE_R + (end.z - ROPE_R) * (1 - f) ** 2)) + Vector((0.04 * math.sin(f * math.pi), 0, 0)))
    _rope_sweep(ctx, pts, ROPE_R, 8, (0.92, 0.86, 0.74, 1.0))
    # a tie of the same rope round the coil's bundle on the -X side
    mid, tr = r0 + 0.0055 * turns, 0.0055 * turns + 2.2 * ROPE_R  # round the bundle's middle
    tie = [Vector((-mid + tr * math.cos(2 * math.pi * k / 16), 0.0, 0.03 + 0.8 * tr * math.sin(2 * math.pi * k / 16))) for k in range(17)]
    _rope_sweep(ctx, tie, ROPE_R * 0.7, 6, (0.85, 0.79, 0.67, 1.0))
    hx, hy, hz = _ground(ctx)
    return [((0.0, 0.0, hz), (hx, hy, hz))]


def _tube(ctx):
    """ctx["tube"] with the texture wrapped once round the cylinder (u round, v along) instead of whole on every side face,
    so paper, plated and painted cylinders read as one surface. Same arguments: (start, end, radius, segs, material, col,
    extend=True)."""
    from mathutils import Vector
    bm, paint = ctx["bm"], ctx["paint"]

    def tube(start, end, radius, segs, material, col, extend=True):
        a, b = Vector(start), Vector(end)
        axis = (b - a).normalized()
        if extend:
            a, b = a - axis * radius * 0.5, b + axis * radius * 0.5
        helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
        u = axis.cross(helper).normalized()
        w = axis.cross(u)
        c = col or (0.9, 0.9, 0.9, 1.0)
        night = (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
        rings = [[bm.verts.new(p + (u * math.cos(2 * math.pi * i / segs) + w * math.sin(2 * math.pi * i / segs)) * radius) for i in range(segs)] for p in (a, b)]
        for i in range(segs):
            j = (i + 1) % segs
            paint(bm.faces.new((rings[0][i], rings[0][j], rings[1][j], rings[1][i])), [(i / segs, 0), ((i + 1) / segs, 0), ((i + 1) / segs, 1), (i / segs, 1)], c, night, material)
        disc = [(0.5 + 0.5 * math.cos(2 * math.pi * i / segs), 0.5 + 0.5 * math.sin(2 * math.pi * i / segs)) for i in range(segs)]
        for ring in rings:
            paint(bm.faces.new(ring), disc, c, night, material)

    return tube


def _torus(ctx, centre, big, small, segs, sides, material, col, axis="z"):
    """A ring of tube `small` round a circle of radius `big` about `centre`, its plane normal to Z (or Y), the texture wrapped
    once round the tube and `segs` times along the ring."""
    from mathutils import Vector
    bm, paint = ctx["bm"], ctx["paint"]
    c = col or (0.9, 0.9, 0.9, 1.0)
    night = (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    o = Vector(centre)
    up = Vector((0, 0, 1)) if axis == "z" else Vector((0, 1, 0))
    def at(i, k):
        a, b = 2 * math.pi * i / segs, 2 * math.pi * k / sides
        radial = Vector((math.cos(a), math.sin(a), 0.0)) if axis == "z" else Vector((math.cos(a), 0.0, math.sin(a)))
        return o + radial * (big + small * math.cos(b)) + up * small * math.sin(b)
    grid = [[bm.verts.new(at(i, k)) for k in range(sides)] for i in range(segs)]
    for i in range(segs):
        for k in range(sides):
            i2, k2 = (i + 1) % segs, (k + 1) % sides
            paint(bm.faces.new((grid[i][k], grid[i2][k], grid[i2][k2], grid[i][k2])), [(0, k / sides), (1, k / sides), (1, (k + 1) / sides), (0, (k + 1) / sides)], c, night, material)


def _obox(ctx, centre, axes, size, material, col, rect=None):
    """A box along three orthonormal `axes` (Vectors), `size` measured along them, every face mapped to `rect`."""
    from mathutils import Vector
    bm, paint = ctx["bm"], ctx["paint"]
    c = Vector(centre)
    h = [a * (s / 2) for a, s in zip(axes, size)]
    v = [bm.verts.new(c + sx * h[0] + sy * h[1] + sz * h[2]) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    col = col or (0.9, 0.9, 0.9, 1.0)
    u0, v0, u1, v1 = rect or (0, 0, 1, 1)
    for a, b, cc, d in ((0, 1, 3, 2), (4, 5, 7, 6), (0, 1, 5, 4), (2, 3, 7, 6), (0, 2, 6, 4), (1, 3, 7, 5)):
        paint(bm.faces.new((v[a], v[b], v[cc], v[d])), [(u0, v0), (u1, v0), (u1, v1), (u0, v1)], col, (col[0] * 0.3, col[1] * 0.3, col[2] * 0.32, 1.0), material)


def _radial(angle, axis="y"):
    """The (radial, tangential, axial) unit vectors at `angle` (degrees) round an axis along Y or Z."""
    from mathutils import Vector
    a = math.radians(angle)
    if axis == "y":
        return Vector((math.cos(a), 0.0, math.sin(a))), Vector((-math.sin(a), 0.0, math.cos(a))), Vector((0.0, 1.0, 0.0))
    return Vector((math.cos(a), math.sin(a), 0.0)), Vector((-math.sin(a), math.cos(a), 0.0)), Vector((0.0, 0.0, 1.0))


MOTOR_AXIS_Z = 0.085  # motor.dff: the shaft's height above the feet
# (source TXD, texture) per motor material, all vanilla and found with gta-scout: the blue container paint (its ribs read as
# the frame's cooling fins), a cast end bell, chrome shaft, black fan cowl, the bistro's louvre on the cowl, rubber gland
MOTOR_TEXTURES = [("continx.txd", "frate64_blue"), ("hubprops2_sfse.txd", "Alumox64b"), ("industrialext.txd", "cj_chromepipe"), ("ballys01.txd", "CJ_blackplastic"), ("bistro.txd", "vent_64"), ("cj_airprt.txd", "CJ_RUBBER")]


def build_motor(ctx):
    """A small three-phase induction motor, 0.31 m: a blue finned frame along Y on two cast feet, a terminal box on top with
    a cable gland out of +X, the cast drive-end bell and a keyed chrome shaft out of +Y, a black fan cowl with a louvred
    end on -Y and an aluminium rating plate on -X. Origin at the base's centre."""
    from mathutils import Vector

    box, tube = ctx["box"], _tube(ctx)
    blue, cast, chrome, black, vent, rubber = 0, 1, 2, 3, 4, 5
    white, dim, dark = (0.9, 0.9, 0.9, 1.0), (0.65, 0.65, 0.65, 1.0), (0.4, 0.4, 0.42, 1.0)
    z = MOTOR_AXIS_Z
    tube((0.0, -0.1, z), (0.0, 0.08, z), 0.066, 16, blue, None, False)
    for k in range(16):  # cooling fins round the frame, none over the feet
        angle = k * 22.5 + 11.25
        if 225 < angle < 315:
            continue
        radial, tangent, axial = _radial(angle)
        _obox(ctx, (radial * 0.074) + Vector((0.0, -0.01, z)), (radial, tangent, axial), (0.018, 0.005, 0.17), blue, dim)
    for y in (-0.065, 0.045):  # the feet: a pad and a web up to the frame
        box((0.0, y, 0.008), (0.15, 0.035, 0.016), blue, dim)
        box((0.0, y, 0.03), (0.09, 0.028, 0.04), blue, dim)
    tube((0.0, 0.08, z), (0.0, 0.102, z), 0.062, 16, cast, None, False)
    tube((0.0, 0.102, z), (0.0, 0.114, z), 0.032, 12, cast, dim, False)
    for k in range(4):  # the bell's through-bolts
        radial, _, _ = _radial(45 + k * 90)
        p = radial * 0.05
        tube((p.x, 0.1, z + p.z), (p.x, 0.106, z + p.z), 0.006, 6, chrome, dim, False)
    tube((0.0, 0.114, z), (0.0, 0.165, z), 0.011, 10, chrome, white, False)
    box((0.0, 0.142, z + 0.0105), (0.006, 0.04, 0.003), black, None)  # the key
    tube((0.0, -0.1, z), (0.0, -0.145, z), 0.068, 16, black, dark, False)
    tube((0.0, -0.145, z), (0.0, -0.147, z), 0.06, 16, vent, white, False)  # the cowl's louvred end
    tz = z + 0.066 + 0.016
    box((0.0, 0.005, tz), (0.07, 0.08, 0.04), blue, None)
    box((0.0, 0.005, tz + 0.022), (0.076, 0.086, 0.006), blue, dim)
    for x, y in ((-0.03, -0.034), (0.03, -0.034), (-0.03, 0.044), (0.03, 0.044)):
        tube((x, y, tz + 0.025), (x, y, tz + 0.028), 0.004, 6, chrome, dim, False)
    tube((0.035, 0.005, tz - 0.002), (0.055, 0.005, tz - 0.002), 0.011, 10, rubber, None, False)  # the gland
    tube((0.055, 0.005, tz - 0.002), (0.075, 0.005, tz - 0.012), 0.006, 8, rubber, dark)
    box((-0.0745, -0.01, z + 0.01), (0.002, 0.06, 0.035), cast, white)  # the rating plate
    return [((0.0, 0.0, 0.095), (0.085, 0.155, 0.095))]


STARTER_AXIS_Z = 0.045  # starter_motor.dff: the armature's height above the lowest point
# (source TXD, texture) per starter_motor material, all vanilla and found with gta-scout: black-painted field frame,
# cast aluminium nose and end cap, zinc-plated solenoid and bolts, copper studs and strap (the strip club's gold), red boot
STARTER_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("hubprops2_sfse.txd", "Alumox64b"), ("industrialext.txd", "cj_chromepipe"), ("lee_strip2.txd", "Strip_Gold"), ("cj_airprt.txd", "CJ_red_COUNTER")]


def build_starter_motor(ctx):
    """A car's pre-engaged starter motor, 0.25 m along Y: the black field frame between a cast end cap (-Y) and the cast
    drive housing (+Y) with a two-ear mounting flange and the pinion gear in its open snout, the zinc solenoid riding on
    top with two copper studs (the battery one in a red boot) and a copper strap down into the frame. Origin at the
    base's centre."""
    from mathutils import Vector

    box, tube = ctx["box"], _tube(ctx)
    black, cast, zinc, copper, red = 0, 1, 2, 3, 4
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    z = STARTER_AXIS_Z
    tube((0.0, -0.085, z), (0.0, 0.035, z), 0.045, 16, black, dim, False)
    tube((0.0, -0.103, z), (0.0, -0.085, z), 0.04, 16, cast, None, False)
    tube((0.0, -0.11, z), (0.0, -0.103, z), 0.016, 10, cast, dim, False)
    for x in (-0.028, 0.028):  # through-bolt heads on the end cap
        tube((x, -0.106, z + 0.02), (x, -0.101, z + 0.02), 0.005, 6, zinc, white, False)
    tube((0.0, 0.035, z), (0.0, 0.07, z), 0.043, 16, cast, None, False)
    box((0.0, 0.058, z), (0.15, 0.012, 0.042), cast, dim)  # the flange's ears
    for x in (-0.06, 0.06):
        tube((x, 0.046, z), (x, 0.072, z), 0.007, 8, zinc, white, False)
    tube((0.0, 0.07, z), (0.0, 0.1, z), 0.03, 14, cast, None, False)
    box((0.0, 0.115, z + 0.018), (0.05, 0.03, 0.02), cast, dim)  # the snout, open underneath
    tube((0.0, 0.1, z), (0.0, 0.128, z), 0.016, 12, zinc, white, False)
    for k in range(10):  # the pinion's teeth
        radial, tangent, axial = _radial(k * 36)
        _obox(ctx, radial * 0.018 + Vector((0.0, 0.114, z)), (radial, tangent, axial), (0.006, 0.005, 0.026), zinc, white)
    sz = z + 0.045 + 0.022
    tube((0.0, -0.035, sz), (0.0, 0.07, sz), 0.024, 14, zinc, None, False)
    tube((0.0, -0.047, sz), (0.0, -0.035, sz), 0.026, 14, black, None, False)  # the solenoid's moulded cap
    for x, boot in ((-0.011, True), (0.011, False)):
        tube((x, -0.047, sz + 0.004), (x, -0.062, sz + 0.004), 0.004, 8, copper, white, False)
        tube((x, -0.05, sz + 0.004), (x, -0.053, sz + 0.004), 0.0065, 6, copper, white, False)  # the nut
        if boot:
            tube((x, -0.054, sz + 0.004), (x, -0.066, sz + 0.004), 0.008, 10, red, None, False)
    box((0.011, -0.07, sz - 0.012), (0.008, 0.004, 0.032), copper, white)  # the strap into the frame
    box((0.011, -0.075, z + 0.03), (0.008, 0.012, 0.004), copper, white)
    tube((0.0, 0.0, z + 0.04), (0.0, 0.0, sz - 0.018), 0.008, 8, zinc, dim, False)  # the solenoid's saddle
    return [((0.0, -0.005, 0.05), (0.075, 0.12, 0.05))]


PSU_W, PSU_D, PSU_H = 0.15, 0.14, 0.086  # power_supply.dff, an ATX box (x, y, z)
CJ_PANEL_DANGER = (0.5, 0.58, 0.98, 0.96)  # industrialext CJ_PANEL: the "DANGER HIGH VOLTAGE" plate
SWATCH_RED, SWATCH_YELLOW = (0.04, 0.7, 0.29, 0.96), (0.04, 0.37, 0.29, 0.63)
# (source TXD, texture) per power_supply material, all vanilla and found with gta-scout: galvanised sheet metal, black
# plastic (fan, sockets, plug), chrome fan guard, the bistro's louvre, the substation's danger plate, red switch, wire colours
PSU_TEXTURES = [("industrialext.txd", "cj_sheetmetal"), ("ballys01.txd", "CJ_blackplastic"), ("industrialext.txd", "cj_chromepipe"), ("bistro.txd", "vent_64"), ("industrialext.txd", "CJ_PANEL"), ("texttest.txd", "kb_red"), ("helixbarrier.txd", "colourboxes")]


def build_power_supply(ctx):
    """A computer power supply, 0.15 x 0.14 x 0.086 m: a galvanised box with a 120 mm fan under a chrome wire guard on
    top, the mains socket, red rocker switch and a louvre on the back (-Y), a danger plate on +X and a loom of red,
    yellow and black wires out of the front (+Y) into a 24-pin plug lying on the floor. Origin at the base's centre."""
    box, tube = ctx["box"], _tube(ctx)
    metal, black, chrome, vent, danger, red, colours = 0, 1, 2, 3, 4, 5, 6
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    w, d, h = PSU_W, PSU_D, PSU_H
    box((0.0, 0.0, h / 2), (w, d, h), metal, None)
    tube((0.0, 0.0, h - 0.002), (0.0, 0.0, h + 0.001), 0.056, 24, black, dim, False)  # the fan
    tube((0.0, 0.0, h + 0.001), (0.0, 0.0, h + 0.004), 0.018, 12, black, white, False)  # its hub sticker
    for i in range(-5, 6):  # the guard's wires
        half = math.sqrt(max(0.0, 0.057 ** 2 - (i * 0.0095) ** 2))
        box((i * 0.0095, 0.0, h + 0.004), (0.0018, 2 * half, 0.0018), chrome, white)
    box((0.0, 0.0, h + 0.004), (0.114, 0.0018, 0.0018), chrome, white)
    for x, y in ((-0.06, -0.06), (0.06, -0.06), (-0.06, 0.06), (0.06, 0.06)):
        tube((x, y, h), (x, y, h + 0.003), 0.004, 6, chrome, dim, False)
    by = -d / 2
    box((-0.03, by - 0.001, 0.045), (0.07, 0.002, 0.055), vent, white)  # the louvre
    box((0.035, by - 0.004, 0.05), (0.028, 0.008, 0.022), black, None)  # the mains socket
    box((0.035, by - 0.009, 0.05), (0.018, 0.002, 0.012), black, dim)
    box((0.055, by - 0.004, 0.024), (0.014, 0.008, 0.018), red, None)  # the rocker switch
    box((w / 2 + 0.001, 0.0, h / 2), (0.002, 0.08, 0.06), danger, white, CJ_PANEL_DANGER)
    # the loom: wires out of a grommet on +Y, down to the floor and along it into the plug
    gy = d / 2
    tube((0.0, gy, 0.06), (0.0, gy + 0.008, 0.06), 0.016, 12, black, None, False)
    for i, rect in enumerate([SWATCH_RED, SWATCH_YELLOW, None] * 2):
        x = -0.0125 + i * 0.005
        mat, col = (colours, white) if rect else (black, None)
        pts = [(x, gy + 0.006, 0.06), (x, gy + 0.035, 0.052), (x, gy + 0.055, 0.025), (x, gy + 0.065, 0.004), (x, gy + 0.11, 0.004)]
        for a, b in zip(pts, pts[1:]):
            _wire(ctx, a, b, 0.0022, mat, col, rect)
    box((0.0, gy + 0.125, 0.008), (0.05, 0.03, 0.016), black, None)  # the plug
    return [((0.0, 0.0, h / 2 + 0.002), (w / 2, d / 2, h / 2 + 0.002))]


def _wire(ctx, a, b, radius, material, col, rect=None):
    """A thin six-sided wire from a to b, every face mapped to `rect`."""
    from mathutils import Vector
    a, b = Vector(a), Vector(b)
    axis = (b - a).normalized()
    helper = Vector((0, 0, 1)) if abs(axis.z) < 0.9 else Vector((1, 0, 0))
    u = axis.cross(helper).normalized()
    w = axis.cross(u)
    length = (b - a).length + radius
    _obox(ctx, (a + b) / 2, (u, w, axis), (radius * 2, radius * 2, length), material, col, rect)


# (source TXD, texture) per fluctuator material, all vanilla and found with gta-scout: black project box, the substation's
# knob-and-meter panel, copper windings, chrome rod and electrodes, the keypad's green lamp, pale ceramic, red wire
FLUCT_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("industrialext.txd", "CJ_Panel2"), ("lee_strip2.txd", "Strip_Gold"), ("industrialext.txd", "cj_chromepipe"), ("kmb_keypadx.txd", "keypad_light"), ("des_telescopestuff.txd", "dish_panel_a"), ("cj_airprt.txd", "CJ_red_COUNTER")]


def build_fluctuator(ctx):
    """The Fluctuator Unit, a stun gun's guts and a radio pole bodged into a project box, 0.16 x 0.09 m and 0.25 m tall: a
    knob-and-meter panel across the front (+Y), a copper-wound coil on a ceramic foot standing on the lid with the
    radio's chrome rod and ball out of it, a green lamp and a toggle beside it, and the stun gun's two prongs out of +X.
    Origin at the base's centre."""
    box, tube = ctx["box"], _tube(ctx)
    black, panel, copper, chrome, lamp, ceramic, red = 0, 1, 2, 3, 4, 5, 6
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    box((0.0, 0.0, 0.03), (0.16, 0.09, 0.06), black, None)
    box((0.0, 0.0, 0.0615), (0.164, 0.094, 0.004), black, dim)  # the lid
    box((0.0, 0.0455, 0.03), (0.15, 0.002, 0.052), panel, white, (1.0, 0.0, 0.0, 1.0))
    for x in (-0.076, 0.076):  # feet
        for y in (-0.04, 0.04):
            tube((x * 0.9, y * 0.85, 0.0), (x * 0.9, y * 0.85, 0.004), 0.006, 8, black, dim, False)
    cx = -0.035
    for z0, r in ((0.0635, 0.03), (0.07, 0.024), (0.0765, 0.03)):  # the ceramic foot's sheds
        tube((cx, 0.0, z0), (cx, 0.0, z0 + 0.0065), r, 16, ceramic, white, False)
    tube((cx, 0.0, 0.083), (cx, 0.0, 0.145), 0.018, 14, black, None, False)
    for i in range(9):  # the windings
        z0 = 0.087 + i * 0.0062
        tube((cx, 0.0, z0), (cx, 0.0, z0 + 0.0048), 0.0215, 16, copper, white, False)
    tube((cx, 0.0, 0.145), (cx, 0.0, 0.151), 0.024, 16, ceramic, white, False)
    tube((cx, 0.0, 0.151), (cx, 0.0, 0.235), 0.0035, 8, chrome, white, False)
    tube((cx, 0.0, 0.235), (cx, 0.0, 0.249), 0.008, 10, chrome, white, False)
    _wire(ctx, (cx + 0.02, 0.0, 0.09), (0.012, 0.012, 0.0635), 0.0022, red, None)
    tube((0.04, 0.02, 0.0635), (0.04, 0.02, 0.071), 0.007, 10, chrome, dim, False)
    tube((0.04, 0.02, 0.071), (0.04, 0.02, 0.078), 0.0055, 10, lamp, white, False)
    tube((0.06, -0.018, 0.0635), (0.06, -0.018, 0.068), 0.006, 8, chrome, dim, False)
    _wire(ctx, (0.06, -0.018, 0.068), (0.064, -0.018, 0.083), 0.0018, chrome, white)  # the toggle
    for y in (-0.016, 0.016):
        tube((0.08, y, 0.03), (0.084, y, 0.03), 0.007, 8, black, dim, False)
        tube((0.084, y, 0.03), (0.108, y, 0.03), 0.0028, 6, chrome, white, False)
    return [((-0.005, 0.0, 0.035), (0.085, 0.047, 0.035)), ((cx, 0.0, 0.16), (0.03, 0.03, 0.09))]


def _cone(ctx, base, radius, height, segs, material, col):
    """An upright cone from a ring at `base` (its centre) up to a point `height` above."""
    bm, paint = ctx["bm"], ctx["paint"]
    x, y, z = base
    ring = [bm.verts.new((x + radius * math.cos(2 * math.pi * i / segs), y + radius * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)]
    tip = bm.verts.new((x, y, z + height))
    night = (col[0] * 0.3, col[1] * 0.3, col[2] * 0.32, 1.0)
    for i in range(segs):
        paint(bm.faces.new((ring[i], ring[(i + 1) % segs], tip)), [(i / segs, 0), ((i + 1) / segs, 0), (0.5, 1)], col, night, material)
    paint(bm.faces.new(ring), [(0.5 + 0.5 * math.cos(2 * math.pi * i / segs), 0.5 + 0.5 * math.sin(2 * math.pi * i / segs)) for i in range(segs)], col, night, material)


# The explosives' triggers (Timed, Trip Mine, Proximity, Phone Remote): each variant is its explosive with the trigger device
# taped on and leads to its detonator. (source TXD, texture) per trigger material, all vanilla and found with gta-scout:
# black plastic, the keypad's dark LCD glass, red LED, pale sensor housing, the payphone's keys, chrome, grey tape, wire colours
TRIGGER_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("kmb_keypadx.txd", "keypad_glass"), ("texttest.txd", "kb_red"), ("des_telescopestuff.txd", "dish_panel_a"), ("keypad.txd", "nt_phone3"), ("industrialext.txd", "cj_chromepipe"), ("cj_airprt.txd", "CJ_RUBBER"), ("helixbarrier.txd", "colourboxes")]
TRIGGERS = {"timer": "Timebomb", "trip": "TripMine", "prox": "ProxMine", "phone": "PhoneBomb"}


def with_triggers(sources):
    """An explosive's sources plus the trigger textures it lacks (a texture twice would export as name.png.001)."""
    have = {t.lower() for _, t in sources}
    return list(sources) + [s for s in TRIGGER_TEXTURES if s[1].lower() not in have]


def _trigger(ctx, kind, at, sources):
    """Builds trigger `kind` sitting on the point `at` (x, y, z), lengthwise along X; returns the point its leads leave."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    names = [t.lower() for _, t in sources]
    m = lambda tex: names.index(tex.lower())
    black, glass, led, pale, keys, chrome, tape = (m(n) for n in ("CJ_blackplastic", "keypad_glass", "kb_red", "dish_panel_a", "nt_phone3", "cj_chromepipe", "CJ_RUBBER"))
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    x, y, z = at
    if kind == "timer":  # a digital countdown timer: red LED digits behind dark glass, three buttons, taped down at the ends
        box((x, y, z + 0.011), (0.064, 0.036, 0.022), black, None)
        box((x, y + 0.004, z + 0.0225), (0.046, 0.018, 0.001), glass, white)
        for dx in (-0.017, -0.007, 0.007, 0.017):
            box((x + dx, y + 0.004, z + 0.0232), (0.007, 0.012, 0.0006), led, white)
        for dz in (-0.003, 0.003):
            box((x, y + 0.004 + dz, z + 0.0232), (0.0015, 0.0015, 0.0006), led, white)
        for dx in (-0.012, 0.0, 0.012):
            tube((x + dx, y - 0.012, z + 0.022), (x + dx, y - 0.012, z + 0.0245), 0.0028, 8, black, dim, False)
        for dx in (-0.029, 0.029):
            box((x + dx, y, z + 0.011), (0.009, 0.038, 0.0235), tape, None)
        return Vector((x + 0.033, y, z + 0.01))
    if kind == "phone":  # an old candybar phone face up: green screen, the keypad, a stub aerial, a band of tape round it
        box((x, y, z + 0.009), (0.105, 0.046, 0.018), black, None)
        box((x + 0.03, y, z + 0.0185), (0.032, 0.034, 0.001), glass, white)
        box((x - 0.024, y, z + 0.0185), (0.045, 0.036, 0.001), keys, white, PHONE_KEYS)
        tube((x + 0.052, y + 0.014, z + 0.011), (x + 0.066, y + 0.014, z + 0.011), 0.004, 8, black, dim, False)
        box((x + 0.006, y, z + 0.009), (0.012, 0.048, 0.0195), tape, None)
        return Vector((x - 0.053, y, z + 0.006))
    if kind == "prox":  # a PIR motion sensor: pale housing, the faceted lens looking out of +Y, a red LED, taped down
        box((x, y, z + 0.017), (0.05, 0.042, 0.034), pale, None)
        tube((x, y + 0.021, z + 0.019), (x, y + 0.029, z + 0.019), 0.013, 12, pale, white, False)
        tube((x, y + 0.029, z + 0.019), (x, y + 0.033, z + 0.019), 0.011, 12, pale, white, False)
        tube((x, y + 0.033, z + 0.019), (x, y + 0.035, z + 0.019), 0.007, 12, pale, white, False)
        tube((x + 0.017, y + 0.021, z + 0.029), (x + 0.017, y + 0.023, z + 0.029), 0.002, 6, led, white, False)
        for dx in (-0.019, 0.019):
            box((x + dx, y, z + 0.017), (0.008, 0.044, 0.0355), tape, None)
        return Vector((x - 0.026, y, z + 0.01))
    if kind == "trip":  # a tilt switch box with a pull pin; the tripwire runs off +Y to a stake in the ground
        box((x, y, z + 0.011), (0.042, 0.032, 0.022), black, None)
        box((x, y, z + 0.011), (0.01, 0.034, 0.0235), tape, None)
        _wire(ctx, (x + 0.012, y + 0.016, z + 0.012), (x + 0.012, y + 0.026, z + 0.012), 0.0012, chrome, white)
        _torus(ctx, (x + 0.012, y + 0.033, z + 0.012), 0.007, 0.0012, 12, 4, chrome, white)
        sx, sy = x + 0.03, y + 0.24
        _wire(ctx, (x + 0.012, y + 0.04, z + 0.012), (sx, sy, 0.035), 0.0005, chrome, white)
        tube((sx, sy, 0.0), (sx, sy, 0.04), 0.003, 6, chrome, dim, False)
        return Vector((x - 0.021, y, z + 0.01))
    raise ValueError(kind)


def _leads(ctx, a, b, sources, arch=0.012):
    """A red and a black lead from `a` to `b`, arched up over the gap."""
    from mathutils import Vector
    names = [t.lower() for _, t in sources]
    colours, black = names.index("colourboxes"), names.index("cj_blackplastic")
    a, b = Vector(a), Vector(b)
    for k, (mat, rect) in enumerate(((colours, SWATCH_RED), (black, None))):
        off = Vector((0.0, -0.002 + 0.004 * k, 0.0))
        mid = (a + b) / 2 + Vector((0.0, 0.0, arch)) + off
        for p, q in ((a + off, mid), (mid, b + off)):
            _wire(ctx, tuple(p), tuple(q), 0.0014, mat, (0.9, 0.9, 0.9, 1.0) if rect else (0.6, 0.6, 0.6, 1.0), rect)


STICK_R = 0.0145  # tnt.dff: a stick of dynamite's radius
# (source TXD, texture) per tnt material, all vanilla and found with gta-scout: the dynamite pickup's red paper, grey
# rubber for the tape, a chrome blasting cap, wire colours
TNT_TEXTURES = [("dynamite.txd", "redcan"), ("cj_airprt.txd", "CJ_RUBBER"), ("industrialext.txd", "cj_chromepipe"), ("helixbarrier.txd", "colourboxes")]
SWATCH_BLUE = (0.71, 0.04, 0.96, 0.29)


def build_tnt(ctx, trigger=None, sources=None):
    """A bundle of seven 0.2 m sticks of dynamite lying along X, bound by two bands of grey tape, a blasting cap in the
    middle stick's +X end with a red and a blue lead trailing out of it; with a `trigger` (and its `sources`) the device
    sits on top and the cap's leads run up to it. Origin at the base's centre."""
    tube = _tube(ctx)
    paper, tape, cap, colours = 0, 1, 2, 3
    white = (0.9, 0.9, 0.9, 1.0)
    r = STICK_R
    cz = 3 * r
    for k in range(7):
        a = math.radians(90 + 60 * k)
        y, z = (0.0, cz) if k == 6 else (2 * r * math.cos(a), cz + 2 * r * math.sin(a))
        tube((-0.1, y, z), (0.1, y, z), r, 10, paper, None, False)
    for x in (-0.055, 0.055):
        tube((x - 0.013, 0.0, cz), (x + 0.013, 0.0, cz), 3 * r + 0.0012, 14, tape, None, False)
    tube((0.1, 0.0, cz), (0.118, 0.0, cz), 0.004, 8, cap, white, False)
    if trigger:
        end = _trigger(ctx, trigger, (-0.02, 0.0, 6 * r), sources)
        _leads(ctx, end, (0.118, 0.0, cz), sources, 0.03)
        return [((0.0, 0.0, cz), (0.1, 3 * r, cz))]
    for dy, rect in ((-0.002, SWATCH_RED), (0.002, SWATCH_BLUE)):
        pts = [(0.118, dy, cz), (0.14, dy, cz - 0.004), (0.155, dy + 0.012, 0.012), (0.165, dy + 0.04, 0.002), (0.17, dy + 0.09, 0.002)]
        for a, b in zip(pts, pts[1:]):
            _wire(ctx, a, b, 0.0013, colours, white, rect)
    return [((0.0, 0.0, cz), (0.1, 3 * r, cz))]


# (source TXD, texture) per ied material, all vanilla and found with gta-scout: galvanised pipe and caps, grey tape, black
# plastic, wire colours, the "dude" brand label on the battery
IED_TEXTURES = [("industrialext.txd", "cj_chromepipe"), ("cj_airprt.txd", "CJ_RUBBER"), ("ballys01.txd", "CJ_blackplastic"), ("helixbarrier.txd", "colourboxes"), ("hubprops2_sfse.txd", "welder")]


def build_ied(ctx, trigger=None, sources=None):
    """A pipe bomb, 0.26 m along X: a galvanised pipe between two hex caps, a 9 V battery taped on top with grey tape and
    red and yellow leads from it into a hole in the +X cap; with a `trigger` (and its `sources`) the device is taped on
    the -X half and its leads run to the cap too. Origin at the base's centre."""
    box, tube = ctx["box"], _tube(ctx)
    pipe, tape, black, colours, label = 0, 1, 2, 3, 4
    white, dim, galv = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0), (0.55, 0.56, 0.58, 1.0)
    z = 0.03
    tube((-0.1, 0.0, z), (0.1, 0.0, z), 0.024, 14, pipe, galv, False)
    for x0, x1 in ((-0.13, -0.098), (0.098, 0.13)):
        tube((x0, 0.0, z), (x1, 0.0, z), 0.03, 6, pipe, dim, False)
    for x in (-0.06, 0.035):
        tube((x - 0.012, 0.0, z), (x + 0.012, 0.0, z), 0.0255, 14, tape, None, False)
    box((0.05, 0.0, z + 0.024 + 0.009), (0.048, 0.026, 0.017), black, None)  # the battery, lying down
    box((0.05, 0.0131, z + 0.033), (0.04, 0.0012, 0.013), label, white, DUDE_LOGO)
    for dy in (-0.006, 0.006):
        tube((0.074, dy, z + 0.033), (0.08, dy, z + 0.033), 0.0035, 6, pipe, white, False)
    for dy, rect in ((-0.003, SWATCH_RED), (0.003, SWATCH_YELLOW)):
        pts = [(0.08, dy - 0.006, z + 0.033), (0.1, dy, z + 0.04), (0.124, dy, z + 0.02), (0.131, dy, z)]
        for a, b in zip(pts, pts[1:]):
            _wire(ctx, a, b, 0.0014, colours, white, rect)
    if trigger:
        end = _trigger(ctx, trigger, (-0.04, 0.0, z + 0.0235), sources)
        _leads(ctx, end, (0.131, 0.0, z + 0.008), sources, 0.04)
    return [((0.0, 0.0, 0.036), (0.13, 0.03, 0.036))]


FIREWORKS_W, FIREWORKS_D, FIREWORKS_H = 0.26, 0.18, 0.1
# (source TXD, texture) per fireworks material, all vanilla and found with gta-scout: cardboard, the drug packets' glossy
# red, blue, green and yellow wraps for the tubes, the barrels' hazard sticker, black fuse
FIREWORKS_TEXTURES = [("cj_banner2.txd", "CJ_CARDBOARD"), ("dyn_drugs.txd", "drugs6"), ("dyn_drugs.txd", "drugs5"), ("dyn_drugs.txd", "drugs4"), ("dyn_drugs.txd", "drugs3"), ("dynbarrels.txd", "yellowmetal"), ("ballys01.txd", "CJ_blackplastic")]


def build_fireworks(ctx):
    """A cardboard box of fireworks, 0.26 x 0.18 x 0.1 m with its two long flaps folded out: rockets with cone heads and
    stick tails, fat roman candles and cake tubes inside, wrapped in red, blue, green and yellow, black fuses, a hazard
    sticker on the front (+Y). Origin at the base's centre."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    card, red, blue, green, yellow, hazard, fuse = 0, 1, 2, 3, 4, 5, 6
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.65, 0.65, 0.65, 1.0)
    w, d, h, t = FIREWORKS_W, FIREWORKS_D, FIREWORKS_H, 0.004
    box((0.0, 0.0, t / 2), (w, d, t), card, dim)
    for y in (-d / 2 + t / 2, d / 2 - t / 2):
        box((0.0, y, h / 2), (w, t, h), card, None)
    for x in (-w / 2 + t / 2, w / 2 - t / 2):
        box((x, 0.0, h / 2), (t, d, h), card, None)
    for s in (-1, 1):  # the flaps, folded out and down
        a = math.radians(35)
        out = Vector((0.0, s * math.cos(a), -math.sin(a)))
        _obox(ctx, Vector((0.0, s * d / 2, h)) + out * 0.045, (Vector((1, 0, 0)), out, Vector((0.0, s * math.sin(a), math.cos(a)))), (w - 0.004, 0.09, t), card, dim)
    box((0.0, d / 2 + 0.0005, 0.05), (0.06, 0.001, 0.06), hazard, white, HAZARD)
    wraps = [red, blue, green, yellow]
    k = 0
    for i, x in enumerate((-0.09, -0.045, 0.0, 0.045, 0.09)):  # cakes and candles: tubes standing in two rows
        for j, y in enumerate((-0.04, 0.04)):
            r = 0.02 if (i + j) % 2 else 0.014
            top = 0.12 + 0.035 * ((i * 3 + j) % 3)
            tube((x, y, t), (x, y, top), r, 10, wraps[k % 4], None, False)
            tube((x, y, top), (x, y, top + 0.003), r * 0.8, 10, fuse, dim, False)
            _wire(ctx, (x, y, top + 0.003), (x + 0.004, y, top + 0.022), 0.0015, fuse, None)
            k += 1
    for x, y, top in ((-0.068, 0.0, 0.2), (0.022, 0.0, 0.24), (0.11, 0.0, 0.22)):  # rockets, their sticks down into the box
        tube((x, y, top - 0.09), (x, y, top), 0.011, 10, wraps[k % 4], None, False)
        _cone(ctx, (x, y, top), 0.013, 0.03, 10, wraps[(k + 1) % 4], white)
        _wire(ctx, (x + 0.012, y, t), (x + 0.012, y, top - 0.05), 0.0025, card, dim)
        k += 1
    return [((0.0, 0.0, h / 2), (w / 2, d / 2, h / 2))]


# (source TXD, texture) per emp material, all vanilla and found with gta-scout: black hard-case plastic, the barber's bumpy
# rubber as egg-crate foam, copper winding and bus bars, cast aluminium can tops and panel, the keypad's green lamp, chrome
# toggles, wire colours, the "dude" label on the battery, the substation's danger plate
EMP_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("genintintbarb.txd", "CJ_BLACK_RUB2"), ("lee_strip2.txd", "Strip_Gold"), ("hubprops2_sfse.txd", "Alumox64b"), ("kmb_keypadx.txd", "keypad_light"), ("industrialext.txd", "cj_chromepipe"), ("helixbarrier.txd", "colourboxes"), ("hubprops2_sfse.txd", "welder"), ("industrialext.txd", "CJ_PANEL")]
EMP_W, EMP_D, EMP_H = 0.34, 0.24, 0.085  # emp.dff: the hard case's base (x, y, z)
EMP_FOAM = 0.05  # the foam bed's top
EMP_LID = 0.07  # the lid's depth: the coil and bank stand up into it when the case is shut
EMP_FOAM_COL = (0.75, 0.75, 0.78, 1.0)


def build_emp(ctx, trigger=None, sources=None):
    """An EMP charge built into an open black hard case, 0.34 x 0.24 m, its lid up at 100 degrees on the back (-Y) hinge:
    egg-crate foam holding a sealed 12 V battery, a 2 x 2 bank of capacitors on copper bus bars and a copper-wound
    solenoid coil lying along Y, heavy red and black cables between them; the lid's foam carries an aluminium switch
    panel (two toggles, a green armed lamp, a danger plate). The front foam slot holds a coiled spare lead, or the
    `trigger` (with its `sources`) wired to the bus bars. Latches and a carry handle on the front (+Y). Origin at the
    base's centre."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    case, foam, copper, alu, lamp, chrome, colours, label, danger = range(9)
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    w, d, h, t = EMP_W, EMP_D, EMP_H, 0.006
    box((0.0, 0.0, t / 2), (w, d, t), case, None)
    for y in (-d / 2 + t / 2, d / 2 - t / 2):
        box((0.0, y, h / 2), (w, t, h), case, None)
    for x in (-w / 2 + t / 2, w / 2 - t / 2):
        box((x, 0.0, h / 2), (t, d, h), case, None)
    for z in (0.02, 0.065):  # moulded bumper ribs round the outside
        box((0.0, 0.0, z), (w + 0.006, d + 0.006, 0.008), case, dim)
    f = EMP_FOAM
    box((0.0, 0.0, (t + f) / 2), (w - 2 * t, d - 2 * t, f - t), foam, EMP_FOAM_COL)
    for x in (-0.1, 0.1):  # latches and the handle on the front
        box((x, d / 2 + 0.006, h - 0.015), (0.03, 0.008, 0.03), case, dim)
    for x in (-0.04, 0.04):
        box((x, d / 2 + 0.01, h - 0.02), (0.012, 0.016, 0.014), case, dim)
    tube((-0.045, d / 2 + 0.02, h - 0.02), (0.045, d / 2 + 0.02, h - 0.02), 0.008, 10, case, None)
    # the sealed battery, back left
    bx, by = -0.11, -0.045
    box((bx, by, f + 0.032), (0.09, 0.065, 0.064), case, None)
    box((bx, by + 0.0326, f + 0.032), (0.08, 0.0012, 0.045), label, white, DUDE_LOGO)
    for dx in (-0.03, 0.03):
        box((bx + dx, by - 0.015, f + 0.068), (0.012, 0.004, 0.008), copper, white)
    # the capacitor bank, 2 x 2, bus bars across the tops
    for x in (-0.035, 0.012):
        for y in (-0.05, -0.004):
            tube((x, y, f), (x, y, f + 0.058), 0.02, 16, case, dim, False)
            tube((x, y, f + 0.058), (x, y, f + 0.06), 0.019, 16, alu, white, False)
            for dx in (-0.007, 0.007):
                tube((x + dx, y, f + 0.06), (x + dx, y, f + 0.065), 0.0025, 6, copper, white, False)
    for dx in (-0.007, 0.007):
        for y in (-0.05, -0.004):
            box((-0.0115 + dx, y, f + 0.066), (0.06, 0.006, 0.002), copper, white)
    # the coil: a black former along Y wound with copper, flanged ends, in two saddles on the right
    cx, cz, r = 0.1, f + 0.04, 0.03
    tube((cx, -0.085, cz), (cx, 0.065, cz), r, 20, case, dim, False)
    for y in (-0.08, 0.06):
        tube((cx, y - 0.003, cz), (cx, y + 0.003, cz), r + 0.01, 20, case, None, False)
    for k in range(17):
        _torus(ctx, (cx, -0.072 + k * 0.0078, cz), r + 0.004, 0.0038, 20, 6, copper, white, axis="y")
    for y in (-0.03, 0.03):
        box((cx, y, f + 0.006), (0.06, 0.012, 0.012), case, dim)
    # heavy cables: battery to the bank, the bank to the coil's ends
    cables = [
        ([(bx - 0.03, by - 0.015, f + 0.072), (-0.09, -0.07, f + 0.09), (-0.042, -0.05, f + 0.068)], SWATCH_RED),
        ([(bx + 0.03, by - 0.015, f + 0.072), (-0.05, 0.02, f + 0.085), (-0.028, -0.004, f + 0.068)], None),
        ([(0.019, -0.05, f + 0.068), (0.06, -0.085, f + 0.07), (cx - 0.02, -0.08, cz + 0.02)], SWATCH_RED),
        ([(0.019, -0.004, f + 0.068), (0.055, 0.04, f + 0.075), (cx - 0.02, 0.06, cz + 0.02)], None),
    ]
    for pts, rect in cables:
        for a, b in zip(pts, pts[1:]):
            _wire(ctx, a, b, 0.0035, colours if rect else case, white if rect else dim, rect)
    if trigger:  # the trigger in the front slot, wired to the bus bars
        end = _trigger(ctx, trigger, (-0.09, 0.07, f), sources)
        _leads(ctx, end, (-0.0115, -0.004, f + 0.067), sources, 0.03)
    else:  # a coiled spare lead in the front slot
        for k in range(4):
            _torus(ctx, (-0.09, 0.07, f + 0.003 + k * 0.004), 0.028, 0.0028, 20, 6, colours, white)
    # the lid, open 100 degrees about the back hinge
    a = math.radians(100)
    ex, ey, ez = Vector((1, 0, 0)), Vector((0.0, math.cos(a), math.sin(a))), Vector((0.0, -math.sin(a), math.cos(a)))
    lh = EMP_LID
    lid = Vector((0.0, -d / 2, h)) + ey * (d / 2) + ez * (lh / 2)
    _obox(ctx, lid, (ex, ey, ez), (w, d, lh), case, None)
    _obox(ctx, lid, (ex, ey, ez), (w + 0.006, d + 0.006, 0.008), case, dim)
    _obox(ctx, lid - ez * (lh / 2 + 0.0005 - 0.0035), (ex, ey, ez), (w - 0.012, d - 0.012, 0.007), foam, EMP_FOAM_COL)
    panel = lid - ez * (lh / 2 + 0.002) + ey * 0.01
    _obox(ctx, panel, (ex, ey, ez), (0.16, 0.09, 0.003), alu, white)
    _obox(ctx, panel - ez * 0.002 + ex * 0.045, (-ex, ey, -ez), (0.05, 0.04, 0.001), danger, white, CJ_PANEL_DANGER)
    for dx in (-0.06, -0.035):  # the toggles
        base = panel + ex * dx - ey * 0.015
        tube(tuple(base), tuple(base - ez * 0.006), 0.005, 8, chrome, dim, False)
        _wire(ctx, tuple(base - ez * 0.006), tuple(base - ez * 0.018 + ey * 0.004), 0.0015, chrome, white)
    lp = panel - ex * 0.0475 + ey * 0.022
    tube(tuple(lp), tuple(lp - ez * 0.006), 0.0055, 10, lamp, white, False)
    return [((0.0, 0.0, h / 2), (w / 2, d / 2, h / 2)), (tuple(lid), (w / 2, lh / 2 + 0.01, d / 2))]


CJ_PANEL_DANGER_FRONT = (0.98, 0.58, 0.5, 0.96)  # on a +Y face
HAZARD_FRONT = (0.3, 0.6, 0.74, 0.88)  # on a -Y face


PHONE_KEYS = (0.53, 0.28, 0.93, 0.97)  # keypad nt_phone3: the orange keys
VEND_KEYS = (0.6, 0.38, 0.8, 0.95)  # keypad kb_vend1: the black key column
DATA_ROWS = (0.02, 0.55, 0.48, 0.98)  # otb_machine ap_screens1: a departures board's rows, read as a terminal
DIAL_FACE = (0.0, 0.0, 1.0, 1.0)


def _flip(rect):
    """A rect for a +Y face (whose u runs along -X seen from the front)."""
    u0, v0, u1, v1 = rect
    return (u1, v0, u0, v1)


# (source TXD, texture) per storage_unit material, all vanilla and found with gta-scout: cast aluminium top, green circuit
# board, black plastic connectors, chrome screws, the "dude" brand label
STORAGE_TEXTURES = [("hubprops2_sfse.txd", "Alumox64b"), ("dkcargoshp_las2.txd", "green_64"), ("ballys01.txd", "CJ_blackplastic"), ("industrialext.txd", "cj_chromepipe"), ("hubprops2_sfse.txd", "welder")]


def build_storage_unit(ctx):
    """A 3.5 inch hard drive, 0.147 x 0.102 x 0.026 m lying label up: a cast aluminium base and lid, the brand label, six
    lid screws, the green board underneath and the data and power sockets on the -Y end. Origin at the base's centre."""
    box, tube = ctx["box"], _tube(ctx)
    alu, board, black, chrome, label = 0, 1, 2, 3, 4
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    box((0.0, 0.0, 0.0015), (0.096, 0.14, 0.003), board, None)
    box((0.0, 0.0, 0.014), (0.102, 0.147, 0.02), alu, dim)
    box((0.0, 0.004, 0.0245), (0.098, 0.138, 0.002), alu, None)  # the lid
    box((0.0, 0.025, 0.0256), (0.07, 0.065, 0.0004), label, white, (0.5, 0.25, 1.0, 0.85))
    for x in (-0.044, 0.044):
        for y in (-0.06, 0.0, 0.065):
            tube((x, y, 0.0255), (x, y, 0.0262), 0.0025, 8, chrome, white, False)
    tube((0.0, -0.035, 0.0255), (0.0, -0.035, 0.0262), 0.004, 10, chrome, white, False)  # the spindle screw
    box((-0.02, -0.0745, 0.009), (0.03, 0.004, 0.007), black, None)  # data and power sockets
    box((0.022, -0.0745, 0.009), (0.022, 0.004, 0.007), black, None)
    return [((0.0, 0.0, 0.013), (0.051, 0.0735, 0.013))]


# (source TXD, texture) per io_unit material, all vanilla and found with gta-scout: grey project box plastic, the payphone's
# orange keys, the keypad's dark green LCD, black plastic, chrome connector shell, ribbon colours
IO_TEXTURES = [("des_telescopestuff.txd", "dish_panel_a"), ("keypad.txd", "nt_phone3"), ("kmb_keypadx.txd", "keypad_glass"), ("ballys01.txd", "CJ_blackplastic"), ("industrialext.txd", "cj_chromepipe"), ("helixbarrier.txd", "colourboxes")]


def build_io_unit(ctx):
    """The I/O Unit, a phone's keypad and screen rehoused in a grey project box, 0.12 x 0.08 x 0.035 m: the orange keys and
    a green LCD on the lid, a serial port and a ribbon cable out of +X, a stub aerial at the back. Origin at the base's
    centre."""
    box, tube = ctx["box"], _tube(ctx)
    grey, keys, lcd, black, chrome, colours = 0, 1, 2, 3, 4, 5
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    box((0.0, 0.0, 0.0175), (0.12, 0.08, 0.035), grey, None)
    box((0.0, 0.0, 0.0355), (0.116, 0.076, 0.001), grey, dim)
    box((-0.018, 0.0, 0.0363), (0.045, 0.06, 0.001), keys, white, PHONE_KEYS)
    box((0.032, 0.012, 0.0363), (0.04, 0.026, 0.001), lcd, white)
    for i in range(3):
        tube((0.02 + i * 0.012, -0.022, 0.036), (0.02 + i * 0.012, -0.022, 0.0385), 0.0035, 8, black, None, False)
    box((0.0605, -0.01, 0.017), (0.003, 0.03, 0.012), chrome, white)  # the serial port
    box((0.062, 0.022, 0.012), (0.006, 0.022, 0.004), black, None)
    for k in range(4):  # the ribbon, flat and slack
        x = 0.065 + k * 0.012
        box((x, 0.022, 0.012 - k * 0.0028), (0.0125, 0.02, 0.0012), grey, dim)
    tube((-0.045, -0.03, 0.035), (-0.045, -0.03, 0.075), 0.004, 8, black, None, False)
    return [((0.0, 0.0, 0.018), (0.06, 0.04, 0.018))]


# (source TXD, texture) per flux_cap material, all vanilla and found with gta-scout: galvanised case, the drug wraps' glossy
# blue (the capacitors' sleeves), cast can tops, copper bus bars, black and red cable, the cooker's numbered dial, the
# substation's danger plate
FLUX_TEXTURES = [("otb_machine.txd", "mp_CJ_GALVANISED"), ("dyn_drugs.txd", "drugs5"), ("hubprops2_sfse.txd", "Alumox64b"), ("lee_strip2.txd", "Strip_Gold"), ("ballys01.txd", "CJ_blackplastic"), ("cj_airprt.txd", "CJ_red_COUNTER"), ("lee_kitch.txd", "Cooker_Dial"), ("industrialext.txd", "CJ_PANEL")]


def build_flux_cap(ctx):
    """The Flux Capacitor, a bank of three large screw-terminal capacitors (blue sleeves, cast tops) standing in a
    galvanised tray, 0.21 x 0.12 m and 0.17 m tall: copper links across their terminals, heavy red and black leads out of
    the end ones to studs on the tray, a selector dial and a danger plate on the front (+Y). Origin at the base's centre."""
    box, tube = ctx["box"], _tube(ctx)
    galv, sleeve, cast, copper, black, red, dial, danger = 0, 1, 2, 3, 4, 5, 6, 7
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    box((0.0, 0.0, 0.002), (0.21, 0.12, 0.004), galv, None)
    for y in (-0.058, 0.058):
        box((0.0, y, 0.025), (0.21, 0.004, 0.05), galv, None)
    for x in (-0.103, 0.103):
        box((x, 0.0, 0.025), (0.004, 0.12, 0.05), galv, None)
    box((0.0, 0.0605, 0.025), (0.06, 0.001, 0.04), danger, white, _flip(CJ_PANEL_DANGER))
    tube((0.06, 0.06, 0.025), (0.06, 0.068, 0.025), 0.013, 16, dial, white, False)
    caps = (-0.065, 0.0, 0.065)
    for x in caps:
        tube((x, -0.008, 0.004), (x, -0.008, 0.15), 0.031, 24, sleeve, white, False)
        tube((x, -0.008, 0.15), (x, -0.008, 0.156), 0.029, 24, cast, white, False)
        for dx in (-0.012, 0.012):
            tube((x + dx, -0.008, 0.156), (x + dx, -0.008, 0.162), 0.005, 8, cast, dim, False)
            tube((x + dx, -0.008, 0.162), (x + dx, -0.008, 0.166), 0.0065, 6, copper, white, False)
    for x0, x1 in ((-0.053, -0.012), (0.012, 0.053)):  # the links, + to -
        box(((x0 + x1) / 2, -0.008, 0.167), (x1 - x0 + 0.014, 0.012, 0.003), copper, white)
    leads = [((-0.077, -0.008, 0.167), (-0.095, -0.008, 0.12), (-0.09, -0.04, 0.05), (-0.08, -0.045, 0.012), red),
             ((0.077, -0.008, 0.167), (0.095, -0.008, 0.12), (0.09, -0.04, 0.05), (0.08, -0.045, 0.012), black)]
    for *pts, mat in leads:
        for a, b in zip(pts, pts[1:]):
            _wire(ctx, a, b, 0.0045, mat, None)
        tube((pts[-1][0], pts[-1][1], 0.004), (pts[-1][0], pts[-1][1], 0.014), 0.006, 6, copper, white, False)
    return [((0.0, 0.0, 0.085), (0.105, 0.06, 0.085))]


# (source TXD, texture) per hack_device material, all vanilla and found with gta-scout: black rugged plastic, the keyboard,
# the departures board as a terminal screen, rubber corners, chrome clips, red and black leads, the keypad's green lamp
HACK_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("a51_detailstuff.txd", "Gen_Keyboard"), ("otb_machine.txd", "ap_screens1"), ("cj_airprt.txd", "CJ_RUBBER"), ("industrialext.txd", "cj_chromepipe"), ("cj_airprt.txd", "CJ_red_COUNTER"), ("kmb_keypadx.txd", "keypad_glass")]


def build_hack_device(ctx):
    """The Hack Interface, a rugged netbook, 0.24 x 0.17 m, open with the screen at 110 degrees: a terminal on the screen,
    the keyboard in the base, rubber corner bumpers, and a lead out of +X to a pair of alligator clips. Origin at the
    base's centre; the screen hinges along the back (-Y) edge."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    black, keyboard, screen, rubber, chrome, red, lcd = 0, 1, 2, 3, 4, 5, 6
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    w, d, h = 0.24, 0.17, 0.022
    box((0.0, 0.0, h / 2), (w, d, h), black, None)
    box((0.0, 0.018, h + 0.0005), (0.21, 0.085, 0.001), keyboard, white, (0.0, 0.55, 1.0, 1.0))
    box((0.0, -0.06, h + 0.0005), (0.06, 0.035, 0.001), black, dim)  # the touchpad
    for x in (-w / 2, w / 2):
        for y in (-d / 2, d / 2):
            box((x * 0.98, y * 0.98, h / 2), (0.016, 0.016, h + 0.002), rubber, None)
    a = math.radians(110 - 90)
    up = Vector((0.0, math.sin(a), math.cos(a)))  # along the lid, away from the hinge
    up = Vector((0.0, -math.sin(a), math.cos(a)))
    out = Vector((0.0, math.cos(a), math.sin(a)))  # the screen's normal, toward the user
    hinge = Vector((0.0, d / 2 - 0.005, h))
    hinge = Vector((0.0, -d / 2 + 0.005, h))
    lid = hinge + up * 0.075
    _obox(ctx, lid, (Vector((1, 0, 0)), out, up), (w, 0.012, 0.15), black, None)
    _obox(ctx, lid + out * 0.0065, (Vector((1, 0, 0)), out, up), (0.2, 0.001, 0.12), screen, white, _flip(DATA_ROWS))
    tube((-w / 2 + 0.02, -d / 2 + 0.005, h), (w / 2 - 0.02, -d / 2 + 0.005, h), 0.007, 10, black, dim, False)
    box((0.09, 0.07, h + 0.0008), (0.012, 0.004, 0.0015), lcd, white)
    tube((w / 2, 0.03, 0.011), (w / 2 + 0.01, 0.03, 0.011), 0.005, 8, black, None, False)
    pts = [(w / 2 + 0.01, 0.03, 0.011), (w / 2 + 0.04, 0.045, 0.003), (w / 2 + 0.07, 0.07, 0.003)]
    for a_, b_ in zip(pts, pts[1:]):
        _wire(ctx, a_, b_, 0.003, black, None)
    for k, (mat, y) in enumerate(((red, 0.06), (black, 0.085))):
        _wire(ctx, (w / 2 + 0.07, 0.07, 0.003), (w / 2 + 0.1, y + 0.01, 0.003), 0.002, mat, None)
        box((w / 2 + 0.115, y + 0.012, 0.004), (0.03, 0.008, 0.007), mat, None)  # the clip's sleeve
        box((w / 2 + 0.136, y + 0.012, 0.004), (0.014, 0.007, 0.004), chrome, white)  # its jaws
    return [((0.0, 0.0, h / 2), (w / 2, d / 2, h / 2)), ((0.0, -d / 2 + 0.03, 0.09), (w / 2, 0.03, 0.075))]


# (source TXD, texture) per advanced_keypad material, all vanilla and found with gta-scout: brushed steel housing, the vending
# machine's key column, the keypad's green LCD and lamp, black plastic, chrome screws
ADV_KEYPAD_TEXTURES = [("otb_machine.txd", "mp_CJ_GALVANISED"), ("keypad.txd", "kb_vend1"), ("kmb_keypadx.txd", "keypad_glass"), ("kmb_keypadx.txd", "keypad_light"), ("ballys01.txd", "CJ_blackplastic"), ("industrialext.txd", "cj_chromepipe")]


def build_advanced_keypad(ctx):
    """An access-control keypad, 0.085 x 0.032 x 0.16 m, standing with its face to +Y: a steel housing, a recessed black
    face with a green LCD, the key column, a card reader pad and a green status lamp, four tamper screws. Origin at the
    base's centre (the back plate on -Y)."""
    box, tube = ctx["box"], _tube(ctx)
    steel, keys, lcd, lamp, black, chrome = 0, 1, 2, 3, 4, 5
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    box((0.0, 0.0, 0.08), (0.085, 0.032, 0.16), steel, None)
    box((0.0, 0.0165, 0.08), (0.07, 0.002, 0.145), black, None)
    box((0.0, 0.018, 0.128), (0.05, 0.001, 0.022), lcd, white)
    box((0.0, 0.018, 0.07), (0.05, 0.001, 0.07), keys, white, _flip(VEND_KEYS))
    box((0.0, 0.018, 0.022), (0.05, 0.001, 0.022), black, dim)  # the card pad
    tube((0.0, 0.0165, 0.022), (0.0, 0.0185, 0.022), 0.008, 12, steel, dim, False)
    tube((0.025, 0.0165, 0.148), (0.025, 0.02, 0.148), 0.003, 8, lamp, white, False)
    for x in (-0.037, 0.037):
        for z in (0.006, 0.154):
            tube((x, 0.016, z), (x, 0.0175, z), 0.0025, 6, chrome, white, False)
    return [((0.0, 0.0, 0.08), (0.0425, 0.016, 0.08))]


# (source TXD, texture) per lockpick material, all vanilla and found with gta-scout: black plastic, rubber grip, chrome pick
# and tension wrench, the keypad's green LCD and lamp, the grinder's yellow
LOCKPICK_TEXTURES = [("ballys01.txd", "CJ_blackplastic"), ("cj_airprt.txd", "CJ_RUBBER"), ("industrialext.txd", "cj_chromepipe"), ("kmb_keypadx.txd", "keypad_glass"), ("kmb_keypadx.txd", "keypad_light"), ("helixbarrier.txd", "yellow")]


def build_lockpick(ctx):
    """An electric pick gun, 0.2 m: a black body along Y with a rubber pistol grip under its tail, a trigger, a tension
    knob and a small LCD on top, a chrome needle pick out of the nose (+Y) and an L-shaped tension wrench clipped beside it,
    a yellow battery cap under the grip. Origin at the grip's foot."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    black, rubber, chrome, lcd, lamp, yellow = 0, 1, 2, 3, 4, 5
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.6, 0.6, 0.6, 1.0)
    bz = 0.11
    box((0.0, 0.0, bz), (0.032, 0.13, 0.045), black, None)
    tube((0.0, 0.065, bz), (0.0, 0.085, bz), 0.012, 12, black, dim, False)
    tube((0.0, 0.085, bz), (0.0, 0.095, bz), 0.006, 10, chrome, white, False)
    _wire(ctx, (0.0, 0.095, bz), (0.0, 0.16, bz), 0.0012, chrome, white)  # the needle
    _wire(ctx, (0.0, 0.16, bz), (0.0, 0.166, bz + 0.003), 0.0012, chrome, white)
    _wire(ctx, (0.0, 0.07, bz - 0.02), (0.0, 0.13, bz - 0.02), 0.0012, chrome, white)  # the tension wrench
    _wire(ctx, (0.0, 0.13, bz - 0.02), (0.0, 0.13, bz - 0.01), 0.0012, chrome, white)
    tilt = math.radians(15)
    up = Vector((0.0, math.sin(tilt), math.cos(tilt)))
    _obox(ctx, Vector((0.0, -0.035, bz - 0.0225)) - up * 0.045, (Vector((1, 0, 0)), Vector((0.0, math.cos(tilt), -math.sin(tilt))), up), (0.03, 0.035, 0.09), rubber, None)
    tube((0.0, -0.035 - math.sin(tilt) * 0.09, 0.0), (0.0, -0.035 - math.sin(tilt) * 0.09, 0.012), 0.017, 12, yellow, None, False)
    _obox(ctx, (0.0, 0.0, bz - 0.032), (Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))), (0.008, 0.012, 0.025), black, dim)  # the trigger
    box((0.0, -0.02, bz + 0.0228), (0.024, 0.035, 0.001), lcd, white)
    tube((0.0, 0.03, bz + 0.0225), (0.0, 0.03, bz + 0.032), 0.009, 12, black, dim, False)  # the tension knob
    tube((0.01, 0.01, bz + 0.0225), (0.01, 0.01, bz + 0.025), 0.0025, 8, lamp, white, False)
    return [((0.0, 0.0, 0.07), (0.016, 0.085, 0.07))]


def _folded(ctx, centre, size, material, col, rect=None, round_front=0.45, round_back=0.15, sides=5):
    """A folded garment: a soft slab `size` (x, y, z) about `centre`, its cross-section (Y-Z) a rectangle with the front
    (+Y, the fold) corners rounded by `round_front` x the height and the back ones by `round_back`, extruded along X with
    capped ends; every face mapped to `rect`, u along X."""
    from mathutils import Vector
    bm, paint = ctx["bm"], ctx["paint"]
    cx, cy, cz = centre
    w, d, h = size
    prof = []
    for (sy, sz, r, a0) in ((1, -1, round_front, -90), (1, 1, round_front, 0), (-1, 1, round_back, 90), (-1, -1, round_back, 180)):
        rad = r * h
        oy, oz = sy * (d / 2 - rad), sz * (h / 2 - rad)
        for k in range(sides + 1):
            a = math.radians(a0 + 90 * k / sides)
            prof.append((oy + rad * math.cos(a), oz + rad * math.sin(a)))
    c = col or (0.9, 0.9, 0.9, 1.0)
    night = (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    u0, v0, u1, v1 = rect or (0, 0, 1, 1)
    n = len(prof)
    ends = [[bm.verts.new((cx + x, cy + py, cz + pz)) for py, pz in prof] for x in (-w / 2, w / 2)]
    run = [0.0]  # distance round the profile, so the flat top and bottom carry most of the texture
    for i in range(n):
        (ya, za), (yb, zb) = prof[i], prof[(i + 1) % n]
        run.append(run[-1] + math.hypot(yb - ya, zb - za))
    for i in range(n):
        j = (i + 1) % n
        va, vb = v0 + (v1 - v0) * run[i] / run[-1], v0 + (v1 - v0) * run[i + 1] / run[-1]
        paint(bm.faces.new((ends[0][i], ends[1][i], ends[1][j], ends[0][j])), [(u0, va), (u1, va), (u1, vb), (u0, vb)], c, night, material)
    for ring in ends:
        uvs = [(u0 + (u1 - u0) * (0.5 + py / d), v0 + (v1 - v0) * (0.5 + pz / h)) for py, pz in prof]
        paint(bm.faces.new(ring), uvs, c, night, material)


# (source TXD, texture) per clothes material, all vanilla and found with gta-scout: the clothes shops' white sweatshirt (its
# body), the short-sleeved blue check shirt (its body), the blue trackies with their side stripes
CLOTHES_TEXTURES = [("cloth_track_t.txd", "sweatrstar"), ("cloth_track_t.txd", "shirtshortblu"), ("cloth_trackies.txd", "trackTrblue")]


def build_clothes(ctx):
    """A pile of folded clothes, 0.33 x 0.26 m: blue track pants at the bottom, a blue check shirt on them, a white
    sweatshirt on top, each a soft slab with its fold toward +Y, stacked a little askew. Origin at the base's centre."""
    from mathutils import Matrix, Vector
    sweat, check, pants = 0, 1, 2
    z = 0.0
    for mat, (w, d, h), rect, (dx, dy), turn in (
        (pants, (0.32, 0.24, 0.034), (0.1, 0.05, 0.6, 0.95), (0.0, 0.0), 0),
        (check, (0.3, 0.23, 0.028), (0.1, 0.08, 0.9, 0.5), (0.01, -0.006), 4),
        (sweat, (0.29, 0.22, 0.036), (0.1, 0.05, 0.9, 0.5), (-0.008, 0.005), -3),
    ):
        first = len(ctx["bm"].verts)
        _folded(ctx, (dx, dy, z + h / 2), (w, d, h), mat, (0.9, 0.9, 0.9, 1.0), rect, round_front=0.5, round_back=0.3)
        ctx["bm"].verts.ensure_lookup_table()
        rot = Matrix.Rotation(math.radians(turn), 3, "Z")
        for v in ctx["bm"].verts[first:]:
            v.co = rot @ v.co
        z += h * 0.92  # the next one sinks in a little
    return [((0.0, 0.0, z / 2), (0.165, 0.125, z / 2))]


PILL_TEXTURES = [("dyn_drugs.txd", "drugs2"), ("dyn_drugs.txd", "drugs1"), ("lee_kitch.txd", "mp_snow"), ("icons.txd", "pill_32")]
# (source TXD, texture) per pills material, all vanilla and found with gta-scout: the drug packets' glossy orange (an amber
# pharmacy vial) and white (its cap), white paper for the label, the HUD's red-and-white capsule


def build_pills(ctx):
    """A pharmacy pill jar, 0.085 m tall: an amber vial with a white paper label round it, a white push-and-turn cap with
    grip ribs, and three red-and-white capsules spilled beside it. Origin at the vial's base centre."""
    from mathutils import Vector
    tube = _tube(ctx)
    amber, white_m, label, capsule = 0, 1, 2, 3
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.7, 0.7, 0.7, 1.0)
    r = 0.019
    tube((0.0, 0.0, 0.0), (0.0, 0.0, 0.066), r, 24, amber, white, False)
    tube((0.0, 0.0, 0.066), (0.0, 0.0, 0.07), r - 0.002, 24, amber, dim, False)  # the neck
    tube((0.0, 0.0, 0.016), (0.0, 0.0, 0.05), r + 0.0006, 24, label, white, False)
    tube((0.0, 0.0, 0.068), (0.0, 0.0, 0.085), r + 0.0025, 24, white_m, white, False)
    for k in range(24):  # the cap's grip ribs
        radial, tangent, axial = _radial(k * 15, "z")
        _obox(ctx, radial * (r + 0.0028) + Vector((0.0, 0.0, 0.0755)), (radial, tangent, axial), (0.0012, 0.0016, 0.013), white_m, dim)
    for x, y, a in ((0.032, 0.012, 20), (0.04, -0.008, 75), (0.026, -0.022, 140)):
        d = Vector((math.cos(math.radians(a)), math.sin(math.radians(a)), 0.0)) * 0.0085
        tube((x - d.x, y - d.y, 0.0035), (x + d.x, y + d.y, 0.0035), 0.0035, 10, capsule, white, True)
    return [((0.0, 0.0, 0.0425), (r + 0.003, r + 0.003, 0.0425))]


def _prism(ctx, prof, x0, x1, material, col, uv_scale=(1.0, 1.0)):
    """A closed prism: the Y-Z polygon `prof` (counter-clockwise seen from +X) from x0 to x1, the sides mapped by distance
    round the profile (v) and along X (u), the end caps planar."""
    bm, paint = ctx["bm"], ctx["paint"]
    c = col or (0.9, 0.9, 0.9, 1.0)
    night = (c[0] * 0.3, c[1] * 0.3, c[2] * 0.32, 1.0)
    n = len(prof)
    ends = [[bm.verts.new((x, y, z)) for y, z in prof] for x in (x0, x1)]
    run = [0.0]
    for i in range(n):
        (ya, za), (yb, zb) = prof[i], prof[(i + 1) % n]
        run.append(run[-1] + math.hypot(yb - ya, zb - za))
    su, sv = uv_scale
    for i in range(n):
        j = (i + 1) % n
        va, vb = run[i] / run[-1] * sv, run[i + 1] / run[-1] * sv
        paint(bm.faces.new((ends[0][i], ends[1][i], ends[1][j], ends[0][j])), [(0, va), (su, va), (su, vb), (0, vb)], c, night, material)
    ys, zs = [p[0] for p in prof], [p[1] for p in prof]
    for ring in ends:
        uvs = [((y - min(ys)) / (max(ys) - min(ys)), (z - min(zs)) / (max(zs) - min(zs))) for y, z in prof]
        paint(bm.faces.new(ring), uvs, c, night, material)


def _rounded(w, h, r, sides=4, cy=0.0, cz=0.0):
    """A rounded rectangle w x h (corner radius r) centred on (cy, cz), counter-clockwise from the bottom right."""
    pts = []
    for sy, sz, a0 in ((1, -1, -90), (1, 1, 0), (-1, 1, 90), (-1, -1, 180)):
        oy, oz = cy + sy * (w / 2 - r), cz + sz * (h / 2 - r)
        for k in range(sides + 1):
            a = math.radians(a0 + 90 * k / sides)
            pts.append((oy + r * math.cos(a), oz + r * math.sin(a)))
    return pts


# (source TXD, texture) per medkit material, all vanilla and found with gta-scout: red moulded plastic, white (the cross),
# grey latch plastic, black rubber
MEDKIT_TEXTURES = [("cj_airprt.txd", "CJ_red_COUNTER"), ("crack_intkb.txd", "white"), ("des_telescopestuff.txd", "dish_panel_a"), ("cj_airprt.txd", "CJ_RUBBER")]


def build_medkit(ctx):
    """A first aid kit lying on its back, 0.26 x 0.18 x 0.085 m: a red moulded case with rounded edges and its lid seam,
    a white cross on the lid, two grey snap latches and a fold-down black handle on the front (+Y), hinge knuckles on the
    back. Origin at the base's centre."""
    box, tube = ctx["box"], _tube(ctx)
    red, white_m, grey, rubber = 0, 1, 2, 3
    white, dim = (0.9, 0.9, 0.9, 1.0), (0.55, 0.55, 0.55, 1.0)
    w, d, h = 0.26, 0.18, 0.085
    _prism(ctx, _rounded(d, h, 0.012, 3, 0.0, h / 2), -w / 2, w / 2, red, None)
    box((0.0, 0.0, 0.052), (w + 0.002, d + 0.002, 0.003), red, dim)  # the lid seam
    box((0.0, 0.0, h + 0.0005), (0.075, 0.022, 0.001), white_m, white)
    box((0.0, 0.0, h + 0.0005), (0.022, 0.075, 0.001), white_m, white)
    for x in (-0.08, 0.08):
        box((x, d / 2 + 0.003, 0.052), (0.024, 0.006, 0.022), grey, None)
    for x in (-0.035, 0.035):
        box((x, d / 2 + 0.004, 0.06), (0.01, 0.008, 0.012), rubber, None)
    tube((-0.035, d / 2 + 0.008, 0.052), (0.035, d / 2 + 0.008, 0.052), 0.006, 10, rubber, None)
    for x in (-0.09, 0.0, 0.09):
        tube((x - 0.02, -d / 2 - 0.002, 0.052), (x + 0.02, -d / 2 - 0.002, 0.052), 0.0045, 8, red, dim, False)
    return [((0.0, 0.0, h / 2), (w / 2, d / 2, h / 2))]


DOCBAG_LEATHER = (0.62, 0.36, 0.26, 1.0)  # day colour over the red leather: an oxblood-brown hide
# (source TXD, texture) per doctor's bag material, all vanilla and found with gta-scout: the ship's red leather (tinted
# brown by its vertex colour), brass fittings, black leather for the handles, the frame's dull steel
DOCBAG_TEXTURES = [("sfeship1.txd", "CJ_RED_LEATHER"), ("lee_strip2.txd", "Strip_Gold"), ("cj_airprt.txd", "CJ_RUBBER"), ("industrialext.txd", "cj_chromepipe")]


def build_doctor_bag(ctx):
    """A Gladstone doctor's bag, 0.4 m long, 0.26 m tall to its handles: a leather body flaring to a flat base, the hinged
    metal frame closed along the top with a brass clasp and lock plate, two rolled leather handles, brass base studs, a
    welt at each end. Origin at the base's centre, the bag lengthwise along X."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    leather, brass, black, steel = 0, 1, 2, 3
    white, dark = (0.9, 0.9, 0.9, 1.0), (0.35, 0.22, 0.17, 1.0)
    L, base_d, top_d, H = 0.4, 0.2, 0.06, 0.2
    half = [(base_d / 2 - 0.02, 0.0)]
    for k in range(1, 4):  # the rounded bottom edge
        a = math.radians(-90 + 90 * k / 4)
        half.append((base_d / 2 - 0.02 + 0.02 * math.cos(a), 0.02 + 0.02 * math.sin(a)))
    half += [(base_d / 2 + 0.006, 0.06), (base_d / 2 - 0.01, 0.13), (top_d / 2 + 0.012, H - 0.01), (top_d / 2, H)]
    prof = half + [(-y, z) for y, z in reversed(half)]
    _prism(ctx, prof, -L / 2, L / 2, leather, DOCBAG_LEATHER, (2.0, 2.0))
    for x in (-L / 2 - 0.002, L / 2 + 0.002):  # the welts
        box((x, 0.0, H / 2), (0.004, base_d * 0.9, 0.01), leather, dark)
    box((0.0, 0.0, H + 0.004), (L - 0.02, top_d + 0.004, 0.008), steel, (0.5, 0.48, 0.45, 1.0))  # the frame
    box((0.0, top_d / 2 + 0.003, H - 0.02), (0.05, 0.003, 0.03), brass, white)  # lock plate
    box((0.0, top_d / 2 + 0.006, H - 0.003), (0.03, 0.006, 0.014), brass, white)  # clasp
    for x in (-0.06, 0.06):  # the handles: posts in brass rings, a rolled grip arching between
        for y in (-0.012, 0.012):
            tube((x, y, H + 0.008), (x, y, H + 0.016), 0.005, 8, brass, white, False)
    for y in (-0.012, 0.012):
        pts = [Vector((-0.06 + 0.12 * k / 8, y, H + 0.016 + 0.045 * math.sin(math.pi * k / 8))) for k in range(9)]
        for a, b in zip(pts, pts[1:]):
            tube(tuple(a), tuple(b), 0.0065, 8, black, None, True)
    for x in (-0.15, 0.15):  # base studs
        for y in (-0.07, 0.07):
            tube((x, y, -0.004), (x, y, 0.0), 0.006, 8, brass, white, False)
    return [((0.0, 0.0, H / 2), (L / 2, base_d / 2, H / 2))]


# (source TXD, texture) per bandage material, all vanilla and found with gta-scout: the clothes shop's white cloth (gauze),
# and a red for the blood on the used one
BANDAGE_TEXTURES = [("cj_exp.txd", "mp_cloth_wall"), ("texttest.txd", "kb_red")]
GRIME, BLOOD = (0.78, 0.68, 0.5, 1.0), (0.42, 0.09, 0.08, 1.0)  # dirty_bandage day colours


def _strip(ctx, path, width, material, col, waves=0.0, seed=0):
    """A flat cloth strip `width` wide along the polyline `path`, both faces, its edges crumpled up by up to `waves`.
    Mapped by length."""
    from mathutils import Vector
    import random
    rnd = random.Random(seed)
    bm, paint = ctx["bm"], ctx["paint"]
    night = (col[0] * 0.3, col[1] * 0.3, col[2] * 0.32, 1.0)
    pts = [Vector(p) for p in path]
    rows, s = [], 0.0
    for i, p in enumerate(pts):
        a, b = pts[max(i - 1, 0)], pts[min(i + 1, len(pts) - 1)]
        along = (b - a).normalized()
        side = Vector((-along.y, along.x, 0.0)).normalized() * (width / 2)
        if i:
            s += (p - pts[i - 1]).length
        rows.append((bm.verts.new(p - side + Vector((0, 0, rnd.uniform(0, waves)))), bm.verts.new(p + side + Vector((0, 0, rnd.uniform(0, waves)))), s))
    drop = Vector((0.0, 0.0, -0.0004))  # the underside: its own vertices just below, so a flipped normal cannot z-fight
    back = [(bm.verts.new(a.co + drop), bm.verts.new(b.co + drop), s) for a, b, s in rows]
    for (a0, a1, s0), (b0, b1, s1) in zip(rows, rows[1:]):
        paint(bm.faces.new((a0, b0, b1, a1)), [(0, s0 * 8), (0, s1 * 8), (1, s1 * 8), (1, s0 * 8)], col, night, material)
    for (a0, a1, s0), (b0, b1, s1) in zip(back, back[1:]):
        paint(bm.faces.new((a1, b1, b0, a0)), [(1, s0 * 8), (1, s1 * 8), (0, s1 * 8), (0, s0 * 8)], col, night, material)


def build_bandage(ctx):
    """A clean roll of gauze bandage, 75 mm wide, lying on its side along X: the roll, 0.055 m across, its end unrolled
    about 0.13 m along the ground toward +Y. Origin at the base's centre."""
    tube = _tube(ctx)
    gauze = 0
    white = (0.95, 0.95, 0.95, 1.0)
    r, w = 0.0275, 0.075
    tube((-w / 2, 0.0, r), (w / 2, 0.0, r), r, 24, gauze, white, False)
    tube((-w / 2 - 0.0005, 0.0, r), (w / 2 + 0.0005, 0.0, r), 0.006, 12, gauze, (0.7, 0.7, 0.7, 1.0), False)  # the core
    path = [(0.0, 0.004, 0.0006), (0.0, 0.03, 0.0008), (0.0, 0.07, 0.002), (0.0, 0.1, 0.0008), (0.0, 0.13, 0.0006)]
    _strip(ctx, path, w * 0.98, gauze, white, 0.002, 1)
    return [((0.0, 0.0, r), (w / 2, r, r))]


def build_dirty_bandage(ctx):
    """A used bandage, unwound and dropped: about 0.7 m of gauze lying in a loose crumpled loop, grimy yellow-brown, a
    small roll left at the end, dried blood soaked through in patches. Origin at the base's centre."""
    from mathutils import Vector
    tube = _tube(ctx)
    gauze, blood = 0, 1
    w = 0.07
    path = []
    for k in range(48):  # a loose, lopsided loop that crosses itself, kinked where it was pulled off
        s = k / 47
        a = s * 2.2 * math.pi
        rad = 0.045 + 0.08 * s + 0.018 * math.sin(a * 3.1 + 1.0)
        path.append((rad * math.cos(a) * 1.25 - 0.02, rad * math.sin(a) * 0.85, 0.001 + 0.003 * k / 47 + 0.007 * abs(math.sin(a * 2.3))))
    _strip(ctx, path, w, gauze, GRIME, 0.008, 7)
    end = Vector(path[-1])
    tube((end.x - w / 2, end.y, 0.016), (end.x + w / 2, end.y, 0.016), 0.016, 16, gauze, GRIME, False)
    for k0, k1 in ((3, 7), (16, 19), (30, 35)):  # blood soaked through: a layer just over the cloth
        _strip(ctx, [(p[0], p[1], p[2] + 0.0035) for p in path[k0:k1]], w * 0.7, blood, BLOOD, 0.0, 7)
    return [((-0.02, 0.0, 0.01), (0.13, 0.13, 0.01))]


FLOOD_HEAD = (0.0, 0.0, 1.45)  # flood_light.dff: the lamp head's centre (on its pivot), the head tilted FLOOD_TILT down
FLOOD_TILT = 15  # degrees the head's face is turned down from +Y
FLOOD_LAMP = (0.0, 0.058, 1.4345)  # flood_light.dff: the centre of the lamp face, where the light comes from
FLOOD_AIM = (0.0, 0.966, -0.259)  # flood_light.dff: the beam's direction, the face's normal
# (source TXD, texture) per flood light material, all vanilla and found with gta-scout: yellow painted housing, black
# plastic (yoke, legs, handle), chrome pipe (the telescoping mast), the SF light tower's own lamp (ws_floodlight: the
# halogen reflector on its left half, the cooling fins on its right), rubber feet
FLOOD_TEXTURES = [("helixbarrier.txd", "yellow"), ("ballys01.txd", "CJ_blackplastic"), ("industrialext.txd", "cj_chromepipe"), ("sfse_hubstuff.txd", "ws_floodlight"), ("cj_airprt.txd", "CJ_RUBBER")]
FLOOD_REFLECTOR = (0.03, 0.05, 0.47, 0.96)  # ws_floodlight: the lamp's face
FLOOD_FINS = (0.55, 0.12, 0.92, 0.88)  # ws_floodlight: the fins


def build_flood_light(ctx):
    """A halogen site work light on a tripod, 1.57 m to the top of its handle: three black legs splayed 0.42 m from a collar
    0.55 m up, a black lower mast and a chrome upper one with a clamp knob between, a black yoke holding a yellow lamp
    head (0.28 x 0.11 x 0.22 m) on side pivots, its face (+Y) turned FLOOD_TILT degrees down, fins on its back and a
    carry handle on top. Origin at the ground under the mast."""
    from mathutils import Vector
    box, tube = ctx["box"], _tube(ctx)
    yellow, black, chrome, lamp, rubber = 0, 1, 2, 3, 4
    white = (0.95, 0.95, 0.95, 1.0)
    collar = 0.55
    tube((0.0, 0.0, collar - 0.05), (0.0, 0.0, collar + 0.05), 0.03, 12, black, None, False)
    for k in range(3):  # the legs, a brace from each to the mast, a rubber foot
        a = math.radians(90 + 120 * k)
        out = Vector((math.cos(a), math.sin(a), 0.0))
        top, foot = out * 0.03 + Vector((0.0, 0.0, collar)), out * 0.42 + Vector((0.0, 0.0, 0.02))
        tube(tuple(top), tuple(foot), 0.012, 8, black, None)
        mid = top.lerp(foot, 0.55)
        tube((0.0, 0.0, 0.27), tuple(mid), 0.007, 6, black, None)
        tube(tuple(foot - Vector((0.0, 0.0, 0.02))), tuple(foot + Vector((0.0, 0.0, 0.01))), 0.02, 8, rubber, None, False)
    tube((0.0, 0.0, 0.25), (0.0, 0.0, 0.95), 0.018, 10, black, None, False)  # the lower mast
    tube((0.0, 0.0, 0.9), (0.0, 0.0, 1.31), 0.013, 10, chrome, white, False)  # the upper mast
    tube((0.0, 0.0, 0.93), (0.0, 0.0, 0.97), 0.024, 10, black, None, False)  # the clamp, its knob out of +X
    tube((0.024, 0.0, 0.95), (0.06, 0.0, 0.95), 0.006, 6, black, None, False)
    tube((0.06, 0.0, 0.95), (0.068, 0.0, 0.95), 0.014, 8, black, None, False)
    hz = FLOOD_HEAD[2]
    box((0.0, 0.0, 1.31), (0.36, 0.03, 0.02), black, None)  # the yoke: a bar across the mast's top, an arm up each side
    for x in (-0.17, 0.17):
        box((x, 0.0, (1.31 + hz) / 2), (0.02, 0.03, hz - 1.31 + 0.02), black, None)
        tube((x, 0.0, hz), (x + math.copysign(0.03, x), 0.0, hz), 0.022, 10, black, None, False)  # the pivot knob
    t = math.radians(FLOOD_TILT)
    ax, ay, az = Vector((1.0, 0.0, 0.0)), Vector((0.0, math.cos(t), -math.sin(t))), Vector((0.0, math.sin(t), math.cos(t)))
    head = Vector(FLOOD_HEAD)
    _obox(ctx, head, (ax, ay, az), (0.28, 0.11, 0.22), yellow, None)
    _obox(ctx, head + ay * 0.0565, (ax, ay, az), (0.24, 0.004, 0.18), lamp, white, FLOOD_REFLECTOR)  # the reflector
    for sx in (-1, 1):  # the bezel round the face, black
        _obox(ctx, head + ay * 0.058 + ax * (sx * 0.13), (ax, ay, az), (0.02, 0.006, 0.22), black, None)
    for sz in (-1, 1):
        _obox(ctx, head + ay * 0.058 + az * (sz * 0.1), (ax, ay, az), (0.28, 0.006, 0.02), black, None)
    _obox(ctx, head - ay * 0.0565, (ax, ay, az), (0.24, 0.004, 0.18), lamp, white, FLOOD_FINS)  # the fins on the back
    top = head + az * 0.11
    for sx in (-0.09, 0.09):  # the carry handle
        tube(tuple(top + ax * sx), tuple(top + ax * sx + az * 0.06), 0.01, 8, black, None, False)
    tube(tuple(top + ax * -0.1 + az * 0.06), tuple(top + ax * 0.1 + az * 0.06), 0.014, 10, black, None)
    return [((0.0, 0.0, 0.67), (0.05, 0.05, 0.67)), ((0.0, 0.0, hz), (0.2, 0.09, 0.15))]


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
    {"name": "locksmith_kit", "id": 20257, "dist": 40, "sources": KIT_TEXTURES, "build": build_locksmith_kit},
    {"name": "chain", "id": 20258, "dist": 40, "sources": CHAIN_TEXTURES, "build": build_chain},
    {"name": "padlock", "id": 20259, "dist": 30, "sources": LOCK_TEXTURES, "build": build_padlock},
    {"name": "lock_chain", "id": 20260, "dist": 40, "sources": LOCK_TEXTURES, "build": build_lock_chain},
    # drawn last (IDE flag 4) for the dials' alpha digits
    {"name": "combo_padlock", "id": 20261, "dist": 30, "sources": COMBO_TEXTURES, "build": build_combo_padlock, "ideFlags": 4},
    {"name": "combo_lock_chain", "id": 20262, "dist": 40, "sources": COMBO_TEXTURES, "build": build_combo_lock_chain, "ideFlags": 4},
    {"name": "combo_padlock_shut", "id": 20263, "dist": 30, "sources": COMBO_TEXTURES, "build": build_combo_padlock_shut, "ideFlags": 4},
    {"name": "combo_padlock_body", "id": 20264, "dist": 30, "sources": COMBO_TEXTURES, "build": build_combo_padlock_body, "ideFlags": 4},
    {"name": "combo_shackle", "id": 20265, "dist": 30, "sources": COMBO_TEXTURES[:1], "build": build_combo_shackle},
    {"name": "tow_bar", "id": 20266, "dist": 80, "sources": TOWBAR_TEXTURES, "build": build_tow_bar},
    {"name": "rope_coil", "id": 20267, "dist": 50, "sources": ROPE_TEXTURES, "build": build_rope_coil},
    {"name": "motor", "id": 20268, "dist": 60, "sources": MOTOR_TEXTURES, "build": build_motor},
    {"name": "starter_motor", "id": 20269, "dist": 50, "sources": STARTER_TEXTURES, "build": build_starter_motor},
    {"name": "power_supply", "id": 20270, "dist": 50, "sources": PSU_TEXTURES, "build": build_power_supply},
    {"name": "fluctuator", "id": 20271, "dist": 50, "sources": FLUCT_TEXTURES, "build": build_fluctuator},
    {"name": "tnt", "id": 20272, "dist": 50, "sources": TNT_TEXTURES, "build": build_tnt},
    {"name": "ied", "id": 20273, "dist": 50, "sources": IED_TEXTURES, "build": build_ied},
    {"name": "fireworks", "id": 20274, "dist": 60, "sources": FIREWORKS_TEXTURES, "build": build_fireworks},
    {"name": "emp", "id": 20275, "dist": 60, "sources": EMP_TEXTURES, "build": build_emp},
    {"name": "storage_unit", "id": 20276, "dist": 40, "sources": STORAGE_TEXTURES, "build": build_storage_unit},
    {"name": "io_unit", "id": 20277, "dist": 40, "sources": IO_TEXTURES, "build": build_io_unit},
    {"name": "flux_cap", "id": 20278, "dist": 50, "sources": FLUX_TEXTURES, "build": build_flux_cap},
    {"name": "hack_device", "id": 20279, "dist": 50, "sources": HACK_TEXTURES, "build": build_hack_device},
    {"name": "advanced_keypad", "id": 20280, "dist": 40, "sources": ADV_KEYPAD_TEXTURES, "build": build_advanced_keypad},
    {"name": "lockpick", "id": 20281, "dist": 40, "sources": LOCKPICK_TEXTURES, "build": build_lockpick},
    {"name": "clothes", "id": 20282, "dist": 50, "sources": CLOTHES_TEXTURES, "build": build_clothes},
    {"name": "pills", "id": 20283, "dist": 30, "sources": PILL_TEXTURES, "build": build_pills},
    {"name": "medkit", "id": 20296, "dist": 40, "sources": MEDKIT_TEXTURES, "build": build_medkit},
    {"name": "doctor_bag", "id": 20297, "dist": 50, "sources": DOCBAG_TEXTURES, "build": build_doctor_bag},
    {"name": "bandage", "id": 20298, "dist": 30, "sources": BANDAGE_TEXTURES[:1], "build": build_bandage},
    {"name": "dirty_bandage", "id": 20299, "dist": 30, "sources": BANDAGE_TEXTURES, "build": build_dirty_bandage},
    {"name": "flood_light", "id": 20300, "dist": 120, "sources": FLOOD_TEXTURES, "build": build_flood_light},
    # the explosives' trigger variants (items <Base><TRIGGERS[kind]>, e.g. TntTimebomb)
    {"name": "tnt_timer", "id": 20284, "dist": 50, "sources": with_triggers(TNT_TEXTURES), "build": lambda ctx, k="timer", s=with_triggers(TNT_TEXTURES): build_tnt(ctx, k, s)},
    {"name": "tnt_trip", "id": 20285, "dist": 50, "sources": with_triggers(TNT_TEXTURES), "build": lambda ctx, k="trip", s=with_triggers(TNT_TEXTURES): build_tnt(ctx, k, s)},
    {"name": "tnt_prox", "id": 20286, "dist": 50, "sources": with_triggers(TNT_TEXTURES), "build": lambda ctx, k="prox", s=with_triggers(TNT_TEXTURES): build_tnt(ctx, k, s)},
    {"name": "tnt_phone", "id": 20287, "dist": 50, "sources": with_triggers(TNT_TEXTURES), "build": lambda ctx, k="phone", s=with_triggers(TNT_TEXTURES): build_tnt(ctx, k, s)},
    {"name": "ied_timer", "id": 20288, "dist": 50, "sources": with_triggers(IED_TEXTURES), "build": lambda ctx, k="timer", s=with_triggers(IED_TEXTURES): build_ied(ctx, k, s)},
    {"name": "ied_trip", "id": 20289, "dist": 50, "sources": with_triggers(IED_TEXTURES), "build": lambda ctx, k="trip", s=with_triggers(IED_TEXTURES): build_ied(ctx, k, s)},
    {"name": "ied_prox", "id": 20290, "dist": 50, "sources": with_triggers(IED_TEXTURES), "build": lambda ctx, k="prox", s=with_triggers(IED_TEXTURES): build_ied(ctx, k, s)},
    {"name": "ied_phone", "id": 20291, "dist": 50, "sources": with_triggers(IED_TEXTURES), "build": lambda ctx, k="phone", s=with_triggers(IED_TEXTURES): build_ied(ctx, k, s)},
    {"name": "emp_timer", "id": 20292, "dist": 50, "sources": with_triggers(EMP_TEXTURES), "build": lambda ctx, k="timer", s=with_triggers(EMP_TEXTURES): build_emp(ctx, k, s)},
    {"name": "emp_trip", "id": 20293, "dist": 50, "sources": with_triggers(EMP_TEXTURES), "build": lambda ctx, k="trip", s=with_triggers(EMP_TEXTURES): build_emp(ctx, k, s)},
    {"name": "emp_prox", "id": 20294, "dist": 50, "sources": with_triggers(EMP_TEXTURES), "build": lambda ctx, k="prox", s=with_triggers(EMP_TEXTURES): build_emp(ctx, k, s)},
    {"name": "emp_phone", "id": 20295, "dist": 50, "sources": with_triggers(EMP_TEXTURES), "build": lambda ctx, k="phone", s=with_triggers(EMP_TEXTURES): build_emp(ctx, k, s)},
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
    from tools.stock_wheels import props_rows as wheel_rows
    from tools.vanilla_props import COPIES
    entries = PROPS_TABLE + [dict(id=p["model"], name=p["asset"], dist=80, prop_txd="bobcat_parts") for p in PARTS] + COPIES + props_rows() + wheel_rows()
    def extra(p):  # a vanilla model whose physical properties it takes, IDE flags it is drawn with
        return "".join(f", {k} = {p[k]}" for k in ("parent", "ideFlags") if p.get(k) is not None)

    def txd_name(p):
        # prop_txd is the file in prop_models/files. `txd` on a vanilla copy is the GTA source, not that file.
        return p.get("prop_txd") or p["name"]

    lines += [f'    [{p["id"]}] = {{ dff = "{p["name"]}", txd = "{txd_name(p)}", dist = {p["dist"]}{extra(p)} }},' for p in entries]
    return "\n".join(lines + ["}", ""])


def render_meta(out_dir: Path) -> str:
    props_lua = out_dir / "props.lua"
    text = props_lua.read_text(encoding="ascii") if props_lua.is_file() else ""
    # A row may share another row's TXD (the stock wheels share stock_wheels.txd). Collision defaults to the dff name.
    names = set()
    for dff in re.findall(r'dff = "([^"]+)"', text):
        names.add(f"{dff}.col")
        names.add(f"{dff}.dff")
    for txd in re.findall(r'txd = "([^"]+)"', text):
        names.add(f"{txd}.txd")
    for col in re.findall(r'\bcol = "([^"]+)"', text):
        names.add(f"{col}.col")
    files = sorted(names)
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
    # a source TXD from gta3.img, else gta_int.img (interior props: the motel's door numbers)
    archives = [(p, read_img_index(p)) for p in (img, gta / "models" / "gta_int.img") if p.is_file()]

    def source_txd(source):
        return next(read_img_entry(p, index[source]) for p, index in archives if source in index)

    for prop in PROPS_TABLE:
        if prop["name"] in names:
            parts = {}
            for source, texture in prop_sources(prop):
                parts.setdefault(source, set()).add(texture.lower())
            txds = [trim_txd(source_txd(source), keep) for source, keep in parts.items()]
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
