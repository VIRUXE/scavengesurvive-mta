local CONTAINERS_SQL = "SELECT c.id, c.kind, c.size FROM containers c "
    .. "LEFT JOIN items owner ON owner.id = c.owner_item_id "
    .. "WHERE c.owner_char_id = ? OR (owner.holder_char_id = ? AND owner.holder_kind = 'bag')"

local function wornBag(charId, cb, ctx)
    Items.db.one(
        "SELECT c.id, c.size FROM items i JOIN containers c ON c.owner_item_id = i.id "
            .. "WHERE i.holder_char_id = ? AND i.holder_kind = 'bag'",
        { charId },
        cb,
        ctx
    )
end

local function put(player, charId, itemId, containerId, onFull)
    Items.db.call("container_put", { itemId, charId, containerId }, function(res, ctx)
        if not isElement(ctx.player) then
            return
        end
        if res and res.ok then
            Items.setHeld(ctx.player, nil)
            triggerEvent("onItemMoved", ctx.player, ctx.itemId, "held", "container")
            return Items.toast(ctx.player, "PUT_AWAY")
        end
        if res and res.code == "CONTAINER_FULL" and onFull then
            return onFull()
        end
        Items.toast(ctx.player, res and res.code or "DB_ERROR")
    end, { player = player, itemId = itemId })
end

local function wearBag(player, charId, item)
    Items.db.exec(
        "UPDATE items SET holder_kind = 'bag' WHERE id = ? AND holder_char_id = ? AND holder_kind = 'held'",
        { item.id, charId },
        function(ok, ctx, affected)
            if not isElement(ctx.player) then
                return
            end
            if ok and affected == 1 then
                Items.setHeld(ctx.player, nil)
                triggerEvent("onItemMoved", ctx.player, ctx.itemId, "held", "bag")
                Items.toast(ctx.player, "BAG_WORN")
            else
                -- uq_items_holder_kind: a second worn bag fails with 1062 (suppressed in the log)
                Items.toast(ctx.player, "BAG_SLOT_USED")
            end
        end,
        { player = player, itemId = item.id }
    )
end

Items.net.handler("onItemsRequestPutAway", function(player)
    local charId, item = Items.charId(player), Items.held[player]
    if not charId then
        return
    end
    if not item then
        return Items.toast(player, "NOT_HELD")
    end
    local t = Items.type(item.uname)
    if t and t.category == "bag" then
        return wearBag(player, charId, item)
    end
    local inv = exports.character:getInventoryContainerId(player)
    if not inv then
        return
    end
    -- inventory first, then the worn bag
    put(player, charId, item.id, inv, function()
        wornBag(charId, function(bag, ctx)
            if not isElement(ctx.player) then
                return
            end
            if not bag then
                return Items.toast(ctx.player, "CONTAINER_FULL")
            end
            put(ctx.player, charId, item.id, bag.id)
        end, { player = player })
    end)
end, { rate = 5 })

local function sendInventory(player)
    local charId = Items.charId(player)
    if not charId then
        return
    end
    Items.db.query(CONTAINERS_SQL, { charId, charId }, function(conts, ctx)
        if not conts or not isElement(ctx.player) then
            return
        end
        local payload = { inventory = {}, bag = false, capacity = { inv = { used = 0, size = 0 }, bag = false } }
        local byId, ids = {}, {}
        for _, c in ipairs(conts) do
            if c.kind == "inventory" then
                byId[c.id] = { rows = payload.inventory, cap = payload.capacity.inv }
                payload.capacity.inv.size = c.size
            else
                payload.bag = {}
                payload.capacity.bag = { used = 0, size = c.size }
                byId[c.id] = { rows = payload.bag, cap = payload.capacity.bag }
            end
            ids[#ids + 1] = string.format("%d", c.id)
        end
        if #ids == 0 then
            return triggerClientEvent(ctx.player, "onClientItemsInventory", ctx.player, payload)
        end
        local sql = "SELECT i.id, i.type_uname AS uname, i.hitpoints AS hp, i.container_id AS cid, t.size AS isize, "
            .. "t.category FROM items i JOIN item_types t ON t.uname = i.type_uname WHERE i.container_id IN ("
            .. table.concat(ids, ",")
            .. ") ORDER BY i.container_id, i.slot"
        Items.db.query(sql, {}, function(rows, c2)
            if not rows or not isElement(c2.player) then
                return
            end
            for _, r in ipairs(rows) do
                local target = byId[r.cid]
                if target then
                    target.rows[#target.rows + 1] = { id = r.id, uname = r.uname, hp = r.hp, category = r.category }
                    target.cap.used = target.cap.used + (tonumber(r.isize) or 1)
                end
            end
            triggerClientEvent(c2.player, "onClientItemsInventory", c2.player, payload)
        end, { player = ctx.player })
    end, { player = player })
end
Items.sendInventory = sendInventory

Items.net.handler("onItemsRequestOpenInventory", function(player)
    sendInventory(player)
end, { rate = 3 })

Items.net.handler("onItemsRequestTake", function(player, itemId)
    local charId = Items.charId(player)
    itemId = tonumber(itemId)
    if not charId or not itemId then
        return
    end
    if Items.held[player] then
        return Items.toast(player, "HANDS_FULL")
    end
    Items.db.call("container_take", { itemId, charId }, function(res, ctx)
        if not isElement(ctx.player) then
            return
        end
        if not res or not res.ok then
            return Items.toast(ctx.player, res and res.code or "DB_ERROR")
        end
        Items.db.one(
            "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
            { ctx.itemId },
            function(row, c)
                if not row or not isElement(c.player) then
                    return
                end
                row.data = Items.decodeData(row.data)
                Items.setHeld(c.player, row)
                triggerEvent("onItemMoved", c.player, c.itemId, "container", "held")
                sendInventory(c.player)
            end,
            { player = ctx.player, itemId = ctx.itemId }
        )
    end, { player = player, itemId = itemId })
end, { rate = 5 })
