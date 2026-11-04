# Chat

Press `T` (MTA's chat key) to type. Every line you send goes out through your [radio](Radio): its mode decides who reads it. Commands are on [Commands](Commands).

## Modes

| Mode | Switch to it / send one line | Who reads it | How it looks |
|:--|:--|:--|:--|
| Local | `/l`, `/local` | players within 40 m of you | light blue, `[Local] Name: text` |
| Global | `/g`, `/global` | everyone on the server who has not turned global off, and the Discord channel (below) | white, `[Global] Name: text` |
| Radio | `/r` | everyone tuned within 0.05 MHz of your frequency | orange, `[98.12] Name: text` (your frequency) |
| Admin | staff only | the staff | the staff member's rank colour, `[Admin] Name: text` |

Typing the command alone switches your mode (`You turn your radio on to the global frequency.`); typing it with text sends that one line in that mode without switching. The radio panel's power and `global`/`freq` buttons switch modes as well: power off is local chat. Every login starts in global; your frequency is saved with your character.

<!-- shot:shot-chat-radio -->

- `/me <text>` sends an action line, `[Local] Name text`, to players within 40 m.
- `/quiet` turns your global receiver off and on. Off hides every global line, including the ones from Discord; you can still send global lines.
- `/freq <87.5-108.0>` tunes the radio, `/radio` opens the panel, `/chatinfo` shows this in game.
- A line longer than 128 characters continues on a second line.
- Sending three lines within one second mutes you for 30 seconds (*Muted from global chat for 30 seconds for chat flooding*). A mute blocks every mode and your voice; see [Reports & Bans](Reports-and-Bans).

## Voice

Push-to-talk voice (MTA's voice key, set in MTA's settings) follows the same rules: players within 40 m always hear you, and in global or radio mode the players who would read your text hear you as well. While muted, nobody hears you and the game tells you so once.

## Lines from the server

- When you join, you read the orange copyright line and, if the staff have set one, `MoTD: ...` (`/motd` repeats it); everyone reads `Name has joined`.
- ` >  ...` lines in yellow or white are the server talking to you: notices, staff messages, command replies.
- `[Admin]` lines exist for the staff only; you never see them.

## Discord

The server is linked to a Discord server.

- Your **global** chat lines are relayed to Discord's `#in-game-chat` channel under your name. Local chat, radio chat and `/me` never leave the game.
- Messages typed in that Discord channel appear in game as a global line, `[Discord] name: text`, for everyone whose global receiver is on.
- Joining, leaving, being kicked or banned, and nickname changes are posted to a `#join-part` channel.
- When the world gets a new vehicle, the general channel is told what it is and in which city.

## Discord Rich Presence

With Discord open and Rich Presence allowed in MTA's settings, your Discord status shows the server's name, *Surviving*, how many players are online and how long you have been playing, with a **Join server** button for your friends. Nothing about your character or position is shared.

See also [Radio](Radio), [Commands](Commands) and [Reports & Bans](Reports-and-Bans).
