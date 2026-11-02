"""Renders composed scenes of game models (a camp, a workbench, an armoury...) in Blender's EEVEE for the wiki.

    python -m tools.render_scenes [--scene NAME ...] [--gta DIR] [--blender EXE] [--size WxH] [--samples N] [--dims] [--parts]
    python -m tools.render_scenes --list

Every scene in SCENES is a declarative list of placed models: an item type (uname), a vehicle type (vehicle), a raw
model id (model) or a port file model (file: the house shells, the towable Airstream), each at a position in metres
(Z up) with a GTA/MTA rotation (rx, ry, rz in degrees, applied as Rz * Rx * Ry like createObject) and a scale. An item
defaults to its type's ground pose (rotx/roty/rotz) plus a yaw, and every placement is dropped onto the ground (or
onto a named placement with "on") unless "drop" is false. Outside Blender the models are staged with
tools.render_item_models.stage (gta3.img, gta_int.img, SAMP.img, the port packs) and the script runs itself inside
Blender (DragonFF). Each scene is lit by a preset (sun, fill and a gradient sky), stands on a procedural ground and is
framed by a three-quarter camera fitted to its contents. Writes docs/images/scenes/<scene>.png plus index.json (the
captions), and a 1200 px wide copy into the wiki clone's images/scenes/.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

RES = ROOT / "resources" / "[scavengesurvive]"
OUT = ROOT / "docs" / "images" / "scenes"
WIKI_OUT = ROOT.parent / (ROOT.name + ".wiki") / "images" / "scenes"
WIKI_WIDTH = 1200
ITEM_TYPES = RES / "data" / "generated" / "item_types.lua"

# Port models that live outside the *_models packs: the enterable house shells and the towable Airstream. A "hide"
# list names the frames (wheel dummies) whose meshes the game never shows.
FILES = {
    "townhouse": {"dir": str(RES / "house_shell" / "files"), "dff": "des_westrn9", "txds": ["des_westrn9"]},
    "cabins": {"dir": str(RES / "house_shell" / "files"), "dff": "cw2_logcabins", "txds": ["cw2_logcabins"]},
    "trailer": {"dir": str(RES / "house_shell" / "files"), "dff": "trailer_large1_01", "txds": ["trailers"]},
    "airstream": {"dir": str(RES / "airstream_trailer" / "files"), "dff": "airstream_tow", "txds": ["airstream_tow"], "vehicle": True, "hide": ["wheel_rb_dummy", "wheel_lb_dummy"]},
}

# items/shared/logic/tent.lua: the pitched tent's parts and the stock models whose TXDs carry their textures
TENT_PANEL, TENT_POLE = 19477, 19087
TENT_MATERIALS = {"net": (2068, "CJ_cammonet"), "camo": (3095, "sam_camo"), "pole": (1270, "lamppost")}
FUEL_PUMP = 1686  # petrolpumpnew, the pump standing at the vehicles resource's fuel outlets
SUPPLY_CRATE, SUPPLY_STACK_Z, PARACHUTE = 3799, 2.465, 2903  # loot/shared/logic/drops.lua; kmb_parachute is the open canopy

LIGHTS = {
    "day": {"sun_elevation": 48, "sun_offset": -75, "sun_energy": 4.5, "sun_colour": (1.0, 0.96, 0.9), "sun_angle": 1.5, "horizon": (0.72, 0.80, 0.90), "zenith": (0.16, 0.34, 0.72), "sky": 0.9, "fill": 0.35, "fill_colour": (0.7, 0.8, 1.0)},
    "overcast": {"sun_elevation": 55, "sun_offset": -60, "sun_energy": 2.4, "sun_colour": (0.92, 0.94, 1.0), "sun_angle": 30, "horizon": (0.62, 0.64, 0.68), "zenith": (0.34, 0.38, 0.46), "sky": 1.0, "fill": 0.3, "fill_colour": (0.8, 0.85, 0.95)},
    "golden": {"sun_elevation": 17, "sun_offset": -80, "sun_energy": 3.6, "sun_colour": (1.0, 0.84, 0.58), "sun_angle": 2, "horizon": (0.90, 0.68, 0.46), "zenith": (0.24, 0.38, 0.66), "sky": 0.85, "fill": 0.3, "fill_colour": (0.6, 0.72, 1.0)},
    "dusk": {"sun_elevation": 8, "sun_offset": -95, "sun_energy": 2.6, "sun_colour": (1.0, 0.66, 0.38), "sun_angle": 2.5, "horizon": (0.92, 0.48, 0.26), "zenith": (0.12, 0.16, 0.34), "sky": 0.75, "fill": 0.28, "fill_colour": (0.45, 0.55, 0.95)},
}

GROUNDS = {
    "dirt": {"a": (0.20, 0.145, 0.10), "b": (0.34, 0.26, 0.17), "patch": (0.27, 0.22, 0.14), "scale": 3.0, "bump": 0.25},
    "grass": {"a": (0.10, 0.17, 0.06), "b": (0.26, 0.29, 0.10), "patch": (0.30, 0.23, 0.12), "scale": 4.0, "bump": 0.3},
    "concrete": {"a": (0.27, 0.27, 0.26), "b": (0.40, 0.39, 0.37), "patch": (0.22, 0.22, 0.21), "scale": 2.0, "bump": 0.08},
    "asphalt": {"a": (0.045, 0.045, 0.045), "b": (0.10, 0.10, 0.095), "patch": (0.07, 0.07, 0.065), "scale": 6.0, "bump": 0.1},
    "sand": {"a": (0.50, 0.42, 0.28), "b": (0.64, 0.56, 0.40), "patch": (0.55, 0.47, 0.32), "scale": 3.0, "bump": 0.2},
}

# textures a model asks for that no game TXD holds under its own name: the game draws the material colour, so the
# render must not borrow a same-named texture from an unrelated TXD (pick_up.txd has no "pills"; bdupsfurn's is black)
NO_FALLBACK = {("2709", "pills")}
# frames and textures of the effect sprites GTA draws only while a weapon fires (hidden in the game's idle model)
EFFECT_NAMES = ("gunflash", "muzzle", "flash", "tracer")
EFFECT_TEXTURE_KEYS = ("laserbeam", "gunflash", "muzzle", "flash", "tracer", "smoke")

VEHICLE_COLOURS = {"Sentinel": (0.42, 0.06, 0.07), "Bobcat": (0.66, 0.58, 0.42), "Rumpo": (0.80, 0.80, 0.78), "Sanchez": (0.78, 0.28, 0.05), "Moonbeam": (0.28, 0.38, 0.52), "Yosemite": (0.18, 0.30, 0.19)}

# every firearm item with a calibre (item_types.lua), in rows from the handguns to the heavy weapons
FIREARMS = [
    ["M9Pistol", "M9PistolSD", "DesertEagle", "Mac10", "Tec9", "MP5", "Sawnoff"],
    ["PumpShotgun", "Spas12", "DogsBreath", "WASR3Rifle", "AK47Rifle", "M16Rifle", "SemiAutoRifle"],
    ["M77RMRifle", "SniperRifle", "Model70Rifle", "LenKnocksRifle", "RocketLauncher", "Heatseeker", "Minigun"],
]
AMMO_ROWS = [["Ammo9mm", "Ammo50", "Ammo9mmFMJ", "AmmoBuck"], ["AmmoFlechette", "Ammo556", "Ammo762", "Ammo357"], ["Ammo308", "Ammo50BMG", "AmmoRocket"]]


def tent_parts(x: float, y: float, z: float, rz: float) -> list[dict]:
    """items/shared/logic/tent.lua M.parts: four leaning camo sheets and two poles around the pack at (x, y, z)."""
    z += 0.4
    rz += 90

    def offset(dist, deg):
        a = math.radians(deg)
        return x + dist * math.sin(a), y + dist * math.cos(a)

    parts = []
    for dist, side, ry, mat in ((0.49, 270, 45, "net"), (0.48, 270, 45, "camo"), (0.49, 90, -45, "net"), (0.48, 90, -45, "camo")):
        px, py = offset(dist, -rz + side)
        parts.append({"model": TENT_PANEL, "at": (px, py, z), "rot": (0, ry, rz), "texture": TENT_MATERIALS[mat], "drop": False})
    for dist in (1.3, -1.3):
        px, py = offset(dist, -rz)
        parts.append({"model": TENT_POLE, "at": (px, py, z + 0.48), "rot": (0, 0, rz), "texture": TENT_MATERIALS["pole"], "drop": False})
    return parts


def arsenal_items() -> list[dict]:
    items = []
    for row, unames in enumerate(FIREARMS):
        for col, uname in enumerate(unames):
            items.append({"uname": uname, "at": (-3.0 + col * 1.0, row * 1.5, 0), "yaw": 0})
        for col, uname in enumerate(AMMO_ROWS[row]):
            items.append({"uname": uname, "at": (-2.6 + col * 1.4 + (0.3 if row == 2 else 0), row * 1.5 + 0.75, 0), "yaw": 15 * (col % 3 - 1)})
    return items


def explosives_items() -> list[dict]:
    items = [{"uname": "WoodenCrate", "at": (0, 0.6, 0), "yaw": 10, "name": "crate"}, {"uname": "Molotov", "at": (0, 0.6, 0), "on": "crate", "yaw": 20}]
    groups = [("Tnt", ["TntTimebomb", "TntProxMine", "TntTripMine", "TntPhoneBomb"], -1.9), ("Ied", ["IedBomb", "IedTimebomb", "IedProxMine", "IedTripMine", "IedPhoneBomb"], 0.0), ("Emp", ["EmpTimebomb", "EmpProxMine", "EmpTripMine", "EmpPhoneBomb"], 1.9)]
    for _, unames, cx in groups:
        for i, uname in enumerate(unames):
            r, c = divmod(i, 3)
            items.append({"uname": uname, "at": (cx + (c - 1) * 0.55, -1.0 - r * 0.6, 0), "yaw": 25 * ((i * 7) % 5 - 2)})
    return items


SCENES = {
    "camp": {
        "caption": "A camp at dusk: the pitched tent, a campfire and a BBQ, a backpack and crates",
        "light": "dusk",
        "ground": "grass",
        "items": tent_parts(0.0, 0.0, 0.0, 20.0) + [
            {"uname": "TentPack", "at": (0, 0, 0), "yaw": 20},
            {"uname": "Campfire", "at": (2.3, -1.6, 0), "glow": (1.0, 0.55, 0.2, 180)},
            {"uname": "Barbecue", "at": (3.4, 1.0, 0), "yaw": -35},
            {"uname": "Backpack", "at": (-1.6, -1.8, 0), "yaw": 35},
            {"uname": "WoodenCrate", "at": (-3.4, 2.4, 0), "yaw": 12, "name": "crate"},
            {"uname": "SmallCrate", "at": (-3.4, 2.4, 0), "on": "crate", "yaw": -8},
            {"uname": "LongCrate", "at": (-2.6, 0.6, 0), "yaw": 100},
            {"uname": "Bottle", "at": (1.4, -2.3, 0)},
            {"uname": "WoodLog", "at": (1.4, -0.8, 0), "yaw": 60},
            {"uname": "WoodLog", "at": (3.1, -2.4, 0), "yaw": 15},
        ],
        "camera": {"azimuth": -28, "elevation": 9, "lens": 32, "fstop": 8},
    },
    "workbench": {
        "caption": "The Workbench with a Wrench, Hammer, Screwdriver, Welder, Scrap Metal and Refined Metal",
        "light": "day",
        "ground": "concrete",
        "items": [
            {"uname": "Workbench", "at": (0, 0, 0), "name": "bench"},
            {"uname": "Wrench", "at": (-0.55, 0.0, 0), "on": "bench", "yaw": 20},
            {"uname": "Hammer", "at": (-0.1, 0.1, 0), "on": "bench", "yaw": -60},
            {"uname": "Screwdriver", "at": (0.3, -0.05, 0), "on": "bench", "yaw": 35},
            {"uname": "ScrapMetal", "at": (0.7, 0.05, 0), "on": "bench", "yaw": 10},
            {"uname": "RefinedMetal", "at": (0.75, -0.2, 0), "on": "bench", "yaw": -15},
            {"uname": "Welder", "at": (1.7, -0.3, 0), "yaw": 70},
            {"uname": "ScrapMetal", "at": (-1.5, -0.6, 0), "yaw": 40},
        ],
        "camera": {"azimuth": -30, "elevation": 22, "lens": 40, "fstop": 5.6},
    },
    "doorway": {
        "caption": "A defence wall: a Metal Door between Metal Panels, with its Keypad and a Crowbar on the ground",
        "light": "overcast",
        "ground": "dirt",
        "items": [
            {"uname": "MetPanel", "at": (-3.45, 0, 0), "rot": (90, 90, 0), "name": "l1"},
            {"uname": "MetPanel", "at": (-3.45, 0, 0), "rot": (90, 90, 0), "on": "l1"},
            {"uname": "MetPanel", "at": (3.45, 0, 0), "rot": (90, 90, 0), "name": "r1"},
            {"uname": "MetPanel", "at": (3.45, 0, 0), "rot": (90, 90, 0), "on": "r1"},
            {"uname": "Door", "at": (0, 0, 0), "rot": (0, 0, 90)},
            {"uname": "Keypad", "at": (-2.3, -0.12, 1.25), "rot": (0, 0, 0), "drop": False},
            {"uname": "Crowbar", "at": (1.3, -1.8, 0), "yaw": 30},
        ],
        "camera": {"azimuth": -32, "elevation": 9, "lens": 35, "fstop": 8},
    },
    "arsenal": {
        "caption": "Every firearm laid out in rows with ammunition between them",
        "light": "day",
        "ground": "dirt",
        "items": arsenal_items(),
        "camera": {"azimuth": 0, "elevation": 45, "lens": 45, "margin": 1.05},
    },
    "medical": {
        "caption": "Medical supplies: Dirty and Antiseptic Bandages, a Medkit, a Doctor's Bag, Pills and an Injector",
        "light": "overcast",
        "ground": "concrete",
        "items": [
            {"uname": "DoctorBag", "at": (0.0, 0.25, 0), "yaw": 15},
            {"uname": "Medkit", "at": (-0.55, -0.05, 0), "yaw": -20},
            {"uname": "Bandage", "at": (0.5, -0.1, 0), "yaw": 40},
            {"uname": "AntiSepBandage", "at": (0.7, 0.3, 0), "yaw": -10},
            {"uname": "Pills", "at": (-0.15, -0.3, 0), "yaw": 60},
            {"uname": "AutoInjec", "at": (0.2, -0.35, 0), "yaw": -35},
        ],
        "camera": {"azimuth": -15, "elevation": 50, "lens": 50, "fstop": 2.8, "margin": 1.15},
    },
    "airstream": {
        "caption": "The towable Airstream hitched behind a Bobcat, a Gas Bottle and a Welder beside it",
        "light": "golden",
        "ground": "dirt",
        "items": [
            {"vehicle": "Bobcat", "at": (0, 0, 0), "rot": (0, 0, 0)},
            {"file": "airstream", "at": (0, -6.4, 0), "rot": (0, 0, 0)},
            {"uname": "GasBottle", "at": (-2.3, -6.6, 0), "yaw": 20},
            {"uname": "Welder", "at": (-2.7, -5.2, 0), "yaw": -30},
        ],
        "camera": {"azimuth": -125, "elevation": 11, "lens": 35, "fstop": 11},
    },
    "scrapyard": {
        "caption": "The machines: Scrap Machine, Refining Machine, Water Purifier and Generator, scrap in front",
        "light": "overcast",
        "ground": "dirt",
        "items": [
            {"uname": "ScrapMachine", "at": (-3.4, 0, 0), "yaw": 10},
            {"uname": "RefineMachine", "at": (-1.3, 0.2, 0), "yaw": -5},
            {"uname": "WaterMachine", "at": (1.3, 0, 0), "yaw": 185},
            {"uname": "Generator", "at": (3.3, -0.2, 0), "yaw": -20},
            {"uname": "ScrapMetal", "at": (-2.8, -1.5, 0), "yaw": 30},
            {"uname": "ScrapMetal", "at": (-2.3, -1.3, 0), "yaw": -50},
            {"uname": "ScrapMetal", "at": (0.2, -1.6, 0), "yaw": 80},
            {"uname": "Wrench", "at": (-0.9, -1.4, 0), "yaw": 15},
            {"uname": "Bottle", "at": (1.6, -1.5, 0)},
            {"uname": "GasCan", "at": (3.0, -1.7, 0), "yaw": 40},
            {"model": 20416, "at": (-5.2, -0.6, 0), "yaw": 30},
            {"model": 20415, "at": (5.0, -0.8, 0), "yaw": -40},
        ],
        "camera": {"azimuth": -30, "elevation": 14, "lens": 35, "fstop": 11},
    },
    "fuel": {
        "caption": "A fuel outlet: Petrol Cans at the pump and a Bobcat waiting",
        "light": "day",
        "ground": "asphalt",
        "items": [
            {"model": FUEL_PUMP, "at": (0, 0, 0), "rot": (0, 0, 0)},
            {"model": FUEL_PUMP, "at": (3.6, 0, 0), "rot": (0, 0, 0)},
            {"uname": "GasCan", "at": (-1.0, -1.3, 0), "yaw": 20},
            {"uname": "GasCan", "at": (-1.4, -1.0, 0), "yaw": -40},
            {"vehicle": "Bobcat", "at": (2.6, -3.6, 0), "rot": (0, 0, 110)},
        ],
        "camera": {"azimuth": -42, "elevation": 12, "lens": 35, "fstop": 11},
    },
    "supply-drop": {
        "caption": "A supply drop: the crate under its parachute, loot spilling out",
        "light": "day",
        "ground": "grass",
        "items": [
            {"model": SUPPLY_CRATE, "at": (0, 0, 0), "rot": (0, 0, 15), "name": "crate"},
            {"model": SUPPLY_CRATE, "at": (0.01, 0.01, 0), "rot": (0, 180, 15), "on": "crate"},
            {"model": PARACHUTE, "at": (0.3, 0.2, 0), "rot": (0, 0, 40), "name": "chute", "on": "crate", "drop": True},
            {"model": 20404, "at": (2.3, -2.0, 0), "yaw": 30},
            {"uname": "Ammo556", "at": (1.5, -2.6, 0), "yaw": 10},
            {"uname": "M9Pistol", "at": (0.7, -2.4, 0), "yaw": -30},
            {"uname": "Medkit", "at": (-1.3, -2.3, 0), "yaw": 50},
            {"uname": "Pills", "at": (-0.5, -2.6, 0), "yaw": 0},
            {"uname": "Bandage", "at": (0.1, -2.9, 0), "yaw": 80},
            {"uname": "AntiSepBandage", "at": (-2.0, -1.9, 0), "yaw": 20},
        ],
        "camera": {"azimuth": -30, "elevation": 12, "lens": 35, "fstop": 11},
    },
    "explosives": {
        "caption": "Explosives around a crate: the TNT, IED and EMP variants and a Molotov",
        "light": "day",
        "ground": "dirt",
        "items": explosives_items(),
        "camera": {"azimuth": -15, "elevation": 26, "lens": 40, "fstop": 8},
    },
    "vehicles": {
        "caption": "Common vehicles: Sentinel, Bobcat, Rumpo, Sanchez, Moonbeam and Yosemite",
        "light": "day",
        "ground": "asphalt",
        "items": [{"vehicle": u, "at": (-9.5 + i * 3.8, 0, 0), "rot": (0, 0, 150)} for i, u in enumerate(["Sentinel", "Bobcat", "Rumpo", "Sanchez", "Moonbeam", "Yosemite"])],
        "camera": {"azimuth": -22, "elevation": 7, "lens": 45, "fstop": 11, "margin": 1.02, "shift_y": 0.05},
    },
    "shelter": {
        "caption": "Shelter: a town house, the log cabins and a trailer, all enterable",
        "light": "golden",
        "ground": "grass",
        "items": [
            {"file": "townhouse", "at": (0, 0, 0), "rot": (0, 0, 0)},
            {"file": "trailer", "at": (14, 3, 0), "rot": (0, 0, 20)},
            {"file": "cabins", "at": (0, 24, 0), "rot": (0, 0, -54), "frame": False},
        ],
        "camera": {"azimuth": -35, "elevation": 10, "lens": 30, "fstop": 16},
    },
}


def item_types() -> dict[str, dict]:
    """uname -> model, name and the ground pose (rotx, roty, rotz) of every item type with a model."""
    out = {}
    for line in ITEM_TYPES.read_text(encoding="utf8").splitlines():
        m = re.match(r"M\.byUname\.(\w+) = \{", line)
        if m:
            f = dict(re.findall(r"\b(model|rotx|roty|rotz|name)\s*=\s*(\"[^\"]*\"|[-\w.]+)", line))
            if "model" in f and f["model"].isdigit():
                rot = (float(f.get("rotx", 0)), float(f.get("roty", 0)), float(f.get("rotz", 0)))
                out[m.group(1)] = {"model": int(f["model"]), "name": f.get("name", m.group(1)).strip('"'), "rot": rot}
    return out


def resolve(name: str, scene: dict, types: dict, vehicles: dict) -> tuple[dict, set[int], set[int]]:
    """A scene with every placement resolved to a job key; the model ids to stage (and the ones needed for a TXD only)."""
    models, txd_only, items = set(), set(), []
    for n, it in enumerate(scene["items"]):
        p = {"at": list(it["at"]), "scale": it.get("scale", 1.0), "drop": it.get("drop", True), "name": it.get("name"), "on": it.get("on"), "frame": it.get("frame", True), "glow": it.get("glow"), "glow_z": it.get("glow_z", 0.35)}
        rot = list(it.get("rot", (0, 0, 0)))
        if "uname" in it:
            t = types.get(it["uname"])
            if not t:
                raise SystemExit(f"{name}: unknown item type {it['uname']}")
            p["key"], p["label"] = str(t["model"]), t["name"]
            rot = list(it.get("rot", t["rot"]))
            models.add(t["model"])
        elif "vehicle" in it:
            if it["vehicle"] not in vehicles:
                raise SystemExit(f"{name}: unknown vehicle type {it['vehicle']}")
            p["key"], p["label"], p["vehicle"] = str(vehicles[it["vehicle"]][0]), it["vehicle"], True
            p["colour"] = list(it.get("colour", VEHICLE_COLOURS.get(it["vehicle"], (0.62, 0.64, 0.66))))
            models.add(vehicles[it["vehicle"]][0])
        elif "model" in it:
            p["key"], p["label"] = str(it["model"]), str(it["model"])
            models.add(it["model"])
        elif "file" in it:
            p["key"], p["label"] = it["file"], it["file"]
        else:
            raise SystemExit(f"{name}: item {n} names no uname, vehicle, model or file")
        rot[2] += it.get("yaw", 0)
        p["rot"] = rot
        if "texture" in it:
            p["texture"] = [str(it["texture"][0]), it["texture"][1]]
            txd_only.add(it["texture"][0])
        items.append(p)
    cam = scene.get("camera", "auto")
    out = {"name": name, "items": items, "camera": {} if cam == "auto" else dict(cam), "light": scene.get("light", "day"), "ground": scene.get("ground", "dirt"), "caption": scene.get("caption", name)}
    return out, models, txd_only - models


# ---------------------------------------------------------------- inside Blender


def build_in_blender(spec_file: Path) -> None:
    import bpy
    from mathutils import Euler, Matrix, Vector

    from DragonFF.ops import dff_importer, txd_importer  # noqa: PLC0415
    import tools.render_item_models as rim  # noqa: PLC0415
    from tools.render_item_models import EFFECT_TEXTURES, CaseDict  # noqa: PLC0415

    spec = json.loads(Path(spec_file).read_text())
    jobs = spec["jobs"]
    width, height = spec["size"]
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.preferences.addon_enable(module="DragonFF")
    scn = bpy.context.scene

    def setattr_safe(obj, name, value):
        try:
            setattr(obj, name, value)
        except (AttributeError, TypeError) as e:
            print("SCENE note", name, "not set:", e)

    txd_cache: dict[str, CaseDict] = {}

    def images_for(key):
        if key not in txd_cache:
            images = CaseDict()
            for t in jobs[key]["txds"]:
                images.update({k.lower(): v for k, v in txd_importer.import_txd({"file_name": os.path.join(jobs[key]["dir"], t + ".txd"), "skip_mipmaps": True, "pack": True}).images.items()})
            txd_cache[key] = images
        return txd_cache[key]

    def socket(node, ident, outputs=False):
        return next(s for s in (node.outputs if outputs else node.inputs) if s.identifier == ident)

    def fix_materials(meshes, images, override):
        lost = set()
        for o in meshes:
            for slot in o.material_slots:
                mat = slot.material
                if not mat or not mat.node_tree:
                    continue
                nodes = mat.node_tree.nodes
                for n in list(nodes):
                    if n.type == "TEX_IMAGE":
                        if override is not None:
                            n.image = override
                        elif not n.image and n.label in images:
                            n.image = images[n.label][0]
                        if not n.image:
                            if n.label.lower() not in EFFECT_TEXTURES:
                                lost.add(n.label)
                            nodes.remove(n)  # an empty image node is black; the material colour is what the game shows
                bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
                if bsdf is not None:
                    bsdf.inputs["Roughness"].default_value = 0.78
                    if "Specular IOR Level" in bsdf.inputs:
                        bsdf.inputs["Specular IOR Level"].default_value = 0.25
                setattr_safe(mat, "surface_render_method", "DITHERED")
        return lost

    def drop_effects(meshes):
        """Muzzle flashes and other effect sprites the game draws only while firing: whole frames named for them, and
        faces whose texture is one (a laser beam would make a gun a speck)."""
        import bmesh  # noqa: PLC0415

        for o in meshes:
            if any(k in o.name.lower() for k in EFFECT_NAMES):
                o.hide_render = o.hide_viewport = True
                continue
            drop = [i for i, sl in enumerate(o.material_slots) if sl.material and sl.material.node_tree and any(n.type == "TEX_IMAGE" and any(k in n.label.lower() for k in EFFECT_TEXTURE_KEYS) for n in sl.material.node_tree.nodes)]
            if drop:
                bm = bmesh.new()
                bm.from_mesh(o.data)
                bmesh.ops.delete(bm, geom=[f for f in bm.faces if f.material_index in drop], context="FACES")
                bm.to_mesh(o.data)
                bm.free()

    protos: dict[tuple, dict] = {}

    def prototype(key, colour, texture):
        """A hidden collection holding one import of the job's model, painted or re-textured; shared by its placements."""
        pk = (key, colour, texture)
        if pk in protos:
            return protos[pk]
        job = jobs[key]
        images = images_for(key)
        override = None
        if texture is not None:
            txd_images = images_for(texture[0])
            if texture[1] in txd_images:
                override = txd_images[texture[1]][0]
            else:
                print("SCENE missing", texture[0], texture[1])
        before = set(bpy.data.objects)
        dff_importer.import_dff({"file_name": os.path.join(job["dir"], job["dff"] + ".dff"), "txd_images": images, "image_ext": None, "connect_bones": False, "use_mat_split": True, "remove_doubles": False, "create_backfaces": False, "group_materials": False, "import_normals": False, "materials_naming": "DEFAULT", "hide_damage_parts": bool(job.get("vehicle"))})
        new = [o for o in bpy.data.objects if o not in before]
        for o in [o for o in new if o.type == "MESH" and o.dff.type == "COL" or o.type == "LIGHT"]:  # collision, 2dfx lights
            bpy.data.objects.remove(o, do_unlink=True)
        new = [o for o in bpy.data.objects if o not in before]
        meshes = [o for o in new if o.type == "MESH"]
        lost = fix_materials(meshes, images, override)
        if lost:
            print("SCENE missing", key, ",".join(sorted(lost)))
        if spec.get("parts"):
            for o in new:
                tex = sorted({n.label for sl in o.material_slots if sl.material and sl.material.node_tree for n in sl.material.node_tree.nodes if n.type == "TEX_IMAGE"}) if o.type == "MESH" else []
                print("SCENE parts %s %s %s parent=%s tex=%s" % (key, o.type, o.name, o.parent.name if o.parent else "-", ",".join(tex)))
        drop_effects(meshes)
        bpy.context.view_layer.update()
        if job.get("vehicle"):
            rim.BODY_COLOUR = tuple(colour or (0.62, 0.64, 0.66)) + (1.0,)
            rim.recolour_vehicle(meshes)
            hide = {h.lower() for h in job.get("hide", [])}
            for o in [o for o in bpy.data.objects if o not in before]:
                if o.parent is not None and o.parent.name.lower() in hide:
                    o.hide_render = o.hide_viewport = True
                for slot in (o.material_slots if o.type == "MESH" else []):  # the paint: glossier than the rest
                    bsdf = next((n for n in slot.material.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None) if slot.material and slot.material.node_tree else None
                    if bsdf is not None and tuple(bsdf.inputs["Base Color"].default_value) == rim.BODY_COLOUR and not any(n.type == "TEX_IMAGE" for n in slot.material.node_tree.nodes):
                        bsdf.inputs["Roughness"].default_value = 0.38
                        if "Specular IOR Level" in bsdf.inputs:
                            bsdf.inputs["Specular IOR Level"].default_value = 0.6
            bpy.context.view_layer.update()
        new = [o for o in bpy.data.objects if o not in before]
        if spec.get("parts") and job.get("vehicle"):
            print("SCENE parts %s after: %s" % (key, " ".join("%s%s@%.2f,%.2f,%.2f" % (o.name, "(hidden)" if o.hide_render else "", *o.matrix_world.translation) for o in new if o.type == "MESH")))
        pts = [o.matrix_world @ Vector(c) for o in new if o.type == "MESH" and not o.hide_render for c in o.bound_box]
        coll = bpy.data.collections.new("proto_%s_%d" % (key, len(protos)))
        for o in new:
            for c in list(o.users_collection):
                c.objects.unlink(o)
            coll.objects.link(o)
            o.name = "%s/%s" % (coll.name, o.name)  # frees the frame names (wheel, bonnet_dam) for the next import
        for c in [c for c in scn.collection.children if not c.objects and not c.children]:
            bpy.data.collections.remove(c)
        if pts:
            lo = Vector([min(p[i] for p in pts) for i in range(3)])
            hi = Vector([max(p[i] for p in pts) for i in range(3)])
            print("SCENE dims %s %s %.2f %.2f %.2f zmin %.2f" % (key, job["dff"], hi.x - lo.x, hi.y - lo.y, hi.z - lo.z, lo.z))
        else:
            print("SCENE nothing", key)
        protos[pk] = {"coll": coll, "corners": pts}
        return protos[pk]

    def clear_scene():
        for o in list(scn.collection.all_objects):
            bpy.data.objects.remove(o, do_unlink=True)
        for c in list(scn.collection.children):
            scn.collection.children.unlink(c)

    def place(items):
        """Collection instances for every placement; the world-space corners that frame the picture."""
        framed, named = [], {}
        for n, it in enumerate(items):
            proto = prototype(it["key"], tuple(it["colour"]) if it.get("colour") else None, tuple(it["texture"]) if it.get("texture") else None)
            rot = Euler([math.radians(a) for a in it["rot"]], "YXZ")
            s = float(it.get("scale", 1.0))
            m = Matrix.LocRotScale(None, rot, Vector((s, s, s)))
            pts = [m @ c for c in proto["corners"]]
            x, y, z = it["at"]
            if it.get("on") and it["on"] in named:
                z += named[it["on"]]
            if it.get("drop", True) and pts:
                z -= min(p.z for p in pts)
            e = bpy.data.objects.new("i%d_%s" % (n, it["label"]), None)
            e.instance_type = "COLLECTION"
            e.instance_collection = proto["coll"]
            e.location = (x, y, z)
            e.rotation_mode = "YXZ"
            e.rotation_euler = rot
            e.scale = (s, s, s)
            scn.collection.objects.link(e)
            if it.get("glow"):  # a fire or a lamp: a point light just above the placement
                r, g, b, watts = it["glow"]
                data = bpy.data.lights.new("glow%d" % n, "POINT")
                data.color, data.energy, data.shadow_soft_size = (r, g, b), watts, 0.25
                lamp = bpy.data.objects.new("glow%d" % n, data)
                lamp.location = (x, y, z + it.get("glow_z", 0.35))
                scn.collection.objects.link(lamp)
            world = [p + Vector((x, y, z)) for p in pts]
            if it.get("name") and world:
                named[it["name"]] = max(p.z for p in world)
            if it.get("frame", True):
                framed += world
        return framed

    def make_world(light, sun_dir):
        """A gradient sky (horizon colour up to the zenith colour, with a glow around the sun) lighting the scene."""
        w = bpy.data.worlds.new("sky")
        w.use_nodes = True
        nt = w.node_tree
        bg = next(n for n in nt.nodes if n.type == "BACKGROUND")
        tc, sep, mr, ramp = nt.nodes.new("ShaderNodeTexCoord"), nt.nodes.new("ShaderNodeSeparateXYZ"), nt.nodes.new("ShaderNodeMapRange"), nt.nodes.new("ShaderNodeValToRGB")
        nt.links.new(tc.outputs["Generated"], sep.inputs["Vector"])
        nt.links.new(sep.outputs["Z"], mr.inputs["Value"])
        mr.inputs["From Min"].default_value, mr.inputs["From Max"].default_value = -0.02, 0.45
        nt.links.new(mr.outputs["Result"], ramp.inputs["Fac"])
        ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.0, tuple(light["horizon"]) + (1.0,)
        ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 1.0, tuple(light["zenith"]) + (1.0,)
        mid = ramp.color_ramp.elements.new(0.3)
        mid.color = tuple((a * 0.5 + b * 0.5) for a, b in zip(light["horizon"], light["zenith"])) + (1.0,)
        dot, power, glow = nt.nodes.new("ShaderNodeVectorMath"), nt.nodes.new("ShaderNodeMath"), nt.nodes.new("ShaderNodeMix")
        dot.operation, power.operation, glow.data_type = "DOT_PRODUCT", "POWER", "RGBA"
        dot.inputs[1].default_value = tuple(sun_dir)
        nt.links.new(tc.outputs["Generated"], dot.inputs[0])
        nt.links.new(dot.outputs["Value"], power.inputs[0])
        power.inputs[1].default_value = 12.0
        power.use_clamp = True
        nt.links.new(ramp.outputs["Color"], socket(glow, "A_Color"))
        socket(glow, "B_Color").default_value = tuple(min(1.0, c * 1.6) for c in light["sun_colour"]) + (1.0,)
        nt.links.new(power.outputs["Value"], socket(glow, "Factor_Float"))
        glow.clamp_factor = True
        nt.links.new(socket(glow, "Result_Color", True), bg.inputs["Color"])
        bg.inputs["Strength"].default_value = light["sky"]
        scn.world = w

    def ground_material(name, preset, horizon, tint):
        """A two-scale noise material (grain, patches) in the preset's colours scaled by tint, fogged toward the sky's
        horizon colour with the distance from the camera."""
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        noise = nt.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value, noise.inputs["Detail"].default_value, noise.inputs["Roughness"].default_value = preset["scale"], 12.0, 0.75
        ramp = nt.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position, ramp.color_ramp.elements[0].color = 0.38, tuple(c * tint for c in preset["a"]) + (1.0,)
        ramp.color_ramp.elements[1].position, ramp.color_ramp.elements[1].color = 0.62, tuple(c * tint for c in preset["b"]) + (1.0,)
        nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        big = nt.nodes.new("ShaderNodeTexNoise")
        big.inputs["Scale"].default_value, big.inputs["Detail"].default_value = 0.12, 5.0
        bigramp = nt.nodes.new("ShaderNodeValToRGB")
        bigramp.color_ramp.elements[0].position, bigramp.color_ramp.elements[1].position = 0.42, 0.6
        nt.links.new(big.outputs["Fac"], bigramp.inputs["Fac"])
        patch = nt.nodes.new("ShaderNodeMix")
        patch.data_type = "RGBA"
        socket(patch, "B_Color").default_value = tuple(c * tint for c in preset["patch"]) + (1.0,)
        nt.links.new(ramp.outputs["Color"], socket(patch, "A_Color"))
        nt.links.new(bigramp.outputs["Color"], socket(patch, "Factor_Float"))
        cam, dist = nt.nodes.new("ShaderNodeCameraData"), nt.nodes.new("ShaderNodeMapRange")
        dist.inputs["From Min"].default_value, dist.inputs["From Max"].default_value = 30.0, 1600.0
        nt.links.new(cam.outputs["View Distance"], dist.inputs["Value"])
        fog = nt.nodes.new("ShaderNodeMix")
        fog.data_type = "RGBA"
        socket(fog, "B_Color").default_value = tuple(horizon) + (1.0,)
        nt.links.new(socket(patch, "Result_Color", True), socket(fog, "A_Color"))
        nt.links.new(dist.outputs["Result"], socket(fog, "Factor_Float"))
        nt.links.new(socket(fog, "Result_Color", True), bsdf.inputs["Base Color"])
        bump = nt.nodes.new("ShaderNodeBump")
        bump.inputs["Strength"].default_value, bump.inputs["Distance"].default_value = preset["bump"], 0.04
        nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
        nt.links.new(bump.outputs["Normal"], bsdf.inputs["Normal"])
        bsdf.inputs["Roughness"].default_value = 0.95
        if "Specular IOR Level" in bsdf.inputs:
            bsdf.inputs["Specular IOR Level"].default_value = 0.2
        return m

    def make_ground(preset, horizon, seed):
        """A plane to the horizon, and a ring of low dark hills far off (the same material, darker) for a skyline."""
        import random  # noqa: PLC0415

        bpy.ops.mesh.primitive_plane_add(size=4000, location=(0, 0, 0))
        g = bpy.context.object
        g.name = "ground"
        g.data.materials.append(ground_material("ground", preset, horizon, 1.0))
        hills = ground_material("hills", preset, horizon, 0.3)
        rng = random.Random(seed)
        for i in range(14):
            a = math.radians(i * 360 / 14 + rng.uniform(-9, 9))
            r = rng.uniform(700, 1300)
            w, h = rng.uniform(220, 600), rng.uniform(10, 42)
            bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=16, radius=1.0, location=(r * math.cos(a), r * math.sin(a), -h * 0.35))
            hill = bpy.context.object
            hill.name = "hill%d" % i
            hill.scale = (w, w * rng.uniform(0.4, 1.0), h)
            hill.rotation_euler.z = rng.uniform(0, math.pi)
            hill.data.materials.append(hills)
            for poly in hill.data.polygons:
                poly.use_smooth = True

    def sky_dir(elevation, azimuth):
        """Unit vector toward a point of the sky: azimuth 0 is south (-Y), growing counter-clockwise, like the camera's."""
        el, az = math.radians(elevation), math.radians(azimuth)
        return Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))

    def sun_at(name, direction, energy, colour, angle, shadow):
        data = bpy.data.lights.new(name, "SUN")
        data.energy, data.color, data.angle, data.use_shadow = energy, colour, math.radians(angle), shadow
        setattr_safe(data, "use_shadow_jitter", True)
        o = bpy.data.objects.new(name, data)
        scn.collection.objects.link(o)
        o.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
        return o

    def make_camera(spec, corners):
        cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        scn.collection.objects.link(cam)
        scn.camera = cam
        lo = Vector([min(p[i] for p in corners) for i in range(3)])
        hi = Vector([max(p[i] for p in corners) for i in range(3)])
        az, el = math.radians(spec.get("azimuth", -35)), math.radians(spec.get("elevation", 16))
        lens, margin = spec.get("lens", 35), spec.get("margin", 1.1)
        target = Vector(spec["target"]) if "target" in spec else Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z + (hi.z - lo.z) * spec.get("target_height", 0.45)))
        d = Vector((math.sin(az) * math.cos(el), -math.cos(az) * math.cos(el), math.sin(el)))
        f = -d
        r = f.cross(Vector((0, 0, 1))).normalized()
        u = r.cross(f)
        th = 18.0 / lens / margin
        tv = th * height / width
        t = 0.0
        for p in corners:
            v = p - target
            depth = v.dot(f)
            t = max(t, abs(v.dot(r)) / th - depth, abs(v.dot(u)) / tv - depth)
        t = spec.get("distance", t)
        cam.location = target + d * t
        if "height" in spec:
            cam.location.z = spec["height"]
        cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
        cam.data.sensor_fit, cam.data.sensor_width, cam.data.lens = "HORIZONTAL", 36.0, lens
        cam.data.clip_start, cam.data.clip_end = 0.05, 6000.0
        cam.data.shift_y = spec.get("shift_y", 0.0)
        if spec.get("fstop"):
            cam.data.dof.use_dof = True
            cam.data.dof.focus_distance = (target - cam.location).length
            cam.data.dof.aperture_fstop = spec["fstop"]
        return cam

    def setup_render(samples):
        engines = [i.identifier for i in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
        scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in engines else "BLENDER_EEVEE"
        scn.render.resolution_x, scn.render.resolution_y, scn.render.resolution_percentage = width, height, 100
        scn.render.film_transparent = False
        scn.render.image_settings.file_format, scn.render.image_settings.color_mode = "PNG", "RGB"
        ee = scn.eevee
        setattr_safe(ee, "taa_render_samples", samples)
        setattr_safe(ee, "use_shadows", True)
        setattr_safe(ee, "shadow_ray_count", 2)
        setattr_safe(ee, "shadow_step_count", 4)
        setattr_safe(ee, "use_raytracing", True)
        setattr_safe(ee, "ray_tracing_method", "SCREEN")
        setattr_safe(ee, "use_fast_gi", True)
        setattr_safe(ee, "fast_gi_method", "GLOBAL_ILLUMINATION")
        setattr_safe(ee, "fast_gi_distance", 8.0)
        setattr_safe(ee, "use_gtao", True)
        setattr_safe(ee, "gtao_distance", 1.0)
        setattr_safe(ee, "use_soft_shadows", True)
        setattr_safe(ee, "use_bokeh_jittered", True)
        setattr_safe(ee.ray_tracing_options, "use_denoise", True)
        for vt in ("AgX", "Filmic", "Standard"):
            try:
                scn.view_settings.view_transform = vt
                break
            except TypeError:
                continue
        for look in ("AgX - Medium High Contrast", "Medium High Contrast", "None"):
            try:
                scn.view_settings.look = look
                break
            except TypeError:
                continue
        scn.view_settings.exposure = 0.05
        print("SCENE note engine", scn.render.engine, "view", scn.view_settings.view_transform, "look", scn.view_settings.look)

    for n, scene in enumerate(spec["scenes"]):
        clear_scene()
        light = LIGHTS[scene["light"]]
        ground = GROUNDS[scene["ground"]]
        framed = place(scene["items"])
        if not framed:
            print("SCENE nothing", scene["name"])
            continue
        cam_spec = dict(scene["camera"])
        make_camera(cam_spec, framed)
        cam_az = cam_spec.get("azimuth", -35)
        sun = sky_dir(light["sun_elevation"], cam_az + light["sun_offset"])
        make_world(light, sun)
        make_ground(ground, light["horizon"], n + 1)
        sun_at("sun", sun, light["sun_energy"], light["sun_colour"], light["sun_angle"], True)
        sun_at("fill", sky_dir(35, cam_az + light["sun_offset"] + 180), light["fill"], light["fill_colour"], 60, False)
        setup_render(spec["samples"])
        path = os.path.join(spec["out"], scene["name"] + ".png")
        scn.render.filepath = path
        bpy.ops.render.render(write_still=True)
        print("SCENE ok", scene["name"], path)


# ---------------------------------------------------------------- outside Blender


def wiki_copy(src: Path, dest_dir: Path) -> Path:
    from PIL import Image

    dest_dir.mkdir(parents=True, exist_ok=True)
    im = Image.open(src).convert("RGB")
    im.thumbnail((WIKI_WIDTH, WIKI_WIDTH * 10), Image.LANCZOS)
    dest = dest_dir / src.name
    im.save(dest, optimize=True)
    return dest


def main(argv=None) -> int:
    from tools.extract_ped_models import find_blender
    from tools.extract_samp_models import detect_gta
    from tools.render_item_models import fetch_vehicle_txd, find_txds, stage, vehicle_models

    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--scene", action="append", help="scene name (repeatable); default: every scene")
    ap.add_argument("--list", action="store_true", help="list the scenes and exit")
    ap.add_argument("--gta", type=Path)
    ap.add_argument("--blender")
    ap.add_argument("--size", default="1920x1080", help="WxH, default 1920x1080")
    ap.add_argument("--samples", type=int, default=64, help="EEVEE render samples, default 64")
    ap.add_argument("--out", type=Path, default=OUT, help="folder for the full-size renders")
    ap.add_argument("--wiki", type=Path, default=WIKI_OUT, help="folder for the 1200 px copies (the wiki clone); '-' to skip")
    ap.add_argument("--dims", action="store_true", help="print every staged model's size and lowest point")
    ap.add_argument("--parts", action="store_true", help="print every staged model's frames and texture names")
    args = ap.parse_args(argv)
    if args.list:
        for n, s in SCENES.items():
            print(f"{n:14s} {s['caption']}")
        return 0
    names = args.scene or list(SCENES)
    unknown = [n for n in names if n not in SCENES]
    if unknown:
        print("render_scenes: unknown scene(s):", ", ".join(unknown), file=sys.stderr)
        return 2
    gta = args.gta or detect_gta()
    blender = find_blender(args.blender)
    if not gta or not blender:
        print("render_scenes: need GTA:SA (--gta) and Blender (--blender)", file=sys.stderr)
        return 2
    m = re.fullmatch(r"(\d+)x(\d+)", args.size)
    if not m:
        print("render_scenes: --size wants WxH", file=sys.stderr)
        return 2
    size = [int(m.group(1)), int(m.group(2))]
    types, vehicles = item_types(), vehicle_models()
    scenes, models, txd_only = [], set(), set()
    for n in names:
        s, ms, ts = resolve(n, SCENES[n], types, vehicles)
        scenes.append(s)
        models |= ms
        txd_only |= ts
    vehicle_ids = {int(it["key"]) for s in scenes for it in s["items"] if it.get("vehicle")}
    work = Path(tempfile.mkdtemp(prefix="render_scenes_"))
    jobs, problems = stage(models | txd_only, gta, work)
    for j in jobs:
        j["key"] = str(j["model"])
        if j["model"] in vehicle_ids:
            j["vehicle"] = True
            if fetch_vehicle_txd(gta, Path(j["dir"])):
                j["txds"].append("vehicle")
    jobs = {j["key"]: j for j in jobs}
    for name, f in FILES.items():
        jobs[name] = dict(f, key=name, model=name)
    staged = set(jobs)
    for s in scenes:
        s["items"] = [it for it in s["items"] if it["key"] in staged and (not it.get("texture") or it["texture"][0] in staged)]
    args.out.mkdir(parents=True, exist_ok=True)
    spec = {"out": str(args.out.resolve()), "size": size, "samples": args.samples, "jobs": jobs, "scenes": scenes, "parts": args.parts}
    spec_file = work / "spec.json"
    spec_file.write_text(json.dumps(spec))
    cmd = [str(blender), "-b", "--python", __file__, "--", str(spec_file)]
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf8", errors="replace")
    lines = (res.stdout + res.stderr).splitlines()
    lost: dict[str, set[str]] = {}
    for line in lines:
        if line.startswith("SCENE missing"):
            _, _, key, names_ = line.split(" ", 3)
            lost.setdefault(key, set()).update(x.lower() for x in names_.split(",") if (key, x.lower()) not in NO_FALLBACK)
    if lost:  # textures a model's own TXD lacks: take them from whichever game TXD holds them and render again
        where = find_txds(set().union(*lost.values()), gta)
        again = False
        for key, names_ in lost.items():
            for t in sorted({where[n][0] for n in names_ if n in where}):
                if key in jobs and t not in jobs[key]["txds"]:
                    (Path(jobs[key]["dir"]) / (t + ".txd")).write_bytes(next(d for n, (x, d) in where.items() if x == t))
                    jobs[key]["txds"].append(t)
                    again = True
            for n in sorted(names_ - set(where)):
                problems.append(f"{key}: texture {n} is in no game TXD")
        if again:
            spec_file.write_text(json.dumps(spec))
            res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf8", errors="replace")
            lines = (res.stdout + res.stderr).splitlines()
    for line in lines:
        if line.startswith("SCENE dims") and args.dims or line.startswith("SCENE parts") and args.parts or line.startswith(("SCENE nothing", "SCENE note")) or "Error" in line or "Traceback" in line:
            print(line)
    index_file = args.out / "index.json"
    index = json.loads(index_file.read_text()) if index_file.is_file() else {}
    done = []
    for s in scenes:
        png = args.out / (s["name"] + ".png")
        if png.is_file() and any(line.startswith("SCENE ok " + s["name"] + " ") for line in lines):
            index[s["name"]] = {"file": png.name, "caption": s["caption"], "light": s["light"], "ground": s["ground"]}
            done.append(png)
            if str(args.wiki) != "-":
                print("wrote", png, "->", wiki_copy(png, args.wiki))
            else:
                print("wrote", png)
        else:
            problems.append(f"{s['name']}: no render written")
    index_file.write_text(json.dumps(index, indent=1, sort_keys=True) + "\n")
    for p in problems:
        print("problem:", p, file=sys.stderr)
    if res.returncode:
        print(res.stderr[-3000:], file=sys.stderr)
    return 0 if len(done) == len(scenes) else 1


if __name__ == "__main__":
    if "bpy" in sys.modules:
        build_in_blender(Path(sys.argv[sys.argv.index("--") + 1]))
    else:
        sys.exit(main())
