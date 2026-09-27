# scavengesurvive-mta — conventions

Scavenge & Survive ported to MTA:SA 1.6 (Lua 5.1) with MariaDB 12.2. Design spec:
`docs/superpowers/specs/2026-09-27-scavengesurvive-mta-port-design.md` (Appendix A = upstream behaviour, Appendix B = verified MTA facts).

## Layout

- `resources/[scavengesurvive]/<name>/` — one MTA resource per domain, **no prefix**. Inside: `meta.xml`, `shared/`, `server/`, `client/`.
- `lib` resource serves modules: `local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()`.
- `sql/migrations/NNNN_name.sql` (DDL, plain statements), `sql/procedures/*.sql` (one `CREATE OR REPLACE PROCEDURE` per file, no DELIMITER), `sql/events/*.sql`, `sql/seed/*.sql` (generated).
- `tools/convert/*.py` — deterministic converters from `../ScavengeSurvive` into `data/generated/` + `sql/seed/`.
- `tests/lua` (busted), `tests/tools` (pytest), `tests/sql` (pytest + live MariaDB database `scavengesurvive_test`).

## Rules

- Events: `on<Domain><Thing><Verb>`; client→server `on<Domain>Request<Verb>` and server→client `onClient<Domain><Verb>` are registered with `addEvent(name, true)` (MTA only delivers `triggerServerEvent`/`triggerClientEvent` to events whose receiving side allows remote triggering); purely local events (e.g. `onClientUiListAction`, `onPlayerAuthenticated`) use `false`. Every resource declares every event it triggers or handles in `shared/events.lua`.
- Remote handlers are registered through `net.handler(...)` from `lib`; trust only the `client` global.
- DB: identical connection string in every resource (`lib/modules/db.lua`), `batch=0`; anything touching more than one row is a stored procedure returning `SELECT ok, code, payload`.
- Stored procedures: `SET TRANSACTION ISOLATION LEVEL READ COMMITTED;` before every `START TRANSACTION` (MariaDB 12 deadlocks/`1020` under REPEATABLE READ with `FOR UPDATE` races); numbers in `JSON_OBJECT` payloads are wrapped in `CAST(x AS SIGNED)` (procedure variables serialise as strings otherwise); compare possibly-NULL ownership columns with `<=>`.
- DB rows: NULL arrives as `false`; DECIMAL as string; FLOAT is 32-bit; never select raw POINT (`ST_X/ST_Y`); every `?` in SQL text is a placeholder (`CHAR(63)` for a literal).
- Client never calls `setElementData`. Server-set element data uses `"deny"`. `elementdata_whitelisted=1`.
- Pure logic lives in `shared/logic/*.lua` and never calls MTA functions at file scope, so busted can `dofile` it with `tests/lua/helpers/mta_mock.lua`.
- Style: `stylua` and `luacheck` clean before every commit. Conventional commits (`feat(items): …`).
- Never commit `server-config/local.settings.xml` (holds the DB password) or anything under `models/files/`.

## Commands

- `pwsh tools/setup-dev.ps1` — hererocks Lua 5.1 + busted/luacheck/luacov, stylua, Python deps.
- `.lua/bin/busted tests/lua` · `.lua/bin/luacheck resources` · `stylua --check resources` · `pytest -q`
- `pwsh server-config/run-local.ps1` — create DB, migrate, seed, link resources into the MTA server, start it.
