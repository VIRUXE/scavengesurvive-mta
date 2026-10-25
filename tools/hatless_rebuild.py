"""Rebuild the hatless twins' bare heads from the reference images (#89).

    python -m tools.hatless_rebuild calibrate [--player VIRUXE]   # Head bone matrices in the studio -> tools/data
    python -m tools.hatless_rebuild prep [skin ...]               # registration + lighting -> tools/data
    python -m tools.hatless_rebuild build [skin ...]              # Blender -> models/files, peds.lua, meta.xml

A twin's head is rebuilt from `docs/images/hatless-refs/<skin>.jpg` (tools/hatless_refs.py): the studio's camera is
known (tools/hatless_proj.py), so once the Head bone's place in the studio is measured, every point of the head maps
to the reference pixel that shows it. tools/blender/rebuild_head.py carves the skull out of the reference's
silhouettes and paints the hair from it.

`calibrate` has the player's client cycle the 22 skins in the studio and write each Head bone matrix
(`getElementBoneMatrix(localPlayer, 5)`) to a private client file, copied into `tools/data/hatless_calib.json`.
`prep` registers the images for each skin: the mesh (hat included) against the studio grid's silhouette, a shift
for the head's idle pose; the studio grid against the reference below the brow, a scale and shift for the image
model's re-framing; and the studio's lighting factor, studio pixel over atlas texel on the face. That goes to
`tools/data/hatless_prep.json`. `build` runs the Blender script per skin and installs `<name>_nohat.dff` and its hair
TXD; restart `models` to see them.
"""
import argparse
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

import numpy as np

from tools import hatless_proj as hp
from tools.extract_ped_models import HEADGEAR, MODELS, find_blender, read_peds, render_peds
from tools.extract_samp_models import detect_gta, read_img_entry, read_img_index, write_meta
from tools.port_hats import HATS

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "tools" / "data"
CALIB = DATA / "hatless_calib.json"
PREP = DATA / "hatless_prep.json"
REFS = ROOT / "docs" / "images" / "hatless-refs"
RCON = ROOT / "server-config" / "rcon.ps1"
SCRIPT = ROOT / "tools" / "blender" / "rebuild_head.py"
PRIV = Path(r"C:\Program Files (x86)\MTA San Andreas 1.6\mods\deathmatch\priv")

# skin -> the cut plane in Head bone space (metres above the bone, which sits at the jaw on these skins): `front` at
# the brow, `back` under the headgear's rim; `blocks` adds atlas blocks (col, row) that are headgear but escape the
# automatic rule. Set by eye from the studio's side shot with height lines drawn on it.
PLANES: dict[int, dict] = {
    2: dict(front=0.115, back=0.07),
    35: dict(front=0.10, back=0.07),
    36: dict(front=0.11, back=0.07),
    37: dict(front=0.11, back=0.08, blocks=[(6, 4), (7, 4)]),
    61: dict(front=0.095, back=0.045),
}


def listed_blocks(skin: int) -> list[tuple[int, int]]:
    """The hat's atlas blocks other tables already name: tools/port_hats.py and the cut table's explicit lists."""
    blocks = set(next((h["blocks"] for h in HATS if h["skin"] == skin), set()))
    gear = HEADGEAR[skin][2]
    if gear not in ("auto", "*"):
        blocks |= {tuple(int(x) for x in b.split(",")) for b in gear.split(";")}
    return sorted(blocks)


def extract(skin: int, work: Path) -> tuple[str, str]:
    """The skin's DFF and TXD from gta3.img into `work`; returns (dff name, texture name)."""
    name, tex = HEADGEAR[skin][0], HEADGEAR[skin][1]
    img = detect_gta() / "models" / "gta3.img"
    index = read_img_index(img)
    for entry in (f"{name}.dff", f"{tex}.txd"):
        (work / entry).write_bytes(read_img_entry(img, index[entry]))
    if tex != name:  # bikdrug wears bikera's TXD; DragonFF looks for <name>.txd
        shutil.copy(work / f"{tex}.txd", work / f"{name}.txd")
    return name, tex


def blender(*args: str) -> str:
    exe = find_blender(None)
    r = subprocess.run([str(exe), "-b", "--python", str(SCRIPT), "--", *args], capture_output=True, text=True)
    if r.returncode != 0 or "Traceback" in r.stdout + r.stderr:
        raise RuntimeError((r.stdout + r.stderr)[-2000:])
    return r.stdout


