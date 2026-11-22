"""Vehicle salvage parts for every car and truck the game spawns (the Bobcat's are tools/bobcat_parts.py, ids 20210+).

Each part is Rockstar's own ok (Good) or dam (Bad) mesh of a vehicle component, cut out by Blender + DragonFF.

    python -m tools.car_parts survey [--gta DIR] [--blender EXE]   frames, dummies and fingerprints per model
    python -m tools.car_parts build  [--gta DIR] [--blender EXE]   exports car_part_models/files + tools/data/car_parts.json
    python -m tools.car_parts manifest                             writes car_part_models/parts.lua + meta.xml
    python -m tools.car_parts print items|seed|rest|models|loot    text for the hand-edited data files

The build works on the Windows box (Blender 5.3 + DragonFF, the game at D:/Games/gtasa).
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "resources" / "[scavengesurvive]"
OUT = RES / "car_part_models"
DATA = ROOT / "tools" / "data" / "car_parts.json"
SURVEY = ROOT / "tools" / "data" / "car_parts_survey.json"
BLENDER_SCRIPT = ROOT / "tools" / "car_parts_blender.py"
FIRST_ID = 21001
LAST_ID = 21999

# GTA model id -> (item prefix, display name). The Bobcat (422) has its own items already.
VEHICLES = {
    403: ("Linerunner", "Linerunner"),
    405: ("Sentinel", "Sentinel"),
    407: ("Firetruck", "Firetruck"),
    416: ("Ambulance", "Ambulance"),
    418: ("Moonbeam", "Moonbeam"),
    424: ("BfInjection", "BF Injection"),
    427: ("Enforcer", "Enforcer"),
    433: ("Barracks", "Barracks"),
    440: ("Rumpo", "Rumpo"),
    455: ("Flatbed", "Flatbed"),
    456: ("Yankee", "Yankee"),
    470: ("Patriot", "Patriot"),
    475: ("Sabre", "Sabre"),
    478: ("Walton", "Walton"),
    479: ("Regina", "Regina"),
    480: ("Comet", "Comet"),
    489: ("Rancher", "Rancher"),
    495: ("Sandking", "Sandking"),
    496: ("Blista", "Blista Compact"),
    498: ("Boxville", "Boxville"),
    500: ("Mesa", "Mesa"),
    504: ("Bloodring", "Bloodring Banger"),
    508: ("Journey", "Journey"),
    515: ("Roadtrain", "Roadtrain"),
    528: ("FbiTruck", "FBI Truck"),
    542: ("Clover", "Clover"),
    543: ("Sadler", "Sadler"),
    549: ("Tampa", "Tampa"),
    554: ("Yosemite", "Yosemite"),
    560: ("Sultan", "Sultan"),
    573: ("Dune", "Dune"),
    578: ("Dft30", "DFT-30"),
    579: ("Huntley", "Huntley"),
    596: ("Police", "Police Car"),
    597: ("PoliceSf", "Police Car SF"),
    598: ("PoliceLv", "Police Car LV"),
    599: ("Ranger", "Ranger"),
}

# model -> the model whose part set it uses (its meshes match closely enough to swap). Filled from the survey.
SHARE: dict[int, int] = {597: 596, 599: 489}  # Police SF = Police LS; Ranger = Rancher

# Frame base name -> (slot name, label, MTA door id or None, MTA panel id or None). Order is the item order.
SLOTS = [
    ("bonnet", "Hood", "Hood", 0, None),
    ("boot", "Trunk", "Trunk", 1, None),
    ("door_lf", "LeftDoor", "Left Door", 2, None),
    ("door_rf", "RightDoor", "Right Door", 3, None),
    ("door_lr", "RearLeftDoor", "Rear Left Door", 4, None),
    ("door_rr", "RearRightDoor", "Rear Right Door", 5, None),
    ("bump_front", "FrontBumper", "Front Bumper", None, 5),
    ("bump_rear", "RearBumper", "Rear Bumper", None, 6),
]
# Pickups and vans call the boot a tailgate (the Bobcat's items do).
TAILGATE = {478, 543, 554, 489, 500, 599, 470, 495, 422}

# Carried: the Bobcat's hand offsets per kind of panel (tools/bobcat_parts.py CARRY).
CARRY = {
    "boot": (0.209, -0.265, 0.002, -117.619, -23.313, -99.375),
    "door": (0.216, -0.216, -0.018, -117.619, -23.313, -9.375),
    "bonnet": (0.293, -0.194, -0.015, -101.189, 55.447, 74.707),
    "bump": (0.090, 0.106, -0.181, -115.952, -13.439, -98.847),
}


def carry_for(mesh: str):
    for key, value in CARRY.items():
        if mesh.startswith(key):
            return value
    raise KeyError(mesh)


def slot_label(model: int, mesh: str) -> tuple[str, str]:
    for m, name, label, _door, _panel in SLOTS:
        if m == mesh:
            if mesh == "boot" and model in TAILGATE:
                return "Tailgate", "Tailgate"
            return name, label
    raise KeyError(mesh)


# --- game files ----------------------------------------------------------------------------------------------------


def find_gta(explicit: Path | None) -> Path:
    for p in [explicit, Path("D:/Games/gtasa")]:
        if p and (p / "models" / "gta3.img").exists():
            return p
    sys.exit("car_parts: no GTA:SA install found (pass --gta)")


def find_blender(explicit: str | None) -> Path:
    from tools.extract_ped_models import find_blender as fb

    b = fb(explicit)
    if not b:
        sys.exit("car_parts: no Blender found (pass --blender)")
    return b


def parse_vehicles_ide(gta: Path) -> dict[int, tuple[str, str, float]]:
    """id -> (dff, txd, wheel scale)"""
    out = {}
    for line in (gta / "data" / "vehicles.ide").read_text(errors="replace").splitlines():
        parts = [p.strip() for p in line.split("#")[0].split(",")]
        if len(parts) >= 14 and parts[0].isdigit():
            out[int(parts[0])] = (parts[1].lower(), parts[2].lower(), float(parts[13]))
    return out


def parse_carcols(gta: Path) -> tuple[list[tuple[int, int, int]], dict[str, tuple[int, int]]]:
    """the colour table and each model's first (primary, secondary) pairing"""
    colours, first, section = [], {}, None
    for raw in (gta / "data" / "carcols.dat").read_text(errors="replace").splitlines():
        line = raw.split("#")[0].strip()
        if not line:
            continue
        if line in ("col", "car", "car4"):
            section = line
            continue
        if line == "end":
            section = None
            continue
        nums = [p for p in re.split(r"[,\s.]+", line) if p]
        if section == "col" and len(nums) >= 3:
            colours.append((int(nums[0]), int(nums[1]), int(nums[2])))
        elif section in ("car", "car4") and len(nums) >= 3:
            first.setdefault(nums[0].lower(), (int(nums[1]), int(nums[2])))
    return colours, first


