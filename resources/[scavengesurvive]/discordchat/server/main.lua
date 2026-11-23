-- Global chat <-> Discord #in-game-chat, and join-part activity -> Discord #join-part.
-- Transport is the third-party discord resource (botder/mtasa-discord-bot, installed outside this repo with its
-- Node relay, see docs/runbooks/discord-bridge.md). Only global chat and player connection events cross.

local function loadFile(path)
    local f = assert(fileOpen(path, true), "discordchat: cannot open " .. path)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=discordchat/" .. path))()
end

local logic = loadFile("shared/logic/discordchat.lua")

local function bridge()
    local res = getResourceFromName("discord")
    return res and getResourceState(res) == "running" and res
end

local function getJoinPartChannel()
    local val = get("joinPartChannel")
    return (type(val) == "string" and val ~= "") and val or "1564285345426833608"
end

local function getInGameChatChannel()
    local val = get("inGameChatChannel")
    return (type(val) == "string" and val ~= "") and val or "in-game-chat"
end

local function getStaffChannel()
    local val = get("staffChannel")
    return (type(val) == "string" and val ~= "") and val or "1563498523507425421"
end

local function getDeathsChannel()
    local val = get("deathsChannel")
    return (type(val) == "string" and val ~= "") and val or "deaths"
end

addEventHandler("characterDeathLogged", root, function(playerName, cause, killerName)
    local res = bridge()
    if not res then
        return
    end
    local victim = logic.strip(playerName)
    local causeText = logic.strip(cause):gsub("^%l", string.upper)
    local killer = type(killerName) == "string" and logic.strip(killerName) or nil
    if victim == "" then
        return
    end
    local text = string.format(
        ":skull: **%s** died%s\n**Cause:** %s · <t:%d:F>",
        victim,
        killer and (" to **" .. killer .. "**") or "",
        causeText ~= "" and causeText or "Unknown",
        getRealTime().timestamp
    )
    call(res, "send", "staff.log", { text = text, channel = getDeathsChannel() })
end)

local spawnImages = loadFile("shared/spawn_images.lua")

local function calibreName(id)
    return exports.data:calibreName(id)
end

local function getSpawnsChannel()
    local val = get("spawnsChannel")
    return (type(val) == "string" and val ~= "") and val or "1572010791199055962"
end

local function spawnImageBase()
    local base = get("spawnImageBase")
    return (type(base) == "string" and base ~= "") and base or "https://dl.scavengesurvive-reborn.com/images/"
end

local function postSpawn(res, embed)
    if embed then
        call(res, "send", "spawn.post", { channel = getSpawnsChannel(), embed = embed })
    end
end

-- #spawns: one embed per vehicle or loot item, the region only (no coordinates).
addEventHandler("vehicleRefillSpawned", root, function()
    local res = bridge()
    if not res or not isElement(source) then
        return
    end
    local x, y, z = getElementPosition(source)
    local vt = exports.data:vehicleType(getElementData(source, "vehicles.type"))
    postSpawn(res, logic.vehicleSpawnEmbed(vt, getZoneName(x, y, z, true)))
end)

function logItemSpawn(playerName, itemUname, itemId, zone)
    local res = bridge()
    if not res then
        return false
    end
    local packet, payload = logic.itemSpawnPayload(playerName, itemUname, itemId, zone, getStaffChannel())
    if packet and payload then
        call(res, "send", packet, payload)
        return true
    end
    return false
end

function sendStaffLog(text)
    local res = bridge()
    if not res then
        return false
    end
    local packet, payload = logic.staffLogPayload(text, getStaffChannel())
    if packet and payload then
        call(res, "send", packet, payload)
        return true
    end
    return false
end

addEventHandler("globalChatSent", root, function(text)
    local res = bridge()
    if res and getElementType(source) == "player" then
        call(res, "send", "chat.message.text", {
            author = logic.strip(getPlayerName(source)),
            text = logic.strip(text),
        })
    end
end)

-- Posted once auth knows the player's language (the join line shows it).
addEventHandler("playerJoinAnnounced", root, function(code)
    local res = bridge()
    if not res then
        return
    end
    local name = getPlayerName(source)
    local langName = exports.data:languageName(code)
    for _, channel in ipairs({ getJoinPartChannel(), getInGameChatChannel() }) do
        local payload = logic.joinPayload(name, channel, langName)
        if payload then
            call(res, "send", "player.join", payload)
        end
    end
end)

addEventHandler("onPlayerQuit", root, function(quitType, reason, responsible)
    local res = bridge()
    if not res then
        return
    end
    local respName = false
    if isElement(responsible) then
        if getElementType(responsible) == "player" then
            respName = getPlayerName(responsible)
        else
            respName = "Console"
        end
    end
    local packet, payload = logic.quitPayload(getPlayerName(source), quitType, reason, respName, getJoinPartChannel())
    if packet and payload then
        call(res, "send", packet, payload)
    end
end)

addEventHandler("onPlayerChangeNick", root, function(previous, nick)
    local res = bridge()
    if not res then
        return
    end
    local payload = logic.nickChangePayload(previous, nick, getJoinPartChannel())
    if payload then
        call(res, "send", "player.nickchange", payload)
    end
end)

addEventHandler("onDiscordPacket", root, function(packet, payload)
    if packet ~= "text.message" or type(payload) ~= "table" then
        return
    end
    local author = type(payload.author) == "table" and logic.strip(payload.author.name) or ""
    local text = type(payload.message) == "table"
            and logic.strip(payload.message.text):gsub("^%s+", ""):gsub("%s+$", "")
        or ""
    if author == "" or text == "" then
        return
    end
    exports.chat:sendGlobalExternal("Discord", author, text)
end)

-- lootSpawned is emitted only after the scarcity-budget placement transaction commits.
addEventHandler("lootSpawned", root, function(spawnId, _, spawnedItems)
    local res = bridge()
    if not res or type(spawnedItems) ~= "table" then
        return
    end
    local channel = get("itemRespawnsChannel") or "1567306210561237032"
    for _, item in ipairs(spawnedItems) do
        local def = exports.data:itemType(item.u)
        local area = getZoneName(item.x, item.y, item.z, false)
        local region = getZoneName(item.x, item.y, item.z, true)
        local text = string.format(
            "**%s** (`%s`)\n%s · %s\n**Coordinates:** `X %.3f · Y %.3f · Z %.3f`\n**Spawn point:** `%s` · <t:%d:T>",
            def and def.name or item.u,
            item.u,
            area,
            region,
            item.x,
            item.y,
            item.z,
            tostring(spawnId),
            getRealTime().timestamp
        )
        call(res, "send", "staff.log", { text = text, channel = channel })
        postSpawn(res, logic.itemSpawnEmbed(def, item.u, region, spawnImages, spawnImageBase(), calibreName))
    end
end)
