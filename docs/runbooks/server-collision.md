# Server-side collision (ml_sageom)

MTA has no world geometry on the server: `getGroundPosition` and `processLineOfSight` are client-only. The
[sa-geom](https://github.com/VIRUXE/sa-geom) server module gives the server the vanilla San Andreas collision, and
the `world` resource adds the port's own map on top of it.

| Piece | Where | Notes |
|---|---|---|
| `ml_sageom.so` | `$MTA/x64/modules/`, `<module src="ml_sageom.so"/>` in `mtaserver.conf` | built from `/gta/sa/sa-geom` (`crates/sa-geom-mta`); loads only at server start |
| Overlay | `world/geom/overlay.toml` + `port.map` | written by `python -m tools.geom_overlay`, committed |
| Loader | `world/server/geom.lua` | applies the overlay once per server process; logs `geom.overlayApplied` |
| Queries | `lib` module `geom` (server) | answers `nil` when the module or the overlay is missing, so callers keep a fallback |

## After changing maps, puzzles or a model pack

1. `python -m tools.geom_overlay` and commit `world/geom/`.
2. Restart the **server**. An overlay cannot be taken out of a running module, so a `world` restart with changed
   files only logs `geom.overlayStale` and keeps answering from the overlay already loaded.

## Upgrading the module

The module is shared with the offline tools (`tools/spawn_ground.py` uses the CLI from the same repo): coordinate
before rebuilding. A module built with world format v2 also reads mesh shapes, so after deploying one run
`python -m tools.geom_overlay --dff`. A v1 module rejects a manifest with `[[dff]]` entries (`geom.overlayFailed`).

## Limits

- Collision only for the main world (dimension 0, interior 0) as the map puts it: no house shells or other
  dimensions, and breakables (fences, bins) stay where the map placed them even after they are knocked over.
- Each query blocks the server thread. Queries are microseconds; applying the overlay takes about 2.5 s at start.