def extract(gta: Path, work: Path, models) -> list[dict]:
    from tools.extract_samp_models import read_img_entry, read_img_index

    img = gta / "models" / "gta3.img"
    index = read_img_index(img)
    ide = parse_vehicles_ide(gta)
    colours, first = parse_carcols(gta)
    jobs = []
    for model in models:
        dff, txd, wheel = ide[model]
        (work / f"{dff}.dff").write_bytes(read_img_entry(img, index[f"{dff}.dff"]))
        (work / f"{txd}.txd").write_bytes(read_img_entry(img, index[f"{txd}.txd"]))
        pair = first.get(dff, (1, 1))
        jobs.append(
            dict(
                model=model,
                dff=str(work / f"{dff}.dff"),
                txd=str(work / f"{txd}.txd"),
                name=dff,
                wheel=wheel,
                paint=[list(colours[pair[0]]), list(colours[pair[1]])],
            )
        )
    shutil.copy(gta / "models" / "generic" / "vehicle.txd", work / "vehicle.txd")
    return jobs


def run_blender(blender: Path, mode: str, jobs: list[dict], work: Path, out: Path) -> dict:
    spec = work / "jobs.json"
    result = work / "result.json"
    spec.write_text(json.dumps(dict(mode=mode, jobs=jobs, work=str(work), out=str(out), result=str(result))))
    cmd = [str(blender), "-b", "--factory-startup", "--python", str(BLENDER_SCRIPT), "--", str(spec)]
    res = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8", errors="replace")
    if res.returncode != 0 or not result.exists():
        sys.exit(f"car_parts: blender failed:\n{res.stdout[-3000:]}\n{res.stderr[-3000:]}")
    return json.loads(result.read_text())


