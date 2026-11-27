-- The HUD draws nothing until it knows the character's stats and hand, and the server pushes both only on change:
-- a (re)started hud client asks for them here and gets the current values back.
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()

net.handler("hudStateRequested", function(player)
    local stats = exports.character:getStats(player)
    if stats then
        local snapshot = { hp = stats.hp, food = stats.food, thirst = stats.thirst, bleed = stats.bleed }
        snapshot.wounds, snapshot.woundParts = stats.wounds, stats.woundParts
        triggerClientEvent(player, "characterStatsSynced", player, snapshot)
    end
    triggerClientEvent(player, "heldItemChanged", player, exports.items:getHeld(player, true) or false)
    local freq, mode = exports.chat:getRadio(player)
    triggerClientEvent(player, "chatRadioChanged", player, freq, mode)
end)

-- TEMP (2026-11-27): client script errors relayed by client/main.lua, to find why the HUD dies at join for some
addEventHandler("hudClientErrorReported", root, function(message, file, line)
    if client and type(message) == "string" then
        outputServerLog(
            ("[hud] clientError %s: %s (%s:%s)"):format(
                getPlayerName(client),
                message:sub(1, 400),
                tostring(file):sub(1, 120),
                tostring(line)
            )
        )
    end
end)
