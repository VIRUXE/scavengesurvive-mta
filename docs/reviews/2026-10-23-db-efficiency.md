# MariaDB efficiency pass — 2026-10-23 (#78)

MariaDB 13.0.2, local dev box (`innodb_flush_log_at_trx_commit=1`, thread pool on). Each scenario ran the SQL the game
sent before this change (baseline) against the new SQL on one connection, like MTA's queue, in a scratch database
built by `python -m tools.sqltool --db scavengesurvive_bench --reset apply`; median of 5 runs.

| Scenario | Before | After | Gain |
|---|---|---|---|
| Loot batch, 300 spawns × 2 items (`item_create` per item + 2 updates per spawn → one `loot_roll`) | 2,610 ms, 1,200 calls | 54 ms, 1 call | ×48 |
| Ammo, 10 guns firing 60 s (`UPDATE` per shot → `item_data_flush` every 5 s) | 1,241 ms, 600 history rows | 73 ms, 120 history rows | ×17 |
| Retire 50 abandoned vehicles (per-id `DELETE` → one `DELETE … RETURNING id`) | 98 ms, 51 calls | 2.4 ms, 1 call | ×41 |
| Item workload on a full world (22k items) with 140k history rows → after `DELETE HISTORY` | 171 ms | 134 ms (125 ms with no history) | ×1.28 |
| Bag/safebox type lookup (`JSON_VALUE` on `category_data` → stored `container_size`) | 395 ms / 2,500 | 331 ms / 2,500 | ×1.19 |
| Pickup + drop ×300, `world_items_pos` by hand → by trigger | 1,400 ms | 1,374 ms | ×1.02, drift 0 |

Both loot paths leave the same rows (600 items, 600 positions, 56 bag containers).

## What changed

- `sql/procedures/loot_roll.sql`: a loot batch is one transaction; `loot/server/main.lua` sends every roll of a
  `rollNear` batch in one call.
- `sql/procedures/item_data_flush.sql` + `items/server/hands.lua`: a held item's ammo data waits in memory and is
  written every 5 s, when the item leaves the hand, and synchronously on resource stop.
- `sql/triggers/items_world_pos_*.sql`: triggers keep `world_items_pos`; six procedures lost their hand-written copy.
- `sql/events/0003_item_history.sql`: hourly `DELETE HISTORY` keeps 7 days of `items` history (dev had 13 history rows
  per live item after three days).
- `item_types.container_size`, a stored generated column, replaces the `JSON_VALUE` pair in the item procedures.
- `vehicles/server/main.lua`: abandoned vehicles go in one `DELETE … RETURNING id`.
- `hands.publishAmmo` is exported; `updateHeldData` (gas can refuel) had been failing on it (#79).

## Rejected

- `PARTITION BY SYSTEM_TIME` on `items`: partitioned InnoDB tables cannot have foreign keys (error 1506).
- A generated `POINT` column with a spatial index instead of `world_items_pos`: a SPATIAL key needs NOT NULL, which
  a generated column cannot declare.
- Returning the moved item's row in `container_take`'s payload instead of the follow-up SELECT: ×0.96. The read is
  ~0.1 ms; commits (~2 ms each) are what costs.
- Refill tick per zone → one statement: ×6, but 2 ms every 5 minutes; not worth the code.

## Live check

Server running, `rr items`, `rr loot`, `rr vehicles`: a `rollNear(2000, -1500, 600)` placed 162 `ls` items in one
call, the zone allowance fell by 162, bags got containers, every world item had its position row (drift 0), no
errors in `server.log`. The ammo flush was not driven live (another session was using the only player); the busted
specs cover it, and the live check is open in #80.
