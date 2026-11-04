# Structured game logging to Loki — design and rollout plan

Status: proposed (2026-11-04). Companion to the port design spec; this document only covers observability.

## 1. Why, and what the logs must answer

A permadeath PvP survival server lives on disputes and on trust: "I was killed by a hacker", "my base was raided
through a wall", "a staff member spawned a gun for their friend", "the server froze and I lost my bag". Today the
answers are spread over `scripts.log`, `server.log`, a few DB tables (`staff_actions`, `connection_log`,
`vehicle_events`, `anticheat_field_logs`) and the Discord staff channel, with 70-odd `util.log` lines of free text.
Nothing is queryable by player or by time across resources.

The logging has to answer, from one Grafana Explore window, within a minute:

| Question | Stream(s) |
| --- | --- |
| What happened to character X between 20:00 and 20:10? | every `kind` filtered by `character_id` |
| Who killed Y, with what, where, and was Y combat-logged? | `character.died`, `combat.*`, `character.combatLogged` |
| Where did item #123 (or every `M4` created this week) come from and go? | `item.*` by `item_id` / `uname` |
| Did a staff member abuse a command? | `staff.*`, `dev.*` by `actor` |
| Is a serial / IP evading a ban? | `session.*` with `serial`, `ip`, `account_id` |
| Did anticheat fire, and on whom, before a ban appeal? | `anticheat.*` |
| Is the server healthy right now: DB errors, slow procedures, resource restarts, players online? | `db.*`, `system.*`, raw MTA logs |
| Is the economy drifting (loot rolled vs picked, vehicles spawned vs abandoned, deaths/hour)? | LogQL aggregates over `loot.*`, `vehicle.*`, `character.died` |

## 2. Architecture

```
resources ──exports.logs:write()──> logs resource ──> logs/game-YYYY-MM-DD.jsonl ─┐
MTA server ───────────────────────> logs/server.log, logs/scripts.log            ├─> Grafana Alloy ──> Loki ──> Grafana
MariaDB ──────────────────────────> mariadb error log                             │
mta-discord-relay ────────────────> journald                                      ┘
```

**File + agent, not direct push.** The game writes newline-delimited JSON to a file and Grafana Alloy ships it.
Reasons, in order: a Loki outage or a slow link never touches the game (the disk is the buffer, Alloy retries with
backoff); the Loki URL and tenant token live in Alloy's config, not in an MTA setting; one agent also ships the
three logs the game cannot produce (`server.log`, `scripts.log` with MTA's own script errors, the MariaDB error
log) and the relay's journal, so an incident is read in one place; no HTTP work on the MTA main thread.
`fetchRemote` push stays out of scope (it would need batching, retry, backoff and a token in `settings.xml`;
Alloy already does all of that and has a Windows build for dev boxes). Promtail is end-of-life since 2026-03;
Alloy is the supported agent.

**One writer.** MTA file functions are sandboxed per resource and nothing serialises writes across resources, so
a single resource owns the file. New resource `logs` (`resources/[scavengesurvive]/logs/`, no prefix, like the
others): opens today's file at start, seeks to the end (MTA has no append mode), buffers lines, flushes on a 1 s
timer and on `onResourceStop`, rolls the file at midnight UTC, deletes files older than `*logs.retain_days`
(default 7; Loki keeps the history). The directory `resources/[scavengesurvive]/logs/logs/` is git-ignored like
`dev/screenshots/` (prod resources are a symlink into the clone).

**Thin API in `lib`.** New module `lib/modules/log.lua`, loaded like `db`:

```lua
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
log.event("item.pickedUp", { player = player, item_id = id, uname = uname, x = x, y = y, z = z })
log.warn("loot", "no spawn rows for zone %s", zone)   -- util.log keeps working; it delegates here
```

`log.event(kind, fields, level)` adds `ts`, `level` (`info` unless given), `resource` (the caller's resource
name), and, when `fields.player` is a player element, replaces it with `player` (name), `account_id`
(`exports.auth:getAccountId`), `character_id` (`exports.character:getCharacterId`) and drops the element. It
calls `exports.logs:write(line)`; when `logs` is not running it falls back to `outputServerLog(line)` so nothing
is lost on a dev box that has not started it. Levels: `debug` (dropped unless `*logs.level=debug`), `info`,
`warn`, `error`. `warn` and `error` are echoed to the server console through `outputServerLog` as today, so the
console stays the quick look and the file is the record.

