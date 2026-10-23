# Live check, 2026-10-23: scarcity-driven respawn (#67, ADR 0001)

Server side only, no client (smoke step 28 a-b). DDL from commit b220dd3 run against `scavengesurvive`
(`items.loot_zone` back-filled on 473 of 538 items), `sqltool apply` for the procedure and the 14 new settings,
then `lib`, `vehicles` and `loot` restarted through `rcon.ps1 lua` in one call.

| Check | Result |
| --- | --- |
| Resources after restart | `lib`, `vehicles`, `loot` running; `60 vehicles rebuilt from the database`; no `ERROR`/`WARNING` from the three resources in `scripts.log`. **Pass.** |
| 28a loot budget rows | Seven rows at start, `allowance = cap`: sf 6648, ls 8078, bc 1088, tr 362, lv 3874, rc 1312, fc 994 (points × 2). **Pass.** |
| 28a vehicles budget row | None before the first tick (the world was rolled before the budget existed); the tick created it: `[vehicles] refill: budget created from the 60 vehicles alive, cap 60`. **Pass** (as documented; `/vehrespawn` gives a first-roll cap). |
| 28b first refill tick (5 min after start) | `[loot] refill: 7 zones, alive 363/22356, allowance 21993 (+181)`: the allowance clamped from 22356 to the deficit and 181 spawns accrued (10 % of the deficit per hour over 5 min). **Pass.** |
| 28c cooldowns | `vehicle_spawn_state` empty: nothing has left a point or exploded since the restart (points rolled before #67 were never cooled). Needs a client to drive or blow one up. **Not run.** |
| 28d loot allowance and 150 m exclusion | Needs a client. **Not run.** |

## Notes for the playtest

- `alive 363/22356` says the loot world is nowhere near its cap: points only materialise within 400 m of players,
  so the cap only bites once the map has been walked. Until then the allowance equals the deficit and loot appears
  exactly as before, minus the 150 m exclusion and the per-point cooldown.
- The vehicles cap of 60 came from the stock alive at the time, not from a first roll (about 80 over the 2,017
  points); `/vehrespawn` on the dev server before balancing.
