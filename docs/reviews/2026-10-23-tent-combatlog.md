# 2026-10-23 — tent pitch/dismantle (#73), pitched tent parts, combat-window HUD signal (#26)

Live check on the dev server with one client (VIRUXE, char 9), driven through `server-config/rcon.ps1`
(`cmd … additem`, `key … dropitem|interact`, `lua …` for teleports, camera and DB readback, `screenshot`).

## #73 — tent pitch/dismantle never ran

Cause confirmed by reading: `hands.lua` raised `tentPitchRequested` / `tentDismantleRequested` with a server-side
`triggerEvent`, and `net.handler` drops any event whose `client` global is not the source. Fix: the logic is
`containers.pitchTent` / `containers.dismantleTent`; the remote handlers wrap them and `hands.lua` calls them.

Second bug found while checking: the per-player world sync (`world.syncPlayer` + `shared/logic/diff.lua`) only
resends rows whose id the client lacks, so a TentPack whose `data` flipped to `{"pitched":true}` (or back) never
reached any client. `world.resendEverywhere(itemId)` forgets the id for every player; the next sync (at once for the
pitching player through `refreshPlayer`, within 2 s for the rest) re-adds the row and the client rebuilds the objects.

| Step | Result |
| --- | --- |
| TentPack dropped, Hammer held, interact | 3 s hold, row 7663 `data = {"pitched":true}`, container `kind = 'tent'` created |
| Crowbar held, interact on the pitched tent | 3 s hold, `data = NULL`, container deleted, pack object back |
| Pitched tent with items inside | not exercised this run (unit test covers the `TENT_NOT_EMPTY` branch) |

## Pitched tent model

The client used stock model 3243 (a large military tent) for a pitched pack: it spawned around the player, who could
not walk out. Upstream (`core/item/tent.pwn`) builds the tent from six SA-MP objects: four Plane003 sheets (19477)
rolled ±45° about the item's heading, textured with `CJ_cammonet` (outer) and `sam_camo` (inner), and two Rope1
poles (19087) 1.3 m along the ridge with the `lamppost` texture. Ported as `items/shared/logic/tent.lua` (geometry,
busted) + `items/client/world.lua` (objects, no collisions, `replace.fx` shader fed by `engineGetModelTextures`,
`CullMode = None` since the sheets are one-sided meshes seen from both sides). Both models were added to the pack
(`STRUCTURE_MODELS` in `tools/extract_samp_models.py`, extracted from the local SA-MP install).

Rotation (#55): measured with a server-side object's `getElementMatrix`, MTA builds an object's matrix as
`Rz(rz) * Rx(rx) * Ry(ry)` (yaw first, then the object's own X, then its own Y; right-handed: `(0, 45, 90)` gives
right = (0, 0.707, -0.707), up = (0, 0.707, 0.707)). That is GTA's own `CMatrix::SetRotate` (ZXY), and the SA-MP
client's `CObject::InstantRotate` (jni/game/object.cpp in the SA-MP Android source) only calls the game's
`set_object_rotation` opcode, so SA-MP objects use the identical convention: angles pass straight through, as the
converted maps already do. Upstream's tent angles unchanged give the A-frame. The sheet mesh (from the DFF:
vertices x = 0, y ±1.389, z ±0.7) stands in its own YZ plane, so the roll about Y is the roof slope. A detour
through a "converted" rotation (mirrored Y) produced a V and was dropped; the attached-object order measured in
b0a0c82 is bone-relative and does not apply to world objects.

Screenshots: `dev/screenshots/VIRUXE-1792775325.jpg` (end view, A-frame) and `VIRUXE-1792775334.jpg` (side).

## #26 — combat window on the watch

`character` sends `combatWindowChanged` (window in ms) to the victim on every hit by a player, 0 on spawn and when
the attacker leaves; `hud` keeps `combatUntil` and the watch text turns red while it is open. Checked by raising the
event from rcon: the watch text went red (`VIRUXE-1792773804.jpg`). The two-player combat-log test (smoke step 12)
still needs a second PC.
