# Incident: MariaDB unreachable

**When:** `scripts.log` fills with `[<tag>] SQL error 2006/2013 …` or `dbConnect failed`, logins stall at the
password prompt, item pickups do nothing, or `rcon.ps1 cmd <player> dbtest` reports `db error`.

**What the server does on its own (design spec, Failure modes):** every resource connects with `autoreconnect=1`;
a failed procedure returns `false` and the action is refused with a toast; `character` keeps ticking in memory and
flushes dirty rows once the connection is back; nothing is lost that was already committed. The held weapons' ammo
waits too: a failed `item_data_flush` (every 5 s) logs `[items] item_data_flush failed` and its rows go back in the
queue for the next flush, unless the weapon fired again meanwhile (the newer count wins).

## Steps

1. Confirm: `mariadb -u root -e "SELECT 1"` from the server host. If it answers, the problem is credentials or the
   port (`server-config/local.settings.xml` `*lib.db_*` vs `my.ini`), not the service.
2. Tell players: `rcon.ps1 say Database trouble: saving is paused, do not log out`. Logging out while the DB is
   down loses nothing committed but the flush of the last minute runs when the connection returns, so a player
   who stays connected is better off.
3. Restart MariaDB (`Restart-Service MariaDB` or the service name on that host). The resources reconnect on the
   next query (`autoreconnect=1`); watch `scripts.log` for the errors to stop and `rcon.ps1 cmd <player> dbtest`
   to answer with a latency.
4. If MariaDB does not come back: check disk space (`innodb` stops on a full disk), `my.ini` changes, and the
   MariaDB error log. A crashed InnoDB recovers on start; do not delete `ib_logfile*`.
5. After recovery: `SELECT @@event_scheduler` must be `ON` (set it again with
   `SET GLOBAL event_scheduler = ON` or `run-local.ps1`), and `SHOW EVENTS` must list the three events (`ev_despawn_items`, `ev_expire_bans`, `ev_item_history`).
6. If the outage exceeded a few minutes, do a controlled restart of the game server (`start-stop-restart.md`) so
   every resource rebuilds from the database rather than from memory that drifted while writes failed.

## Rollback

None; this is recovery. If data was corrupted, `backup-restore.md`.

## Escalation

Repository owner. Record the incident (time, duration, cause, what was lost) in `docs/reviews/` with the date.
