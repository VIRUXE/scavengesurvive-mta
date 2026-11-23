# /replay — staff replay of what a player did in a time range (2026-11-23)

Staff command (level 2+, on duty) that replays one player's movements and everything they touched between two
timestamps, inside the real map, with the live world's loose items hidden for that staff member only.

## Goals

- `/replay <player|account|char id> <from> [<to>|<duration>]`, e.g. `/replay KaijaLV 2026-11-18 19:15 19:40`,
  `/replay WinFast -2h 30m`. Opens a replay session for the issuing staff member only.
- The viewer sees: the subject as a ghost ped (skin, heading, anim, weapon, aim, shots, crouch/sprint, hp), the vehicles
  they used, the world items, defences and containers **as they were at each replayed moment**, and a marker for every
  event (item taken/dropped/picked up, defence placed/removed/moved/keypad, container opened, vehicle
  entered/exited/locked, shots/hits/kills, deaths, chat, staff actions).
- Other players found near the subject (their own track or recorder samples in the same range) play as grey ghosts, so a
  raid shows both sides.
- Live world items, other players' ghosts and live vehicles do not clash with the replay: for the viewer only, the
  loose world items and live vehicles/players are hidden (alpha 0, no collisions) while replaying; everything returns on
  exit. No other client is affected.
- Timeline UI: play/pause, speed (0.25x … 32x, skip-idle), scrub, jump to previous/next event, follow-cam (third
  person, side, top-down) or free fly, event list with click-to-jump, subject switch, export (`/replay save`, `/replay
  load`) not needed in v1.

## Data

Two sources, merged per range; the better one wins per moment.

### 1. Existing history (works from now for the past)

| Need | Source | Notes |
| --- | --- | --- |
| path | `character_track` (since 2026-11-12) | point every 2 s while moving ≥1.5 m; has int, dim, vehicle model, seat |
| world items / defences / containers | `items FOR SYSTEM_TIME AS OF t` (system-versioned since 2026-10-25) | reconstruct the set at the start with one `AS OF`, then apply the row history (`FOR SYSTEM_TIME BETWEEN`) in order |
| vehicle use | `vehicle_events` (since 2026-11-01) | enter/exit/lock with x,y,z |
| events | game log lines in `mods/deathmatch/logs/server.log` (+ rotated) | structured JSON per line; Loki on prod is **not** receiving, so the importer reads the file |
| death | `characters.died_at/death_cause/killer_char_id` | |
| staff actions | `staff_actions` | |

A backfill tool `tools/replay_import_log.py` loads kinds worth replaying from the server log into `replay_event`
(idempotent: unique key on `at, kind, char_id, item_id`), so one query serves every range.

### 2. New high-rate recorder (exact for new sessions)

`replay` resource, server side, 5 Hz sampling timer per authenticated, alive, spawned character:

sample = `{ dt_ms, x, y, z (cm ints), rz (deg int), int, dim, hp (0..100), anim block + name (hashed to a small id map),
move state (stand/crouch/walk/run/sprint/jump/fall/swim), weapon id, aiming (bool + aim point), firing, vehicle id,
seat, vehicle pos/rot/health/velocity (for the vehicle the subject drives) }`

- Only changed fields are stored (delta against the previous sample), idle collapses to a heartbeat every 5 s.
- Samples are buffered per player and written every 10 s as **one row** per (char, 10 s) in `replay_chunk`
  (`char_id, t0 DATETIME(1), n SMALLINT, data MEDIUMBLOB` = compact JSON, optionally `COMPRESS()`ed). One procedure call
  per flush with a JSON array of chunks (`replay_chunk_save`), never a statement per sample.
