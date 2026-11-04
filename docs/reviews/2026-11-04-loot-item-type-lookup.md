# Loot item type lookup optimization

Applied live on 2026-11-04 to `loot_roll`, then exported the procedure with `SHOW CREATE PROCEDURE`.

The INSERT SELECT already joins `item_types t` to validate each item type. Its hitpoints projection also
ran a correlated subquery against the same unique item-type key. Use `t.max_hitpoints` directly instead.
The joins, transaction, creation order, container creation, budget update and cooldown update are unchanged.
This removes redundant SQL work and does not require a new MariaDB 13.1 feature.

## Measurement

MariaDB 13.1.1, read-only `ANALYZE FORMAT=JSON` on the actual INSERT's source SELECT, using live item types
and loot spawn IDs with synthetic JSON payloads. Alternate old and new queries; one warmup and fifty
measured executions per variant and batch size. Use a fixed session timestamp and assert identical SELECT
results, including JSON data, hitpoints, locations and despawn timestamps.

| Mixed item types per batch | Previous median | New median | Reduction |
| ---: | ---: | ---: | ---: |
| 10 | 0.1778 ms | 0.1129 ms | 36.5% |
| 100 | 1.3472 ms | 0.9174 ms | 31.9% |
| 1,000 | 10.2683 ms | 8.9368 ms | 13.0% |

Mixed batches cycle through up to 100 item types. A separate repeated-single-type run had smaller gains:
0.1251 to 0.0997 ms at 10 items, 0.9402 to 0.8949 ms at 100, and 8.0892 to 7.8576 ms at 1,000.
These timings exclude INSERT writes, triggers, transaction commits and the rest of the loot procedure;
they do not establish an equivalent percentage improvement in total loot refill or gameplay latency.

Verified the live definition matched the old repository definition before replacement, and that the
exported definition matches the new SQL. An empty live batch returned OK with zero items created.
No gameplay items were created during verification. No resource restart is required.

Pre-change full backup including history:
`/gta/sa/mta/backups/scavengesurvive-pre-loot-join-20261104-024020.sql`.
Rollback: restore the previous `loot_roll` procedure from this backup or Git.
