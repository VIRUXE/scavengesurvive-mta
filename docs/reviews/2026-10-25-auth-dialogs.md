# Login, register and welcome dialogs live check, 2026-10-25

Issue #81. Dev server, one connected client (`VIRUXE`), driven with `rcon.ps1`: `rr ui`, `rr auth` (every
connected client is re-prompted when `auth` restarts), then `clua` to open the boxes through `exports.ui:dialogOpen`
with the real language strings (`exports.data:t`) and to type through `triggerEvent("onClientCharacter", …)`,
`screenshot` between the steps, `chat` for the results. Nine HTTP calls spaced 3 s apart stayed under the flood
guard. The first screenshot caught the peer session's hat studio behind the dialog; the client was logged in
through the new box by its owner before the scripted steps.

## Results

| Step | Checked | Result |
| --- | --- | --- |
| 1 | `rr auth` re-prompts the connected client; the real login path | pass: `Login To Your Account`, `Welcome Back VIRUXE, Please log into to your account below!` with the yellow `Enjoy your stay :)`, masked field with a blinking caret, `Accept` / `Leave`; the owner typed the password and `isAuthenticated` returned true, `character` respawned the character (`docs/images/auth-dialog-login.jpg`) |
| 2 | register box with eight typed characters | pass: `Register For A New Account`, `Hello VIRUXE, You must be new here!` with `password` in blue, eight asterisks in the field, box width from the longest line (`auth-dialog-register.jpg`) |
| 3 | wrong-password body | pass: `Incorrect password! 2 out of 5 tries`, the box narrows to the line (`auth-dialog-wrong-password.jpg`) |
| 4 | welcome box (`triggerEvent("authWelcomeShown", localPlayer)`) | pass: the upstream text in white, teal, blue and yellow, one centred button reading `7` three seconds in, `Accept` after the countdown, `dialogClose()` returned true (`auth-dialog-welcome-countdown.jpg`, `auth-dialog-welcome-accept.jpg`) |
| 5 | Leave kick with the grey broadcast; server re-prompt after a real wrong password | not driven: both need a client that is not logged in, and the only one belonged to a logged-in account; covered by `tests/lua/spec/auth_prompt_spec.lua` and `auth_flow_spec.lua` |
| 6 | Ctrl+V paste | not driven (added after the run); `dialog.pasted` has a spec, the handler has no server side |

## Also seen

- The welcome body's longest line (the `/rules` and `/help` sentence) sets the box at about 840 px on 720p, well
  inside the 600-unit cap; shorter dialogs sit at the list dialog's 280 units.
- Typing arrives through `onClientCharacter` while `guiSetInputMode("no_binds")` is on, so **T** and **Y** do not
  open the chat box and **H** does not open the inventory while a field is focused.
- Restarting `auth` while a peer session is using the client interrupts its screenshots: check `rcon.ps1 chat` for
  recent `[clua]` lines before `rr auth`.

## Follow-ups filed

#82 `/changepass`, #83 post-login alias report and banned-alias kick, #84 join/quit broadcasts and the MoTD on
connect, #85 reuse of the new dialogs where the port deviated (report reason, radio frequency, `/help`,
`/chatinfo`, `/welcome`), #86 auto-login by IP and auto-whitelist.
