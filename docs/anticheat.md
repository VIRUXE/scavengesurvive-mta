# Anticheat port

The `anticheat` resource ports the server-side checks that remain useful in MTA. Start it through
`server-config/resources.xml`; its SQL tables are in `sql/schema.sql`. Issue
[#100](https://github.com/VIRUXE/scavengesurvive-mta/issues/100) tracks live verification and any follow-up on
detection-field parity.

## Checks

| Check | MTA behavior |
| --- | --- |
| Unexpected on-foot teleport | MTA `onPlayerTeleport` alerts are rolled back to the previous coordinates, logged and filed as a `TELE` report. Staff on duty, players in vehicles, dead players, the first 20 seconds after joining, the first second after spawn, and the first 5 seconds after leaving a vehicle are exempt. Repeat alerts are logged and reported at most once per 10 seconds. |
| Moved while frozen | Once a second: a player under `/freeze` who moves more than 1 m is put back and reported (`TELE`, at most every 10 s). |
| Jetpack | `isPedWearingJetpack` files a `FLY` report and bans. |
| Swim-fly | The client claims to be in water (`isElementInWater`, interior 0) where upstream's water map says there is none (`shared/logic/water.lua`: Sherman dam, sea level and map bounds, the quarry/SFPD/LVPD/tunnel/dry-dock exceptions, 25 lakes and pools). Three seconds in a row files a `FLY` report and bans (upstream banned on the first). |
| Vehicle health | A driver (not passengers) in a vehicle above 990 health files a `VHP` report and bans; the vehicle is set to 300. The `vehicles` resource caps spawn, DB load and repair at 990, and the anticheat shuts all 50 garage doors at start so Pay 'n' Spray cannot repair past it. |
| Vehicle teleport | An empty, untowed vehicle that jumps 15 m or more (more than 2x its speed allows, under 500 m) next to a player files a `VTP` report and kicks that player. Vehicles used within the last 5 s, and players who spawned within 15 s, are exempt. |
| Hacker traps | 31 loot items upstream placed out of reach (`data/traps.lua`, converted from upstream once, now edited by hand), kept in the world through `anticheat_traps`. `items` asks every pickup through the cancellable `itemPickupAttempted` event; for a trap the pickup is cancelled, a `TRAP` report is filed and the player is banned. They have no despawn time and no loot spot; one that is gone is made again at the next anticheat start. |
| Excess accuracy | Ring of the last 10 shots at moving players (`shared/logic/accuracy.lua`); 7 or more hits warn staff of level 2+. Never punishes. |
| Locked vehicle entry | `vehicles` cancels entry on the server. |
| Ammo and magazine | `items` owns held weapon ammo and decrements the server state for every accepted shot. |
| Ping | Every second, kick after 10 consecutive samples above `player.ping_limit` (default 400 ms; +100 ms with 10 or fewer players). New connections receive a 10-second grace period. Staff on duty are exempt. |
| Client event flood | MTA's `onPlayerTriggerEventThreshold` kicks the client that exceeds the server's configured event trigger threshold. |
| Invalid client event | MTA's `onPlayerTriggerInvalidEvent` kicks the client that attempts an event that is missing or not remote-enabled. |
| Alt-tab / Idle | Client MTA-focus loss is reported to the server. A player is kicked after `player.max_tab_out_time` seconds (default 60); staff on duty are exempt. Can be toggled on/off or configured via `/idlekick [on|off|<seconds>]` (staff command) and setting `player.idle_kick`. |
| Detection fields | Four-point XY polygons with a Z band log each player's entry once (`anticheat/server/fields.lua`, pure logic in `shared/logic/fields.lua`). They never punish players. Staff manage them with `/field` in the `staff` resource, see below. |

The MTA server's event trigger threshold and `player_teleport_alert` control the native movement and event alarms.
The focus report depends on the client resource (`anticheatFocusChanged`, a `net.handler` event declared in
`shared/events.lua`), so it is an AFK policy signal rather than a tamper-proof fact.

## Detection fields

The command lives in the `staff` resource (`staff/server/fields.lua`, level 2, listed in `docs/staff-commands.md`)
like every other privileged command, and each add or remove is a `field_add` / `field_remove` row in
`staff_actions`. After a change it calls `exports.anticheat:refreshFields()` so the sweep reloads the table.

```text
/field add <name> <x1 y1 x2 y2 x3 y3 x4 y4 minZ maxZ>
/field list
/field log <name>
/field remove <name>
```

The polygon points are in order around the boundary. Entries are written to `anticheat_field_logs` and printed to
the server log. The log command shows the latest 10 entries. This is a smaller interface than upstream's dialog
editor: it does not support player exceptions, renaming, drawing, or per-entry deletion.

**Decision (2026-10-26, #100):** neither the dialog editor nor the per-field player exceptions get a follow-up port.
The staff panel (`docs/staff-commands.md`, CEGUI) gives `/field add` a form with a field per argument, which
covers everything the editor did that matters on a live server; renaming is a remove and an add. Exceptions existed upstream so that a staff member
crossing a field did not fill its log; here a field never punishes, the log is read by the same staff and shows
who entered, and a line from a staff member on duty is easy to tell apart (`/field log`). If a field ever gains
consequences, exceptions come back as an `anticheat_field_exceptions` table keyed by account, not by name.

## Replaced or dropped checks

- Server-side item range checks plus the hacker traps replace the unreachable-loot guard: clients cannot directly pick up a
  named item.
- Packet flooding beyond `triggerServerEvent` counts is left to MTA's native protection.
- Money, vehicle nitro/hydraulics, camera distance, shooting-animation and invalid-hit checks are dropped as SA-MP
  sync artifacts or MTA-owned behavior (the server cannot read a player's money, MTA validates component and hit data).

Automatic bans go through `exports.staff:autoBan` (permanent, `by_name` "Server", never against staff), reports through
`anticheat/server/report.lua` into the `reports` table (`/reports`), and staff warnings through
`exports.staff:notifyStaff`.

## Verification

The port has not yet been verified in a live server. Follow the **Anticheat** smoke section in
[`mvp-smoke-checklist.md`](mvp-smoke-checklist.md), then record results in `docs/reviews/` before treating the checks
as production-verified.
