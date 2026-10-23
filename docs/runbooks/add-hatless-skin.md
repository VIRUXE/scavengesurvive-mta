# Add a hatless twin for a skin with built-in headgear

Some GTA:SA skins carry their hat, cap or helmet in the mesh (the sheriffs, the army and SWAT men, the
firefighters, the police caps, hard hats, the pizza and burger uniforms, the bikers, ...). A worn hat sits on the
head bone, so the built-in one pokes through it. The fix (#75) is a copy of the skin with that headgear cut
away, which each client shows in place of the real skin while a hat is worn: the server and the database never
see the twin.

## Pieces

- `tools/extract_ped_models.py`: `HEADGEAR` lists the skins. For each it pulls `<name>.dff` from `gta3.img`,
  runs Blender headless with DragonFF (`tools/blender/cut_headgear.py`) and writes
  `resources/[scavengesurvive]/models/files/<name>_nohat.dff`, `models/peds.lua` (base skin -> twin) and
  `models/meta.xml` (both manifests). The twin shares the base skin's TXD, so nothing else is extracted.
- `models/client/main.lua`: loads every twin with `engineRequestModel("ped", base)` on the client, so the ids
  differ per client like the object ids, and exports `hatlessSkin(base)`.
- `items/client/attach.lua`: when a player's hat slot fills, the client calls `setElementModel` on that player
  with the twin; when it empties, with the real skin again. Client-side `setElementModel` is never synced.
  `swapped[player]` keeps the real skin, and every per-skin row (`skins.lua`) is looked up by it. A server-side
  skin change (duty, clothes) arrives through `onClientElementModelChange`, which drops the swap and re-applies
  it for the new skin; the pack reloading or stopping re-applies through `sampModelsChanged`.

## Adding a skin

1. Confirm the clipping in the studio: `rcon.ps1 studio <p> face`, set the skin and wear a hat
   (`lua setElementData(p, "items.hat", "HelmArmy")`), screenshot.
2. Add the skin to `HEADGEAR` in `tools/extract_ped_models.py`: `(dff name, texture name, "auto", 0.045)`. The
   texture name is what `engineGetModelTextureNames(skin)` returns on a client (`rcon.ps1 clua`). `"auto"`
   cuts the faces above the Head bone whose 8x8 texture block reaches further from the head axis than a bare
   skull (0.135 m) or higher than one (0.21 m); `cut_headgear.py` prints the blocks it chose. When that takes too
   much or too little, list the blocks by hand as `"col,row;col,row"` (row 0 at the top of the texture; dump the
   atlas with `engineGetModelTextures` + `dxGetTexturePixels` to see it), or `"*"` for every block when a cap
   shares its blocks with the hair (then everything above the floor goes, which a worn hat covers). The last
   number is how far above the Head bone the cut starts; the bone sits at the chin.
3. `python -m tools.extract_ped_models <skin>` (needs the GTA:SA install from the registry or `--gta`, and
   Blender with the DragonFF add-on, found under Program Files or given with `--blender`). Commit the DFF,
   `peds.lua` and `meta.xml`.
4. `rcon.ps1 rr models`, then `rr items`, and screenshot the skin with a hat on and off. Bare, the twin shows the
   hole GTA leaves under the headgear; that is expected, since it is only ever shown under a hat.

## Bare heads (remodelled skulls)

A twin cut by `cut_headgear.py` is hat-only: GTA models no skull under a hat, so bare it shows a flat fill or a
hole. `tools/blender/remodel_head.py` builds a bare head instead: it deletes the headgear by height, texel darkness
or texture block (`HEADS` holds the rule per skin, set by eye), welds the cut rim and raises a skull over it, a
thin band that continues the face skin and rings of hair textured from the darkest patch of the ped's own atlas,
all weighted to the Head bone. Run it in Blender (`blender --python tools/blender/remodel_head.py -- <ped dir>
<out dir> [skin ...]`, the ped dir holding `<name>.dff` and `<name>.txd` from `gta3.img`) and judge the result in
the viewport and the studio (force the twin bare with `clua <p> setElementModel(localPlayer,
exports.models:hatlessSkin(<skin>))`). All 24 headgear skins now have remodelled bare heads with
anatomical cranial hair domes: police and sheriffs (4, 119, 284, 265, 283, 288), military and SWAT (287, 285),
firefighters (277-279), services and civilian (61, 35, 268, 155, 205, 161, 36, 37, 2, 311), and bikers (247, 248, 254).
Maccer 2 carries custom hair texture UV sampling and a contoured hairline matching his dirty-blond mop.

Two facts cost a long detour: a DFF stores one UV per vertex, so a hairline vertex needs a skin copy and a hair
copy; and the exporter is fine with new vertices, so when a head looks stretched in the game compare the dome's
size with the face, not the file.

## Caveats

- Never restart `models` while a client is still downloading (docs/runbooks/start-stop-restart.md).
- A twin cut with `"auto"` can take some hair with it: harmless under a hat, but check the brow line and the
  ears, which a small hat (beanie, cap) does not cover.
- Skins whose headgear is the whole head (the chicken suit 167) cannot be fixed this way; leave them out.
