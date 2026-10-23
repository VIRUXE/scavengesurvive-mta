# Release

**When:** a milestone's exit criteria are met (roadmap issue #57) and the live checks are recorded under
`docs/reviews/`. Releases are annotated tags on `main`; there is no CI and no build artefact, the server runs the
checked-out tree through the junction created by `run-local.ps1`.

**Prerequisites:** a clean working tree, the local checks green, the server booted once from this commit.

## Steps

1. Checks, from the repo root (CLAUDE.md "Commands"):
   `.lua/bin/busted.bat tests/lua`, `.lua/bin/luacheck.bat resources`, `stylua --check resources`, `pytest -q`
   (needs MariaDB for `tests/sql`). All four must pass; the two luacheck line-length warnings in files owned by
   work in progress block a release, not a commit.
2. Boot: stop the server, `pwsh server-config/run-local.ps1` (no `-Reset`), confirm `0 failed` in `server.log`
   and no `ERROR` in `scripts.log`, log in with one client and run the smoke steps for the milestone in
   `docs/mvp-smoke-checklist.md`; write the results to `docs/reviews/<date>-live-checks.md`.
3. Update the docs that changed meaning: `README`/`server-config/README.md` (commands, settings), the milestone
   comment on #57, the epic issue (`gh issue comment`), and close the issues the release delivers.
4. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z: <milestone>"` and `git push origin main --tags`. Version scheme:
   `v0.<milestone>.<fix>` until the server opens to players (`v0.1.0-mvp` was the MVP exit, `v0.7.0` is M7).
5. `gh release create vX.Y.Z --generate-notes --title "vX.Y.Z <milestone>"` so the notes link the closed issues.

## Rollback

`git checkout <previous tag>` in the repo (the junction follows), run `run-local.ps1` to restart. A release that
changed `sql/schema.sql` cannot be rolled back below that change without reverse DDL or a database restore
(`change-database-schema.md`).

## Escalation

Repository owner cuts tags; a Lead may request one with the review document attached to the roadmap issue.
