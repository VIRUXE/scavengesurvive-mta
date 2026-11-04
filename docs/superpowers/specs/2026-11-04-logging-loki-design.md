# Structured game logging to Loki — design and rollout plan

Status: proposed (2026-11-04, transport decided the same day: direct push from the server, no agent). Companion to
the port design spec; this document only covers observability.

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
| Is the server healthy right now: DB errors, slow procedures, resource restarts, players online? | `db.*`, `system.*`, `script.*` |
| Is the economy drifting (loot rolled vs picked, vehicles spawned vs abandoned, deaths/hour)? | LogQL aggregates over `loot.*`, `vehicle.*`, `character.died` |

## 2. Architecture

```
resources ──exports.logs:write()──> logs resource ──batches, fetchRemote POST──> Loki /loki/api/v1/push ──> Grafana
MTA script errors/warnings ──onDebugMessage──┘
```

**Direct push, no agent, no file.** The game resources hand every event to one resource, `logs`, which batches
lines in memory and POSTs them to Loki's push API from the server itself (user decision 2026-11-04). Nothing is
installed on the host beside MTA and MariaDB, and a dev box only needs the Loki URL in `local.settings.xml`.
The costs of that choice, and how the design pays them:

- *Loki down or slow*: the batch stays in memory and is retried with backoff; the buffer is bounded
  (`*logs.max_lines`, default 20 000 ≈ 10 MB), the oldest lines are dropped beyond it and the drop is counted and
  reported as `system.logDropped` once the push works again. A `shutdown` loses the lines of the last flush
  interval that were not yet acknowledged (1 s); the console still shows every `warn`/`error`, so an incident
  is never silent even when Loki is unreachable.
- *Secrets on the game host*: the URL, tenant and token live in `local.settings.xml`, which is git-ignored and
  already holds the DB password (`*lib.db_pass`), under `*logs.url`, `*logs.tenant`, `*logs.user`, `*logs.pass`.
- *MTA's own logs*: `server.log` and `scripts.log` live outside the resource sandbox, so they cannot be read and
  pushed. Script errors and warnings are captured instead through the server event `onDebugMessage`, which
  fires for every `scripts.log` line (`script.error` / `script.warning` kinds below). The MariaDB error log and
  the Discord relay journal are not shipped; if they are ever wanted, a Grafana Alloy install on the host is
  the add-on, not a change to this design.
- *Main-thread cost*: `fetchRemote` runs the request on MTA's HTTP worker and calls back on the main thread; the
  only main-thread work is building one JSON body per flush (string concatenation of already-serialised lines).

**One sender.** New resource `logs` (`resources/[scavengesurvive]/logs/`, no prefix): exports `write(line)` and
keeps the buffer, the flush timer, the retry state and the heartbeat. Other resources never call `fetchRemote`.
When `logs` is not running, the `lib` module falls back to `outputServerLog`, so a dev box that has not started
it loses nothing on the console.

**Thin API in `lib`.** New module `lib/modules/log.lua`, loaded like `db`:

```lua
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
log.event("item.pickedUp", { player = player, item_id = id, uname = uname, x = x, y = y, z = z })
log.warn("loot", "no spawn rows for zone %s", zone)   -- util.log keeps working; it delegates here
```

`log.event(kind, fields, level)` adds `level` (`info` unless given), `resource` (the caller's resource
name), and, when `fields.player` is a player element, replaces it with `player` (name), `account_id`
(`exports.auth:getAccountId`), `character_id` (`exports.character:getCharacterId`) and drops the element. It
serialises the line once and calls `exports.logs:write(line, labels)`. Levels: `debug` (dropped unless
`*logs.level=debug`), `info`, `warn`, `error`. `warn` and `error` are echoed to the server console through
`outputServerLog` as today, so the console stays the quick look and Loki is the record.

**Line format** (one object per entry, flat, numbers unquoted, no nesting beyond one level):

```json
{"level":"info","resource":"items","kind":"item.pickedUp",
 "msg":"Bob picked up M9Pistol#123","player":"Bob","account_id":12,"character_id":34,
 "item_id":123,"uname":"M9Pistol","x":2041.2,"y":-1764.9,"z":13.5,"int":0,"dim":0,"zone":"LS"}
```

- `kind` is `<domain>.<pastTenseVerb>` camelCase, the same convention as event names (`itemPickedUp` the event,
  `item.pickedUp` the log kind), so a reader of `shared/events.lua` recognises them. Domains are the resource
  names plus `session`, `combat`, `db`, `system`, `script`.
- `msg` is optional, English, for the Explore view; every fact in it is also a field.
- There is no `ts` inside the line: `logs` stamps each entry on arrival with the Loki nanosecond timestamp (UTC,
  a string, from `getRealTime` at start plus `getTickCount` deltas, re-synced hourly, a per-line counter in the last
  six digits), so a retried batch keeps the real order.
