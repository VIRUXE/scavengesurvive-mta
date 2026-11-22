# Vehicle wheel HD sources

`python -m tools.vehicle_wheel_hd build` builds the vehicle pack only. It does not
change the game install, the item wheels, geometry, UVs or vehicle registrations.
Requires Python 3 with Pillow (DDS/DXT support), NumPy and `stylua` on PATH.

## Inventory and provenance

`inventory.json` records **192 vehicle models and all 17 upgrade wheels**, with
513 model/texture bindings and **114 distinct decoded pixel contents**. All 212
vanilla vehicle definitions were examined; the other 20 models have no wheel
atomic (boats and aircraft without wheels). Wheeled aircraft, trains, trailers,
RC vehicles, bicycles and motorcycles are included as well as cars and trucks.
There are no unresolved material textures.

The inventory follows atomic frame ancestry, rather than searching texture names
in DFF strings. For upgrades every atomic is examined. Only material slots used
by triangles are counted. Each atomic records its frame ancestry, geometry,
material slots, per-material UV bounds and untextured slots. Untextured metal is
geometry/material colour, not a missing texture. Sources resolve first in the
model's own TXD, then `models/generic/vehicle.txd`, then `wheels.txd`.

Content identity is SHA-256 of width and height as little-endian uint32 values
followed by decoded top-level RGBA bytes. Every native name and dictionary is
retained, including aliases with identical pixels and same-name differences:
`glendale92wheel64` has two different pixel contents. Models never share a rim
merely because its name matches.

`originals/` holds decoded vanilla evidence from `D:/Games/gtasa/models/gta3.img`
or `models/generic/vehicle.txd`, not enhanced source duplicates. There are **112
new image-generation repaints**, using registered 4x4 sheets of actual wheel UV
regions. `batches.json` records exact placements; `batches/` retains reference and
generated sheets; `prompts.json` records the built-in image-generation prompt.
No substitute vanilla texture was used. The two shared reviewed HD sources are
referenced directly, without copying their PNGs:

- `../wheel_hd/wheel/vehicletyres128.png`: 64x128 to 256x512.
- `../wheel_hd/wheel/vehiclegeneric256.png`: 256x256 to 1024x1024.

Each new `repaints/<content>.png` has exactly four times the native width and
height. Only the wheel's sampled rectangle is repainted; unused atlas regions
retain the original layout. Native alpha is retained. Magenta review borders
are removed before resampling by extending adjacent painted pixels, preventing
registration colours from entering compressed textures or mips.

## Runtime and budget

`build.json` records input/output SHA-256, DDS dimensions, format, mip payload
size, sampled UV region and sampler transform. Output: **103 DXT1 and 11 DXT5
files**, complete chains through 1x1, **6,583,416 bytes (6.28 MiB)**. Each source
content produces one DDS and each client creates its texture/shader once on
first use. Scripts and mapping add about 50 KiB to the download.

To stay below 8 MiB, 45 atlas regions are cropped in the DDS, padded to powers of
two with extended edge texels, never stretched. The crop shader remaps existing
UVs and retains the original texture outside the sampled rectangle. It inherits
GTA vertex processing and diffuse lighting. Full textures use stage-zero fixed
function replacement, retaining GTA's material render states. Hardware without
ps_2_0 retains vanilla for cropped atlases.

Only `vehicletyres128` is applied without a target element; the shader itself is
restricted to vehicle rendering. Every other texture name is applied with the
owning vehicle as `targetElement`. Bindings update on initial enumeration,
stream-in/out, model change and destruction. MTA has no client upgrade-change
event, so only streamed vehicles are checked once a second for changes in wheel
slot 12. Upgrades add their material mappings to the vehicle's own mapping;
removal/model changes remove old bindings. Stop removes bindings before freeing
the shared shader/texture elements.

API spellings/signatures were checked against the official MTA wiki, notably
[dxCreateShader](https://wiki.multitheftauto.com/wiki/DxCreateShader),
[dxCreateTexture](https://wiki.multitheftauto.com/wiki/DxCreateTexture),
[dxSetShaderValue](https://wiki.multitheftauto.com/wiki/DxSetShaderValue),
[engineApplyShaderToWorldTexture](https://wiki.multitheftauto.com/wiki/EngineApplyShaderToWorldTexture),
[engineRemoveShaderFromWorldTexture](https://wiki.multitheftauto.com/wiki/EngineRemoveShaderFromWorldTexture),
[getVehicleUpgradeOnSlot](https://wiki.multitheftauto.com/wiki/GetVehicleUpgradeOnSlot)
and the element streaming/model/destroy and resource start/stop events.

## Rebuild and review

```powershell
python -m tools.vehicle_wheel_hd build
python -m tools.vehicle_wheel_hd audit
python -m tools.vehicle_wheel_hd render
```

The build is offline and deterministic from the checked-in PNGs. It writes DDS,
the return-table module `vehicles/shared/data/wheel_hd.lua`, `build.json` and its
marked block in `vehicles/meta.xml`. The audit verifies 4x input dimensions,
hashes, DDS headers, every mip byte count, complete file/meta coverage and budget.

To reproduce extraction with the game and installed DragonFF:

```powershell
python -m tools.vehicle_wheel_hd inventory --gta D:/Games/gtasa
python -m tools.vehicle_wheel_hd prep
# Reassemble reviewed generated sheets, without contacting image generation:
1..7 | ForEach-Object {
    $batch = "tools/data/vehicle_wheel_hd/batches/batch_{0:00}_generated.png" -f $_
    # accept expects a distinct input path so its archived original is never overwritten
    $copy = "$env:TEMP/vehicle-wheel-batch-$_.png"
    Copy-Item -LiteralPath $batch -Destination $copy
    python -m tools.vehicle_wheel_hd accept --batch $_ --image $copy
}
python -m tools.vehicle_wheel_hd build
```

Blender 5.3 + DragonFF reads the actual DFF wheel atomics; its before/after
materials use decoded original TXD pixels and decoded **shipping DDS** pixels.
Identical cameras and neutral Workbench shading isolate texture/UV changes.
These previews do not simulate MTA's lighting or reflections. The render
manifest records DFF, geometry, DDS/recipe hashes, triangles, textures and Blender
version. Render caching invalidates when the recipe or DDS content changes.

Review output lives in
`C:/Users/flavi/AppData/Local/Temp/codex_vehicle_wheels/`: original contact sheets,
seven repaint review sheets, 218 wheel-geometry before/after pairs in 19 contact
sheets, per-wheel PNGs, render manifest/log, and live MTA screenshots. Every one
of the 114 texture contents is represented by the rendered geometry. Original,
batch and final comparisons were posted to Discord `#tmp` (1566505956404367480).
