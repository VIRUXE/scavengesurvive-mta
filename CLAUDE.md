# scavengesurvive-mta — conventions

Scavenge & Survive ported to MTA:SA 1.6 (Lua 5.1) with MariaDB 13.0 (12.2 also verified). Design spec:
`docs/superpowers/specs/2026-09-27-scavengesurvive-mta-port-design.md` (Appendix A = upstream behaviour, Appendix B = verified MTA facts).

## Layout

- `resources/[scavengesurvive]/<name>/` — one MTA resource per domain, **no prefix**. Inside: `meta.xml`, `shared/`, `server/`, `client/`.
- `lib` resource serves modules: `local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()`.
- `sql/migrations/NNNN_name.sql` (DDL, plain statements), `sql/procedures/*.sql` (one `CREATE OR REPLACE PROCEDURE` per file, no DELIMITER), `sql/events/*.sql`, `sql/seed/*.sql` (generated).
- `tools/convert/*.py` — deterministic converters from `../ScavengeSurvive` into `data/generated/` + `sql/seed/`;
  `maps.py` writes `maps/data/<ZONE>.lua`, `maps/data/zones.lua`, `maps/meta.xml` and `docs/maps-census.md` (all generated, all committed).
- `tests/lua` (busted), `tests/tools` (pytest), `tests/sql` (pytest + live MariaDB database `scavengesurvive_test`).

## Rules

- Events: `on<Domain><Thing><Verb>`; client→server `on<Domain>Request<Verb>` and server→client `onClient<Domain><Verb>` are registered with `addEvent(name, true)` (MTA only delivers `triggerServerEvent`/`triggerClientEvent` to events whose receiving side allows remote triggering); purely local events (e.g. `onClientUiListAction`, `onPlayerAuthenticated`) use `false`. Every resource declares every event it triggers or handles in `shared/events.lua`.
- Remote handlers are registered through `net.handler(...)` from `lib`; trust only the `client` global.
- DB: identical connection string in every resource (`lib/modules/db.lua`), `batch=0`; anything touching more than one row is a stored procedure returning `SELECT ok, code, payload`.
- Stored procedures: `SET TRANSACTION ISOLATION LEVEL READ COMMITTED;` before every `START TRANSACTION` (MariaDB 12 deadlocks/`1020` under REPEATABLE READ with `FOR UPDATE` races); numbers in `JSON_OBJECT` payloads are wrapped in `CAST(x AS SIGNED)` (procedure variables serialise as strings otherwise); compare possibly-NULL ownership columns with `<=>`.
- DB rows: NULL arrives as `false`; DECIMAL as string; FLOAT is 32-bit; never select raw POINT (`ST_X/ST_Y`); every `?` in SQL text is a placeholder (`CHAR(63)` for a literal).
- Client never calls `setElementData`. Server-set element data uses `"deny"`. `elementdata_whitelisted=1`.
- Pure logic lives in `shared/logic/*.lua` and never calls MTA functions at file scope, so busted can `dofile` it with `tests/lua/helpers/mta_mock.lua`.
- No global tables used as static classes or singletons for a resource's state (`Maps = { stats = {}, … }`, `Character.byPlayer`): new code keeps state in file-local tables or closures, returns a module table, and passes state as arguments. The older `Character`/`Items`/`UI` globals are converted when their resource is reworked, not in passing.
- Never call `engineSetPoolCapacity("building", …)`: MTA grows the building pool on demand, and re-applying a capacity on a resource restart shrank a pool in use and crashed the client (2026-10-22).
- Style: `stylua` and `luacheck` clean before every commit. Conventional commits (`feat(items): …`).
- Never commit `server-config/local.settings.xml` (holds the DB password).
- SA-MP-only object models (ids 11682–11753, 18631+) live in the `models` resource (`manifest.lua` + `files/`, both
  committed). When an item type starts using one that is not in the pack, run `python -m tools.extract_samp_models`
  on a box with a SA-MP client and commit the result. Clients create item objects with `ItemModels.forType(t)`.

## Commands

- `pwsh tools/setup-dev.ps1` — hererocks Lua 5.1 + busted/luacheck/luacov, stylua, Python deps.
- `.lua/bin/busted.bat tests/lua` · `.lua/bin/luacheck.bat resources` · `stylua --check resources` · `pytest -q`
- `pwsh server-config/run-local.ps1` — create DB, migrate, seed, link resources into the MTA server, start it.
- `pwsh server-config/rcon.ps1 <command>` — drive the running server over its HTTP port (`help`, `players`, `rr items`,
  `cmd <player> additem M9Pistol`, `key <player> interact|inventory|arrow_d|enter|escape`, `lua return …`,
  `screenshot <player> [w h]`, `studio <player> [front|back|left|right|threequarter|top|face|hands|yaw dist height|off]`
  puts the ped alone on a chroma-green set for screenshots, see `docs/dev-studio.md`). MTA has no RCON; this is the `dev` resource's
  HTTP export. Verify MTA API names with the `mta-wiki` MCP (e.g. it is `takePlayerScreenShot`, capital S).
