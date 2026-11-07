# Voice

The server runs MTA's built-in voice chat. Hold MTA's voice key (push-to-talk, set in MTA's settings under the key binds) and talk; let go to stop. Nothing has to be carried or switched on in game, and there is no voice command of your own.

## Who hears you

Voice follows your [chat](Chat) mode:

| Your radio is in | Who hears you |
|:--|:--|
| Local (`/l`) | players within 40 m |
| Global (`/g`) | players within 40 m, and everyone who would read your global text |
| Radio (`/r`) | players within 40 m, and everyone tuned within 0.05 MHz of your frequency ([Radio](Radio)) |

Players within 40 m always hear you, whatever the mode. The audience is checked again every half second while you talk, so someone who walks up or tunes in mid-sentence catches the rest of it.

While you are muted ([Reports & Bans](Reports-and-Bans)), pressing the key does nothing and the game tells you once per mute: *You are muted: nobody hears your voice until the mute ends.* Before you have logged in, voice is off too.

## The talking indicator

<!-- shot:shot-voice-indicator -->

While anyone you can hear is talking, a block of rows appears at the left of the screen, centred vertically:

- When **you** talk, the top row is your indicator: a green bar, a pulsing speaker icon and `TALKING [LOCAL]`, `TALKING [GLOBAL]` or `TALKING [98.12]` with your frequency in radio mode, so you always know who is on the other end.
- Under it, one row per player talking: your own row in yellow as `Name (You)`, the others in their name colour behind a blue bar. Your row comes first, then the others in the order they started talking.

Over the head of every talking player within 40 m a speaker icon floats, green for you and in the player's name colour for the others. It is drawn only while you have a clear line of sight to them, never through a wall, and it shrinks with distance. Dead players show nothing. Rows and icons go as soon as the key is released.

See also [Chat](Chat), [Radio](Radio) and [Reports & Bans](Reports-and-Bans).