def txd_textures(data: bytes) -> tuple[int, int, dict[str, bytes]]:
    from tools.extract_samp_models import txd_natives

    version, device, natives = txd_natives(data)
    return version, device, {c[32:64].split(b"\0", 1)[0].decode("latin1").lower(): c for c in natives}


def plan_renames(jobs: list[dict], work: Path) -> None:
    """Every part draws from one shared TXD, so a texture name two cars' TXDs both use with different pixels
    (copcarla and copcarvg's interiors) is renamed <name>_<model> for every car but the first."""
    _v, _d, generic = txd_textures((work / "vehicle.txd").read_bytes())
    seen: dict[str, bytes] = dict(generic)
    for job in jobs:
        _v, _d, own = txd_textures(Path(job["txd"]).read_bytes())
        job["rename"] = {}
        for name, chunk in own.items():
            if name in seen and seen[name][32:] != chunk[32:]:
                job["rename"][name] = f"{name[:26]}_{job['model']}"
            else:
                seen.setdefault(name, chunk)


def shared_txd(jobs: list[dict], work: Path, used: dict[str, list[str]]) -> bytes:
    """One TXD with every texture the parts use: each car's own (renamed where planned), then vehicle.txd's."""
    import struct

    version, device, generic = txd_textures((work / "vehicle.txd").read_bytes())
    chosen: dict[str, bytes] = {}
    for job in jobs:
        _v, _d, own = txd_textures(Path(job["txd"]).read_bytes())
        back = {new: old for old, new in job["rename"].items()}
        for tex in used.get(str(job["model"]), []):
            if tex in chosen:
                continue
            src = back.get(tex, tex)
            chunk = own.get(src) or generic.get(src)
            if chunk is None:
                print(f"car_parts: {job['model']} uses {tex}, found in neither TXD", file=sys.stderr)
                continue
            if src != tex:  # the native's name field: 32 bytes at offset 32
                chunk = chunk[:32] + tex.encode("latin1").ljust(32, b"\0") + chunk[64:]
            chosen[tex] = chunk
    natives = list(chosen.values())
    body = struct.pack("<IIIHH", 0x01, 4, version, len(natives), device) + b"".join(natives)
    body += struct.pack("<III", 0x03, 0, version)
    return struct.pack("<III", 0x16, len(body), version) + body


# --- ids and data --------------------------------------------------------------------------------------------------


def sets(data: dict) -> list[dict]:
    """One entry per item set (a model that owns parts), in model order, with ids assigned."""
    nid = FIRST_ID
    out = []
    for key in sorted(data["models"], key=int):
        model = int(key)
        if model in SHARE:
            continue
        m = data["models"][key]
        prefix, vname = VEHICLES[model]
        parts = []
        for mesh, *_ in SLOTS:
            if mesh not in m["parts"]:
                continue
            name, label = slot_label(model, mesh)
            for good, suffix in ((True, "ok"), (False, "dam")):
                p = m["parts"][mesh][suffix]
                parts.append(
                    dict(
                        id=nid,
                        mesh=mesh,
                        suffix=suffix,
                        good=good,
                        uname=prefix + name + ("Good" if good else "Bad"),
                        name=f"{vname} {label} ({'Good' if good else 'Bad'})",
                        label=label,
                        asset=f"{m['name']}_{mesh}_{suffix}",
                        **p,
                    )
                )
                nid += 1
        if nid - 1 > LAST_ID:
            sys.exit("car_parts: out of model ids")
        out.append(dict(model=model, prefix=prefix, vehicle=vname, name=m["name"], parts=parts))
    return out


def load_data() -> dict:
    if not DATA.exists():
        sys.exit(f"car_parts: {DATA.relative_to(ROOT)} missing, run build first")
    return json.loads(DATA.read_text())


# --- commands ------------------------------------------------------------------------------------------------------


