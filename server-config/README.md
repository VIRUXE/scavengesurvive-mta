# Local server configuration

`pwsh server-config/run-local.ps1` prepares the MTA:SA 1.6 server in `C:\Program Files (x86)\MTA San Andreas 1.6\server`
and starts it. Every step is safe to run again. Stop the server first; the script refuses to run while it is up.

1. `python -m tools.sqltool --db scavengesurvive apply` (`-Reset` adds `--reset` and wipes all data).
2. `SET GLOBAL event_scheduler = ON` (lost when MariaDB restarts; add `event_scheduler=ON` under `[mysqld]` in `my.ini` to keep it).
3. Copies `local.settings.xml` to `mods\deathmatch\settings.xml`, first creating it from `local.settings.example.xml`
   if missing. `local.settings.xml` is git-ignored: put the DB password there, never in the example.
4. Rebuilds `mods\deathmatch\mtaserver.conf` from `mtaserver.conf.stock` (saved on the first run): removes every stock
   `<resource>` line, adds the lines from `resources.xml`, and sets `elementdata_whitelisted=1`, `fpslimit=60`,
   `scriptdebugloglevel=3`, `servername`, and `ase=0` so the dev server (open dev commands) is never advertised on the
   master list.
5. Junctions `mods\deathmatch\resources\[scavengesurvive]` to this repo, so edits are live after `restart <name>`.
6. Edits `acl.xml` (original saved as `acl.xml.stock`): rebuilds a `ScavengeSurvive` group holding every resource in
   `resources.xml` with an ACL granting `function.loadstring` (the stock `Default` ACL denies it, and every resource
   loads `lib` modules with `loadstring`), `function.takePlayerScreenShot` (dev's `screenshot`), `function.kickPlayer`
   (auth kicks banned and non-whitelisted players, staff kicks on `/kick`, `/ban`, `/warn`) and
   `function.restartResource` (staff `/restart`), and adds `resource.dev` to the `Admin` group so `/rr` can restart
   resources. A resource added to `resources.xml` only gets these rights on the next run (stopped server).
   **Security:** `function.loadstring` is a code-execution right. In production, grant it only to exactly these
   resources (as the script does) and review the grant.
7. Starts `MTA Server.exe` (skip with `-NoStart`).

The stock resources (`[admin]`, `[gameplay]`, `[managers]`, …) are still on disk but no longer start.
You can still start one by hand from the server console (`start admin`).

## Revert to the stock server

1. Stop the server.
2. `Copy-Item mtaserver.conf.stock mtaserver.conf -Force` and `Copy-Item acl.xml.stock acl.xml -Force` in `mods\deathmatch`.
3. Delete `mods\deathmatch\settings.xml`.
4. Remove the junction without touching the repo: `(Get-Item -LiteralPath 'mods\deathmatch\resources\[scavengesurvive]').Delete()`.
5. Optional: `mariadb -u root -e "DROP DATABASE scavengesurvive"`.

## HTTP rcon (resource `dev`)

MTA has no RCON. The `dev` resource exports `rcon(line)` over the server's HTTP port (22005) so scripts and LLM agents
can drive a local test server: `pwsh server-config/rcon.ps1 <command>` posts the line to `/dev/call/rcon` with HTTP
Basic auth and prints the reply. Commands: `help`, `players`, `start|stop|restart|rr <resource>`,
`cmd <player> <command> [args]` (runs a chat command as that player, e.g. `cmd Bob additem M9Pistol`),
`key <player> <command|key>` (runs a bound client command like `interact`, `putaway`, `dropitem`, `inventory` or
dispatches a client key press like `arrow_u`, `arrow_d`, `enter`, `escape`), `say <text>`,
`lua <code>`, `screenshot <player> [w h]` (the client renders a frame and uploads it to `dev/screenshots/`, git-ignored;
the client must not be minimised), `shutdown`.

The account is `*dev.http_user` / `*dev.http_pass` from `local.settings.xml` (`run-local.ps1` fills in a random
password when it creates the file; `dev` creates or re-passwords the MTA account on start). Its ACL group
`ScavengeSurviveHttp` grants only `general.http`, so the export alone decides what it can do. **Security:** `lua` is
server-side code execution behind a plain-HTTP password; the HTTP port binds every interface, so keep this on a
machine or LAN you trust, and set `*dev.http_pass` empty to disable the account.

## Dev commands (resource `dev`)

Allowed for everyone while the `dev` setting `*dev.open` is `true` (the default); otherwise only accounts with
`admin_level > 0`. Commands: `/additem <uname>`, `/rollloot`, `/stats`, `/sethp <n>`, `/setfood <n>`, `/setbleed <n>`, `/weather [id|NAME]`, `/zone [x y]`, `/vehcount`, `/vehrespawn`,
`/dbtest`, `/rr <resource>` (also `rr <resource>` in the server console).

## Economy settings (table `settings`, ADR 0001)

Read on resource start (`rr loot`, `rr vehicles` after a change). Carrying capacity: `loot.items_per_point` (2.0) ×
`loot.cap_multiplier` (1.0) items per loot point and zone; `vehicles.cap_multiplier` (1.0) × the first vehicle roll.
Refill every `world.refill_interval_s` (300): `loot.refill_rate` / `vehicles.refill_rate` (0.10 of the deficit per
hour) with a floor of `loot.refill_floor` / `vehicles.refill_floor` (0.02 of the cap per hour). Cooldown of a consumed
point: `loot.cooldown_minutes` (60) ± `loot.cooldown_jitter` (0.5); `vehicles.cooldown_hours` (6) ±
`vehicles.cooldown_jitter` (0.33). Nothing respawns within `world.min_player_distance` (150 m) of a player. A vehicle
driven more than `vehicles.leave_radius` (100 m) from its point frees the point and is removed, trunk contents
included, after `vehicles.abandon_days` (3) without anyone entering it or opening its trunk. `loot.count_carried` (1) counts items players carry against
their zone; set it to `0` to count only items in the world and in containers. Lower the multipliers for a harsher world.

## Player commands

`/lang <code>` (resource `auth`) sets the language of every translated line for the session and stores it on the account; `/lang` alone lists the codes.

## Staff commands (resource `staff`)

Gated by `accounts.admin_level` (1 Game Master … 5 Developer); the server console counts as level 5. Give yourself a
level with `mariadb -u root scavengesurvive -e "UPDATE accounts SET admin_level = 5 WHERE name = 'You'"` and relog,
then `/acmds` lists what you may use. Full table, upstream rules and deviations: `docs/staff-commands.md`.
`rcon.ps1 cmd <player> ban Someone 1d reason` runs a staff command as that player (their level applies).