**Line format** (one object per line, flat, numbers unquoted, no nesting beyond one level):

```json
{"ts":"2026-11-04T20:03:11.412Z","level":"info","resource":"items","kind":"item.pickedUp",
 "msg":"Bob picked up M9Pistol#123","player":"Bob","account_id":12,"character_id":34,
 "item_id":123,"uname":"M9Pistol","x":2041.2,"y":-1764.9,"z":13.5,"int":0,"dim":0,"zone":"LS"}
```

- `kind` is `<domain>.<pastTenseVerb>` camelCase, the same convention as event names (`itemPickedUp` the event,
  `item.pickedUp` the log kind), so a reader of `shared/events.lua` recognises them. Domains are the resource
  names plus `session`, `combat`, `db`, `system`.
- `msg` is optional, English, for the Explore view; every fact in it is also a field.
- `ts` is UTC RFC 3339 with milliseconds, derived from `getRealTime().timestamp` at resource start plus
  `getTickCount()` deltas (re-synced hourly). Alloy uses it as the entry timestamp, so a late flush keeps the real
  order.
- Built with `toJSON(fields, true)` and the outer `[ ]` stripped (as `death.lua` already does). Strings are
  truncated at 512 characters; chat text at 256.
- `serial` and `ip` appear only in `session.*` kinds; nothing else carries them.

**Loki labels** (index) stay small: `job` (`ss-game`, `ss-server`, `ss-scripts`, `mariadb`, `discord-relay`),
`host`, `level`, `resource`, `kind` (~70 values). `player`, `account_id`, `character_id`, `item_id`, `vehicle_id`
go to structured metadata (Loki 3.x) so `{job="ss-game"} | player="Bob"` is fast without indexing names.

## 3. Event catalogue

Each row is one `log.event` call site (or one shared helper). "Fields" lists what the line carries besides the
common ones; `pos` means `x y z int dim zone`.

### system / db (resource `logs`, `lib`)

| kind | level | where | fields |
| --- | --- | --- | --- |
| `system.resourceStarted` / `resourceStopped` | info | `logs` listens to `onResourceStart`/`Stop` on `root` | `name`, `stop_reason` |
| `system.heartbeat` | info | `logs`, every 60 s | `players`, `uptime_s`, `lua_kb`, `queued_lines`; a missing heartbeat is the "server down" alert |
| `db.connectFailed` | error | `db.connect` | `tag` |
| `db.queryFailed` | error | `db.lua` `poll` | `tag`, `errno`, `error`, `sql` (first 200 chars), `ms` |
| `db.callFinished` | debug (info when `ms` > `*logs.slow_ms`, default 50) | `db.call` wrapper: every stored procedure, success or not | `proc`, `ok`, `code`, `ms`; the wrapper measures from `dbQuery` to callback, so queue wait is included |
| `log.message` | as given | `util.log` | `tag`, `msg` (the 70 existing lines keep working unchanged; they are converted to real kinds domain by domain) |

### session (resource `auth`)

| kind | level | fields |
| --- | --- | --- |
| `session.joined` | info | `serial`, `ip`, `version`, `country` (if fetched) — on `onPlayerJoin` |
| `session.authenticated` | info | `account_id`, `method` (`password`, `autologin`, `register`, `restored`) — where `playerAuthenticated` is raised |
| `session.refused` | info | `reason` (`banned`, `inactive`, `alreadyOnline`, `notWhitelisted`, `badPassword`), `ban_id` — the 6 existing `refused` lines |
| `session.kicked` | info | `reason` (`whitelistCountdown`, …) |
| `session.left` | info | `quit_reason`, `duration_s` — on `playerLoggedOut` |
| `session.languageSet`, `session.passwordChanged` | info | `lang` / `code` |
| `session.whitelistToggled` | info | `on`, `staff_online` |

### staff / dev / anticheat

