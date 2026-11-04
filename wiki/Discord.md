# Discord

The server is linked to the community's Discord server in two ways: a chat bridge that carries lines between the game and Discord, and Rich Presence, which shows your friends that you are playing.

## The chat bridge

What crosses from the game to Discord:

- Your **global** chat lines (`/g`), posted to the `#in-game-chat` channel under your name. Local chat, radio chat and `/me` never leave the game, and neither does voice.
- **Joins and parts**: joining, leaving, being kicked or banned and nickname changes go to a `#join-part` channel.
- **Deaths**: every character death is posted with the name, who killed them when a player did, the cause and the time.
- **New vehicles**: when the world gets a new vehicle through the scarcity refill ([Loot & Respawn](Loot-and-Respawn)), the general channel is told what it is and in which city (Los Santos, San Fierro or Las Venturas), nothing more precise.
- Items spawned by staff commands and the loot the world respawns are posted to channels of their own, for the staff.

Colour codes are stripped from relayed text, and a relayed line never pings anyone on Discord.

What crosses from Discord to the game:

- A message typed in `#in-game-chat` appears for everyone whose global receiver is on, as a global line: `[Discord] name: text`. `/quiet` hides these together with the rest of global chat ([Chat](Chat)).

Nothing else comes in: nobody on Discord can run commands or read local chat.

If the bridge is down for a while, the game carries on; lines sent in the meantime are simply not relayed.

## Rich Presence

With Discord open on your computer and Rich Presence allowed in MTA's settings, your Discord status shows:

- the server's name,
- *Surviving*,
- how many players are online out of the server's capacity, refreshed every 15 seconds,
- how long you have been on the server,
- a **Join server** button that connects a friend straight to the server (see [Joining the Server](Joining-the-Server)).

Nothing about your character, your position, your items or your chat is shared. The status clears when you leave.

See also [Chat](Chat), [Joining the Server](Joining-the-Server) and [Reports & Bans](Reports-and-Bans).
