-- The HUD draws nothing until it knows the character's stats and hand, and the server pushes both only on change:
-- a (re)started hud client asks for them here and gets the current values back.
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()

net.handler("hudStateRequested", function(player)
    local stats = exports.character:getStats(player)
    if stats then
        triggerClientEvent(
            player,
            "characterStatsSynced",
            player,
            { hp = stats.hp, food = stats.food, bleed = stats.bleed }
        )
    end
    triggerClientEvent(player, "heldItemChanged", player, exports.items:getHeld(player) or false)
end)
