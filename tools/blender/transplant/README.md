# Cranium transplant (#89)

The hatless twins' bare heads come from other peds: each twin keeps its own face, ears and neck, and the whole cranium
above a seam is replaced by the cranium of a donor ped from the game (aligned to the face), so every head is a real,
different GTA skull. The hair takes the colour of the skin's hatless reference image (`docs/images/hatless-refs`).
This replaced the ellipsoid and the reference-carved skulls of `tools/hatless_rebuild.py build`, which read as
helmets from most angles.

These scripts run inside a live Blender through the Blender MCP (`execute_blender_code`), not headless: they share
state through `bpy.app.driver_namespace` (`ns`). They reproduce the installed twins byte for byte (checked on 36).

## Run

1. `python tools/blender/transplant/fetch_peds.py <work>`: every ped's DFF and TXD out of `gta3.img` into
   `<work>/peds`, plus `<work>/list.txt`. Takes a minute.
2. In Blender (DragonFF enabled), set `os.environ["SS_HATLESS_WORK"] = <work>`, then exec in order: `session.py`,
   `transplant.py`, `tp_strip.py`, `tp3.py`, `tp_tex.py`, `run.py`, each with globals `{"ns": ns, "bpy": bpy}`.
3. `ns["hatless_build"](skin)` builds the twin in the `work` object; `ns["hatless_review"](skin, "x-")` renders it
   from ten angles, textured and grey, into `<work>/renders` (`python tools/blender/transplant/sheet.py out.png
   tex,grey <work>/renders/x-<skin>` lays them out); `ns["hatless_export"](skin)` writes `<work>/export/<name>_nohat.dff`
   and `.txd`. `ns["hatless_build_all"](do_export=True, tag="x-")` does all of `tools/data/hatless_transplant.json`.
4. Check the exports headless: `blender -b --python review_heads.py -- <prefix> <dff> <base txd> <twin txd>` (the
   TXDs must sit in the DFF's folder) prints `HEALTH open_edges_above_jaw=... nonmanifold=... inward_faces_upper=...`
   and renders the same ten views.
5. Copy the exports to `resources/[scavengesurvive]/models/files/`, restart `models`.

## How a twin is built (`tp3.transplant3`, `tp_tex.texture`)

- **Donor**: `tools/data/hatless_transplant.json` names one per skin, all different. They were first ranked by how
  well the donor's silhouette matches the reference in four views and how closely its face fits the twin's (ICP
  error), then assigned one-to-one (Hungarian); 35, 247, 248, 254, 278, 283 and 311 were then picked by hand from
  the donor heads rendered with textures.
- **Alignment**: `align` fits rotation, per-axis scale (0.85 to 1.2) and translation of the donor head (Head bone
  and its child bones) to points sampled on the twin's face under the old hat (`cut3` strips the hat first).
- **Seam**: a brow plane across the face (`HR.PLANES[skin]["front"]`, lowered under any hat band lying on the skin),
  two vertical temple planes through the cranium centre at `face_az` (62 deg) and a nape plane that tilts down
  towards the back (`nape_side` to `nape_back`). Vertices within `snap_eps` of a plane are snapped onto it, both
  meshes are bisected along the planes, and everything of the twin on the cranium side goes, along with hat faces
  left below it (cut3's block rule) and stray hat islands. The donor is cut on the same planes pushed `gap` (8 mm,
  6 deg) into the cranium, its scalp hidden under a hair shell is dropped, and only its largest piece is kept.
- **Join**: the two cut loops are zipped with a strip of triangles textured from the donor's surface, every hole
  left near the seam is filled, the donor's offset from the twin fades out biharmonically over `blend` (5 cm)
  from the seam, and a narrow band across the brow and temple seams is smoothed (damped thin plate, `band_t`,
  `band_d`, `mu`). Donor vertices take the bone weights of the nearest original vertex.
- **Texture**: the twin's atlas is copied as `<name>_bare`; the donor's texture becomes `<name>_hair`, recoloured
  per texel. Texels the donor painted as skin (two-means split around its forehead colour) take the twin's skin tone
  keeping their shading; texels painted as hair take the hair colour, which is the reference's hair cluster unless
  the config gives `hair_rgb`. The donor's own hairline is kept, a bald crown gets hair, the back of the head is
  hair down to a nape line, a dark run just above the brow seam with skin over it (the donor's eyebrows) turns to
  skin, and a per-position colour correction fades in from the seam. Options: `fabric` (one colour, SWAT 285's
  balaclava), `hair_back` (the bikers, whose long hair below the seam is their own), `deshadow` (lift a hat's baked
  shadow on the kept face), `ref_front` (hairline from the reference; off, it painted hair down to the brows).

## State (2026-10-25)

Installed and committed: the 19 twins of `hatless_transplant.json`. Health per head: at most 10 open edges and 5
non-manifold edges above the jaw.

Known flaws, worst first:

- 277, 278, 279 (firefighters): the kept face still carries the goggle straps painted on the original texture, and
  278/279 show a jagged line where the collar meets the new nape.
- 288: a dark diamond and a vertical streak on the crown, a UV seam of the donor's texture.
- 35, 36, 155: a visible tone step at the brow seam (35 keeps the hat's shadow on its forehead).
- 205: the donor's bob is spiky hair cards (61 faces face inwards).
- 248: faint blond patches above the eyes (the donor's brows, mostly removed).
- 161: the donor's balding pattern shows through the grey.
- No in-game look at the new twins yet; the 3D viewer artifact still shows the old heads.

Not done:

- 4, 119, 284 (helmeted cops with sunglasses) have no rebuilt twin. Their bare-headed duty versions are donors made
  for them (lapd1, sfpd1, lvpd1: same faces); add `PLANES` rows and config rows.
- Headless port: fold `session.py`, `transplant.py`, `tp_strip.py`, `tp3.py`, `tp_tex.py` into a
  `tools/hatless_rebuild.py transplant` action that runs Blender with `-b`, like `build` does, and retire the
  ellipsoid/carving path (`skull`, `build`, `tools/blender/rebuild_head.py`).