def calibrate(player: str) -> None:
    skins = ",".join(str(s) for s in sorted(HEADGEAR))
    code = f"local L={{{skins}}} local out={{}} local i=0 local function step() if i>0 then out[tostring(L[i])]=getElementBoneMatrix(localPlayer,5) end i=i+1 if L[i] then setElementModel(localPlayer,L[i]) setTimer(step,1500,1) else local f=fileCreate('@hatless_calib.json') fileWrite(f,toJSON(out)) fileClose(f) end end step()"
    subprocess.run(["pwsh", "-NoProfile", str(RCON), "studio", player, "0", "0.8", "0.68", "0.64"], check=True, capture_output=True)
    time.sleep(3)
    subprocess.run(["pwsh", "-NoProfile", str(RCON), "clua", player, code], check=True, capture_output=True)
    time.sleep(1.5 * len(HEADGEAR) + 5)
    src = max(PRIV.glob("*/dev/hatless_calib.json"), key=lambda p: p.stat().st_mtime)
    matrices = json.loads(src.read_text(encoding="utf8"))[0]
    DATA.mkdir(exist_ok=True)
    CALIB.write_text(json.dumps({k: matrices[k] for k in sorted(matrices, key=int)}, indent=1) + "\n", encoding="ascii")
    print(f"{len(matrices)} Head bone matrices -> {CALIB}")