def cmd_survey(args):
    gta = find_gta(args.gta)
    blender = find_blender(args.blender)
    work = Path(tempfile.mkdtemp(prefix="car_parts_"))
    jobs = extract(gta, work, sorted(VEHICLES) + [422])
    result = run_blender(blender, "survey", jobs, work, work)
    SURVEY.write_text(json.dumps(result, indent=1, sort_keys=True))
    for key in sorted(result["models"], key=int):
        m = result["models"][key]
        slots = [s for s, *_ in SLOTS if s in m["parts"]]
        print(f"{key} {m['name']:10} drop={m['groundDrop']:.2f} slots={','.join(slots)}")
    print(f"written {SURVEY.relative_to(ROOT)}")


def cmd_build(args):
    gta = find_gta(args.gta)
    blender = find_blender(args.blender)
    work = Path(tempfile.mkdtemp(prefix="car_parts_"))
    models = [m for m in sorted(VEHICLES) if m not in SHARE]
    jobs = extract(gta, work, models)
    plan_renames(jobs, work)
    files = OUT / "files"
    files.mkdir(parents=True, exist_ok=True)
    for old in files.glob("*"):
        old.unlink()
    result = run_blender(blender, "build", jobs, work, files)
    # one TXD for every part: each car's textures plus the shared vehicle.txd, only what the parts use
    (files / "car_parts.txd").write_bytes(shared_txd(jobs, work, result["textures"]))
    result["share"] = {str(k): v for k, v in SHARE.items()}
    DATA.write_text(json.dumps(result, indent=1, sort_keys=True))
    print(f"written {DATA.relative_to(ROOT)} and {len(list(files.glob('*.dff')))} parts")


def cmd_manifest(_args):
    data = load_data()
    lines = [
        "-- Generated by tools/car_parts.py manifest; do not edit. Port model id -> a vehicle salvage part in",
        "-- car_part_models/files/, every one on the shared car_parts.txd.",
        "return {",
    ]
    files = ["car_parts.txd"]
    for s in sets(data):
        for p in s["parts"]:
            lines.append(f'    [{p["id"]}] = {{ dff = "{p["asset"]}", txd = "car_parts", dist = 80 }},')
            files += [p["asset"] + ".dff", p["asset"] + ".col"]
    lines.append("}")
    (OUT / "parts.lua").write_text("\n".join(lines) + "\n", newline="\n")
    meta = [
        "<meta>",
        '    <info author="scavengesurvive-mta" type="script" name="car_part_models" '
        'description="Vehicle salvage parts: the ok and dam panels of every car" version="0.1.0"/>',
        '    <min_mta_version server="1.6.0" client="1.6.0-9.21695"/>',
        "    <download_priority_group>90</download_priority_group>",
        '    <include resource="lib"/>',
        '    <script src="server/main.lua" type="server"/>',
        '    <script src="client/main.lua" type="client"/>',
        '    <file src="parts.lua"/>',
    ]
    meta += [f'    <file src="files/{f}"/>' for f in sorted(files)]
    meta += ['    <export function="resolve" type="client"/>', "</meta>"]
    (OUT / "meta.xml").write_text("\n".join(meta) + "\n", newline="\n")
    print(f"written parts.lua and meta.xml ({len(files)} files)")


def lua_num(x: float) -> str:
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return s if s not in ("-0", "") else "0"


# Loot: a fixed total weight per table for every body part, split between the part sets by the summed spawn chance
# of the models each one fits (data/generated/vehicle_types.lua), evenly over a set's slots, Bad twice as likely as
# Good, with a floor so a rare truck's parts still turn up. The Bobcat's set (tools/bobcat_parts.py) takes its share.
LOOT_BUDGET = {"world_industrial": 12.0, "vehicle_industrial": 4.0}
LOOT_FLOOR = (0.005, 0.01)
BOBCAT_SLOTS = ["Tailgate", "LeftDoor", "RightDoor", "Hood", "FrontBumper", "RearBumper"]


def spawn_chances() -> dict[int, float]:
    text = (RES / "data" / "generated" / "vehicle_types.lua").read_text(encoding="utf-8")
    out: dict[int, float] = {}
    for line in text.splitlines():
        m = re.search(r"model = (\d+),.*spawnChance = ([\d.]+)", line)
        if m:
            out[int(m.group(1))] = out.get(int(m.group(1)), 0.0) + float(m.group(2))
    return out


