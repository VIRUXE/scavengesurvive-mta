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
