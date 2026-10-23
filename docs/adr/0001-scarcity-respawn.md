# ADR 0001: Scarcity-driven respawn for loot and vehicles

Status: Accepted (2026-10-23, implemented in #67). Supersedes the fixed 30-minute loot re-roll and the one-shot
vehicle roll.

## Context

Upstream re-rolled every loot point and every loot vehicle at each gamemode start and restarted the server every
5 hours (`max-uptime 18000`), so resources refreshed per cycle and were finite inside it. This port keeps the world
in MariaDB across restarts, so that reset never happens. Today loot points re-roll whenever they are empty and 30
minutes have passed (unlimited resources over time), and vehicles are rolled once and only ever disappear
(`vehicles` resource, 416d4f8): the map drifts toward empty. Both contradict a survival economy, where resources
must come back, but slowly, and never beyond what the world can carry.

## Decision

One mechanism for loot items and vehicles: a carrying capacity per category with refill proportional to the
deficit, per-point cooldowns, and placement away from players.

1. **Cap (carrying capacity).** `cap = initial_roll × cap_multiplier` (setting, default 1.0). Vehicles: the size
   of the first roll over the 2,017 points (about 80). Loot: per zone, the item count the seed produced on its
   first roll. Everything alive counts: world items, items in containers, items players carry, vehicles players
   parked. Hoarding reduces what respawns for everyone.
2. **Refill proportional to the deficit, with a floor.** Every `refill_interval` (5 min): `deficit = cap − alive`;
   `spawns = floor(max(deficit × refill_rate, cap × refill_floor) × interval / 1 h)` with `refill_rate` default 0.10
   (10 % of the deficit per hour, exponential approach, half-life about 7 h) and `refill_floor` default 0.02 (a
   trickle of 2 % of the cap per hour that spawns even when hoarding keeps the deficit small, so a newcomer finds
   something within the hour). The accumulated fractional remainder carries over so small deficits still refill.
   Never above the cap, floor included.
3. **Cooldown on empty, with jitter.** When a point's spawn is consumed (last item picked up, vehicle destroyed or
   driven more than `leave_radius` from its point), the point gets `next_roll_at = now + cooldown × (1 ± jitter)`:
   vehicles 6 h ± 33 %, loot 60 min ± 50 %.
4. **Placement away from players.** A refill picks a random cooled point of the category (and zone, for loot) with
   no player within `min_player_distance` (150 m). Loot keeps lazy materialisation (points roll only inside the
   400 m box around players) but inside that box the 150 m exclusion holds.
5. **Decay frees budget.** World items despawn after `loot.despawn_minutes` (120). Vehicles untouched for
   `vehicles.abandon_days` (3) are removed; wrecks are removed 30 s after exploding (as now). Destroyed, eaten and
   used-up items free their slot immediately.
6. **State in the DB, numbers in settings.** `loot_spawn_state.next_roll_at` already exists; add
   `vehicle_spawn_state(spawn_id, next_roll_at)` and a `world_budget(category, zone, cap, remainder)` row per
   category/zone written on the first roll. Settings: `loot.cap_multiplier`, `loot.refill_rate`, `loot.refill_floor`, `loot.count_carried`, `loot.cooldown_minutes`,
   `loot.cooldown_jitter`, `vehicles.cap_multiplier`, `vehicles.refill_rate`, `vehicles.refill_floor`, `vehicles.cooldown_hours`,
   `vehicles.cooldown_jitter`, `vehicles.abandon_days`, `world.min_player_distance`, `world.refill_interval_s`.

## Consequences

- Resources are finite at any moment and come back only as others are consumed, destroyed or decay; the pace is
  tunable live through settings (lower `cap_multiplier` for a harsher world).
- Restarts no longer matter; there is no need for upstream's 5-hour restart.
- The `loot` roller changes from "re-roll empty points every 30 min" to "spend the budget on cooled points"; the
  `vehicles` resource changes from a one-shot roll to the same refill loop; both need the consumed-point hook.
  `/vehrespawn` stays as the dev reset.
