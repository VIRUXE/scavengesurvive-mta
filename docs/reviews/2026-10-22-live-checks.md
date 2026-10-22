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

## Still open

- HUD draws on the black screen before the camera fades in (review minor 12), seen again on the first join frame.
- Rotation spike #55: no anomaly observed, but there was no SA-MP side by side; the data passes rx/ry/rz through.
- Zone colshapes / `getZoneAt` from the spec's `maps` row are not part of the maps resource yet (follow-up issue).
