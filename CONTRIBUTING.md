# Contributing

1. Read `CLAUDE.md` (conventions) and the design spec in `docs/superpowers/specs/`.
2. Set up the toolchain: `pwsh tools/setup-dev.ps1`; local MariaDB 12.x for `tests/sql`.
3. Pick an issue from the [project board](https://github.com/users/VIRUXE/projects/3) or open one with a template.
4. Write the failing test first, then the code. Before committing, run the local checks:
   `.lua/bin/busted tests/lua`, `.lua/bin/luacheck resources`, `stylua --check resources`, `pytest -q`.
5. Commit straight to `main` with a conventional-commit message. There is no CI and there are no pull requests;
   the local checks are the gate.

New code is released under the Unlicense. Converted upstream data stays MPL-2.0 (`THIRD_PARTY_NOTICES.md`).
Never commit SA-MP model files or passwords.
