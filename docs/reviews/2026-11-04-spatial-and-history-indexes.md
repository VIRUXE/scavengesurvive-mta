# Spatial queries and item history indexes

Applied live on 2026-11-04. The game server had no connected players and was cleanly stopped for item-table
DDL, then restarted. Items, crafting, vehicles and explosives report running. Scheduler events are enabled.

## Spatial queries

Added `lib/modules/spatial.lua`: a server-coordinate bounding box for queries against `world_items_pos p`.
Use `MBRContains` to enable the existing `sp_world_items_pos` index, keeping the exact distance check and
all ownership, interior/dimension, type and exclusion filters. The box is expanded by one micrometre and
formatted with 17 significant digits to retain points on circle boundaries. Callers that previously rounded
the exact query centre/radius retain that same rounded centre/radius for the bounding box.

Applied to nearest-item lookup, ground crafting, deconstruction, workbench lookup, campfire food pickup,
furniture pickup, explosion victims and both trailer cargo reads. World streaming and loot placement
already use bounding boxes and are unchanged.

Read-only before/after queries joined items to positions at forty centres selected by ascending item id.
Verified identical item-ID sets at each radius. Median MariaDB execution times:

| Radius | Distance only | Bounding box + exact distance |
| ---: | ---: | ---: |
| 0.3 m | 1.8783 ms | 0.0639 ms |
| 2.5 m | 1.8736 ms | 0.0642 ms |
| 20 m | 1.8648 ms | 0.0645 ms |

An initial single-location plan examined 4,025 position rows without bounds and one with bounds, using the
spatial index. Synthetic cases also matched for negative/fractional centres, circle edges, square corners,
points just outside the radius and zero radius. These sample spatial reads, not gameplay latency or every
query's full set of joins/filters. Dense locations and larger radii can produce smaller gains.

## Item history indexes

Existing single-column indexes included historical versions. Changed:

- `ix_items_loot_zone`: `(loot_zone)` to `(loot_zone, row_end)`.
- `ix_items_despawn`: `(despawn_at)` to `(row_end, despawn_at)`.

The implicit version timestamp fields could not be indexed directly. Converted them to explicit system
versioning fields with the same names, preserving their timestamps and history. MariaDB already included
`row_end` internally in the primary/unique keys; the generated schema now exposes it there. The version
fields also become visible to SELECT *. Gameplay queries use named item columns.

Isolated session-local InnoDB table containing current and historical item versions, with old and proposed
indexes present. Read-only ANALYZE FORMAT=JSON, alternating comparisons, thirty measured executions after
one warmup. For the largest current loot zone, results were identical:

| Lookup | Old index median | New index median |
| --- | ---: | ---: |
| All current zone stock | 2.0035 ms | 0.0393 ms |
| Uncarried current zone stock | 1.6366 ms | 0.1501 ms |
| Expired world items | 15.4295 ms | 0.0103 ms |

The all-stock lookup examined 5,288 historical/current entries with the old index versus 108 with the new.
The expiry result was empty during measurement. A live pre-change expiry plan chose a full scan; the
new live plan chooses a range on the new index. New live medians across thirty measured reads after warmup:
zone 0.0448 ms, uncarried zone 0.1760 ms, expiry 0.0093 ms. These are read measurements; write overhead and
concurrent player load were not benchmarked. Replaced the two indexes rather than retaining duplicate ones.

## Deployment and preservation

Fresh full backup including history:
`/gta/sa/mta/backups/scavengesurvive-pre-history-indexes-20261104-042445.sql`.

With the game stopped, temporarily disabled its enabled scheduler events. Captured every item field,
including row_start and row_end, in `(id, row_end)` order before and after DDL. Both snapshots had 88,417
versions (9,429 current items) and SHA-256:
`d4157567533bb974f53994e3e4372b5be692636d5cedc57c1910865896dc2d24`.
Restored the enabled events and started the game. Exported the table with SHOW CREATE TABLE to schema.sql.
World startup can subsequently create/remove items normally.

The DDL for another existing database is in the commit body. `tools.sqltool apply` creates missing tables
but does not alter an existing items table. Stop the game and take a fresh backup before that DDL.

SQL rollback can restore the two original index definitions while retaining explicit version columns.
Spatial-query rollback is a code revert and resource reload. No permanent test suite was added.

## Checks

Touched Lua files pass StyLua. LuaCheck has no new findings: the vehicles file retains its four existing
warnings (unused TIRE_REPAIRED, count shadowing and two long lines). All other touched Lua files are clean.