- Retention 14 days (MariaDB event, same as `character_track`'s purge), `*replay.keep_days` setting.
- Recording is on by default; `*replay.record` = 0 turns it off. Staff on duty are recorded too (their own tag in the
  chunk) but a staff's own replay marks the data as duty so it is not misread as a character's.
- Events (kinds whitelist in `replay/shared/logic/kinds.lua`) are mirrored from `log.event` into `replay_event` by the
  `logs` resource: when an event has `x,y,z` or a character id it is buffered and inserted in batches
  (`replay_event_save`, JSON array), so every future event has the same shape the importer produces.

## Schema (live DDL, then `sqltool dump`)

```
replay_chunk(char_id INT, t0 DATETIME(1), n SMALLINT, data MEDIUMBLOB, PRIMARY KEY (char_id, t0), KEY (t0))
replay_event(id BIGINT AUTO_INCREMENT PK, at DATETIME(3), kind VARCHAR(48), char_id INT NULL, other_char_id INT NULL,
             account_id INT NULL, item_id INT NULL, vehicle_id INT NULL, x FLOAT NULL, y FLOAT NULL, z FLOAT NULL,
             interior TINYINT, dimension INT, data JSON, UNIQUE KEY (at, kind, char_id, item_id), KEY (char_id, at),
             KEY (at), KEY (x, y))
```

Procedures (all return `SELECT ok, code, payload`):

- `replay_chunk_save(json)`, `replay_event_save(json)` — batch writers.
- `replay_range(char_id, from, to)` — one call returns the subject's path (chunks, falling back to `character_track` for
  uncovered spans), the events for the subject and for others within `R` metres of the subject's path in the range,
  nearby characters' paths, vehicle events, and the death/deaths in range.
- `replay_world_at(from, x, y, z, radius)` — the items/defences/containers rows `AS OF from` within a box around the
  path, plus `replay_world_changes(from, to, box)` for the history rows in range (type, x,y,z,rz, data, holder, container,
  `row_start`, `row_end`) so the client can apply creations/removals/moves at their timestamps.
- `replay_retention()` event.

Payloads can be large: `replay_range` returns the path sampled to ≤ 20 000 points per subject, the client asks for
more per sub-range (`replay_range` takes `lod`), and a session streams chunks of 2 minutes ahead of the cursor.

## Server (`replay` resource)

- `server/recorder.lua` — the 5 Hz sampler, delta encoder, buffer, flush.
- `server/session.lua` — per-staff sessions: validates level + duty, resolves the target (name/account/char id), parses
  times (absolute `YYYY-MM-DD HH:MM`, `HH:MM` today, relative `-2h`, `30m` durations, server local time), calls
  `replay_range`/`replay_world_at`, streams to the staff client in chunks, tracks the session so `/replay stop` and
  quit clean up. Every start/stop is a `staff_actions` row + `log.event("replay.started" / "replay.stopped", …)`.
- `server/commands.lua` — `ctx.command` via the `staff` resource's registry (staff owns the command surface: the
  command is declared in `staff/server/replay.lua` and calls `exports.replay`), subcommands `/replay`, `/replay stop`,
  `/replay at <time>`, `/replay follow <player>`, `/replay list` (recent recorded ranges per player).
- Nothing in the replay changes state: the staff is moved with the existing duty/teleport helpers and put back at the
  saved position on stop (save the position/interior/dimension in the same call that teleports, as the staff duty
  commands already do).

## Client (`replay` resource)

- `client/main.lua` — session state, timeline clock (`getTickCount` based, speed multiplier), applies `replayStarted`,
  `replayChunk`, `replayStopped`.
- `client/world.lua` — builds the reconstructed world: loose items as the same representative props the live world uses
  (`items:getWorldModel(type_uname)` export taking the item row and returning model + offsets/scale, the same function
  `items/client/world.lua` uses to draw them); defences/containers/tents/crates through the same builder. Created in the
  replay's own element container with `setElementDimension` unchanged (the map objects are in dimension 0), tagged
  `replay=true`, destroyed on stop. While the session runs, `items:setWorldHidden(true)` makes the client's live item
  elements invisible (alpha 0, collisions off) for this client only and restores them on stop; live vehicles and players
  get the same treatment through `replay` itself (`setElementAlpha`, `setElementCollisionsEnabled`) with an
  `onClientElementStreamIn` hook for new ones.
- `client/actors.lua` — ghost peds for the subject and other characters (skin from the sample, `setPedAnimation` with
  the recorded block/name, `setPedWeaponSlot`/`giveWeapon`, aim via `setPedAimTarget`, shots as muzzle effect + tracer,
  crouch/sprint/swim states as ped animations), ghost vehicles for vehicles used (model from `vehicles` row or sample,
  position/rotation/colours/lights from samples, driver ped placed in seat). Interpolation between samples: position
  cubic Hermite, heading shortest-arc lerp, 5 Hz is smooth; for 2 s-sparse `character_track` spans it is Catmull-Rom with
  speed clamps so a ghost never teleports through walls (`geom` ray check for obviously-straight lines, otherwise it
  just walks the line and a "sparse data" marker shows in the timeline).
