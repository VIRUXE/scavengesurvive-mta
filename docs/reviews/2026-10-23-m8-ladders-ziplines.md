# M8 ladders and ziplines (#50), 2026-10-23

Commit `ecf1a34`. Upstream: the sampctl dependencies `Southclaws/samp-ladders` and `Southclaws/samp-zipline` (not in
the `../ScavengeSurvive` checkout; behaviour and constants taken from the libraries). Positions come from the
`CreateLadder` / `CreateZipline` calls in `world/zones/*.pwn`, converted by `tools/convert/features.py` into
`resources/[scavengesurvive]/world/data/features.lua` (14 ladders, 13 ziplines). Constants and maths with upstream
citations: `world/shared/logic/features.lua`; mechanics: `world/client/features.lua`.

## Port decisions

| Upstream | Port | Why |
| --- | --- | --- |
| Zipline rope drawn with 2.46 m objects of model 19087 laid end to end | `dxDrawLine3D` between the anchors, dark line, client-side | 19087 is SA-MP-only and not in the model pack; one line per rope instead of dozens of objects |
| Ladders have no object | none: the map geometry already has the ladders | nothing to create |
| Dynamic circle (ladder base) and spheres (zipline start, end) with enter/leave callbacks | client distance tests against the 14 / 13 entries, using `shared/logic/features.lua` (`ladderAt`, `ziplineProject`) | the data is tiny; no colshapes, no server round trip |
| Climb and ride driven from `OnPlayerUpdate` velocity writes | `onClientRender` writes the velocity for ladders (0.1 up, 0.07 down, 0.01 hold) and a 50 ms timer ramps the zipline speed 0.2 -> 0.5 | the local player's movement is client-owned, so the climb and the ride run on the client |
| SIF buttons and action text ("Climb ladder" etc.) | hud key-actions lines `F Climb ladder`, `F Grab zipline`, `F Let go` fed by `exports.world:nearbyFeature` | one key list for everything, see `hud/shared/logic/keyactions.lua` |
| Library hooks the F press itself | `hud/client/keys.lua` `worldInteract` calls `exports.world:tryInteract` first, then the other interact routes | a single **F** binding, no competing handlers |
| Ladder grab: 1 m circle, between base - 1 and top + 2; snap to top - 2.0926 or base + 1.5 | same | upstream numbers |
| Auto-exit near the ends only after 1 s on the ladder | same (`ladderShouldExit`) | the snap moves the player across the thresholds |
| Zipline grab within 2 m of the start or the rope; hang 1.2 m below; let go at the 6 m end sphere, 5 m off the line, or with F | same, with a forward boost on release | upstream numbers |
| Guards | no grab while knocked out, cuffed, dead or in a vehicle; `rr world` drops the player back to normal controls | the state must not be left locked on a resource restart |

## Verified

- `busted`: 246 pass in total (`tests/lua/spec/world_features_spec.lua`: ladder circle and span, enter snap, climb
  velocity, exit rule and step-off velocity, zipline vector and projection, grab/end/drop distances, speed ramp).
- `pytest tests/tools`: 54 pass (`test_zones.py::test_parses_ladders_and_multi_line_ziplines`: ladders and ziplines
  whose arguments span several lines).
- Not run against the live server: it was being restarted by another session.

## Pending live (smoke step 27)

A logged-in client at a ladder and at a zipline is needed: the climb pose and snap, the W/S speeds, the step-off and
the F drop, the visible rope, the hang height, the release boost and the guards. Step 27 a-c covers it.
