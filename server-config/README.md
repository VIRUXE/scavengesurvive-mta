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
   loads `lib` modules with `loadstring`), and adds `resource.dev` to the `Admin` group so `/rr` can restart resources.
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
`cmd <player> <command> [args]` (runs a chat command as that player, e.g. `cmd Bob additem M9Pistol`), `say <text>`,
`lua <code>`, `shutdown`.

The account is `*dev.http_user` / `*dev.http_pass` from `local.settings.xml` (`run-local.ps1` fills in a random
password when it creates the file; `dev` creates or re-passwords the MTA account on start). Its ACL group
`ScavengeSurviveHttp` grants only `general.http`, so the export alone decides what it can do. **Security:** `lua` is
server-side code execution behind a plain-HTTP password; the HTTP port binds every interface, so keep this on a
machine or LAN you trust, and set `*dev.http_pass` empty to disable the account.

## Dev commands (resource `dev`)

Allowed for everyone while the `dev` setting `*dev.open` is `true` (the default); otherwise only accounts with
`admin_level > 0`. Commands: `/additem <uname>`, `/rollloot`, `/stats`, `/sethp <n>`, `/setfood <n>`, `/setbleed <n>`,
`/dbtest`, `/rr <resource>` (also `rr <resource>` in the server console).
