"""Reference images for the hatless twins' bare heads (#89): each headgear skin shot in the dev studio, then edited
bare-headed by an image model.

    python -m tools.hatless_refs shoot [--player VIRUXE] [skin ...]   # studio shots through server-config/rcon.ps1
    python -m tools.hatless_refs shoot-top [skin ...]                 # the two high cameras, for the crown
    python -m tools.hatless_refs grid-top [skin ...]                  # <skin>-studio-top.jpg: top, top-back, front, side
    POLLINATIONS_KEY=sk_... python -m tools.hatless_refs edit [skin ...]  # 2x2 grids -> gpt-image-2 edits

`shoot` puts the player's client on each original skin (client-side `setElementModel`, never synced) and has the
server take `takePlayerScreenShot` from four head-height cameras: front, three-quarter, side, back. The shots land in
`dev/screenshots/orig-<skin>-<view>.jpg` (git-ignored). Per camera one client chunk cycles the skins every 3 s and one
server chunk shoots 1.5 s into each step, so the whole set is eight rcon calls, well clear of the HTTP flood guard.

`edit` pastes a skin's four views into one 2x2 grid (`docs/images/hatless-refs/<skin>-studio.jpg`) and sends it to
Pollinations' `gpt-image-2` edit endpoint with the row of HATLESS below; editing the four views in one call keeps the
hair consistent across them. The result is `docs/images/hatless-refs/<skin>.jpg`; skins that already have one are
skipped. Each call costs about 0.031 Pollen (Pollinations' prepaid credit): the free balance covers a few images.
"""
import argparse
import base64
import io
import os
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from tools import hatless_proj as hp

ROOT = Path(__file__).resolve().parents[1]
SHOTS = ROOT / "resources" / "[scavengesurvive]" / "dev" / "screenshots"
OUT = ROOT / "docs" / "images" / "hatless-refs"
RCON = ROOT / "server-config" / "rcon.ps1"
ENDPOINT = "https://gen.pollinations.ai/v1/images/edits"
VIEWS = hp.GRIDS["level"]  # grid order: top left, top right, bottom left, bottom right
# studio camera per view ("yaw dist height lookZ") and the grids' crops: tools/hatless_proj.py, which the rebuild
# projects through. The crown is the part the four level views constrain least: a second grid looks down on it,
# keeping front and side as anchors (`<skin>-studio-top.jpg`, edited to `<skin>-top.jpg`)
CAMERAS = {view: " ".join(str(x) for x in cam) for view, cam in hp.CAMERAS.items()}
TOP_VIEWS = hp.GRIDS["top"]
CROP_TOP = hp.CROP_TOP

# skin -> (who, headgear to remove, what the bare head shows)
HATLESS: dict[int, tuple[str, str, str]] = {
    2: ("a fast-food worker", "white bucket hat", "messy dirty-blond mop of hair"),
    4: ("a police motorcycle officer", "white police motorcycle helmet and its chin strap", "short black hair; keep the sunglasses"),
    35: ("an older gardener", "straw bucket hat", "short greying black hair of an older man"),
    36: ("a golfer", "blue baseball cap", "short dark brown hair"),
    37: ("a golfer", "red baseball cap", "short dark brown hair"),
    61: ("an airline pilot", "pilot's peaked cap", "short neatly combed dark brown hair"),
    119: ("a police motorcycle officer", "two-tone police helmet and its chin strap", "short black hair; keep the sunglasses"),
    155: ("a pizza delivery man", "pizza delivery cap", "short brown hair"),
    161: ("an old farmer", "brown cowboy hat", "thin messy greying brown hair of an older farmer"),
    205: ("a burger-shop waitress", "giant burger hat", "her brown bob haircut"),
    247: ("a biker", "black bandana skull cap", "long brown hair slicked back into his ponytail"),
    248: ("a biker", "red headband", "his long blond hair"),
    254: ("a biker", "black bandana skull cap", "long brown hair slicked back into his ponytail"),
    277: ("a firefighter", "yellow firefighter helmet and goggles", "short dark brown hair"),
    278: ("a firefighter", "black firefighter helmet and goggles", "short black hair"),
    279: ("a firefighter", "black firefighter helmet and goggles", "short dark brown hair"),
    283: ("a sheriff's deputy", "cowboy hat", "short neatly combed light brown hair matching his sideburns"),
    284: ("a police motorcycle officer", "white police motorcycle helmet and its chin strap", "short black hair; keep the sunglasses"),
    285: ("a SWAT officer", "tactical helmet and goggles", "the black balaclava covering his whole head"),
    287: ("a soldier", "camouflage cap", "a short military buzz cut, brown"),
    288: ("a sheriff's deputy", "cowboy hat", "short neatly combed light brown hair"),
    311: ("Big Smoke", "black fedora hat", "short black hair; keep the glasses"),
}


