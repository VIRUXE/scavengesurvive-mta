-- Food is the MVP use-case; other categories are handled by other resources through onItemUse (cancel = consumed).
local OWNED_SQL = "SELECT i.type_uname AS uname FROM items i "
    .. "LEFT JOIN containers c ON c.id = i.container_id LEFT JOIN items owner ON owner.id = c.owner_item_id "
    .. "WHERE i.id = ? AND (i.holder_char_id = ? OR c.owner_char_id = ? OR owner.holder_char_id = ?)"

local function eat(player, itemId, t, fromHand)
    local food = t.categoryData or {}
    local amount = (tonumber(food.biteValue) or 0) * (tonumber(food.maxBites) or 1)
    -- destroy first: the stat only changes once the item is really gone
    Items.destroy(itemId, player, function(ok, code)
        if not ok then
            return Items.toast(player, code)
        end
        exports.character:modifyStat(player, "food", amount)
        Items.toast(player, "ATE")
        if not fromHand then
            Items.sendInventory(player)
        end
    end)
end

local function use(player, itemId, uname, fromHand)
    if not triggerEvent("onItemUse", player, itemId, uname) then
        return -- cancelled by a handler that consumed it
    end
    local t = Items.type(uname)
    if t and t.category == "food" then
        eat(player, itemId, t, fromHand)
    end
end

Items.net.handler("onItemsRequestUse", function(player, itemId)
    local charId = Items.charId(player)
    itemId = tonumber(itemId)
    if not charId or not itemId then
        return
    end
    local held = Items.held[player]
    if held and held.id == itemId then
        return use(player, itemId, held.uname, true)
    end
    -- only items the character owns (inventory or worn bag) can be used
    Items.db.one(OWNED_SQL, { itemId, charId, charId, charId }, function(row, ctx)
        if not isElement(ctx.player) then
            return
        end
        if not row then
            return Items.toast(ctx.player, "NOT_OWNER")
        end
        use(ctx.player, ctx.itemId, row.uname, false)
    end, { player = player, itemId = itemId })
end, { rate = 3 })
