# Wheel texture sources

The PNGs here are the reviewed source assets for `python -m tools.wheel_hd build`.
The build needs Python with Pillow DDS/BC1 support (made with Pillow 12.2.0). It
writes only `prop_models/files/wheel.txd` and `stock_wheels.txd`. Every native is
opaque D3D9 DXT1/565, repeat addressing, trilinear filtering, with a complete mip
chain down to 1x1. Smaller-than-4x4 levels occupy one complete BC1 block.

## Provenance

All visible repaints were made with the built-in image-generation tool from the
existing textures, rather than enlarged vanilla replacements. Final PNGs are
stored here so rebuilding does not need image generation or the game install.
Names, UV layouts, wheel designs and rim-to-sidewall radii remain compatible with
the existing DFFs. No geometry, UVs, collisions, item rows or model ids changed.

| PNGs | Original source | Original -> source PNG |
| --- | --- | --- |
| `stock_wheels/whee_rim64.png` | `models/generic/wheels.txd`, `whee_rim64` | 64x64 -> 256x256 |
| `stock_wheels/wheel_<style>64.png` (nine) | same TXD, same native names | 64x64 -> 256x256 |
| `stock_wheels/tyre64a.png` | same TXD, `tyre64a` | 64x64 -> 256x256 |
| `wheel/vehicletyres128.png` | `models/generic/vehicle.txd`, `vehicletyres128`, as carried in the existing wheel TXD | 64x128 -> 256x512 |
| `wheel/vehiclegeneric256.png` | same vehicle TXD, `vehiclegeneric256` | 256x256 -> 1024x1024 |
| `wheel/vehiclespecdot64.png` | original wheel TXD's plain environment/specular mask | 256x256 unchanged; compression and mipmaps only |

The specular mask is an intentional smooth black/white disc, not a blurry surface
texture. Inventing detail or increasing its resolution would add no surface
detail to the wheel.

The ten face repaints were generated as a registered 5x2 sheet, then split and
resampled to 256px with Lanczos. Row one: rim, truck, sport, smallcar, saloon.
Row two: offroad, lightvan, lighttruck, classic, alloy. Tread and the two generic
atlases were generated separately and resampled to their target dimensions.
`prompts.json` records the instructions used. The final PNGs, not the model
service's output dimensions, define the build inputs.

## Vanilla comparison

GTA Scout's existing `output/sa-source` snapshot located the local game at
`D:/Games/gtasa` and reported no source failures. Searching its texture metadata
for tyre/tire/wheel gave 265 occurrences, decoded and deduplicated to 140 pixel
images. Four contact sheets were inspected visually. These included vehicle
and cutscene wheels, garage equipment, trailer/lorry wheels, junk tyres and
tyre stacks. None supplied sharper matching layouts for these eleven stock
natives or the generic wheel's atlases. In particular:

- `csgaragetrolley/CJ_GENER_WHEEL` and `ce_loadbay/sw_wheel1` have relatively
  readable 128px complete wheels, but incompatible rim designs and proportions.
- Vehicle TXDs generally pack a low-resolution quarter-wheel with other parts.
- `junkpiles/CJ_tyre`, `cj_ammo/CJ_WHEEL1`, `hubprops2_sfe/tyretread_64H` and
  `genintgarage2a/kb_tyre` were visually checked; their layouts, appearance or
  resolution did not improve this set while preserving its designs.

No candidate was accepted based on its filename. No additional vanilla texture
was substituted. The discovery images and decoded game originals remain in the
temporary review directory, outside the repository.

## Rebuilding and review

```powershell
python -m tools.wheel_hd build
python -m tools.wheel_hd audit
python -m tools.wheel_hd render --phase after --output $env:TEMP/codex_tyres
python -m tools.wheel_hd compare --output $env:TEMP/codex_tyres
```

For a fresh before/after run, run `render --phase before` before replacing the
TXDs. `--files DIR` can instead read a saved original set of DFFs and TXDs, and
`--assets wheel,wheel_truck` limits an iteration to selected meshes. The existing
stock-wheel and generic-wheel builders reapply these HD sources when rebuilding
their dictionaries. They were not run for this texture-only update.

Blender 5.3.0 and the installed DragonFF import the actual compressed TXDs and
DFFs for the comparisons. Each model has an identical-framing face view and
lower tread view, before and after. These are neutral Workbench texture previews;
they do not simulate MTA's vertex-colour lighting multiplier. Per-phase manifests
record model/TXD hashes, Blender version, triangle counts and missing textures.

The 2026-11-22 review files are in
`C:/Users/flavi/AppData/Local/Temp/codex_tyres/`:

- `compare_wheel.png`: generic wheel.
- `compare_wheel_<style>.png`: ten inflated wheels.
- `compare_wheel_<style>_flat.png`: ten flat wheels.
- `before/` and `after/`: the individual 720px face/tread renders and manifests.
- `registration_review.png`: face textures with mesh rim-radius overlays.
- `vanilla_sheet_1.png` through `vanilla_sheet_4.png`: rejected vanilla candidates.

| Dictionary | Before (bytes) | After (bytes) |
| --- | ---: | ---: |
| `stock_wheels.txd` | 181,672 | 482,544 |
| `wheel.txd` | 557,480 | 830,700 |

All 21 meshes rendered with no missing textures. The existing UVs aligned with
the repaints, including the depressed flat-tyre sidewalls, so no DFF rebuild was
needed. Face edges, holes, moulded rings, lettering and tread cuts are visibly
clearer. The generic wheel retains its original polygonal silhouette and its
original shared tread/shoulder mapping.