- `client/ui.lua` — timeline bar (event ticks coloured by kind, drag to scrub, skip-idle toggle, speed buttons, camera
  buttons), the event list on the right, a tooltip on a ghost (name, hp, weapon) and on item/defence markers, a
  top-left banner "REPLAY — name — time" so it cannot be confused with live play. `bindKey` bindings: space play/pause,
  [ ] speed, ←/→ step 1 s (shift 10 s), PgUp/PgDn previous/next event, C camera mode, Esc stop.
- `client/camera.lua` — follow cam (smoothed), top-down, side, free fly (WASD + mouse, shift fast).
- Replay clock drives item timing: at each cursor move the world builder applies every `replay_world_changes` row
  with `row_start <= t < row_end` (create/destroy/move), so a gate the subject crowbars disappears at that exact second
  and a dropped item appears where it landed.

## Safety and limits

- Staff level ≥ 2, on duty, not in a vehicle; one session per staff member; max range 3 h per query (`*replay.max_range_s`).
- The viewer never receives data about accounts above their level (staff `admin_level` > viewer's) unless they are the
  viewer, same rule as the other staff tools.
- Keypad codes and passcodes (`data.defence.passcode`, `keypad`) are stripped from every row sent.
- Chat from the subject is included for staff ≥ 2 only, flagged `chat.messageSent` events.
- Load: 5 Hz × 20 players costs one more timer and ~0.3 ms/tick; flush is one DB call per 10 s; the DB grows ~1 MB per
  player-hour compressed. Both numbers must be measured on prod after rollout (record row count and bytes/day).

## Build order

1. Schema + procedures + retention, `replay_event` backfill tool (data layer, verifiable with SQL alone).
2. Recorder + event mirror (data starts accumulating — ship early).
3. `replay_range` / `replay_world_at` / `replay_world_changes` + `/replay` server session, `staff_actions`.
4. Client: world reconstruction + hiding, ghosts, timeline clock, camera, UI.
5. Check against the 2026-11-18 raid: replay KaijaLV 19:20–19:35 at WinFast's base, verify the removals match the log.
6. Wiki + `site/data/changes.json` entries, `docs/staff-commands.md` row.

## Appendix A — wire contract server → client (fixed so both halves can be built in parallel)

Times: `t` is **milliseconds since the session's `from`**; `from`/`to` are unix seconds (server clock). All coordinates
are floats in metres; `rz` degrees; `sdata` is a row's `data` with passcodes/keypad codes removed.

Server → client (declared in `replay/shared/events.lua`, registered `addEvent(name, true)` on the client):

- `replaySessionStarted(info)` — `info = { id, from, to, subject = { char_id, name, skin }, origin = { x, y, z, int, dim }, kinds = { [kind] = { label, color } } }`
- `replayChunkReceived(id, seq, total, part)` — `part` carries any of these keys (merge by key, later `seq` appends):
  - `actors = { [char_id] = { name, skin, role = "subject"|"other", samples = { { t, x, y, z, rz, int, dim, hp, move, anim, weapon, aim, fire, veh, seat } … } } }`
    (`move`: "stand"|"crouch"|"walk"|"run"|"sprint"|"jump"|"fall"|"swim"|"climb"|"vehicle"; `anim`: `"block|name"` or nil;
    `aim`: `{x,y,z}` or nil; `fire`: bool; `veh`: key of an entry in `vehicles` or nil; `seat`: int or nil; `sparse`: true on
    samples that come from the 2 s `character_track` rather than the recorder)
  - `vehicles = { [key] = { id, model, colors, samples = { { t, x, y, z, rx, ry, rz, hp } … } } }`
  - `events = { { t, kind, char_id, other_char_id, item_id, vehicle_id, x, y, z, label, data } … }`
  - `world = { items = { [item_id] = { id, uname, x, y, z, rz, int, dim, sdata, holder, container, t_on, t_off } } }`
    — `t_on` ≤ 0 means present at the start; `t_off` nil means present at the end; an item that moves has one entry per
    version (`id` repeated, distinct `t_on`/`t_off`); rows held by a character (`holder`) or in a container are included
    only when `container` is a world crate/dumpster/tent (they draw as that structure), never inventories.
- `replaySessionEnded(id, reason)` — then the client restores everything.

Client → server (`net.handler`):

- `replayStopRequested(id)`, `replaySeekRequested(id, tMs)` (server may stream more chunks around `tMs`),
  `replaySubjectSwitchRequested(id, char_id)`.

Server-side exports of `replay`: `startSession(staff, spec)`, `stopSession(staff)`, `isReplaying(staff)`.
Client-side exports consumed from `items`: `setWorldHidden(bool)` and `getWorldModel(row)` (to be added by the client half).

## Appendix B — as built (server half, 2026-11-23)

Differences from the text above, so the client half reads the right thing:

- **No `logs`/Loki on prod.** Events come from `server.log` through `tools/replay_import_log.py` (kinds listed in
  `replay/shared/logic/kinds.lua`, timer in `ops/replay/`); the recorder adds only `replay.hit` itself. Log events have
  1 s resolution; recorder samples 200 ms.
- **`world.items` is keyed `"<item id>:<n>"`** (a string), because one item can have several versions; iterate with
  `pairs` and read `entry.id`. Each entry: `{ id, uname, x, y, z, rz, int, dim, sdata, container, t_on, t_off }` with
  `t_on` possibly negative (present at the start) and `t_off` nil (present at the end). `sdata` is the item's `data`
  as a table (usually an array `{ { defence = {...} } }`), `passcode`/`password`/`token`/`code` removed and `keypad`
  turned into `true`.
- **Vehicle keys are strings**: `"180"` (database id), `"m463"` (model only, trail-only data), `"-463"` (recorder, id
  unknown). `vehicles[key] = { id?, model, colors, samples = { { t, x, y, z, rx, ry, rz, hp } } }`; an actor sample's
  `veh` is that key. A passenger's or trail-only vehicle has `rx = ry = 0` and `hp = nil`.
- **Actor samples** carry exactly `t, x, y, z, rz, int, dim, hp, move, anim, weapon, aim ({x,y,z} in metres), fire,
  veh, seat, duty, sparse`; absent fields are nil. `t` may be negative for the last recorder sample before `from`.
  `move` is one of stand/crouch/walk/run/sprint/jump/fall/swim/climb/vehicle. Runs of identical samples are thinned to
  their first and last (interpolate between neighbours, do not assume a fixed rate). `sparse = true` samples come from
  the 2 s trail: heading is derived from movement and may be nil when standing.
- **Events** carry `{ t, kind, char_id, other_char_id, item_id, vehicle_id, x, y, z, int, dim, label, data }`.
  `building.removed` x/y/z is the position of the **defence**, not the player; the player's own position is on their
  neighbouring `item.taken`/`vehicle.*` events and in the actor samples. `info.kinds[kind] = { label, color, group }`.
- All data is sent up front in `replayChunkReceived` parts (about 60 ms apart); `replaySeekRequested` is accepted and
  does nothing. `replaySubjectSwitchRequested(id, charId)` restarts the session for that character (a new
  `replaySessionStarted` with a new id follows `replaySessionEnded(oldId, "switching")`).
- Aim and animation are not readable on the server: `replay/client/pose.lua` reports move state, animation and aim
  point (only on change, at most 5/s) as `replayPoseReported`; without it the recorder derives walk/run/crouch/swim
  from speed and leaves `anim`/`aim` empty (shots still record their end point).
- `ev_item_history` now keeps 14 days (was 7); a replay can show items only that far back. Recorder chunks 14 days,
  events 30 days.
- Command: `/replay <player|#charId> <from> [<to>|<length>]`, `/replay stop`, `/replay list <player>`; staff
  level >= 2 and on duty. `/replay at` and `/replay follow` are client-side controls, not server subcommands.
- Dev check without a viewer: `exports.replay:dryRun(target, fromUnix, toUnix)` then `exports.replay:getDryRun()` (JSON).
