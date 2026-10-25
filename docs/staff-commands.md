# Staff commands (resource `staff`, Milestone M7)

Levels come from `accounts.admin_level` (set with `/setadmin`, or by hand: `UPDATE accounts SET admin_level = 4 WHERE
name = 'You'`; the player relogs or a level-4 staff runs `/setadmin`). The server console counts as level 5 for every
command that does not need a connected player. Every action writes a row to `staff_actions` (actor, action, target,
details); bans and warnings write theirs inside the `staff_ban` / `staff_warn` procedures.

| Level | Upstream name | Commands |
| --- | --- | --- |
| 1 | Game Master | `/a`, `/mute`, `/unmute`, `/warn`, `/kick`, `/msg`, `/clearchat`, `/aliases`, `/serial`, `/history`, `/reports`, `/acmds` |
| 2 | Moderator | `/duty`, `/goto`, `/get`, `/gotopos`, `/freeze`, `/unfreeze`, `/ban`, `/unban`, `/banlist`, `/banned`, `/spec`, `/free`, `/nametags`, `/profile`, `/setmotd`, `/deletereports` |
| 3 | Administrator | `/whitelist`, `/ip`, `/setactive`, `/resetpassword`, `/adminlist` |
| 4 | Lead | `/players`, `/setadmin`, `/restart`, `/sc [type]` (supply crate here), `/wc` (weapons cache here) |
| 5 | Developer | everything above; the debug toggles live in the `dev` resource (`/sethp`, `/setfood`, `/setbleed`, `/weather`, `/additem`, `/rr`, `/move`, `/fly`) |
| 0 | Player | `/report <name|near|killer> <reason>` |

Durations (`/mute`, `/ban`): a bare number is seconds; `10m`, `2h`, `3d`, `2w`, `1mo` and the full words work;
`forever`, `perm`, `0` or `-1` mean no expiry. Player arguments accept a unique prefix or substring of the name
(case-insensitive); exact names win.

## Rules carried over from upstream

- A staff member may act only on players of a **lower** level, or on themselves (`level1.pwn` "return 3").
- `/kick` by someone who is not the highest level online becomes a **request** sent to the highest staff online.
- `staff.max_warnings` (5) warnings = a `staff.warn_ban_hours` (24 h) ban; the counter restarts afterwards.
- `/goto`, `/get`, `/gotopos`, `/spec` need **duty** unless the actor is level 5.
- Bans record name, IP **and serial** (upstream had no serial field; ADR 0007). `auth` refuses a joining player whose
  name, IP or serial matches an active ban, prints the date / reason / unban lines and kicks after one second.
  Timed bans expire through the `ev_expire_bans` scheduler event and are also filtered by expiry in every query.
- Whitelist (`/whitelist on|off`, setting `server.whitelist`): when on, a logged-in account that is not in the
  `whitelist` table and has level 0 is kicked after the login succeeds. Staff accounts always pass.
- Mutes cancel `onPlayerChat` and persist on the account (`accounts.muted`, `mute_until`), so a relog does not
  lift them.
- `/duty` swaps to the upstream duty skin (217 male / 211 female), turns name tags on and sets element data
  `staff.duty`; `weapons` ignores player hits on a victim with that flag.
- `/spec` parks the watcher frozen, invisible and without collisions where they stood, follows the target's
  dimension and interior, and the arrow keys cycle through players; `/free` or `/spec off` returns them.

## Intentional deviations

