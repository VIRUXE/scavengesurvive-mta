-- Food is the MVP use-case; other categories are handled by other resources through itemUseAttempted (cancel = consumed).
-- ctx = { db, net, state, type, charId, toast, destroy, sendInventory } built by server/main.lua.
return function(ctx)
    local db, net, state = ctx.db, ctx.net, ctx.state
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast

    local OWNED_SQL = "SELECT i.type_uname AS uname FROM items i "
        .. "LEFT JOIN containers c ON c.id = i.container_id LEFT JOIN items owner ON owner.id = c.owner_item_id "
        .. "WHERE i.id = ? AND (i.holder_char_id = ? OR c.owner_char_id = ? OR owner.holder_char_id = ?)"

    local function eat(player, itemId, t, fromHand)
        local food = t.categoryData or {}
        local amount = (tonumber(food.biteValue) or 0) * (tonumber(food.maxBites) or 1)
        -- destroy first: the stat only changes once the item is really gone
        ctx.destroy(itemId, player, function(ok, code)
            if not ok then
                return toast(player, code)
            end
            exports.character:modifyStat(player, "food", amount)
            toast(player, "ATE")
            if not fromHand then
                ctx.sendInventory(player)
            end
        end)
    end

    local function use(player, itemId, uname, fromHand)
        if not triggerEvent("itemUseAttempted", player, itemId, uname) then
            return -- cancelled by a handler that consumed it
        end
        local t = itemType(uname)
        if t and t.category == "food" then
            eat(player, itemId, t, fromHand)
        end
    end

    net.handler("itemUseRequested", function(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        local held = state.held[player]
        if held and held.id == itemId then
            return use(player, itemId, held.uname, true)
        end
        -- only items the character owns (inventory or worn bag) can be used
        db.one(OWNED_SQL, { itemId, cid, cid, cid }, function(row, c)
            if not isElement(c.player) then
                return
            end
            if not row then
                return toast(c.player, "NOT_OWNER")
            end
            use(c.player, c.itemId, row.uname, false)
        end, { player = player, itemId = itemId })
    end, { rate = 3 })
end
