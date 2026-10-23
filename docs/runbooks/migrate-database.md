# Migrate the database

**When:** a commit added or changed a file under `sql/migrations`, `sql/procedures`, `sql/events` or `sql/seed`.

**Prerequisites:** a fresh backup (`backup-restore.md`); the server stopped for a migration that alters a table
players write to (`items`, `characters`, `vehicles`, `accounts`); procedures and seeds can be applied live.

## Steps

1. Read the migration. Rules it must follow (CLAUDE.md): plain statements split on `;` at line end, idempotent
   (`CREATE TABLE IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS`), ends with its `schema_migrations` row. A migration
   that alters a system-versioned table (`accounts`, `items`, `bans`) starts with
   `SET SESSION system_versioning_alter_history = KEEP;` or MariaDB refuses it (error 4119).
2. Dry run against the test database: `python -m pytest -q tests/sql` recreates `scavengesurvive_test` from
   scratch with `--reset`, which exercises every migration in order, then runs the procedure tests.
3. Apply: `python -m tools.sqltool --db scavengesurvive apply` (add `--password` when needed). Migrations whose
   version is already in `schema_migrations` are skipped; procedures, events and seeds are re-applied every time
   (`CREATE OR REPLACE`, `INSERT … ON DUPLICATE KEY UPDATE`), so running it twice is safe. `run-local.ps1` does
   this step on every start.
4. Verify: `mariadb -u root scavengesurvive -e "SELECT version, name, applied_at FROM schema_migrations"` lists the
   new version; `SHOW EVENTS` lists `ev_despawn_items` and `ev_expire_bans` with `ENABLED`; `SELECT @@event_scheduler`
   is `ON` (it is lost on a MariaDB restart unless `event_scheduler=ON` is in `my.ini`).
5. Restart the resources that read the changed objects (`rr items`, `rr staff`, …) or do a full start.

## Rollback

There are no down-migrations. Restore the backup taken in the prerequisites (`backup-restore.md`), or write a
forward fix migration (`NNNN+1_fix_x.sql`) and apply it. Seeds never delete rows, so a wrong seed value is
corrected by the next seed run (`svalue = svalue` keeps edited settings; change the key if the default must win).

## Escalation

Whoever wrote the migration; the repository owner for anything touching `accounts` or `items` history.
