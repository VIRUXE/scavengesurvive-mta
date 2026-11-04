# Character drop ring cache investigation

Compared the current `character_drop_items` with a candidate that extracts the nine drop spots into a
session-local indexed MEMORY table once per call. Both retain the existing ordered locking cursor and
one UPDATE per item. The candidate joins cached coordinates by item index modulo ring length.

On MariaDB 13.1.1, used an isolated database with the production schema, triggers and system versioning.
Synthetic inventory fixtures contain one held item and the remaining items in an inventory container.
Each variant ran once for warmup then ten measured times, alternating variants. Timings include the full
procedure call and caller transaction commit. Cached timings include table creation, population and removal.
Assertions checked the returned drop count and that every fixture item left its holder/container and
received a world position. This was an exploratory performance comparison, not complete result/concurrency
verification suitable for deploying the candidate.

| Items | Existing median | Cached median |
| ---: | ---: | ---: |
| 1 | 2.794 ms | 3.181 ms |
| 10 | 4.802 ms | 8.628 ms |
| 50 | 19.083 ms | 18.325 ms |

Rejected: the smaller batches regress; the large batch's small improvement does not justify the extra
session state and cleanup. The nine-position ring is much smaller than the world refill JSON batch that
benefited from extraction once. The live procedure was not changed. The isolated database was removed.
This approach uses no new MariaDB 13.1 feature.
