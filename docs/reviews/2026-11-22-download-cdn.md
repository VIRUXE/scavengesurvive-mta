# Resource downloads through Cloudflare (2026-11-22)

**Question:** does serving the MTA `httpdownloadurl` through Cloudflare's edge make file downloads faster for the
players we have?

**Change:** `dl.scavengesurvive-reborn.com` proxied (was DNS only), a Cache Rule making `dl…/downloads/*` cacheable
with the edge TTL from the origin, nginx on nasa sending `Cache-Control: public, max-age=86400` there, Smart Tiered
Cache on, and a Configuration Rule turning Browser Integrity Check and challenges off for `dl` (the MTA client cannot
pass them). Setup and operation: `docs/runbooks/website-hosting.md`.

## Who plays

Top 20 accounts by hours in the last 30 days (`connection_log`), country from the server's own `ip2c` table, looked up
on nasa: Latvia (41.5 h), Russia (28.6 h), Brazil (25.8 h, and 6 of the 20), UK, Morocco, Portugal, Serbia, Iceland,
Spain, Lithuania, Hungary, Romania.

## Method

check-host.net HTTP checks from 15 nodes, each round fetching the same file from the same node at the same moment twice:
**direct** = `http://ss.flaviopereira.dev/reborn/downloads/…` (unproxied, same folder on nasa, London) and
**Cloudflare** = `http://dl.scavengesurvive-reborn.com/downloads/…`. Files: `samp_models/files/beanie1.txd` (683 KB,
56 KB gzipped) and `hud/shared/logic/bars.lua` (small). One warm-up round, then medians of 3 rounds ("now") and one
round 6 minutes later ("later"). Times are whole requests in ms. No node in Latvia, Lithuania or Morocco (Poland and
Sweden stand in for the Baltics); the Romanian node failed or hung on both URLs and is left out.

## Results (1-day edge TTL, Smart Tiered Cache)

| Node | Big direct | Big CF now | Big CF later | Small direct | Small CF now | Small CF later |
| --- | --- | --- | --- | --- | --- | --- |
| São Paulo | 724 | 26 | 44 | 363 | 27 | 33 |
| Los Angeles | 554 | 36 | 49 | 276 | 33 | 27 |
| New York | 341 | 66 | 70 | 165 | 78 | 72 |
| Belgrade | 166 | 27 | 74 | 78 | 24 | 24 |
| Stockholm | 134 | 23 | 31 | 67 | 27 | 23 |
| Warsaw | 108 | 30 | 69 | 55 | 26 | 27 |
| Madrid | 109 | 34 | 103 | 54 | 25 | 25 |
| Nyiregyhaza | 146 | 43 | 69 | 74 | 44 | 38 |
| Reykjavik | 180 | 94 | 64 | 113 | 54 | 67 |
| Viana (PT) | 156 | 60 | 135 | 78 | 70 | 57 |
| Moscow | 187 | 65 | 194 | 94 | 108 | 85 |
| St Petersburg | 225 | 110 | 210 | 91 | 107 | 114 |
| Nuremberg | 67 | 55 | 75 | 36 | 50 | 54 |
| London | 37 | 38 | 69 | 15 | 45 | 55 |

## The 5-minute TTL first tried

With `max-age=300` an edge copy expired between joins, and Cloudflare then revalidated with nasa before answering. For
small files that was slower than direct (São Paulo 364 → 533 ms, Los Angeles 273 → 305 ms), so the TTL was raised to a
day. Fresh copies under 5 minutes had measured São Paulo 725 → 98 ms.

## Conclusions

- Brazil and the Americas gain the most (about 15× and 5–10×), most of Europe 2–5×; London, Germany and Russia stay
  about the same (nasa is in London).
- The "Map download progress" box on every join (about 1.2 MB) is the join packet over the game connection
  (`m_pBigPacketTransferBox`, `CClientGame.cpp`), not files, and Cloudflare does not touch it.
- After an `rr`, changed files stay stale at the edges for up to a day unless `dl…/downloads/<resource>/` is purged: the
  client catches the checksum mismatch and fetches that file again from port 22005 (`#1011` in `server.log`).
