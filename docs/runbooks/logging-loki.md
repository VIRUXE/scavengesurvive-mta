# Game log in Loki

**When:** setting up the log push on a host, a Grafana panel stays empty, the console prints `[logs] push to … failed`,
`system.logDropped` shows up, or a player dispute needs the record of what happened.

**What runs where:**

| Piece | Where | Notes |
| --- | --- | --- |
| `logs` (this repo) | `resources/[scavengesurvive]/logs` | buffers the lines and POSTs them to `<url>/loki/api/v1/push` every second; the only resource that calls `fetchRemote` |
| `lib` module `log` | `lib/modules/log.lua` | `log.event(kind, fields, level)` in every resource; falls back to the console when `logs` is not running |
| Loki + Grafana | anywhere reachable by HTTP (dev: `ops/loki/docker-compose.yml`) | no agent is installed on the game host |
| Dashboards, alert rules | `ops/grafana/dashboards`, `ops/loki/rules.yaml` | provisioned by the dev compose; import the JSON by hand elsewhere |

Design, event catalogue and label scheme: `docs/superpowers/specs/2026-11-04-logging-loki-design.md`.

## Set up

1. A Loki 3.x with `allow_structured_metadata: true` and the TSDB v13 schema (`ops/loki/loki.yaml` is a working
   single-binary config). Locally: `docker compose -f ops/loki/docker-compose.yml up -d`.
2. In `server-config/local.settings.xml` (git-ignored) add the one line a local Loki needs:
   `<setting name="*logs.url" value="http://127.0.0.1:3100"/>`. Credentials are optional and only used when set:
   `*logs.tenant` (header `X-Scope-OrgID`), `*logs.user` + `*logs.pass` (basic auth, Grafana Cloud: stack user id and an
   access policy token with `logs:write`), `*logs.bearer` (bearer token, replaces basic auth). `*logs.env` should be
   `prod` on the production host; `*logs.host` names the machine.
3. Stop the server and run `pwsh server-config/run-local.ps1` once: it adds `logs` to the startup list and grants only
   that resource `function.fetchRemote` (group `ScavengeSurviveLogs`). `start logs` on a running server without that
   run fails with `Access denied @ 'fetchRemote'`.
4. Start the server. `server.log` shows `[logs] pushing to http://127.0.0.1:3100 (no auth), host mta, env dev`.

## Check

1. Grafana Explore, `{job="ss-game"}`: `system.resourceStarted` for every resource and a `system.heartbeat` every minute.
2. From a staff account log in and out: `{job="ss-game", resource="auth"}` shows the session lines.
3. `rcon.ps1 cmd <player> additem M9Pistol` runs a stored procedure: with `*logs.level` at `debug` (or when it takes
   more than `*logs.slow_ms`) `{job="ss-game"} | kind="db.callFinished"` shows it with its `proc` and `ms`.

## Fix

- **`[logs] push to … failed (no connection)`**: Loki is down or the URL is wrong. The game keeps running, the lines
  wait in memory (`*logs.max_lines`, 20000, about 10 MB) and go out when Loki answers; the console prints this at
  most once a minute. Retries back off 2, 4, 8 … 60 s.
- **`HTTP 401/403/404`**: the credentials, tenant or URL path are wrong (`*logs.url` is the base, without
  `/loki/api/v1/push`). The batch is kept and retried every 60 s.
- **`Loki refused a batch … (HTTP 400)`**: usually `entry too far behind` after a long outage; raise
  `reject_old_samples_max_age` in Loki. That batch is dropped, the next ones go on.
- **`system.logDropped`**: the buffer overflowed during an outage; `dropped` is the count of lines lost, `outage_s`
  how long Loki was unreachable.
- **A debug evening** (every hit, every procedure call): set `<setting name="*logs.level" value="debug"/>`, `rr logs`;
  expect up to 10 lines per second in a fight. Set it back afterwards.
- **No `[logs]` line at all at start**: the resource did not start; `Access denied` means step 3 was skipped.
- **Token rotation**: change `*logs.pass` / `*logs.bearer` in `local.settings.xml`, run `run-local.ps1`, restart the
  server (settings are copied to `mods\deathmatch\settings.xml` at start).
- **Disabling the push**: remove the `*logs.url` line (or leave it empty). Warn and error lines still reach the
  console; nothing leaves the host.

## Rollback

Remove `logs` from `server-config/resources.xml`. The `log` module falls back to the server console, so no resource
needs a change. A dashboard or alert rule is reverted with the file in git.

## Escalation

Repository owner. The privacy note: `session.*` lines carry IPs and serials, everything else only names and ids;
nothing logs passwords, keypad codes or tokens.
