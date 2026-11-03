# Branch consolidation and production reload — 2026-11-03

Consolidated all local and origin branch histories into `main` and pushed the result. Deleted the five non-main local branches and seven non-main remote branches (GitHub removed `imgbot` after its merge; the remaining six were deleted explicitly). Each branch tip was verified as an ancestor before deletion. The older crafting branch was superseded by the current complete recipe sets, recipe browser, construction fixes and localization; its obsolete implementation and retired tests were not restored. Current map placement rules and intentional image removals were preserved.

The EMP change drains installed car batteries to 0% inside the existing 12 m radius, stops engines and headlights, and uses the existing battery start check to prevent restarting. The regular vehicle flush persists the flat charge, including on a clean resource/server stop. Batteries removed afterward retain their flat charge. Other EMP effects are unchanged.

## Database and backups

- Pre-change database dump (including system-versioned history, routines, events and triggers), production configuration, all-ref Git bundle, EMP working patch and the untracked Blender backup are saved under `/gta/sa/mta/backups/consolidation-20261103/`.
- Compared the live schema with the merged schema: existing table definitions matched; the missing routines were `vehicle_part_install`, `vehicle_part_remove` and `vehicle_parts_detached`.
- Applied the schema and seed data with the project's SQL loader, then regenerated `sql/schema.sql` from production; it matched the committed schema.
- Confirmed the three routines exist, the event scheduler is ON, and all three scheduler events are ENABLED. Item seed names are `Wrench` → Tyre Wrench and `Spanner` → Spanner.
- Checked spawn identities and pre-update vehicle links/cooldowns against the backup after the seed refresh. No previous links or cooldown rows required restoration.

## Production verification

Reloaded `anticheat`, `lib`, `data`, `auth`, `character`, `items`, `vehicles`, `crafting`, `building`, `explosives` and `hud`; started `stove`. Enabled stove startup in the repository startup list and production `mtaserver.conf`. Verified all twelve resources are running. Both connected players authenticated again after the auth reload. The vehicles resource reports 70 managed vehicles. The Portuguese Car Battery translation resolves through the new data export, and the battery export rejects an invalid vehicle.

The reload interval produced no script-log entries and no server ERROR, access-denied or failed-resource messages. Initial included-resource warnings during the anticheat reload were resolved by the subsequent explicit dependency reloads. Detailed reload logs are in the backup directory. The wiki's Explosives and Vehicles pages now describe the battery effect as active.

Validation: luacheck reports 0 warnings / 0 errors across 278 checked files; StyLua passes; Lua 5.1 syntax checks pass for 300 Lua sources (excluding the non-source `attachedit-out.lua` export fragment); resource manifest file references resolve; the language QA report is current; `git diff --check` passes. Language QA now reads the hand-edited runtime string tables instead of the retired converter inputs.

No automated tests were added or run. A player-operated EMP detonation and battery replacement were not exercised; production checks covered resource startup, exports, translation lookup, persisted schema and logs.