def loot_entries(data: dict) -> dict[str, list[tuple[str, float]]]:
    """table -> [(uname, weight)] for every part, the Bobcat's first"""
    chances = spawn_chances()
    groups = [(422, [("Bobcat" + n + "Good", "Bobcat" + n + "Bad") for n in BOBCAT_SLOTS])]
    for s in sets(data):
        pairs = [(s["parts"][i]["uname"], s["parts"][i + 1]["uname"]) for i in range(0, len(s["parts"]), 2)]
        groups.append((s["model"], pairs))

    def chance(model):
        return chances.get(model, 0.0) + sum(chances.get(k, 0.0) for k, v in SHARE.items() if v == model)

    total = sum(chance(m) for m, _ in groups)
    out = {}
    for table, budget in LOOT_BUDGET.items():
        rows = []
        for model, pairs in groups:
            per_slot = budget * chance(model) / total / len(pairs)
            good = max(LOOT_FLOOR[0], round(per_slot / 3, 3))
            bad = max(LOOT_FLOOR[1], round(2 * per_slot / 3, 3))
            for g, b in pairs:
                rows += [(g, good), (b, bad)]
        out[table] = rows
    return out


def cmd_print(args):
    data = load_data()
    all_sets = sets(data)
    what = args.what
    for s in all_sets:
        for p in s["parts"]:
            if what == "items":
                rx, ry, rz = p["rest"]
                ax, ay, az, arx, ary, arz = carry_for(p["mesh"])
                print(
                    f"M.byUname.{p['uname']} = {{ attrx = {arx}, attry = {ary}, attrz = {arz}, attx = {ax}, atty = {ay}, "
                    f'attz = {az}, boneid = 6, buttonz = 0.96, category = "generic", categoryData = nil, colour = -1, '
                    f"longPickup = true, maxHitpoints = {5 if p['good'] else 2}, model = {p['id']}, "
                    f'modelz = {lua_num(p["modelz"])}, name = "{p["name"]}", '
                    f'partName = "%s {p["label"]} ({"Good" if p["good"] else "Bad"})", partVehicle = "{s["vehicle"]}", '
                    f"price = 1, rotx = {lua_num(rx)}, roty = {lua_num(ry)}, rotz = {lua_num(rz)}, size = 6, "
                    f'uname = "{p["uname"]}", useCarryAnim = true }}'
                )
            elif what == "order":
                print(f'"{p["uname"]}", ', end="")
            elif what == "seed":
                print(f"('{p['uname']}','{p['name']}',{p['id']},6,{5 if p['good'] else 2},'generic',NULL),")
            elif what == "rest":
                print(f'    {p["uname"]} = {{ {", ".join(lua_num(v) for v in p["restRow"])} }},')
    if what == "loot":
        for table, rows in loot_entries(data).items():
            print(f"{table}: {len(rows)} entries, total {sum(w for _, w in rows):.2f}")
            for uname, w in rows:
                print(f"    {uname} {w}")
    if what == "models":
        for s in all_sets:
            m = data["models"][str(s["model"])]
            users = [s["model"]] + [k for k, v in SHARE.items() if v == s["model"]]
            for model in users:
                mm = data["models"].get(str(model), m)
                print(f'    [{model}] = {{ prefix = "{s["prefix"]}", groundDrop = {lua_num(mm["groundDrop"])}, slots = {{')
                for mesh, *_ in SLOTS:
                    if mesh not in m["parts"]:
                        continue
                    name, _ = slot_label(s["model"], mesh)
                    _, _, _, door, panel = next(x for x in SLOTS if x[0] == mesh)
                    x, y = mm["slots"].get(mesh, m["slots"][mesh])
                    kind = f"door = {door}" if door is not None else f"panel = {panel}"
                    print(f'        {{ name = "{name}", {kind}, x = {lua_num(x)}, y = {lua_num(y)} }},')
                print("    } },")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    for name in ("survey", "build"):
        p = sub.add_parser(name)
        p.add_argument("--gta", type=Path)
        p.add_argument("--blender")
    sub.add_parser("manifest")
    p = sub.add_parser("print")
    p.add_argument("what", choices=["items", "order", "seed", "rest", "models", "loot"])
    args = ap.parse_args()
    {"survey": cmd_survey, "build": cmd_build, "manifest": cmd_manifest, "print": cmd_print}[args.cmd](args)


if __name__ == "__main__":
    main()
