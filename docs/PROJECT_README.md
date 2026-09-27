# Scavenge & Survive → MTA — project board

Tracks the port of Scavenge & Survive from SA-MP (Pawn) to MTA:SA 1.6 (Lua) with MariaDB 12.
Design: `docs/superpowers/specs/`. MVP plan: `docs/superpowers/plans/`.

## Fields

| Field | Values | Source of truth |
| --- | --- | --- |
| Status | Todo / In Progress / Done | built-in |
| Phase | M0 … M8 | issue milestone |
| Area | auth, character, items, … infra | `area/*` label |
| Port class | port / replace / drop / defer | `port/*` label |
| Size | XS … XL | `size/*` label |
| Target | date | roadmap due date |

## Views

- **Board** — columns by Status; group by Phase.
- **Backlog** — table of open items, grouped by Phase, sorted by Size.
- **Roadmap** — Target date bars with milestone markers.

## Manual setup (UI only, about 2 minutes)

The API cannot set a view's group-by, sort, column field or roadmap dates. In each view open the
view menu and set: Board → Column by: Status, Group by: Phase; Backlog → Group by: Phase, Sort: Size;
Roadmap → Dates: Target, Markers: Milestones. Discussions categories (Announcements, Design, Q&A,
Show and tell) are also created in the UI.