| kind | level | fields |
| --- | --- | --- |
| `staff.actionTaken` | info | `actor`, `actor_account_id`, `action`, `target`, `target_account_id`, `details` — **one call in `ctx.log`** covers every privileged command; `staff_ban` / `staff_warn` / `staff_unban` log from their callbacks with `ban_id`, `expires_at` |
| `staff.dutyChanged` | info | `on` |
| `staff.reportFiled` / `reportRead` / `bugReported` | info | `report_id`, `reason`, `about` |
| `dev.commandUsed` | warn | `command`, `args` — every `dev` command (`/additem`, `/sethp`, `rr`, HTTP `lua`), because on a shared server these are the item-dupe path |
| `anticheat.detected` | warn | `check`, `detail` — in the existing `log()` helper in `anticheat/server/main.lua` |
| `anticheat.kicked` | warn | `check`, `reason` |
| `anticheat.trapTriggered`, `anticheat.fieldEntered` | warn | `trap_id` / `field_id`, `pos` |

### character / combat (resources `character`, `weapons`)

| kind | level | fields |
| --- | --- | --- |
| `character.created` | info | `name`, `skin` |
| `character.spawned` | info | `pos`, `fresh` (new character or re-login) |
| `character.died` | info | `cause`, `killer`, `killer_account_id`, `killer_character_id`, `weapon`, `pos`, `age_s` (character lifetime), `items_dropped` — from `death.die` after `character_death_drop` returns |
| `character.combatLogged` | warn | `attacker`, `window_s`, `since_damage_s` — the quit handler branch that counts as a death |
| `character.knockedOut` / `character.wokeUp` | info | `by` |
| `combat.hit` | debug | `attacker`, `victim`, `weapon`, `bodypart`, `loss`, `distance`, `pos` — in `weaponHitReported` after validation; debug because of volume, switched on for an evening when a cheating report comes in |
| `combat.hitRejected` | warn | `reason` (`maxLoss`, `dimension`, `dead`, `cuffed`, …), `attacker`, `victim` — rejected reports are the cheat signal, so these are always on |
| `character.dropAll` | info | `items` — `/dropall` |

### items (resource `items`, `crafting`, `explosives`)

One helper per procedure callback: `logic.logProc(kind, player, res, extra)` writes `ok`/`code` with the fields, so a
refused action (`code="NOT_NEAR"`, `"FULL"`) is logged at `info` with `ok=false` rather than silently dropped.

| kind | fields |
| --- | --- |
| `item.pickedUp`, `item.dropped`, `item.putAway`, `item.taken` | `item_id`, `uname`, `pos` |
| `item.given` | `item_id`, `uname`, `to`, `to_account_id`, `to_character_id` — trades are the dupe/RMT path |
| `item.destroyed` | `item_id`, `uname`, `reason` (`used`, `broken`, `burned`, `staff`) |
| `item.containerMoved` (put/take/move) | `item_id`, `uname`, `container_id`, `container_uname`, `direction` |
| `item.worn` / `item.unworn` | `item_id`, `uname` |
| `item.created` | `item_id`, `uname`, `source` (`loot`, `craft`, `staff`, `dev`, `body`, `vehicleKey`, …), `pos` — in the `itemCreated` handler of the creator, which knows the source |
| `item.worldMoved` | `item_id`, `vehicle_id` — trunk cargo following a vehicle (batched; log the count, not each row) |
| `crafting.finished` / `crafting.failed` | `recipe`, `inputs` (unames), `output_uname`, `output_id`, `code` |
| `machine.finished` | `machine_id`, `machine_uname`, `output_uname` |
| `explosive.armed` / `explosive.disarmed` / `explosive.detonated` | `item_id`, `uname`, `pos`, `victims` (names), `vehicles` (ids), `defences` (ids) |
| `weapon.unloaded` / `ammoFlushFailed` | `item_id`, `rounds` |

### vehicles / building / world economy

| kind | fields |
| --- | --- |
| `vehicle.spawned` / `vehicle.removed` | `vehicle_id`, `model`, `pos`, `reason` (`refill`, `abandoned`, `exploded`, `staff`) |
| `vehicle.entered` / `vehicle.exited` | `vehicle_id`, `seat`, `pos` — next to the existing `vehicle_events` insert |
| `vehicle.lockToggled`, `vehicle.keypadFailed`, `vehicle.keypadOpened` | `vehicle_id`, `locked` / `attempts` |
| `vehicle.exploded` | `vehicle_id`, `model`, `pos`, `cargo` (item count lost) |
| `vehicle.partInstalled` / `partRemoved` / `carmourWelded` / `carmourAttached` | `vehicle_id`, `part`, `item_id` |
| `building.placed` / `building.removed` | `defence_id`, `uname`, `pos`, `plot_id` |
| `building.keypadFailed` / `keypadOpened` / `keypadInstalled` | `defence_id`, `attempts` — raid evidence |
| `loot.rolled` | `zone`, `spots`, `items`, `ms` — per `loot_roll` batch, not per item |
| `loot.refillTicked` | `zone`, `cap`, `alive`, `spawned` — the ADR 0001 budget per tick |
| `loot.supplyDropped` / `loot.cacheSpawned` | `pos`, `items` |
| `world.treeFelled`, `world.crateOpened`, `world.buttonPressed` | ids, `pos` |

