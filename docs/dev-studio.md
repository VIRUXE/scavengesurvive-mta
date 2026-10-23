# Green-screen studio (`dev` resource)

A photo set for looking at a ped on its own. `/studio` moves the player into a private dimension high above the
map. They stand frozen inside a closed box of pure chroma green (`#00FF00`), with the camera placed on a fixed orbit.
Screenshots then show only the ped and what it wears or holds: skin, held items, apparel and attachments. No
scenery, sky, other players or HUD gets in the way, and lighting is the same from shot to shot.

| `threequarter` | `left` |
| :---: | :---: |
| ![threequarter preset](images/studio-threequarter.jpg) | ![left preset](images/studio-left.jpg) |

## Use

In game (dev commands, so `*dev.open` or an admin level is required):

| Command | Effect |
| :--- | :--- |
| `/studio [cam]` | Enter the studio. With no argument while inside, leave it. |
| `/studiocam <cam>` | Move the camera. |
| `/studiopose <rz>` | Turn the ped to heading `rz` (0 = facing north, toward the `front` camera). |

`cam` is either a preset or `yaw dist height [lookZ]`:

| Preset | yaw | dist | height | lookZ |
| :--- | ---: | ---: | ---: | ---: |
| `front` | 0 | 3.5 | 0.3 | 0 |
| `back` | 180 | 3.5 | 0.3 | 0 |
| `left` | 270 | 3.5 | 0.3 | 0 |
| `right` | 90 | 3.5 | 0.3 | 0 |
| `threequarter` (default) | 35 | 3.2 | 0.6 | 0 |
| `top` | 0 | 1.2 | 3.5 | 0 |
| `face` | 0 | 1.0 | 0.65 | 0.65 |
| `hands` | 30 | 1.4 | 0.1 | -0.1 |

- `yaw` is in degrees around the ped. 0 puts the camera in front of a ped facing north, and 90 puts it on the
  ped's right.
- `dist` is the horizontal distance.
- `height` and `lookZ` are the camera height and the look-at point, both measured from the ped's origin (about 1 m
  above its feet).
- Values are clamped so the camera stays inside the box.

From a script, or an agent driving the local server:

```powershell
pwsh server-config/rcon.ps1 studio VIRUXE threequarter   # enters if needed, then sets the camera
pwsh server-config/rcon.ps1 screenshot VIRUXE            # -> resources/[scavengesurvive]/dev/screenshots/VIRUXE-<time>.jpg
pwsh server-config/rcon.ps1 studio VIRUXE off            # back to where they were
```

## How it works

- **Set.** The client draws the box every frame with `dxDrawPrimitive3D("trianglelist", "postfx", …)`, so there are
  no model files. The `postfx` stage runs after colour correction, so the green reaches the screen unchanged. The
  draw is depth-tested, so the ped occludes the walls.
- **Floor.** Model 8661 (`gnhtelgrnd_lvs`, a flat slab) sits at `alpha 0` under the ped in the studio dimension, so
  the ped stands rather than playing a fall animation.
- **Isolation.** Each occupant gets the lowest free dimension from 60000 up, at interior 0, with the ped at
  `(0, 0, 2500)`. The box encloses the camera completely, so nothing outside it can show.
- **Light.** While in the studio the client re-applies noon (`setTime(12, 0)`) and weather 1 every frame, and
  stretches the minute duration. The `world` resource's minute-by-minute clock sync therefore cannot change the
  light mid-session. The previous time, weather and minute duration are restored on exit.
- **HUD.** The hud's dx draws are not post-GUI, so `takePlayerScreenShot` captures them. The studio calls the new
  client export `exports.hud:setHidden(true)`, which also hides the stock components. Chat and CEGUI are never
  captured.
- **Heading.** The player's own client owns its ped's rotation, so a server-side `setElementRotation` does not
  stick. The server sends the heading (0 on entry, the saved one on exit, `/studiopose`) and the client applies it.
- **Survival.** The character survival tick keeps running in the studio. Long sessions used to starve or bleed the
  frozen ped to death, so on entry the server records hp and food from `exports.character:getStats` and restores
  them every second with `modifyStat`. Bleed is left alone, because raising it through `modifyStat` counts a new
  wound and bleed only kills through hp anyway.
- **Restore.** On entry the server saves position, heading, interior, dimension and frozen state, and puts them back
  on `/studio`, `studio <p> off` or `dev` stopping.
  - **Quit.** The `onPlayerQuit` handler runs at priority `high+10`, so the player is back in place before auth
    raises `playerLoggedOut` and character saves the position. A quit from the studio never persists the studio
    spot.
  - **Death.** The studio state is only dropped and character's normal respawn takes over. While a player is in
    the studio the server keeps its real spot in element data `character.realPosition` (`local` sync, never sent to
    clients). `character`'s death drop uses that spot, so the inventory is not left in the private dimension.

## Tuning attachments

Worn items get their per-skin rows from `wearOffsets` on the item type. Those rows are generated from upstream's
`Set{Hat,Mask}OffsetsForSkin` and `ArmourSkinData`. Hand-tuned values live in
`items/shared/logic/apparel.lua`:

- `BORROW` gives a wearable upstream never placed a donor item's rows, plus its own `rot`, `shift` and `scale`.
- `OVERRIDES` replaces one skin's row.
- `items/shared/logic/skins.lua` knows every human ped model's gender and build class, and the ordered donor
  chain per class. A skin with no row of its own (upstream tuned 17 skins for hats, masks and armour and 54 for
  bags) borrows the first donor in its chain that has one, so a duty skin, a clothes-item skin or a custom ped
  model wears gear like the nearest spawn skin. `BUILD` moves a model off its gender's average chain.

