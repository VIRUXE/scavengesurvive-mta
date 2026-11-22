# Armour vest texture

Special Armour uses the native GTA:SA model 1242 with the `gun_armour.png`
atlas in this folder. The built-in image tool repainted the original GTA
Scout atlas in slate-blue cloth with stitched seams and dark webbing, keeping
the UV layout. The asset was resampled to 512×512. To rebuild its TXD from the
repository root:

```powershell
python -c "from pathlib import Path; from PIL import Image; from tools.make_vending import write_txd; from tools.wheel_hd import native_dxt1; write_txd(Path('resources/[scavengesurvive]/prop_models/files/special_armour.txd'), [native_dxt1('gun_armour', Image.open('tools/data/armour_texture/gun_armour.png'))])"
```

The rest of this document describes the regular Armour vest.

`swat.png` is the reviewed 512x1024 diffuse atlas for SA-MP armour vest 19515
(`swatagrey.dff`). Rebuild its dedicated dictionary with:

```powershell
python -m tools.armour_texture
```

The source was repainted with the built-in image-generation tool from the
existing `samp_models/files/swatgrey.txd` texture `swat` (128x256). The repaint
keeps the atlas layout, neutral charcoal palette and existing panel positions,
adding ballistic nylon weave, stitching, reinforced binding, velcro and restrained
wear. The generated atlas was resampled to 512x1024 with Lanczos for the game.
The generation tool does not expose a model selector.

The vest's original geometry, UVs, collision, model id and wear offsets are kept.
Its UVs use the upper 56% of the atlas, including two small islands at the right.
The lower skin/boot regions are unused by the vest. The SWAT helmet (19514) still
uses the original `swatgrey.txd`; only the vest loads `swatagrey.txd`.

The builder writes one opaque D3D9 BC1 texture named `swat`, with trilinear
filtering, repeat addressing and all 11 mip levels through 1x1. It reuses the
existing dictionary writer and BC1 encoder. Pillow with DDS writing is required.
`tools/extract_samp_models.py` preserves the dedicated dictionary when rebuilding
the model pack. No game installation or image generation is needed to rebuild.

## Repaint instructions

Edit the existing GTA San Andreas SWAT atlas into a sharp HD diffuse texture.
Preserve every UV island, outline, boundary, panel, strap and black gutter in
exactly the same normalized position. Keep the 1:2 aspect ratio. Improve the
armour regions with matte charcoal-grey ballistic nylon/Cordura, fine tightly
woven cloth, crisp double stitching along existing seams, reinforced binding,
subdued velcro and light edge abrasion/dust. Keep the circular neck opening and
horizontal upper straps in place. Preserve the neutral palette and broad values.
Avoid shiny plastic, excessive grunge, dramatic lighting, camouflage, text,
logos, badges, extra pouches, hardware or panels. Keep unused regions structurally
identical. Flat UV texture, soft diffuse illumination, no perspective, object
render, wireframe or annotations.
