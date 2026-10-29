# Discord bridge and Rich Presence

**When:** global chat stops reaching Discord `#in-game-chat` (or Discord messages stop showing in game), Rich
Presence shows nothing, or the bridge has to be set up on another host.

**What runs where (prod):**

| Piece | Where | Notes |
| --- | --- | --- |
| `discordchat` (this repo) | `resources/[scavengesurvive]/discordchat` | relays `/g` global chat to `#in-game-chat` and join/quit/kick/ban/nickchange activity to `#join-part` (`1564285345426833608`); `chat` raises `globalChatSent`, Discord lines arrive through `exports.chat:sendGlobalExternal` as `[Discord] name: text` |
| `presence` (this repo) | `resources/[scavengesurvive]/presence` | Rich Presence; `*appId` / `*joinUrl` settings in its `meta.xml` |
| `discord` (third party, MIT) | `$DM/resources/[discord]/discord`, not in git | transport from [botder/mtasa-discord-bot](https://github.com/botder/mtasa-discord-bot); its `discord-events` resource is not installed (it relays every chat mode); `config.xml` holds the channel name and the shared passphrase |
| `ml_sockets.so` 1.4 | `$MTA/x64/modules/`, `<module src="ml_sockets.so"/>` in `mtaserver.conf` | from `nightly.mtasa.com/files/modules/64/`; loads only at server start |
| Node relay | `$MTA/discord-relay`, systemd `mta-discord-relay.service` (user `mta`, `/usr/bin/node`) | `src/` of the same repo; deps via `pnpm install --prod`; `config.json` (mode 600) holds the bot token, guild id and passphrase |

Discord side: application and bot **Scavenge & Survive** (id `1564023462010429470`) in the Developer Portal,
Message Content intent on, invited with View Channels + Send Messages + Read Message History. It talks only in
the guild set in `config.json` (it leaves any other) and only in the channel named there.

Local changes to the vendored relay (reapply after an upstream update): the socket server listens on
`127.0.0.1` only (`library/Server.js`); `Bot.sendMessage` passes `allowedMentions: { parse: [] }` so relayed
text never pings; `Bot.sendMessageTo` and `Bot.getChannel` resolve channels by ID or name; `PlayerEventHandler` routes
join/quit/kick/ban/nickchange activity to `joinPartChannel` (`1564285345426833608`); `ChatMessageHandler` routes
`staff.log` and messages with `channel` to `staffChannel` (`1563498523507425421`) or the specified channel;
`Bot._channelCreate` no longer deletes every new channel (upstream compared discord.js 14's numeric channel types against `"text"`).

## Check

1. `systemctl status mta-discord-relay` and `journalctl -u mta-discord-relay -n 20`: `Server listening on 8100`,
   `Bot Scavenge & Survive connected`.
2. `$DM/logs/server.log` after a start: `[Discord] Connected to 127.0.0.1`, `Authentication successful`,
   `Channel has been bound`. `Module 'ml_sockets' not found` means the `<module>` line or the file is missing.
3. Type `/g test` in game: the line shows in `#in-game-chat`; a message there shows in game as `[Discord]`.

## Fix

- Relay down: `systemctl restart mta-discord-relay`; the `discord` resource reconnects by itself (15 s).
- Token revoked or leaked: Developer Portal > Bot > Reset Token (needs the owner's MFA), put it in
  `discord-relay/config.json`, restart the relay.
- Channel renamed: change both `config.json` (`bots[0].channel`) and `[discord]/discord/config.xml`, restart the
  relay and `restart discord`.
- Passphrase: generate one (`openssl rand -hex 24`), set it in both files, restart both.

**Rollback:** stop and disable `mta-discord-relay`, remove `discord` and `discordchat` from the startup list (the
`chat` hooks are harmless without them).