def prompt(skin: int) -> str:
    who, hat, bare = HATLESS[skin]
    return f"This image shows one low-poly GTA San Andreas character ({who}) on a green screen from four angles in a 2x2 grid: top left front, top right three-quarter, bottom left side profile, bottom right back. Edit it: remove the {hat} from every view and show the character bare-headed with {bare}, on an anatomically correct skull (cranium rising above the forehead and extending back past the neck). Keep everything else identical: the four views in the same grid positions and scale, the same face, ears, neck, clothes, green background and low-poly game texture style."


def rcon(*args: str) -> None:
    subprocess.run(["pwsh", "-NoProfile", str(RCON), *args], check=True, capture_output=True)


def shoot(player: str, skins: list[int], views=VIEWS) -> None:
    lst = ",".join(str(s) for s in skins)
    n = len(skins)
    for view in views:
        cam = CAMERAS[view]
        rcon("studio", player, *cam.split())
        time.sleep(2.5)
        rcon("clua", player, f"local L={{{lst}}} local i=0 local function step() i=i+1 if L[i] then setElementModel(localPlayer, L[i]) end end step() setTimer(step, 3000, {n})")
        shot = f"local function shot() i=i+1 takePlayerScreenShot(p, 1280, 960, 'orig-'..L[i]..'-{view}', 90, 5000000, 50000) end"
        rcon("lua", f"local p=getPlayerFromName('{player}') local L={{{lst}}} local i=0 {shot} setTimer(function() shot() if {n} > 1 then setTimer(shot, 3000, {n - 1}) end end, 1500, 1)")
        time.sleep(3 * n + 4)
        print(f"{view}: {n} shots")


def grid(skin: int, views=VIEWS):
    from PIL import Image

    g = Image.new("RGB", (1024, 1024))
    for i, view in enumerate(views):
        im = Image.open(SHOTS / f"orig-{skin}-{view}.jpg")
        w, top = im.size[0], CROP_TOP.get(view, 0)
        g.paste(im.crop((w // 2 - 300, top, w // 2 + 300, top + 600)).resize((512, 512)), ((i % 2) * 512, (i // 2) * 512))
    return g


def prompt_top(skin: int) -> str:
    who, hat, bare = HATLESS[skin]
    return f"This image shows one low-poly GTA San Andreas character ({who}) on a green screen from four angles in a 2x2 grid: top left seen from above (looking down on the top of the head), top right from behind and above, bottom left front, bottom right side profile. Edit it: remove the {hat} from every view and show the character bare-headed with {bare}, on an anatomically correct skull; in the two views from above the round crown of the head and the hair on top must be clearly visible. Keep everything else identical: the four views in the same grid positions and scale, the same face, ears, neck, shoulders, green background and low-poly game texture style."


def edit(skin: int, key: str) -> str:
    import requests
    from PIL import Image

    dst = OUT / f"{skin}.jpg"
    if dst.exists():
        return f"{skin}: exists"
    g = grid(skin)
    g.save(OUT / f"{skin}-studio.jpg", quality=88)
    buf = io.BytesIO()
    g.save(buf, "PNG")
    headers = {"Authorization": f"Bearer {key}"}
    form = {"model": "gpt-image-2", "prompt": prompt(skin), "size": "1024x1024"}
    for _ in range(3):
        r = requests.post(ENDPOINT, headers=headers, data=form, files={"image": ("grid.png", buf.getvalue(), "image/png")}, timeout=600)
        if r.status_code == 200:
            Image.open(io.BytesIO(base64.b64decode(r.json()["data"][0]["b64_json"]))).convert("RGB").save(dst, quality=88)
            return f"{skin}: ok"
        if r.status_code == 402:
            return f"{skin}: out of Pollen ({r.json()['error']['message'][:80]})"
        time.sleep(15)
    return f"{skin}: failed, HTTP {r.status_code} {r.text[:200]}"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("action", choices=("shoot", "shoot-top", "grid-top", "edit"))
    ap.add_argument("skins", nargs="*", type=int)
    ap.add_argument("--player", default="VIRUXE")
    args = ap.parse_args(argv)
    skins = args.skins or list(HATLESS)
    if args.action in ("shoot", "shoot-top"):
        shoot(args.player, skins, VIEWS if args.action == "shoot" else ("top", "topback"))
        return 0
    if args.action == "grid-top":
        for s in skins:
            grid(s, TOP_VIEWS).save(OUT / f"{s}-studio-top.jpg", quality=88)
        return 0
    key = os.environ.get("POLLINATIONS_KEY")
    if not key:
        print("set POLLINATIONS_KEY (a key from enter.pollinations.ai/keys allowed to use gpt-image-2)", file=sys.stderr)
        return 2
    OUT.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(3) as ex:
        for line in ex.map(lambda s: edit(s, key), skins):
            print(line, flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
