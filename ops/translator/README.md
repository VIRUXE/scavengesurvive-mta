# Chat translator (ops/translator)

Translates game chat for the `chat` resource with Claude Haiku through the Claude Code CLI (the machine's
`claude` login, i.e. a Claude subscription; no API key).

- `server.py`: HTTP on 127.0.0.1:8130. `POST /translate` with `{speaker, mode, text, targets}` (targets are the
  game's language codes: en es fr pt ptbr ru ro id bhs cs) answers `{source, t: {code: translation}}`, leaving
  out the languages the line is already in. `GET /health`.
- One `claude -p` process stays up in stream-json mode, so each chat line is a turn of the same session and Haiku
  sees the recent conversation; it is recycled every 150 lines (`SSMTA_TRANSLATOR_MAX_TURNS`) or on an error or a
  15 s timeout. Requests run one at a time, in order. About 1 s per line.
- Fallback: when Claude fails (error, timeout, usage limit), the same line goes to Google Cloud Translation v2
  (project `scavenge-and-survive-reborn`, key restricted to that API and the server's IPv4, in
  `/etc/ssmta-translator.env` as `SSMTA_GOOGLE_TRANSLATE_KEY`, mode 0600), one call per target and without context.
  Claude is then skipped for 15 min after a usage-limit error, 1 min after anything else. `GET /health` shows
  `claude_paused_s`; replies carry `"via": "claude"` or `"google"`. Google calls are forced onto IPv4.
- `chat/server/main.lua` only calls it when the audience mixes languages (the speaker's, every reader's, plus
  English for global lines, which Discord gets in English).

## Install
1. `claude` logged in as root (`claude auth status` shows `authMethod: claude.ai`).
2. `cp ssmta-translator.service /etc/systemd/system/ && systemctl daemon-reload && systemctl enable --now ssmta-translator`
3. The `chat` resource needs `function.fetchRemote` in the server ACL: a group with `resource.chat` and an ACL
   granting it (the `Everyone` group maps `resource.*` to `Default`, which denies it). `aclReload()` applies an
   edited `acl.xml` without a restart.

Logs: `journalctl -u ssmta-translator` (one line per translation: time, source, targets). Failed calls show up in
the game log as `chat.translationFailed`.
