-- Global chat <-> Discord #in-game-chat, and join-part activity -> Discord #join-part.
-- Transport is the third-party discord resource (botder/mtasa-discord-bot, installed outside this repo with its
-- Node relay, see docs/runbooks/discord-bridge.md). Only global chat and player connection events cross.

local function loadFile(path)
    local f = fileOpen(path, true)
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

local function getStaffChannel()
    local val = get("staffChannel")
    return (type(val) == "string" and val ~= "") and val or "1563498523507425421"
end

local function getGeneralChannel()
    local val = get("generalChannel")
    return (type(val) == "string" and val ~= "") and val or "general"
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

addEventHandler("vehicleRefillSpawned", root, function()
    local res = bridge()
    if not res or not isElement(source) then
        return
    end
    local vt = exports.data:vehicleType(getElementData(source, "vehicles.type"))
    local x, y = getElementPosition(source)
    local zone = logic.cityAt(x, y)
    local packet, payload = logic.vehicleSpawnPayload(vt and vt.name, zone, getGeneralChannel())
    if packet and payload then
        call(res, "send", packet, payload)
    end
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

addEventHandler("onPlayerJoin", root, function()
    local res = bridge()
    if not res then
        return
    end
    local payload = logic.joinPayload(getPlayerName(source), getJoinPartChannel())
    if payload then
        call(res, "send", "player.join", payload)
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
    end
end)
