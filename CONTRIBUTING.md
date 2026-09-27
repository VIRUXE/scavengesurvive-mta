# Contributing

1. Read `CLAUDE.md` (conventions) and the design spec in `docs/superpowers/specs/`.
2. Set up the toolchain: `pwsh tools/setup-dev.ps1`; local MariaDB 12.x for `tests/sql`.
3. Pick an issue from the [project board](https://github.com/users/VIRUXE/projects) or open one with a template.
4. Branch from `main`, write the failing test first, keep `luacheck`, `stylua`, `busted` and `pytest` green.
5. Open a PR with a conventional-commit title. CI must pass (`luacheck, stylua, busted, tools, sql, docs`);
   PRs are squash-merged.

New code is released under the Unlicense. Converted upstream data stays MPL-2.0 (`THIRD_PARTY_NOTICES.md`).
Never commit SA-MP model files or passwords.
