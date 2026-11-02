# Bobcat salvage parts

Twelve standalone items, model ids 20210–20221: tailgate, left and right doors, hood, front and rear bumpers, each Good/Bad. Geometry is the original Bobcat ok/dam component, including broken glass on damaged doors. UVs and dimensions are preserved. Paint uses the stock Bobcat pairing 96/25 (grey and charcoal), with vehicle paint markers converted to fixed material colours. Original texture names, texture alpha and material alpha are retained; vehicle-only reflection/specular plugins are removed for standalone objects. Preview shaders multiply texture colours by material tints and preserve glass/decal alpha; origins are centred at ground level. Each has a box collision, combined Bobcat/vehicle TXD and a two-handed carry configuration. All twelve variants spawn at industrial world loot points (`world_industrial`), with weight 0.6 for good parts and 1.2 for bad parts. They do not spawn inside vehicle containers.

Hold a part, stand next to its matching component on an unlocked Bobcat (422), turn the engine off and press interact (F). A four-second installation uses the Repair skill time modifier. Moving over 0.8 m, changing the held item, entering a vehicle, leaving the correct side, a moving Bobcat or death cancels the action. One installer per vehicle is allowed. Good parts restore an intact component; bad parts replace a missing component with a damaged one. Intact components and non-improving replacements refuse without consuming the part. Only the matching component changes; engine health is untouched.

`bobcat_part_install` commits the held-item consumption and saved damage together. Ownership, item type, positive hitpoints, Bobcat model and unlocked state are checked again in the transaction. All panels, six doors (including hood/tailgate), lights and wheels now persist through regular vehicle flushes. Installed components use the Bobcat’s native geometry and vehicle paint.

`tools/bobcat_parts.py` is the item/model manifest. `python3 -m tools.convert items` regenerates item definitions and the database seed. `tools/make_props.py` preserves their model registrations.

Use GTA Scout's `prepare-asset-catalog-views.mjs` with a local model record for 422 (bobcat/bobcat, vehicles.ide); the stock object catalogue omits vehicles. Prepare a second record using bobcat.dff and vehicle.txd for shared texture preview decoding. Then:

```
blender -b -t 2 --python tools/build_bobcat_parts.py -- SCOUT_INPUT GTA_DIRECTORY
blender -b -t 6 --python tools/render_bobcat_parts.py -- SCOUT_INPUT SHARED_INPUT
```

Editable comparison: `docs/bobcat_parts.blend`. Renders: `docs/images/bobcat_parts_1.png` and `_2.png`. The updated data, loot, vehicles, HUD and model resources have been loaded. Live database checks covered all twelve component/condition mappings, consumption, refusal to downgrade an intact panel, and regular damage persistence. Player-operated carry and installation animations have not been visually checked.
