# Server-side collision (ml_sageom)

MTA has no world geometry on the server: `getGroundPosition` and `processLineOfSight` are client-only. The
[sa-geom](https://github.com/VIRUXE/sa-geom) server module gives the server the vanilla San Andreas collision, and
the `world` resource adds the port's own map on top of it.

| Piece | Where | Notes |
|---|---|---|
| `ml_sageom.so` | `$MTA/x64/modules/`, `<module src="ml_sageom.so"/>` in `mtaserver.conf` | built from `/gta/sa/sa-geom` (`crates/sa-geom-mta`); loads only at server start |
| Overlay | `world/geom/overlay.toml` + `port.map` | written by `python -m tools.geom_overlay`, committed |
| Loader | `world/server/geom.lua` | applies the overlay at server start (`geom.overlayApplied`); on a restart with changed files the module rebuilds its world with the new overlay (`geom.overlayReloaded`) |
| Queries | `lib` module `geom` (server) | answers `nil` when the module or the overlay is missing, so callers keep a fallback |

## After changing maps, puzzles or a model pack

1. `python -m tools.geom_overlay` and commit `world/geom/`.
2. Restart `world` (`rr world`). An overlay cannot be taken out of a running world, so the module builds a fresh one
   with the new overlay on a background thread (`sageomReload`, about 3–4 s) and swaps it in. Meanwhile root data
   `geom.stale` is true and `lib` geom answers `nil` (callers fall back: drops lie at feet height); the swap logs
   `geom.overlayReloaded`, a failure `geom.overlayFailed` and leaves it stale. Check with
   `rcon.ps1 -Prod lua "return getElementData(root, 'geom.stale')"` (false once it is in).
   A module older than `sageomReload` (sa-geom before 2026-11-21) only logs `geom.overlayStale` and keeps the old
   overlay until the **server** restarts.

Locally the server is 32-bit: `cargo build --release -p sa-geom-mta --target i686-pc-windows-msvc` in sa-geom and copy
`ml_sageom.dll` into the server's `mods/deathmatch/modules/`; `run-local.ps1` loads it whenever it is there.

## Upgrading the module

The module is shared with the offline tools (`tools/spawn_ground.py` uses the CLI from the same repo): coordinate
before rebuilding. A module built with world format v2 also reads mesh shapes, so after deploying one run
`python -m tools.geom_overlay --dff`. A v1 module rejects a manifest with `[[dff]]` entries (`geom.overlayFailed`).

## Limits

- Collision only for the main world (dimension 0, interior 0) as the map puts it: no house shells or other
  dimensions, and breakables (fences, bins) stay where the map placed them even after they are knocked over.
- Each query blocks the server thread: a short ray (a few to tens of metres) costs about 0.015 ms, one crossing
  hundreds of metres of map up to 0.5 ms; applying the overlay takes about 2.5 s at start.
