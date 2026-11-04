# Explosion JSON cache investigation

On MariaDB 13.1.1, compared four JSON_TABLE aggregate reads of the same synthetic `{id,dmg}` array with
loading it once into a session-local MEMORY table and reading that table four times. Thirty measured
iterations per size after one warmup, alternating variants. Times include client/server round trips.
The MEMORY table was created before measurement; per-batch cleanup and population were included.

| Batch size | Four JSON parses | Populate and reuse MEMORY table |
| ---: | ---: | ---: |
| 10 | 0.753 ms | 0.848 ms |
| 100 | 1.520 ms | 1.127 ms |
| 1,000 | 10.325 ms | 3.964 ms |

This is a parsing microbenchmark, not a benchmark of explosion_damage: it excludes item lookups,
row locking, mutations, triggers, history, payload aggregation and transaction commits. The scratch table
was session-local and removed automatically on disconnect. No gameplay data was changed.

Decision: do not deploy unconditional caching. Small batches regressed even with table creation excluded.
The columns are integers, so this candidate also uses no feature newly available in 13.1. A deployment
would need full procedure measurements and result/concurrency verification, plus an observed batch-size
distribution to justify a threshold. Keep the existing procedure for now.