def register(skin: int, mesh: dict, atlas_png: Path) -> dict:
    """Per-view offsets (mesh -> studio grid), reference re-framing (studio grid -> reference) and lighting."""
    from PIL import Image, ImageDraw

    plane = PLANES[skin]
    bone_m = json.loads(CALIB.read_text())[str(skin)]
    v, w = np.array(mesh["verts"]), np.array(mesh["headw"])
    faces = [f for f in mesh["faces"] if all(w[i] > 0.5 for i in f[0])]
    studio = np.asarray(Image.open(REFS / f"{skin}-studio.jpg").convert("RGB")).astype(np.float32) / 255
    ref = Image.open(REFS / f"{skin}.jpg").convert("RGB").resize((1024, 1024))
    atlas = np.asarray(Image.open(atlas_png).convert("RGB")).astype(np.float32) / 255
    green = (studio[..., 1] > studio[..., 0] + 0.2) & (studio[..., 1] > studio[..., 2] + 0.2)
    out = {"offset": {}, "ref_xform": {}}
    ratios = []
    for view in hp.GRIDS["level"]:
        base = hp.to_grid("level", view, hp.to_shot(view, hp.to_world(bone_m, v)))
        # the mesh against the studio silhouette, top of the head to the chin
        best = None
        for dy in range(-14, 15):
            for dx in range(-14, 15):
                xy = base + [dx, dy]
                img = Image.new("1", (1024, 1024))
                draw = ImageDraw.Draw(img)
                for f in faces:
                    draw.polygon([tuple(xy[i]) for i in f[0]], fill=1)
                m = np.asarray(img)
                hv = xy[[i for f in faces for i in f[0]]]
                y0, y1 = int(hv[:, 1].min()) - 10, int(np.percentile(hv[:, 1], 80))
                x0, x1 = int(hv[:, 0].min()) - 10, int(hv[:, 0].max()) + 10
                a, b = m[y0:y1, x0:x1], ~green[y0:y1, x0:x1]
                iou = (a & b).sum() / max(1, (a | b).sum())
                if best is None or iou > best[0]:
                    best = (iou, dx, dy)
        out["offset"][view] = [best[1], best[2]]
        # the reference against the studio grid below the brow: scale about the cell centre, then shift
        ox, oy = hp.cell_origin("level", view)
        fx = hp.to_grid("level", view, hp.to_shot(view, hp.to_world(bone_m, v[(v[:, 0] < plane["front"] - 0.01) & (v[:, 0] > 0) & (w > 0.5)])), out["offset"][view])
        brow = int(fx[:, 1].min()) - oy
        cell = Image.fromarray((studio[oy : oy + 512, ox : ox + 512] * 255).astype(np.uint8))
        rcell = ref.crop((ox, oy, ox + 512, oy + 512))
        small = {k: np.asarray(cell.resize((512 // k, 512 // k))).astype(np.float32) / 255 for k in (1, 4)}

        def score(s, tx, ty, k):
            warped = rcell.transform((512, 512), Image.AFFINE, (s, 0, 256 - 256 * s + tx, 0, s, 256 - 256 * s + ty), resample=Image.BILINEAR)
            a = np.asarray(warped.resize((512 // k, 512 // k))).astype(np.float32) / 255
            return np.abs(a[brow // k : 500 // k, 6 // k : 506 // k] - small[k][brow // k : 500 // k, 6 // k : 506 // k]).mean()

        fit = min(((score(s, tx, ty, 4), s, tx, ty) for s in np.arange(0.70, 1.101, 0.04) for ty in range(-64, 65, 8) for tx in range(-48, 49, 8)), key=lambda r: r[0])
        for ds, dt in ((0.02, 4), (0.01, 2), (0.005, 1)):
            _, s0, x0, y0 = fit
            fit = min(((score(s, tx, ty, 1), s, tx, ty) for s in (s0 - ds, s0, s0 + ds) for ty in (y0 - dt, y0, y0 + dt) for tx in (x0 - dt, x0, x0 + dt)), key=lambda r: r[0])
        out["ref_xform"][view] = [round(float(fit[1]), 3), int(fit[2]), int(fit[3])]
        # lighting: studio pixel over atlas texel on the front of the face
        if view in ("front", "three"):
            for idx, uvs in faces:
                if not all(0.0 < v[i, 0] < plane["front"] - 0.02 for i in idx):
                    continue
                c = base[idx].mean(0) + out["offset"][view]
                u, vv = np.array(uvs).mean(0)
                texel = atlas[int((1 - vv % 1.0) * atlas.shape[0]) % atlas.shape[0], int((u % 1.0) * atlas.shape[1])]
                if not green[int(c[1]), int(c[0])]:
                    ratios.append(studio[int(c[1]), int(c[0])] / np.maximum(texel, 0.03))
        print(f"{skin} {view}: offset {out['offset'][view]} (iou {best[0]:.3f}), reference {out['ref_xform'][view]} (diff {fit[0]:.3f})")
    out["light"] = [round(float(x), 3) for x in np.median(np.array(ratios), 0)]
    return out


def prep(skins: list[int]) -> None:
    data = json.loads(PREP.read_text()) if PREP.is_file() else {}
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for skin in skins:
            name, tex = extract(skin, work)
            blender("dump", str(work), name, tex, str(work / f"{name}.json"), str(work / f"{name}-atlas.png"))
            data[str(skin)] = register(skin, json.loads((work / f"{name}.json").read_text()), work / f"{name}-atlas.png")
    PREP.write_text(json.dumps({k: data[k] for k in sorted(data, key=int)}, indent=1) + "\n", encoding="ascii")


def build(skins: list[int]) -> None:
    calib, preps = json.loads(CALIB.read_text()), json.loads(PREP.read_text())
    files = MODELS / "files"
    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for skin in skins:
            name, tex = extract(skin, work)
            p = preps[str(skin)]
            job = dict(ped_dir=str(work), name=name, tex=tex, out_dir=str(work), plane=PLANES[skin], listed_blocks=listed_blocks(skin), bone_matrix=calib[str(skin)], offset=p["offset"], ref_xform=p["ref_xform"], light=p["light"], reference=str(REFS / f"{skin}.jpg"))
            (work / "job.json").write_text(json.dumps(job), encoding="utf8")
            print(next(line for line in blender("build", str(work / "job.json")).splitlines() if line.startswith("REBUILT")))
            for ext in ("dff", "txd"):
                shutil.copy(work / f"{name}_nohat.{ext}", files / f"{name}_nohat.{ext}")
    peds = read_peds(MODELS / "peds.lua")
    txds = {d for d in peds.values() if (files / f"{d}.txd").is_file()}
    (MODELS / "peds.lua").write_text(render_peds(peds, txds), encoding="ascii", newline="\n")
    write_meta(MODELS)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("action", choices=("calibrate", "prep", "build"))
    ap.add_argument("skins", nargs="*", type=int)
    ap.add_argument("--player", default="VIRUXE")
    args = ap.parse_args(argv)
    skins = args.skins or sorted(PLANES)
    unknown = [s for s in skins if s not in PLANES]
    if args.action != "calibrate" and unknown:
        print(f"no cut plane for {unknown}: add them to PLANES", file=sys.stderr)
        return 2
    {"calibrate": lambda: calibrate(args.player), "prep": lambda: prep(skins), "build": lambda: build(skins)}[args.action]()
    return 0


if __name__ == "__main__":
    sys.exit(main())
