# /replay data feed

`/replay` (staff command, `resources/[scavengesurvive]/replay`, design in
`docs/superpowers/specs/2026-11-23-replay-design.md`) reads three kinds of history:

- `replay_chunk`: the 5 Hz flight recorder, written by the `replay` resource itself (nothing to install);
- `character_track` and the system-versioned `items`: already kept by the game;
- `replay_event`: the game log's events. The prod server does not run `logs` (no Loki), so every event is only a
  line of `mods/deathmatch/logs/server.log`; `tools/replay_import_log.py` reads the kinds listed in
  `resources/[scavengesurvive]/replay/shared/logic/kinds.lua` from it. Idempotent (`sig` unique), so a run twice or a
  full re-read never doubles a row.

## Install the timer (once)
The importer connects with the game's own `*lib.db_*` settings from `mods/deathmatch/settings.xml` (readable by
`mta`), so there is no secrets file to create.

1. `cp ssmta-replay-import.service ssmta-replay-import.timer /etc/systemd/system/ && systemctl daemon-reload &&
   systemctl enable --now ssmta-replay-import.timer`
2. Check: `journalctl -u ssmta-replay-import -n 3` ("read N lines from byte …"), `SELECT COUNT(*), MAX(at) FROM replay_event`.

First backfill by hand (root, reads /root/.my.cnf): `python3 -m tools.replay_import_log --from-start`. Until the
timer is installed run it by hand (or `--state` with a file) before a replay that needs the newest events.

## Retention
`ev_replay_purge` (daily 04:10): chunks 14 days, events 30 days; `ev_item_history` keeps the `items` history 14 days
(it was 7), which is how far back a replay can show items, defences and containers.
