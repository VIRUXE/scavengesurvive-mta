-- server-local (between resources)
addEvent("globalChatSent", false)
addEvent("vehicleRefillSpawned", false) -- triggered by vehicles when the refill tick adds a vehicle
addEvent("onDiscordPacket", false) -- triggered by the third-party discord resource, name is theirs

addEvent("lootSpawned", false) -- successful scarcity-budget loot placements
