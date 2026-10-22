# Live checks, 2026-10-22 (one client, driven through `rcon.ps1`)

Server booted from `run-local.ps1` on 05e1183…ac52d59: `215 loaded, 0 failed`, migration 0002 and the vehicle
seed applied, no `ERROR` in `scripts.log`. One client (nicks ClaudeA/B/C; MTA's launcher hands a second
`mtasa://` to the running instance, so a second player needs a second PC). Camera placed with `setCameraMatrix`
from rcon, frames taken with `rcon screenshot`.

| Step | Result |
| --- | --- |
| 13 weather and clock (#21) | Rain (8) and sandstorm (19) visible on screen after `/weather`; `/weather 20` refused; clock `real 17:10 game 17:10` with `setMinuteDuration(60000)`; `rr world` re-rolled to 16 and the clock stayed right. **Pass.** |
| 14 static maps (#19) | `maps: 8844 buildings, 14367 objects, 0 SA-MP models skipped, 0 failed, 127 removals in 1381 ms` on join (1.1 s on a later join). Grove Street fortified, hollow house at the Houses.map removal spot with no vanilla model left, compound-rotated objects (crate 964 at rx 91, 1777 at rx 269/ry 356) sit flush with their neighbours. **Pass after one fix** (below). `rr models` swaps the 209 SA-MP models under the running maps without a hitch. |
| 12 combat log (#26) | **Not run**: needs two players and one PC cannot open two clients. Unit tests only. |

## Found and fixed

- **`rr maps` crashed the client** (gta_sa.exe access violation at +0x4B85, one second into the restart) while the
  first build had been fine. Cause: `engineSetPoolCapacity("building", 13000)` on every start. MTA grows the
  building pool on demand, so the second call shrank a pool that was in use. The call is gone (f28581b); the
  restart now rebuilds in 0.9 s.

## Later the same day: refactor and loot vehicles

- **Module-local state refactor (#66, 0e6f0d8…a3dfc64).** Every resource restarted live without errors during the
  work; afterwards a fresh client (ClaudeD) registered through the GUI, the HUD drew, `/additem HotDog` put a
  labelled SA-MP-model item on the ground, and the maps built again (`8844 buildings … 1452 ms`): the `ui`, `hud`,
  `items` and `maps` client modules work in-game after the conversion.
- **Loot vehicles (#30, a45e089).** First boot: `rolled 2017 spawn points: 71 vehicles` (27 locked, avg health 421,
  avg fuel 2.96); `rr vehicles`: `71 vehicles rebuilt from the database`; `respawnAll`: a fresh 60; a battered,
  smoking Blista stands where its row says. Checklist step 15 passes for roll, rebuild and respawn; driving,
  explosion cleanup and `/vehcount` in chat were not watched.
- **Found and fixed:** the first roll lost every vehicle without damage data (boats, bikes, helicopters) because
  `db.exec` unpacked its parameters with `#params`, dropping the trailing nil, so the JSON column got the text `?`
  and refused it. `db.query`/`db.exec` now honour `params.n` like `db.call` (f9ce851).
- **Design question raised:** wrecks never respawn and loot points re-roll forever; proposal in
  docs/adr/0001-scarcity-respawn.md (status Proposed).

## SA-MP UI and HUD rework (69fde12, a0da42b, 649aeb7)

Driven end-to-end on client `ClaudeD` at 1920×1080 (`2.25 px` per `640×480` unit) using `rcon.ps1 cmd`, the new
`rcon.ps1 key <player> <command|key>` verb (runs bound commands `interact`, `putaway`, `dropitem`, `inventory` and
dispatches client key events `arrow_u`, `arrow_d`, `enter`, `escape`), and `rcon.ps1 screenshot ClaudeD 1920 1080`,
measured pixel-by-pixel with Pillow against the 1280×720 reference frames from `docs/ui-reference-samp.md` (`1.5×` for
1080p equivalence):

| Element | Live measurement (1080p) | Reference (720p × 1.5) | Result |
| --- | --- | --- | --- |
| Watch ellipse & text (#49) | Ellipse `241×198 px` bottom-left; `123 DEG` `26 px`, `21:19` `39 px`, `98.12` `30 px` tall with clear separation | Ellipse `243×200 px`; three Bank Gothic lines (`0.30/1.50`, `0.50/2.00`, `0.30/1.50`) | **Pass** |
| Hunger bar | `517.8, 78.7` (`76×3.2` units) directly above MTA's stock health bar (`1645..1816 × 222..235 px`) | `progress2` green bar above the health bar at its width | **Pass** |
| Key-actions column | `F Eat / Y Put away / N Drop item / H Open inventory` right-aligned at `x=618, y=120`, `#E8E890` keys + white verbs | Right-aligned column under the HUD, hidden while a dialog is open | **Pass** |
| Action text | `"You ate it"` / `"You put on the bag"` centred at `320, 350`, white with outline, replaces in place | Centred white line at `y≈351` units | **Pass** |
| Inventory & Bag dialogs | `Inventory (4/6)` lists `[01]Combat Knife`, `[02]Wrench`, `[01]Hotdog`, `<Empty>`, `<Empty>`, `Daypack >`; `arrow_d` + `enter` opens `Daypack (0/8)` with 8 `<Empty>` rows and `My Inventory >` highlighted in `#81181B` | Centred dark box, `#81181B` selection, `[NN]Name` / `<Empty>` rows, `<ContainerName> >` and `My Inventory >` | **Pass** |
| Vehicle panel (#30) | Driving the loot Blista draws `DOR / ENG / DMG` at `53×20 px` (`#FF0000` locked/wrecked, `#808000` engine on), `6.51L/40.00` (`159×22 px`), `0KM/H` (`80×21 px`), `BLISTA COMPACT` (`320×22 px`) bottom-right | `DOR / ENG / DMG` `58.5×19.5 px`, fuel `196.5×19.5 px`, speed `118.5×19.5 px`, name `21.0 px` tall | **Pass** |
| Brightness overlay | `/sethp 15` darkens the world and stock GTA HUD (`(40 − hp) × 4.4 = 110` alpha); `/sethp 100` fades back at `4 / 100 ms` | Full-screen black box tracking `(40 − hp) × 4.4` | **Pass** |
| Death screen | 30 s rising camera (`z+1` → `z+20`) looking down at the body, `213.3×48` unit dark box (`0x55`) and shadowed `YOU ARE DEAD!` (`366×29 px`) / `>Play Again<` (`230×28 px`) under the `185`-alpha brightness overlay; text max RGB `(79,77,78)` | Rising death camera, `480×108 px` box, `YOU ARE DEAD!` `364.5×27 px`, `>Play Again<` `234×27 px`, text max RGB `(80,80,82)` (`p52g-vd0syA @ 11:52`) | **Pass** |

### Found and fixed during the UI live check

- **Blank HUD after `rr hud` (a0da42b):** the server pushes character stats and the held item only on change, so restarting `hud` left `state.spawned = false`. Added `onHudRequestState` so a starting `hud` client requests current stats and held item from the server.
- **Uncaught `exports.ui` error while `ui` restarts (a0da42b):** MTA logs failed cross-resource calls to `clientscript.log` instead of raising a Lua error catchable by `pcall`. `hud` now checks `getResourceState(getResourceFromName("ui")) == "running"` before calling `exports.ui:listIsOpen()`.
- **Font aspect ratios and Bank Gothic line height (a0da42b, 649aeb7):** MTA's `bankgothic` at scale 1 is `22 px` tall (not `16 px`) and much wider than GTA's font 2, while `default-bold` is narrower than GTA's font 1. Added per-font `DX_LINE_PX`, `X_FACTOR` (`default-bold = 1.5`, `bankgothic = 0.95`) and `Y_FACTOR` (`bankgothic = 0.85`), and passed the upstream `lx` values on the watch clock (`0.50`), vehicle rows (`0.25`) and vehicle name (`0.35`).
- **Bag row and title hardcoded to `"Bag"` (649aeb7):** `items/server/containers.lua` now includes `owner.type_uname` in `capacity.bag` so `items/client/inventory.lua` shows the worn bag's display name (`"Daypack >"` and `"Daypack (0/8)"`).
- **Death screen hid the camera and box (649aeb7):** `character/client/deathscreen.lua` drew a `255`-alpha opaque black rectangle under the `0x55` box and lacked the font-1 horizontal stretch. Switched to upstream's rendering order (rising camera → `0x55` box + shadowed white lines with `1.25×` horizontal stretch → `185`-alpha brightness overlay, with hover highlight above the overlay).

## Still open

- Rotation spike #55: no anomaly observed, but there was no SA-MP side by side; the data passes rx/ry/rz through.
- Zone colshapes / `getZoneAt` from the spec's `maps` row are not part of the maps resource yet (#65).
