# Fort Defiance: what upstream built, and what gets rebuilt

Companion to [the survey](2026-10-31-fort-defiance-survey.md) (205 rows, 15 clusters, measured against the Rockstar
natives). The goal is to **keep what upstream built and build it correctly from custom models**: same places, same
purpose, nothing poking through the houses. Contact sheets of every cluster from two angles, taken in Ariane with
upstream's rows back in the scene: `docs/images/fort-defiance/inventory/sheet1..4.jpg`.

## What it is

Upstream's "Mad Max fortification built around Grove Street" is not a wall around the cul-de-sac. It is a **rooftop
network**: wooden walkways and ramps link the roofs of the houses around the sand; the roofs carry the defences (sandbag
nests with miniguns, a lab deck, a satellite dish, missiles); the sand itself is a camp (a pole barn with beds under
it, a helipad, a wreck pile, fire barrel, junk, chain-link and mesh fences, a crane light tower).

## Structures

`kit` = rebuilt as a custom model, `keep` = vanilla prop that fits and stays exactly as upstream placed it.

| # | structure | upstream rows (model at x, y, z) | what is wrong | decision |
| ---: | --- | --- | --- | --- |
| A1 | south roof walkways | 3406 `cxref_woodjetty` x4 at 2521,-1688,16.4 · 2513,-1694,14.9 (x2, a duplicate) · 2516,-1693,15.8 | an 8.8 x 2.2 x 8.2 m desert-pier prop laid across roofs; two rows are the same prop on the same spot; the legs go through the roof | **kit**: plank walkway modules (deck, rope rails, posts) sized to each span, one prop per walkway |
| A2 | north roof walkways | 16502 `cn2_jetty1` 15 m at 2504,-1643,14.0 · 11496 `des_wjetty` 7 x 16 m at 2491,-1640,17.4 | 15 and 16 m props tilted 4-8 degrees to hit two rooftops; the ends float or sink | **kit**: the same module, with ramps at the ends |
| A3 | stairs / ramps | 3361 `cxref_woodstair` 8.5 m at 2493,-1652,14.2 · 974 `tall_fence` 6.7 m used as a ramp at 2492,-1639 · 1245 `newramp` 2516,-1681 · 1503 `dyn_ramp` 2519,-1680 · 3260 `oldwoodpanel` 2534,-1670 | stock ramps leaned on roofs by eye | **kit**: stair and ramp modules for the same climbs |
| B | pole barn shelter with beds | 17010 `truth_barn03` 14.6 x 6.7 x 5.7 m at 2484,-1664,12.3 (a barn exterior on bare ground), beds/couch/cooker/bar stools under it | a whole barn mesh with walls clipped away; roof reads as a red slab | **kit**: a pole shelter of the same footprint (roof, posts, braces), furniture under it stays |
| B2 | hut skeleton | 16405 `desn2_hutskel03` 6 x 5 x 4 at 2459,-1667,14.4 | stands in the road verge | **kit** lean-to (already built, 20307) |
| C1 | rooftop lab deck (NE) | 3095 `a51_jetdoor` 9 x 9 m at 2523,-1652,17.3 used as a floor · 3386/3392 a51 racks · 1997 trolleys x3 · 2709 pills x5 · 2977/2976/2044/2057/2059 crates and guns | a 9 m Area 51 door as a floating slab 4.7 m above the roof | **kit**: a plank roof deck on posts at the real roof height; racks and loot props stay |
| C2 | satellite dish (E roof) | 1595 `satdishbig` 9.6 x 8.4 x 10.6 at 2527,-1674,24.2 · 11327 garage door as a roof panel at 2527,-1666,18.7 · 3393 desk | the dish is vanilla and fine; the door "panel" and its mount are not | **keep** the dish, **kit** a mount and a roof hatch |
| C3 | sandbag nests (N roof) | 2060 `CJ_SANDBAG` x10, 2061 shell boxes x4, 2985 `minigun_base` x2, 2977 crates | 1.2 m bags placed one by one | **kit**: sandbag run / nest modules; minigun bases and crates stay |
| C4 | SW roof with missiles | 3790/3793/3795 missiles, 2033/2034 sawn-offs, 2064 field gun, 1636 rcbomb x5, 1672 gas grenades, 1449 crate | props on a roof | **keep** (small props sitting on a surface) once the roof surface is verified in Ariane |
| D1 | chain-link perimeter | 16370 `by_fuelfence` 32 x 33 m at 2466,-1672,14.0 · 11474 `des_swtfence2` x2 · 4100 `meshfence1` 2462,-1674 · 8167 `apgate1` gate 2469,-1679 · DYN_MESH 1413/1447/1468 | vanilla fences, no protrusion found | **keep** |
| D2 | crane light towers | 8879 `vgsEcnstrct08` at 2506,-1664 · 8877 `vgsEcnstrct10` at 2455,-1674, 12 m yellow lattice | vanilla, stands on the sand | **keep** |
| D3 | camp on the sand | 13591 `kickcar28` wreck pile 2490,-1675 · 3928 helipad · 849-854 rubble · 1362 fire barrel · 1676 pump · 1342 noodle cart · 7090 flag · bins, bags, boxes | ground-level vanilla props | **keep** |
| D4 | roadblock trailer | 3569 `lasntrk3` 3.6 x 17.7 x 5.1 at 2462,-1655,14.6 | sits across the road mouth | **keep** (it is the road-side gate), moved only if it blocks the entry |
| E | furniture and loot in the houses | beds, TVs, couches, bar props, ammo, guns, toilets, outhouses (the 111-row west cluster and the rest) | none: these are furnishings | **keep** |

