-- Global chat <-> Discord #in-game-chat. Transport is the third-party discord resource (botder/mtasa-discord-bot,
-- installed outside this repo with its Node relay, see docs/runbooks/discord-bridge.md); only global chat crosses,
-- local, radio and admin chat never leave the game.

local function strip(s)
    return (tostring(s or ""):gsub("#%x%x%x%x%x%x", ""))
end

local function bridge()
    local res = getResourceFromName("discord")
    return res and getResourceState(res) == "running" and res
end

addEventHandler("globalChatSent", root, function(text)
    local res = bridge()
    if res and getElementType(source) == "player" then
        call(res, "send", "chat.message.text", { author = strip(getPlayerName(source)), text = strip(text) })
    end
end)

addEventHandler("onDiscordPacket", root, function(packet, payload)
    if packet ~= "text.message" or type(payload) ~= "table" then
        return
    end
    local author = type(payload.author) == "table" and strip(payload.author.name) or ""
    local text = type(payload.message) == "table" and strip(payload.message.text):gsub("^%s+", ""):gsub("%s+$", "")
        or ""
    if author == "" or text == "" then
        return
    end
    exports.chat:sendGlobalExternal("Discord", author, text)
end)