- Encoded by `log.build` itself (flat object, arrays of scalars allowed, no `toJSON`), invalid UTF-8 replaced,
  strings cut at 512 bytes on a character boundary (chat text is cut at 256 by its caller).
- `serial` and `ip` appear only in `session.*` kinds; nothing else carries them.

**Loki labels** (index) stay small: `job="ss-game"`, `host` (`*logs.host`), `env` (`*logs.env`: `prod`/`dev`),
`level`, `resource`, `kind` (~70 values). `player`, `account_id`, `character_id`, `item_id`, `vehicle_id` go to
structured metadata (Loki 3.x) so `{job="ss-game"} | player="Bob"` is fast without indexing names.

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
| `script.error` / `script.warning` | error / warn | `logs` listens to `onDebugMessage` (every `scripts.log` line) | `file`, `line`, `msg`; `outputDebugString` info lines are ignored |
| `system.logDropped` | warn | `logs`, after a push succeeds following drops | `dropped`, `outage_s` |
| `system.pushFailed` | error (console only, never pushed) | `logs`, on the first failure and then once a minute | `status`, `error`, `queued` |

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
| `vehicle.starterFailed` | `vehicle_id`, `model`, `pos` — the start that spent the starter motor's life |
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

## 4. The push, and the Loki side

**Push mechanics** (`logs/server/push.lua`, pure parts in `logs/shared/logic/batch.lua`):

- `write(line, labels)` appends `{ ts_ns, line, labels, meta }` to the buffer. Entries are grouped per label set
  at flush time into Loki's `streams` array: `{"stream":{"job":"ss-game","host":…,"level":…,"resource":…,
  "kind":…},"values":[["<ns>","<line>",{"player":"Bob","item_id":"123"}]]}`. The third element of a value is
  the structured metadata (Loki ≥ 3.0, schema v13 / TSDB); string values only.
- The nanosecond timestamp is a **string built by concatenation** (`seconds .. ("%03d"):format(ms) ..
  "000000"`): a Lua 5.1 double cannot hold 1.7e18 exactly.
- Flush every `*logs.flush_ms` (1000) or when 500 entries are waiting, whichever first; a batch is at most 500
  entries / ~1 MB (Loki's default request limit is larger, but a smaller body retries cheaply).
- `fetchRemote(url .. "/loki/api/v1/push", options, cb)` with `options = { method = "POST", headers = {
  ["Content-Type"] = "application/json" }, postData = body, queueName = "loki", connectionAttempts = 1,
  connectTimeout = 5000 }`. **Credentials are optional**: `pushOptions(settings)` in
  `logs/shared/logic/batch.lua` adds `username`/`password` only when both `*logs.user` and `*logs.pass` are
  non-empty, and `headers["X-Scope-OrgID"]` only when `*logs.tenant` is non-empty, so a local Loki with
  `auth_enabled: false` (the user's case) takes a bare `url` and sends no auth header and no tenant, while
  Grafana Cloud or a Loki behind basic auth gets both from the same three settings. A token-style setup
  (`Authorization: Bearer …`) is `*logs.bearer`, added as a header the same way. `queueName` serialises the
  pushes so batches arrive in order; retries are ours, not MTA's. Verify the option names against the
  `mta-wiki` MCP before coding (the table form of `fetchRemote` is the 1.5.7+ signature; the callback receives
  `data, info` with `info.success` and `info.statusCode`).
- Response handling: `204` → done, send the next batch at once if one is waiting. `429` or `5xx` or
  `success=false` → keep the batch at the front of the queue, back off 2 s → 4 s → … → 60 s, console
  `system.pushFailed` once, then once a minute while it lasts. `400` → the batch is malformed or too old
  (`too far behind` after a long outage with a small `reject_old_samples_max_age`): log the body's first 300
  characters to the console, drop that batch, continue; the design keeps lines small enough that the only
  realistic `400` is age. Any other `4xx` (401/403/404) → configuration: drop nothing, back off at 60 s and
  console once a minute.
- Buffer bound: `*logs.max_lines` entries (20 000); beyond it the oldest entries are dropped and counted;
  `system.logDropped` goes out with the first successful push afterwards.
- `onResourceStop` of `logs`: one last flush is sent; its callback may never run, which is the accepted 1 s loss
  on `shutdown`. `onResourceStart` of any other resource re-attaches nothing: `write` is an export, so
  `rr items` keeps logging without `rr logs`.
- ACL: the stock `Default` ACL allows `function.fetchRemote`; if a host's ACL was hardened, `run-local.ps1` adds
  it to the `ScavengeSurvive` group like `function.loadstring`.

**Settings** (`logs/meta.xml`, overridden in `local.settings.xml` as `*logs.<name>`): `url` (empty = pushing
off, console only), `tenant`, `user`, `pass`, `bearer` (all empty by default = no auth, no tenant header),
`host`, `env`, `level` (`info`), `slow_ms` (50), `flush_ms` (1000), `max_lines` (20000). `run-local.ps1`
adds the `logs` lines to the example settings file it creates, with only `url` filled in
(`http://127.0.0.1:3100`). The local case is therefore one line in `local.settings.xml`:

```xml
<setting name="*logs.url" value="http://127.0.0.1:3100"/>
```

Grafana Cloud takes `user` = the stack's numeric user id and `pass` = an access policy token with
`logs:write`; a self-hosted Loki behind basic auth works the same; a reverse proxy expecting a bearer token
takes `bearer`. `logs` prints which of the three it is using (never the secret) in one console line at start.

**Loki**: `retention_enabled` with `retention_period` 90 days for `ss-game`; `session.*` carries IPs and
serials, so a shorter period is one `retention_stream` selector on `kind=~"session\\..*"`. Set
`reject_old_samples_max_age` to at least 24 h so a long outage's buffer is accepted when the server
reconnects. Structured metadata requires Loki ≥ 3.0 and schema v13 / TSDB.

**Grafana**: three dashboards built from LogQL, no Prometheus needed in v1.

- **Ops**: `rate({job="ss-game", level="error"}[5m])`, `db.callFinished` p95 `ms` by `proc`
  (`quantile_over_time`), players from `system.heartbeat` (`unwrap players`), resource restarts,
  `script.error` lines, `system.logDropped`.
- **Moderation**: last 200 `staff.*`, `anticheat.*`, `combat.hitRejected`, `chat.messageSent` with a `player`
  variable; a "player timeline" panel: `{job="ss-game"} | player="$player" or killer="$player" or to="$player"`.
- **Economy**: deaths/hour, `item.created` by `source`, `loot.refillTicked` cap vs alive by zone, vehicles
  spawned vs removed.

**Alerts** (Loki ruler, Grafana contact point to the Discord staff channel, so it complements `sendStaffLog`):
no `system.heartbeat` for 3 min (server down **or** Loki unreachable from it; the console `system.pushFailed`
tells which); `db.queryFailed` > 0 in 5 min; `anticheat.kicked` > 5 in 10 min; `character.combatLogged` > 10
in 1 h; `db.callFinished` p95 > 250 ms for 10 min; any `system.logDropped`.

## 5. Rollout, in commits

Each step is one conventional commit, `luacheck` and `stylua` clean, `rr <resource>` on the dev server, a line in
`docs/reviews/<date>-live-checks.md` when it touches play.

1. **`feat(logs): push structured game logs to Loki`** — the `logs` resource (buffer, batching, push with
   retry and backoff, heartbeat, `onDebugMessage`, resource start/stop), `lib/modules/log.lua`, `util.log`
   delegating to it, `server-config/resources.xml` entry and the settings in `local.settings.example.xml` (a
   `run-local.ps1` run for the ACL). `db.lua` gets `db.queryFailed` and the `db.call` timing wrapper. Proven
   on the dev box against a local Loki in Docker (`grafana/loki` with `auth_enabled: false` + `grafana/grafana`,
   one `docker compose` file under `ops/loki/` for dev only, no credentials involved). Deliverable: every existing log line and every script error arrives
   in Loki with level and resource, DB failures and slow procedures are visible.
2. **`docs(runbooks): logging-loki`** — `docs/runbooks/logging-loki.md` (the settings, how to check a line
   reaches Loki with `rcon.ps1 lua`, what `system.pushFailed` on the console means and the backoff, how to
   switch `*logs.level` to `debug` for an evening, token rotation), and the `incident-db-down.md` step 1
   pointing at the Grafana Ops dashboard instead of grepping `scripts.log`.
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
off ⇒ under 1 MB/min, ~1 GB/day uncompressed, ~150 MB/day in Loki chunks; 90 days ≈ 15 GB. The push is one
POST per second of a few KB; building the body is one `table.concat` on the main thread. A 20 000-line buffer
is about 10 MB of Lua memory and covers a 1–2 h Loki outage at that rate. `combat.hit` on adds up to 10
lines/s in a fight; `*logs.level=debug` is for a session, not a default.

## 8. Out of scope

Metrics (Prometheus exporters) and traces; any host-side agent (Grafana Alloy) and with it `server.log`,
the MariaDB error or slow log and the Discord relay journal (an Alloy install would add them later without
touching this design); a disk spill for the buffer during a Loki outage (bounded memory and a drop counter
are the accepted trade-off); replacing the DB audit tables, which the in-game staff commands read; the Discord
relay staff channel, which stays as the push notification path and gains Grafana alerts beside it.
