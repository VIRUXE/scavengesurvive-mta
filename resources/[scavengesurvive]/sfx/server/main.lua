-- Dev tool: /sfx [container bank sound] opens (or closes) the sound browser on the caller's client, for whoever the
-- dev resource lets use its commands (exports.dev:isAllowed). A sound the browser marks is logged (sfx.marked), so
-- the picks can be read back from the game log.
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

local function allowed(player)
    local dev = getResourceFromName("dev")
    return dev and getResourceState(dev) == "running" and exports.dev:isAllowed(player) == true
end

addCommandHandler("sfx", function(player, _, container, bank, sound)
    if not allowed(player) then
        return outputChatBox("[sfx] not allowed", player, 255, 120, 120)
    end
    triggerClientEvent(player, "sfxBrowserToggled", resourceRoot, container, tonumber(bank), tonumber(sound))
end)

net.handler("sfxMarked", function(player, container, bank, sound, note)
    if not allowed(player) then
        return
    end
    log.event("sfx.marked", {
        player = player,
        container = tostring(container),
        bank = tonumber(bank),
        sound = tonumber(sound),
        note = type(note) == "string" and note:sub(1, 64) or nil,
    })
end, { rate = 5 })
