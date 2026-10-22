# Contributing

1. Read `CLAUDE.md` (conventions and rules) and the design spec in `docs/superpowers/specs/`; decisions that changed
   the design since then are in `docs/adr/`.
2. Set up the toolchain: `pwsh tools/setup-dev.ps1`; a local MariaDB 13.0 (12.2 also works) for `tests/sql`.
3. Pick an issue from the [project board](https://github.com/users/VIRUXE/projects/3) or open one with a template.
   Work is tracked there: a commit that fixes, advances or re-scopes an issue closes or comments on it.
4. Write the failing test first, then the code. Pure logic goes in `shared/logic/*.lua` (busted), data conversion in
   `tools/convert` (pytest), multi-row DB work in `sql/procedures` (pytest against the live test database).
5. Before committing, the four local checks must pass: `.lua/bin/busted.bat tests/lua`,
   `.lua/bin/luacheck.bat resources`, `stylua --check resources`, `pytest -q`.
6. Commit straight to `main` with a conventional-commit message (`feat(items): …`). There is no CI and there are no
   pull requests; the local checks are the gate.
7. Verify on the local server when it matters: `pwsh server-config/run-local.ps1`, then `pwsh server-config/rcon.ps1`
   to restart resources, run commands as a player and take screenshots. Record live findings in `docs/reviews/`.

New code is released under the Unlicense. Converted upstream data stays MPL-2.0 and the map placements CC BY-SA 4.0
(`THIRD_PARTY_NOTICES.md`). Never commit passwords (`server-config/local.settings.xml`). Generated files
(`data/generated/`, `maps/data/`, `sql/seed/`, `docs/maps-census.md`, the `models` pack) are committed on purpose;
regenerate them with `python -m tools.convert all` and `python -m tools.extract_samp_models` rather than editing.
