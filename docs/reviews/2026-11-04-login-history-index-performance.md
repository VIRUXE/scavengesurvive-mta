# Login history index performance — 2026-11-04

Replaced `connection_log(account_id)` with `(account_id, joined_at)` on the live database.
The account login-history query filters by account and returns the latest 20 connections; the
previous plan sorted matching rows, while the composite index supplies the requested order.

## Applied DDL

```sql
ALTER TABLE connection_log
  DROP INDEX ix_connection_log_account,
  ADD INDEX ix_connection_log_account_joined (account_id, joined_at),
  ALGORITHM=INPLACE, LOCK=NONE;
```

Applied online with a five-second metadata lock timeout. Regenerated `sql/schema.sql` from the live
database using `tools.sqltool.render_schema` (local client connection defaults); normalized whitespace-only
lines from routine definitions. No resource or database restart was needed.

Full pre-change backup, including system-versioned history:
`/gta/sa/mta/backups/scavengesurvive-pre-login-index-20261104-054003.sql`.

## Performance comparison

MariaDB 13.1.1 on the same host, session-local temporary InnoDB table cloned from the live table.
Both indexes existed on that temporary table; each SELECT forced its corresponding index. Production
data and indexes were not modified during benchmarking. Used the actual login-history SELECT fields
(`DATE_FORMAT(joined_at, ...), ip, serial`), account filter, descending timestamp order and `LIMIT 20`.

20 warmups per plan, then 400 measured SELECTs per plan, alternating execution order. Times include
the local Unix-socket round trip and fetching results. `SQL_NO_CACHE` bypassed the query cache; these
are warm-cache read measurements, not measurements of concurrent gameplay, disk-cold reads or writes.

| Dataset | Total rows | Matching account rows | Before median | After median | Speedup | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Current data copy | 128 | 40 | 0.415 ms | 0.371 ms | 1.12× | 0.547 ms | 0.488 ms |
| Synthetic: 100 accounts | 100,000 | 1,000 | 2.134 ms | 0.425 ms | 5.02× | 2.355 ms | 0.534 ms |

The current-data case used the account with the most login records. Synthetic records used unique
timestamps and 1,000 connections per account. Both plans returned identical results for each tested
account. EXPLAIN and ANALYZE confirmed the old plan uses filesort and the new plan does not; live
EXPLAIN also selects the new index without a hint. The present-day absolute improvement is small;
the synthetic case illustrates how the query scales as per-account login history grows.

The wider composite index replaces the old index rather than keeping both. Write overhead and
index size were not benchmarked. No service-request schema was identified, so this change applies
only to game login history.

## Rollback

```sql
ALTER TABLE connection_log
  DROP INDEX ix_connection_log_account_joined,
  ADD INDEX ix_connection_log_account (account_id),
  ALGORITHM=INPLACE, LOCK=NONE;
```

Regenerate the schema after rollback. Existing databases need the forward DDL above; applying
`schema.sql` alone does not alter an existing table.