### chat (resource `chat`)

| kind | level | fields |
| --- | --- | --- |
| `chat.messageSent` | info | `mode` (`local`, `global`, `radio`, `whisper`), `frequency`, `text` (256 chars), `pos` — in the `onPlayerChat` handler; the moderation record |
| `chat.commandUsed` | debug | `command` — `onPlayerCommand`, for the unknown-command noise question |

Voice start/stop, HUD, UI and client-only events are not logged.

## 4. Alloy and Loki configuration

`ops/alloy/config.alloy` (new directory in the repo; the host copies it to `/etc/alloy/`):

- `local.file_match` + `loki.source.file` for `<resources>/logs/logs/game-*.jsonl` (`job="ss-game"`),
  `$DM/logs/server.log` (`ss-server`), `$DM/logs/scripts.log` (`ss-scripts`), the MariaDB error log (`mariadb`);
  `loki.source.journal` with `_SYSTEMD_UNIT=mta-discord-relay.service`.
- `loki.process` for `ss-game`: `stage.json` → `stage.timestamp` (`ts`, RFC3339) → `stage.labels`
  (`level`, `resource`, `kind`) → `stage.structured_metadata` (`player`, `account_id`, `character_id`, `item_id`,
  `vehicle_id`). For `ss-scripts`: `stage.regex` on `^\[(?P<ts>[^\]]+)\] (?P<level>ERROR|WARNING|INFO)` → label
  `level`; for `ss-server`: timestamp only.
- `loki.write` to the Loki endpoint with `tenant_id` / basic auth from `/etc/alloy/env` (never in git).
- `$DM/logs/*.log` are never rotated by MTA: add a `logrotate` rule with `copytruncate` (Alloy follows
  truncation) and keep `game-*.jsonl` rotation inside the `logs` resource.

Loki: `retention_enabled` with per-stream retention: `ss-game` 90 days, `ss-server`/`ss-scripts` 14 days,
`mariadb`/`discord-relay` 14 days. `session.*` carries IPs and serials; if a shorter retention is wanted for
those it is one more `retention_stream` selector on `kind=~"session\\..*"`. Structured metadata requires Loki
≥ 3.0 and schema v13 / TSDB.

Grafana: three dashboards built from LogQL, no Prometheus needed in v1.

- **Ops**: `rate({job="ss-game", level="error"}[5m])`, `db.callFinished` p95 `ms` by `proc`
  (`quantile_over_time`), players from `system.heartbeat` (`unwrap players`), resource restarts, `ss-scripts`
  ERROR lines.
- **Moderation**: last 200 `staff.*`, `anticheat.*`, `combat.hitRejected`, `chat.messageSent` with a `player`
  variable; a "player timeline" panel: `{job="ss-game"} | player="$player" or killer="$player" or to="$player"`.
- **Economy**: deaths/hour, `item.created` by `source`, `loot.refillTicked` cap vs alive by zone, vehicles
  spawned vs removed.

Alerts (Loki ruler, Grafana contact point to the Discord staff channel, so it complements `sendStaffLog`):
no `system.heartbeat` for 3 min; `db.queryFailed` > 0 in 5 min; `anticheat.kicked` > 5 in 10 min;
`character.combatLogged` > 10 in 1 h; `db.callFinished` p95 > 250 ms for 10 min.

## 5. Rollout, in commits

Each step is one conventional commit, `luacheck` and `stylua` clean, `rr <resource>` on the dev server, a line in
`docs/reviews/<date>-live-checks.md` when it touches play.

1. **`feat(logs): structured game log file and lib log module`** — the `logs` resource (writer, rotation,
   heartbeat, resource start/stop), `lib/modules/log.lua`, `util.log` delegating to it, `.gitignore` entry,
   `server-config/resources.xml` entry (and a `run-local.ps1` run for the ACL). `db.lua` gets `db.queryFailed`
   and the `db.call` timing wrapper. Deliverable: every existing log line arrives in Loki as JSON with level and
   resource, DB failures and slow procedures are visible.
