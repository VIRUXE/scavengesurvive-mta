-- Worn masks against the toxic cloud (shared/logic/masks.lua). ctx = { state, hands, destroy, world, masks, toast,
-- sendInventory, log } built by server/main.lua; a mask's condition lives in its item data and reaches the DB
-- through hands.queueData, like armour points.
return function(ctx)
    local state, hands, destroy, world, masks = ctx.state, ctx.hands, ctx.destroy, ctx.world, ctx.masks
    local toast, sendInventory, log = ctx.toast, ctx.sendInventory, ctx.log
    local shown = {} -- player -> the whole % the inventory last showed, so it is resent only when that changes

    local function left(item)
        local d = item.data
        return math.ceil(tonumber(d.wear) or tonumber(d.filter) or 0)
    end

    -- The player breathed gas of this strength for dt seconds: the worn mask takes its wear and the share of the
    -- gas it kept out is returned (0 without a mask).
    local function breathed(player, concentration, dt)
        local item = state.mask[player]
        if not item or not masks.spec(item.uname) then
            return 0
        end
        if masks.ensure(item, math.random) then
            hands.queueData(item)
        end
        local kept = masks.protection(item.uname, item.data)
        local wear = masks.breathe(item, concentration, dt)
        if not wear then
            return kept
        end
        if wear == "spent" then
            hands.setGear(player, "mask", nil)
            destroy(item.id, player, nil, "worn out")
            world.syncPlayer(player)
            shown[player] = nil
            toast(player, "MASK_SPENT")
            log.event("items.maskWorn", { player = player, item_id = item.id, uname = item.uname, spent = true })
            return kept
        end
        hands.queueData(item)
        if wear == "filter" then
            toast(player, "FILTER_SPENT")
            log.event("items.maskWorn", { player = player, item_id = item.id, uname = item.uname, filter = 0 })
        end
        local now = left(item)
        if shown[player] ~= now then
            shown[player] = now
            hands.publishMask(player)
            sendInventory(player)
        end
        return kept
    end

    -- A Filter used from the hand: it goes into the worn mask, the old one is thrown away. True when handled.
    local function useFilter(player, filterId)
        local item = state.mask[player]
        local m = item and masks.spec(item.uname)
        if not m or m.kind ~= "filtered" then
            toast(player, "FILTER_NO_MASK")
            return true
        end
        destroy(filterId, player, function(ok)
            local worn = isElement(player) and state.mask[player]
            if not ok or not worn or worn.id ~= item.id then
                return
            end
            masks.fitFilter(worn)
            hands.queueData(worn)
            shown[player] = nil
            hands.publishMask(player)
            sendInventory(player)
            toast(player, "FILTER_FITTED")
            log.event("items.filterFitted", { player = player, item_id = worn.id, uname = worn.uname })
        end, "used")
        return true
    end

    addEventHandler("onPlayerQuit", root, function()
        shown[source] = nil
    end)

    return { breathed = breathed, useFilter = useFilter }
end
