-- The HUD draws nothing until it knows the character's stats and hand, and the server pushes both only on change:
-- a (re)started hud client asks for them here and gets the current values back.
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()

net.handler("hudStateRequested", function(player)
    local stats = exports.character:getStats(player)
    if stats then
        local snapshot = { hp = stats.hp, food = stats.food, bleed = stats.bleed }
        triggerClientEvent(player, "characterStatsSynced", player, snapshot)
    end
    triggerClientEvent(player, "heldItemChanged", player, exports.items:getHeld(player) or false)
    local ok, freq, mode = pcall(function()
        return exports.chat:getRadio(player)
    end)
    if ok and freq then
        triggerClientEvent(player, "chatRadioChanged", player, freq, mode)
    end
end)
