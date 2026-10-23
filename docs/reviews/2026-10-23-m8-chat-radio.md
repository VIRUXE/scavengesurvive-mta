# M8 chat modes and radio (#49), 2026-10-23

New `chat` resource. Upstream `core/player/chat.pwn` (modes, flood mute, line split, `/g /l /r /me /quiet`) and
`core/ui/radio.pwn` (the panel). The watch already drew a frequency; it now draws the live one.

## Port decisions

| Upstream | Port | Why |
| --- | --- | --- |
| `OnPlayerText` returns 0 and re-sends per mode | `onPlayerChat` cancelled, delivery by mode in `chat/server/main.lua`; MTA's own broadcast never happens | same shape |
| `[Local] (id) Name: text` | `[Local] Name: text` (light blue), `[Global]` white, `[101.30]` orange, `[Admin]` in the staff level colour | MTA has no player ids |
| Chat bubbles (`SetPlayerChatBubble`) | none | MTA has no chat bubble; nametags are hidden anyway |
| Flood: 3 messages within 1 s = 30 s mute (in chat.pwn's own mute) | same rule in `chat.flood`, the mute itself goes through `exports.staff:mutePlayer` so it persists and shows in `/profile` | one mute system |
| Frequency input dialog (87.5-108.0) | knobs ±0.5, mouse wheel over the frequency ±0.01, `/freq <value>` | no input dialog in the dx kit |
| Knob sprites `LD_DRV:nawtxt` | boxes in the knob colour with `<` `>` | no sprite shipped |
| Radio opened from the inventory "Radio" row or R in a vehicle | R in a vehicle (hud lists `R Open radio`) or `/radio` anywhere | the inventory list is owned by `items`, in progress in another session |
| Frequency/mode saved in the player file | `characters.radio_freq`, `chat_mode` (migration 0008) | |
| `/a` toggles admin chat mode or sends | `/a <text>` sends (staff resource); the admin **mode** (`chat_mode` 3) is reachable through `exports.chat:setChatMode` but has no toggle command yet | avoid two `/a` handlers |

Textdraw colours decoded for the panel: `16777215` is `0x00FFFFFF` (cyan, the mode and frequency labels),
`-16776961` is `0xFF0000FF` (red, the power label); `docs/ui-reference-samp.md` previously called it blue.

## Verified

- `busted`: 222 pass (`chat_logic_spec.lua`: band clamp/parse, 0.05 channel window, flood streak, line split,
  labels, toggles, panel hit tests). `luacheck` 0 warnings in 120 files, `stylua --check` clean, no call split
  across lines. `pytest tests/tools tests/sql`: 77 pass (migration 8 in the schema list).
- Live (dev server): see the section below.

## Live run (dev server, 11:55)

- Migration 0008 applied to the live database, `chat` started (ACL group extended over rcon as for `staff`), `staff`
  and `hud` restarted with it: all `running`, no `scripts.log` errors, `exports.chat:getRadio` answers.
- `rcon.ps1 cmd VIRUXE freq 101.3` set the frequency (`getRadio` returned 101.3); `/g`, `/l` and `/r` dispatched
  (`executeCommandHandler` true) but delivered nothing and the frequency was not persisted: the connected player
  had **no auth session and no character** (`isAuthenticated` false) because `auth` was restarted earlier in the
  day by the event-rename session and sessions live in that VM. The chat gate refusing an unauthenticated player
  is the intended behaviour; delivery, persistence and the panel are therefore smoke step 24 after a relog.