- **Hoarding is deliberate scarcity.** Carried items and parked vehicles count against the cap, so a clan
  stockpile slows respawns for the whole server; the floor keeps the map from looking dead, and a lost base or a
  death returns its stock to the economy through drops and despawn. Counting only world and container items was
  rejected: a pickup would free its slot and resources would become unlimited again, only delayed.
  `loot.count_carried` (default on) exists for a server owner who wants the softer rule. The carried count is one
  aggregate query per zone per interval (`items` joined to `characters` positions).
- Risk: with a low refill rate a looted-out hub stays empty for hours by design; the jitter and the random point
  choice spread refills instead of refilling the hub first. Tune `refill_rate` and `cooldown` on the playtest.

## Implementation (2026-10-23, #67)

- **Arithmetic** in `lib/modules/budget.lua` (busted: `tests/lua/spec/lib_budget_spec.lua`): `cap`, `refill`
  (nothing accrues at capacity, the fraction carries in `remainder`, never above the deficit), `cooldown`,
  `clearOfPlayers` and `pickClear`.
- **Schema** (`sql/schema.sql`): `world_budget(category, zone, cap, remainder, allowance)`,
  `vehicle_spawn_state(spawn_id, next_roll_at)`, `vehicles.left_spawn`, `vehicles.last_used_at` and
  `items.loot_zone`. `loot_roll` (and `item_create`, given a loot point) copies the zone of the loot point into
  `items.loot_zone`, and `item_pickup` leaves it alone, so an item keeps counting against its zone wherever it
  goes. `loot.reroll_minutes` is deleted.
- **Vehicles** (`vehicles/server/main.lua`): the first roll writes `world_budget('vehicles','all')` and cools every
  used point. Every `world.refill_interval_s` the tick removes abandoned vehicles (`left_spawn = 1` and unused for
  `vehicles.abandon_days`), computes `budget.refill` against `COUNT(*) FROM vehicles`, and spawns on random cooled
  points with no vehicle still on them and no player within `world.min_player_distance`, with the per-point chance
  forced to 100 (the type's own chance still applies). The minute flush marks `left_spawn` the first time a vehicle
  is more than `vehicles.leave_radius` from its point and cools the point; an explosion cools it too; entering the
  vehicle or opening its trunk stamps `last_used_at` at most every 5 minutes, so a parked stash truck whose trunk is
  visited stays. Removing a vehicle deletes its trunk container and everything in it (the same cascade a wreck has). `/vehrespawn` clears the spawn state and rolls a
  fresh budget. A world rolled before the budget existed gets `cap = vehicles alive` on the first tick.
- **Loot** (`loot/server/main.lua`): a `world_budget('loot', zone)` row per zone with
  `cap = enabled points × loot.items_per_point × loot.cap_multiplier`, `allowance = cap` on creation (the world
  starts full). The tick adds `budget.refill` to the allowance (clamped to the deficit) with
  `alive = COUNT(items WHERE loot_zone = zone)`, carried items included unless `loot.count_carried = 0`.
  `rollNear` rolls a due, empty point only while the zone has allowance and no player is within
  `world.min_player_distance`; the roll spends its item count and sets `next_roll_at` to now plus
  `loot.cooldown_minutes ± loot.cooldown_jitter`. The `lootAllowances` export reports the cached allowance per zone.
  Since #78 a `rollNear` batch is one `CALL loot_roll(rolls_json, loot.despawn_minutes)`: Lua picks the items and
  trims each roll to the cached allowance, and the procedure, in one transaction, inserts every item (bags and
  safeboxes get their container, the `items` trigger the `world_items_pos` row), spends each zone's allowance by
  the items it created and sets each point's `next_roll_at`. Before, every spawn cost one `item_create` per item
  plus a budget and a cooldown `UPDATE`.
- **Deviations from the decision above.** The loot cap is `points × items_per_point` rather than the count of the
  first roll, so it is deterministic and a settings change applies on the next start. The loot cooldown runs from
  the roll, not from the last pickup (a point rolls again when it is empty and the cooldown has passed). Supply
  drops, weapon caches, crafted and staff-given items have no `loot_zone` and never count.
- **Live check:** smoke step 28 in `docs/mvp-smoke-checklist.md`; settings in `server-config/README.md`.
