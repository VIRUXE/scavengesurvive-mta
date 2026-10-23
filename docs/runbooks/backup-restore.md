# Backup and restore

**When:** nightly (scheduled task), before every migration, and when restoring after corruption or an operator
mistake. The game state is entirely in MariaDB; the MTA server directory holds only configuration
(`mtaserver.conf`, `acl.xml`, `settings.xml`, `internal.db` with the rcon account) and logs.

**Prerequisites:** `mariadb-dump` and `mariadb` on `PATH`; a backup directory outside the server and repo
(`$BACKUPS`); for point-in-time recovery, binary logging enabled in `my.ini` (`[mysqld]` `log_bin=ON`,
`binlog_format=ROW`, `expire_logs_days=7`) before the incident, not after.

## Backup

```powershell
$stamp = Get-Date -Format yyyyMMdd-HHmmss
mariadb-dump -u root --single-transaction --routines --events --triggers --hex-blob `
  --databases scavengesurvive | Set-Content -Encoding utf8 "$BACKUPS\scavengesurvive-$stamp.sql"
Copy-Item "$DM\mtaserver.conf", "$DM\acl.xml", "$DM\settings.xml" "$BACKUPS\config-$stamp\" -Force
```

`--single-transaction` gives a consistent snapshot without stopping the server. `--routines --events` carries the
stored procedures and scheduler events (they are also in git under `sql/`, so a restore can reapply them with
`tools.sqltool`). System-versioned history rows (`accounts`, `items`, `bans`) are included.

Verify a backup by restoring it into a scratch database once a week:
`mariadb -u root -e "CREATE DATABASE restore_check"` then `mariadb -u root restore_check < dump.sql` and
`SELECT COUNT(*) FROM restore_check.items`.

## Restore (full)

1. Stop the server (`start-stop-restart.md`). Players keep playing against a database you are about to replace
   otherwise, and their writes are lost.
2. `mariadb -u root -e "DROP DATABASE scavengesurvive; CREATE DATABASE scavengesurvive CHARACTER SET utf8mb4
   COLLATE utf8mb4_uca1400_ai_ci"` then `mariadb -u root scavengesurvive < "$BACKUPS\scavengesurvive-<stamp>.sql"`.
3. `python -m tools.sqltool --db scavengesurvive apply` to bring the schema to the current commit (migrations
   after the dump, latest procedures).
4. Point-in-time (binlog on): find the position just before the mistake with `mariadb-binlog --base64-output=DECODE-ROWS
   -v <binlog file>`, then `mariadb-binlog --start-datetime="<dump time>" --stop-datetime="<just before>" <files> | mariadb -u root scavengesurvive`.
5. Start the server; check `scripts.log` for a clean boot and `rcon.ps1 players`.

## Restore (one thing)

For a single item, character or account, prefer the system-versioned history to a full restore:
`SELECT * FROM items FOR SYSTEM_TIME AS OF TIMESTAMP '2026-10-23 10:00:00' WHERE id = 123` shows the row as it
was; copy the values back with an `UPDATE`. `SELECT * FROM bans FOR SYSTEM_TIME ALL WHERE name = 'X'` shows every
edit of a ban. Log what you did in `staff_actions` (`exports.staff:logAction("Ops", "restore", "X", "why")`
from `rcon.ps1 lua`, or a plain `INSERT`).

## Rollback

A restore that went wrong is itself restored from the previous dump; keep the last seven nightly dumps plus the
pre-migration dumps.

## Escalation

Repository owner (the only MariaDB admin today). Announce the outage window in game with `rcon.ps1 say` first.
