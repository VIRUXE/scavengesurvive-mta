-- Worn armour durability (upstream item/armour.pwn). ctx = { state, hands, destroy, world, armour, sendInventory }
-- built by server/main.lua; the points live in the item's data.ap and reach the DB through hands.queueData.
return function(ctx)
    local state, hands, destroy, world, armour = ctx.state, ctx.hands, ctx.destroy, ctx.world, ctx.armour
    local sendInventory = ctx.sendInventory
    local M = {}

    -- A chest hit on a worn Armour: returns the bleed that gets through (the armour's penetration cut) and
    -- drains the points; at 0 the item is destroyed. Without armour (or points) the bleed is unchanged.
    function M.hit(player, bleed, penetration)
        local item = state.armour[player]
        if not item then
            return bleed
        end
        if armour.ensure(item, math.random) then
            hands.queueData(item)
        end
        local ap = tonumber(item.data.ap) or 0
        if ap <= 0 then
            return bleed
        end
        local through, left = armour.hit(ap, bleed, penetration)
        if left > 0 then
            item.data.ap = left
            hands.queueData(item)
            sendInventory(player)
            return through
        end
        item.data.ap = 0
        hands.setGear(player, "armour", nil)
        destroy(item.id, player, nil, "broken")
        world.syncPlayer(player)
        return through
    end

    return M
end
