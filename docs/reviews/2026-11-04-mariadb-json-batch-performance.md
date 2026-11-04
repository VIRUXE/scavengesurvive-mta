# MariaDB 13.1 world item batch optimization

Applied live on 2026-11-04 to `scavengesurvive.item_create_many`, then exported its definition using
`SHOW CREATE PROCEDURE` into `sql/schema.sql`. MariaDB 13.1.1 or newer is now required.

## Change

World container refill (`world/server/boxes.lua`) sends every missing placement in one JSON batch. The previous
procedure built a JSON path for each placement and searched the entire batch repeatedly for its type, six
coordinates/interior fields, and nested contents. Its cost grew sharply with batch size.

The procedure now opens a cursor over a single `JSON_TABLE` joined to item types. MariaDB 13.1's explicit
[`FORMAT JSON` columns](https://mariadb.com/docs/server/reference/sql-functions/special-functions/json-functions/json_table#format-json-columns)
extract each nested contents array alongside its scalar fields. The cursor inserts each world item and its
contents in input order, keeping one transaction, generated parent IDs, content slots, and the existing
return payload. Unknown and unsupported item types are skipped as before.

## Measured results

Isolated database on the same MariaDB 13.1.1 server, using the production schema, triggers, system versioning,
and item type catalog. Each synthetic safebox has two generic contents items, so 1,000 boxes creates 3,000
items and 1,000 containers. Old and new procedures alternated on cleared tables. One warmup and six measured
calls per implementation at each size; times include the database round trip and transaction commit.

| Boxes per call | Previous median | New median | Speedup |
| ---: | ---: | ---: | ---: |
| 1 | 4.568 ms | 3.937 ms | 1.16x |
| 50 | 44.118 ms | 18.289 ms | 2.41x |
| 250 | 673.621 ms | 92.101 ms | 7.31x |
| 1,000 | 9,299.870 ms | 373.862 ms | 24.88x |

These compare SQL implementations on the same database version, rather than attributing the difference to
the version upgrade. They measure synthetic refill batches, not gameplay latency or concurrent player load.

## Verification

Compared complete returned payloads and created item rows, including content ownership and slot order,
for empty batches, duplicate types/contents, unknown types, unsupported weapon types, mixed generic/safebox
placements, empty/null nested contents, and unknown content types. Old and new results matched across four
batches. Injecting an out-of-range interior after a valid placement made both versions roll back the entire
batch. No permanent test suite was added.

After deployment, an empty live batch returned `OK`, with zero created/inside items. No orphan world-position
rows were found. No resource restart is required: subsequent `CALL item_create_many` uses the new definition.

Pre-change full backup including history:
`/gta/sa/mta/backups/scavengesurvive-pre-json-optimization-20261104-023321.sql`.
Rollback: restore the previous procedure body from that backup or the previous Git revision.