SA-MP bone 2 (head) is GTA node 5. On it, X points up the skull, Y forward and Z to the side. So `rx` turns an
item about the vertical (yaw), `ry` about the forward axis (roll) and `rz` about the side axis (pitch). Restart
`items` after an edit, wear the item through element data (`lua setElementData(p, "items.hat", "Beanie")`) and
shoot it from `face` and `left`. `tests/lua/spec/items_apparel_spec.lua` fails if a spawn skin lacks a row for
any wearable.

### Attachment editor (`attachedit` resource)

Instead of editing, restarting and reshooting, preview values live on the player's own client. `items` exports two
client functions for this. `setAttachPreview(slot, offsets, scale)` makes the local player's attachment in `slot`
(`hat`, `mask`, `armour`, `bag`, `holster`, `held` or `cuffs`) use `offsets = { x, y, z, rx, ry, rz }` and
`scale = { sx, sy, sz }` instead of its configured row. The preview survives a skin or item change in that slot.
`setAttachPreview(slot, nil)` rebuilds the slot from its configured values. `getAttachConfig(slot)` returns the live
`uname`, `skin`, `bone` (SA-MP id), `offsets`, `scale` and `preview` flag, or nil when nothing is drawn (an empty
slot, or a real weapon GTA draws itself). Other players never see a preview.

In game, `/attachedit <slot>` opens an editor on the item in that slot. Like the dev commands, it needs `*dev.open`
or an admin level. The editor starts from the live values and shows the slot, item, skin and bone, all nine values
and the step:

| Key | Effect |
| :--- | :--- |
| `1`–`9`, up / down | select x, y, z, rx, ry, rz, sx, sy, sz |
| right, `+` (`=`), page up / left, `-`, page down | add / subtract the step |
| `0` / backspace | next / previous step: 0.001, 0.005, 0.02 m; 1, 5, 15°; 0.01, 0.05 scale |
| Enter | print `[skin] = { x, y, z, rx, ry, rz, sx, sy, sz }, -- uname slot` to chat and the server log, and append it to `resources/[scavengesurvive]/attachedit/attachedit-out.lua` (git-ignored) with a timestamp |
| Escape | clear the preview and close (MTA lets a script cancel Escape only once, so a second quick press opens the main menu) |

The row pastes straight into `OVERRIDES[uname]`. `/attachedit <same slot>` closes the editor but keeps the preview.
The keys come through `onClientKey`, and only while the editor is open. Each one it uses is cancelled, so GTA
controls and other binds on that key do not fire, and keys are ignored while chat input, the console or the main
menu is open. The panel is drawn post-GUI, so `takePlayerScreenShot` leaves it out of rcon screenshots. rcon
`key <player> enter|escape|arrow_d|…` drives the editor as well.

With no keyboard, use the rcon verb (dev forwards it to `exports.attachedit:rcon`):

```powershell
pwsh server-config/rcon.ps1 attach VIRUXE hat 0.152 0 -0.006 0 0 0 1.1 1.1 1.1   # preview (scale optional, default 1)
pwsh server-config/rcon.ps1 screenshot VIRUXE
pwsh server-config/rcon.ps1 attach VIRUXE hat get                              # last values the client reported
pwsh server-config/rcon.ps1 attach VIRUXE hat off                              # back to the configured row
```

An HTTP rcon call cannot wait for the client, so `get` prints the server's cached copy of the client's last report
for that slot, with its age, and asks the client for a new one. The client reports after every `set`, every `off`
and every editor nudge, so a `get` a moment after a `set` is current. Otherwise run `get` twice; the first call of
a session says "no report yet". Stopping `attachedit` clears every preview it set.

## Files

- `resources/[scavengesurvive]/dev/shared/logic/studio.lua` holds the pure logic: constants, presets, box
  triangles, camera orbit, `parseCam`, dimension allocation. Tested in `tests/lua/spec/dev_studio_spec.lua`.
- `resources/[scavengesurvive]/dev/server/studio.lua` handles enter and leave, the commands, and restoring on
  quit, death or stop. `server/main.lua` loads it and adds the `studio` rcon verb.
- `resources/[scavengesurvive]/dev/client/studio.lua` draws the box and pins the camera, time and weather.
- `resources/[scavengesurvive]/hud/client/main.lua` adds the `setHidden(bool)` export.
- `resources/[scavengesurvive]/attachedit/` is the attachment editor: `shared/logic/attachedit.lua` (fields, steps,
  clamping, key map, row format, rcon arguments; tested in `tests/lua/spec/attachedit_logic_spec.lua`),
  `client/main.lua` (editor and preview relay) and `server/main.lua` (`/attachedit`, the `rcon` export, the output
  file). The preview hook is in `items/client/attach.lua`, exported from `items/client/main.lua`.

## Limits

- **Server crash.** If the server crashes while someone is in the studio, the last periodic `character_flush` may
  have stored the studio x/y/z. Only `flushOne` stores interior and dimension. Acceptable for a local dev tool.
- **Lighting.** GTA's ped lighting leaves peds fairly dark even at noon. If shots need to be brighter, look at the
  ped's lighting rather than the set.
- **No collision.** The set is drawn, not a model, so it has no collision of its own. If a real 3D set is ever
  needed (with walls the ped can touch, for example), generate it with an existing RenderWare library rather than
  writing DFF, TXD or COL writers here.