## Rebuild list (custom models)

1. Walkway module(s): deck + rope rails + posts, with ramp and stair variants. Replaces A1, A2, A3 (12 rows).
2. Pole shelter (B) and lean-to (B2), 2 rows.
3. Roof deck (C1) and a dish mount / hatch (C2), 3 rows.
4. Sandbag run / nest (C3), ~10 rows.

About **30 of the 205 rows** are replaced by custom models; the rest stay as placed. The kit that exists (walls, gate,
tower, lean-to, barricade; ids 20301-20308) is reused where it fits: the lean-to for B2, the barricade for sandbag
nests; the ring layout is not used.

## Open measurements before modelling

- Every roof height and edge the walkways meet (Ariane `raycast_segment` per span).
- Whether the minigun / missile props sit on a roof or float (the survey's `floats` says cluster 13 floats 4.7 m).
- Which duplicate rows to drop (3406 appears twice at the same position).

## Measured spans

From [the spans report](2026-10-31-fort-defiance-spans.md) (`python -m tools.fort_spans`: the first surface under each
structure's long axis every 0.5 m, looking past the fort's own props). Heights are world z; the cul-de-sac ground is 12.5.

| walkway | from | to | what the prop does today |
| --- | --- | --- | --- |
| south roof, 3406 at 2513.4,-1694.4 (two identical rows) and at 2516.4,-1692.8 | `lshouse1` ridge 16.1 → 17.4 over 8.8 m | same roof | a boardwalk lying along the south house's pitched roof; the prop is 8 m tall, so its legs run through the roof down to z 8.8 |
| south bridge, 3406 at 2520.9,-1687.7 | `lshouse1` roof 17.2 (x 2519-2521) | `sweetshou1` roof 18.5 (x 2522), over 2.4 m of ground at 12.6 | a real bridge: house roof to the next house's roof, ~5 m up |
| north bridge, 16502 at 2504.1,-1643.0 | `lshouse3` roof 17.5 (7 m) | `lshouse1` roof 16.8-17.1, over a 7.4 m gap of grass at 12.5 | a 15 m bridge, 4° tilt; the right shape, wrong prop |
| north ramp, 11496 at 2491.3,-1640.0 | ground 12.5 at y -1647.6 | rises to 19.3 at y -1631.8, no roof under its axis | a 16 m ramp up to the minigun nest on the north roof at 2493.4,-1632.7 |
| stairs, 3361 at 2492.7,-1652.4 | ground 12.5 at y -1647.4 | 17.7 at y -1655.9 | 8.4 m stairs up to the same roof from the cul-de-sac |
| east ramps, 1245 at 2515.7,-1680.7 and 1503 at 2519.0,-1679.6 | sidewalk 12.5 → 13.7 | `sweetshou1` roof 18.4 | two stacked stock ramps climbing 6 m in 4 m |
| east plank, 11327 at 2527.2,-1666.0 | ground 14.2 | `lshouse3` roof 18.2-18.7 over 10 m | a garage door laid as a ramp to the east roof |
| ramp, 974 at 2492.3,-1639.2 (turned 91°) | grass 12.5 | `lshouse3` roof 16.3-16.8 | a fence panel used as a 5.6 m ramp |

Other findings:

- **Lab deck, 3095 `a51_jetdoor`** at 2523.1,-1651.9, z 17.3: a 9 x 9 m door with nothing under it but ground at 13.1, so it
  floats 4.2 m up on air; it needs posts or it sits on the house roof it was meant for.
- **Minigun base 2985** at 2493.4,-1632.7, z 18.6: over the `lshouse3` roof at 16.3 (2.3 m above it) and half off its edge.
  The other one at 2537.4,-1682.1 (z 18.9) sits right on the `sweetshou1` roof at 18.9.
- **Satellite dish 1595** at 2526.5,-1673.5, z 24.2 (prop base 18.9): the base is on the `sweetshou1` roof at 18.9. It is fine.
- **Barn 17010, hut skeleton 16405, crane towers 8879 / 8877, blast door 2929:** all stand on the ground (12.3-12.5); the
  blast door is a 4 m ramp panel at 2478.5,-1644.9.
- **Duplicate:** the 3406 row at 2513.4,-1694.4 is in the map twice.

So the walkways are real: four bridges and ramps between five roofs plus the stairs, and every one of them needs a model that
meets the roof at its actual height and edge. The measured heights above are the targets.