| Upstream | Port | Why |
| --- | --- | --- |
| `/ban [name]` then two input dialogs (reason, duration) | `/ban <name> <duration> <reason>` | the dx UI kit has list dialogs only; no text input |
| `/report` menu with 4 modes and an input dialog | `/report <name\|near\|killer> <reason>` | same; `near` = closest player within 100 m not on duty, `killer` = the last player who killed you |
| Duty logs the character out of the world (`Logout`) | character stays loaded, duty = damage immunity + skin + tags | `character` has no suspend/resume export yet; follow-up when that resource is reworked |
| `/country`, `/allcountry` (GeoIP) | not ported | no GeoIP service; `/ip` shows IP and serial |
| `/delete` (drop account) | not ported; `/setactive <name> 0` blocks the login instead | accounts are system-versioned; deletion is a DBA job |
| `/setpinglimit`, `/dbl`, `/gmx`, `/loadfs`, `/reloadfs`, `/unloadfs`, `/hud`, `/gamename`, `/hostname`, `/mapname` | not ported | SA-MP server internals; MTA has `mtaserver.conf`, `/restart <resource>` covers the resource case |
| `/aliases [i/p/h/a]` (same IP, password, gpci hash, all) | `/aliases <name> [i\|s]`: every name seen in `connection_log` with the same IP **or** serial by default, `i` = IP only, `s` = serial only (`h` accepted as `s`, `a` = both); the mode is logged in `staff_actions.details` | SA-MP's `gpci` becomes MTA's `getPlayerSerial` (32 hex chars, per machine, logged on every login and kept as `accounts.last_serial`); the password mode `p` is dropped because bcrypt hashes are salted, so "same password" cannot be looked up |
| Post-login alias check (`CheckForExtraAccounts`): `Aliases: (n) a, b` to staff of the highest alias's level, red warning to level 1+ when one is banned, kick with no staff online | Same on `playerAuthenticated` in `staff` (`moderation.checkAliases`, decision in `logic.aliasReport`): names from `connection_log` with the player's IP **or** serial, six listed, count of all | Matches by IP or serial, not password (salted bcrypt). Upstream only looked for a banned alias with two or more aliases; the port checks any count. This also catches a name banned while offline, whose `bans` row has no IP or serial for the join check |
| Player-list gpci views (accounts by hash, hashes by name) | `/serial <serial>` (level 1) lists the names seen with a raw serial in `connection_log`, hiding accounts that outrank the caller; `/history <name> [n]` lists a name's serials and IPs per login | the serial replaces the gpci hash; both lookups are logged in `staff_actions` |
| Reports listed with red (banned) / yellow (unread) rows | `[banned]` / `[new]` markers | the dx list draws no colour codes |
| Mutes end on disconnect | mutes persist on the account | upstream's own comment says they should save; the file-based save never did |

## Where things are

- `resources/[scavengesurvive]/staff/shared/logic/staff.lua`: levels, registry, durations, lookup, list rows
  (busted: `tests/lua/spec/staff_logic_spec.lua`).
- `server/main.lua`: level gate, action log, mutes, MOTD, list-dialog plumbing; `server/moderation.lua`,
  `bans.lua`, `reports.lua`, `duty.lua`: the commands.
- `resources/[scavengesurvive]/auth/shared/logic/access.lua`: ban query and whitelist decision (busted:
  `tests/lua/spec/auth_access_spec.lua`); `auth/server/main.lua` applies them on join and login.
- `sql/schema.sql` (`bans`, `whitelist`, `reports`, `staff_actions`, `accounts.warnings/muted/mute_until`), `sql/procedures/staff_{ban,unban,warn}.sql`, `sql/events/0002_expire_bans.sql`
  (pytest: `tests/sql/test_staff.py`).
- ACL: `function.kickPlayer` and `function.restartResource` on the `ScavengeSurvive` ACL (`server-config/run-local.ps1`).

## Names MTA owns: `/kick`, `/ban`, `/mute`, `/unmute`, `/restart`

These five are MTA server console commands too, or names the stock Default ACL denies to every player as
`command.<name>`. A player typing one reaches the server's hardcoded handler first (gated by that right, "ACL:
Access denied" otherwise) and a script handler never runs. So `staff/client/main.lua` registers them client-side
and forwards the arguments through `staffCommandIssued`; the server dispatches to the same registry entry after
the level gate, and cancels `onPlayerCommand` for those names so MTA neither runs its own kick/ban nor prints
the denial. The set is `logic.CHAT_BRIDGED` (`shared/logic/staff.lua`); a new command with one of MTA's
names goes there. `executeCommandHandler` applies the same ACL check, so `rcon.ps1 cmd <player> kick …` falls
back to `exports.staff:runCommand(player, name, args)` (live run: `docs/reviews/2026-10-23-m7-live.md`).
