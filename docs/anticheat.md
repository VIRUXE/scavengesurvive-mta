# Anticheat port

The `anticheat` resource ports the server-side checks that remain useful in MTA. Start it through
`server-config/resources.xml`; its SQL tables are in `sql/schema.sql`. Issue
[#100](https://github.com/VIRUXE/scavengesurvive-mta/issues/100) tracks live verification and any follow-up on
detection-field parity.

## Checks

| Check | MTA behavior |
| --- | --- |
| Unexpected on-foot teleport | MTA `onPlayerTeleport` alerts are rolled back to the previous coordinates and logged. Staff on duty, players in vehicles, dead players, the first 20 seconds after joining, the first second after spawn, and the first 5 seconds after leaving a vehicle are exempt. Repeat alerts are logged at most once per 10 seconds. |
| Locked vehicle entry | `vehicles` cancels entry on the server. |
| Ammo and magazine | `items` owns held weapon ammo and decrements the server state for every accepted shot. |
| Ping | Every second, kick after 10 consecutive samples above `player.ping_limit` (default 400 ms; +100 ms with 10 or fewer players). New connections receive a 10-second grace period. Staff on duty are exempt. |
| Client event flood | MTA's `onPlayerTriggerEventThreshold` kicks the client that exceeds the server's configured event trigger threshold. |
| Invalid client event | MTA's `onPlayerTriggerInvalidEvent` kicks the client that attempts an event that is missing or not remote-enabled. |
| Alt-tab | Client MTA-focus loss is reported to the server. A player is kicked after `player.max_tab_out_time` seconds (default 60); staff on duty are exempt. |
| Detection fields | Four-point XY polygons with a Z band log each player's entry once. They never punish players. See `/field` below. |

The MTA server's event trigger threshold and `player_teleport_alert` control the native movement and event alarms.
The focus report depends on the client resource, so it is an AFK policy signal rather than a tamper-proof fact.

## Detection fields

Level 2+ staff can use:

```text
/field add <name> <x1 y1 x2 y2 x3 y3 x4 y4 minZ maxZ>
/field list
/field log <name>
/field remove <name>
```

The polygon points are in order around the boundary. Entries are written to `anticheat_field_logs` and printed to
the server log. The log command shows the latest 10 entries. This is a smaller interface than upstream's dialog
editor: it does not support player exceptions, renaming, drawing, or per-entry deletion.

## Replaced or dropped checks

- MTA-owned vehicle synchronization replaces SA-MP's unoccupied-vehicle teleport callback.
- Server-side item range checks replace the unreachable-loot trap: clients cannot directly pick up a named item.
- Packet flooding beyond `triggerServerEvent` counts is left to MTA's native protection.
- Swim-fly, jetpack, money, vehicle-mod, camera-distance, shooting-animation, and invalid-hit checks are dropped as
  SA-MP sync artifacts or MTA-owned behavior.

## Verification

The port has not yet been verified in a live server. Follow the **Anticheat** smoke section in
[`mvp-smoke-checklist.md`](mvp-smoke-checklist.md), then record results in `docs/reviews/` before treating the checks
as production-verified.