2. **`chore(ops): Alloy config, logrotate rule, runbook`** — `ops/alloy/config.alloy`, `ops/logrotate/mta`,
   `docs/runbooks/logging-loki.md` (install Alloy, where the token lives, how to check a line reaches Loki, how
   to switch `*logs.level` to `debug` for an evening, what to do when the disk fills), and the
   `incident-db-down.md` step 1 pointing at the Grafana Ops dashboard instead of grepping `scripts.log`.
3. **`feat(auth): session log kinds`** — replace the 13 `util.log` lines with `session.*`; `connection_log` stays
   (the in-game `/aliases`-style commands read it).
4. **`feat(staff): staff, dev and anticheat log kinds`** — `ctx.log`, the three ban/warn callbacks, duty, reports,
   `dev` commands and the HTTP `rcon` export, anticheat `log()`/`kick()`, traps and fields.
5. **`feat(character): death, combat-log and combat kinds`** — `death.die`, the quit handler, knockouts,
   `weaponHitReported` (debug hit, warn rejection).
6. **`feat(items): item graph kinds`** — the `logProc` helper and one call per procedure callback across
   `items/server/*.lua`, `crafting`, `explosives`, `weapons`; `item.created` with `source` from each creator.
7. **`feat(vehicles): vehicle kinds`**, **`feat(building): building kinds`**, **`feat(loot): economy kinds`**,
   **`feat(chat): chat record`** — one commit each; `world` trees, crates and buttons ride with `loot`.
8. **`feat(logs): dashboards and alert rules`** — `ops/grafana/*.json` (provisioned dashboards) and
   `ops/loki/rules.yaml`.
9. Optional, after a month of data: client error relay (`clientErrorReported` through `net.handler`, rate 1/s,
   from `addDebugHook("postFunction"...)` on the client, kind `client.scriptError` with `file`, `line`, `msg`,
   `fps`, `ping`) and a `client.sample` every 5 min (`fps`, `ping`, `streamed_objects`) for the "it lags for me"
   reports.

Order rationale: step 1 alone turns the existing lines into something searchable and makes the DB layer
observable, which is where every incident so far was diagnosed; steps 3–5 are small (a few dozen lines each) and
carry the highest moderation value; step 6 is the largest surface and benefits from the helper settled in step 5.

## 6. Rules that come with it (to add to CLAUDE.md when step 1 lands)

- A server-side state change that a player can dispute (anything that creates, moves, destroys or transfers an
  item, kills or spawns a character, places or removes a defence, spawns or removes a vehicle, or acts on an
  account) logs one `log.event` with the ids involved; refused actions log with `ok=false` and the `code`.
- Kinds are `<domain>.<pastTenseVerb>`; fields are flat, snake_case, numbers unquoted; a player element goes in as
  `player` (or `attacker`, `victim`, `to`, `actor`) and the module expands it; `serial` and `ip` only in `session.*`.
- Nothing per frame or per tick: `combat.hit` is `debug`, `item.worldMoved` and `loot.rolled` log the batch.
- No secrets, passwords, keypad codes or tokens in any field (log `attempts`, never the code entered).
- `util.log` stays for free-text diagnostics; a fact a dashboard will count gets a kind.

## 7. Volume and cost

At 50 players: ~2 item events/s, ~1 chat line/s, `combat.hit` off, heartbeat 1/min, `db.callFinished` at debug
off ⇒ under 1 MB/min, ~1 GB/day uncompressed, ~150 MB/day in Loki chunks; 90 days ≈ 15 GB. Writing is one
`fileWrite` + `fileFlush` per second on the main thread (sub-millisecond on an SSD). `combat.hit` on adds up to
10 lines/s in a fight; `*logs.level=debug` is for a session, not a default.

## 8. Out of scope

Metrics (Prometheus exporters, `prometheus.exporter.unix`) and traces; shipping MariaDB's general or slow query
log (enable the slow log on the host and add one more `loki.source.file` if a procedure needs it); replacing the
DB audit tables, which the in-game staff commands read; the Discord relay staff channel, which stays as the
push notification path and gains Grafana alerts beside it.
