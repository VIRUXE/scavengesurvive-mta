# Start, stop and restart

**When:** first start on a machine, a planned restart, or reloading one resource after a code change.

**Prerequisites:** MariaDB running and reachable with the credentials in `server-config/local.settings.xml`;
Python with the repo's requirements; the MTA server installed at `$MTA`.

## Start (full)

1. `pwsh server-config/run-local.ps1` from the repo root. It refuses to run while `MTA Server.exe` is up.
   It applies pending SQL (`tools.sqltool apply`: procedures, triggers, events, seeds, missing tables), turns the
   event scheduler on (item despawn, ban expiry, `items` history retention), copies the settings file,
   regenerates `mtaserver.conf` from the stock copy with the startup list from `server-config/resources.xml`,
   junctions the resources into `$DM\resources\[scavengesurvive]`, rebuilds the `ScavengeSurvive` ACL group and
   starts the server. Add `-NoStart` to prepare without starting, `-Reset` to drop and recreate the database
   (destroys every account, character and item: never on a live world).
2. Check `$DM\logs\server.log` for `Resources: N loaded, 0 failed` and `Server started and is ready to accept
   connections!`, and that `$DM\logs\scripts.log` has no `ERROR` or `Access denied` line since the start.
3. `rcon.ps1 players` answers (proves the HTTP export, and therefore the `dev` resource, is up).

## Stop

1. Warn players: `rcon.ps1 say Server restarting in 2 minutes`.
2. `rcon.ps1 shutdown` (or type `shutdown` in the server console). Every resource flushes in `onResourceStop`
   (`character` writes dirty stats, `vehicles` writes positions, `items` writes the held weapons' ammo, which it
   otherwise batches every 5 s), so a clean stop loses nothing. A crash can lose the last 5 s of fired rounds.
3. Confirm the process is gone before touching files (`run-local.ps1` checks this for you).

## Restart one resource

- `rcon.ps1 rr <name>` or `restart <name>` in the console. Every resource rebuilds its state from MariaDB on
  start (items, vehicles, zones), so a single restart is safe for players online. Restarting `auth` re-prompts
  every connected player for their password (sessions live in that VM); restarting `character` writes and
  re-reads every character (stats survive, a knocked-out player stands up).
- Never restart a `*_models` resource while a client is loading (it re-requests every custom model); never call
  `engineSetPoolCapacity("building", …)` (CLAUDE.md).
- A new resource needs its name in `server-config/resources.xml` **and** a `run-local.ps1` run (stopped server)
  so the ACL group grants it `function.loadstring`; `start <name>` on a running server fails with
  `Access denied @ 'loadstring'` until then.

## Rollback

A bad code change: `git revert <sha>` (or check out the previous tag), then `rr <resource>`. A bad schema change:
see `change-database-schema.md`; there is no automatic undo.

## Escalation

Lead (level 4) owns restarts in play hours; the repository owner owns `run-local.ps1`, the ACL and the server
configuration.
