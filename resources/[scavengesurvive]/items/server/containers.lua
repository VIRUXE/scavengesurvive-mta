-- Inventory and worn-bag containers: put away, take, and the inventory list sent to the client.
-- ctx = { db, net, state, type, charId, toast, hands } built by server/main.lua; state.held is shared with it.
return function(ctx)
    local db, net, state, hands = ctx.db, ctx.net, ctx.state, ctx.hands
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast
    local M = {}

    local CONTAINERS_SQL = "SELECT c.id, c.kind, c.size, owner.type_uname AS uname FROM containers c "
        .. "LEFT JOIN items owner ON owner.id = c.owner_item_id "
        .. "WHERE c.owner_char_id = ? OR (owner.holder_char_id = ? AND owner.holder_kind = 'bag')"

    local function wornBag(cid, cb, c)
        db.one(
            "SELECT c.id, c.size FROM items i JOIN containers c ON c.owner_item_id = i.id "
                .. "WHERE i.holder_char_id = ? AND i.holder_kind = 'bag'",
            { cid },
            cb,
            c
        )
    end

    local function put(player, cid, itemId, containerId, onFull)
        db.call("container_put", { itemId, cid, containerId }, function(res, c)
            if not isElement(c.player) then
                return
            end
            if res and res.ok then
                hands.setHeld(c.player, nil)
                triggerEvent("onItemMoved", c.player, c.itemId, "held", "container")
                return toast(c.player, "PUT_AWAY")
            end
            if res and res.code == "CONTAINER_FULL" and onFull then
                return onFull()
            end
            toast(c.player, res and res.code or "DB_ERROR")
        end, { player = player, itemId = itemId })
    end

    local function wearBag(player, cid, item)
        -- bag_wear refuses a second bag with BAG_SLOT_USED instead of tripping uq_items_holder_kind (1062 in the log)
        db.call("bag_wear", { item.id, cid }, function(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            hands.setHeld(c.player, nil)
            hands.setWorn(c.player, c.item)
            triggerEvent("onItemMoved", c.player, c.item.id, "held", "bag")
            toast(c.player, "BAG_WORN")
        end, { player = player, item = item })
    end

    net.handler("onItemsRequestPutAway", function(player)
        local cid, item = charId(player), state.held[player]
        if not cid then
            return
        end
        if not item then
            return toast(player, "NOT_HELD")
        end
        local t = itemType(item.uname)
        if t and t.category == "bag" then
            return wearBag(player, cid, item)
        end
        local inv = exports.character:getInventoryContainerId(player)
        if not inv then
            return
        end
        -- inventory first, then the worn bag
        put(player, cid, item.id, inv, function()
            wornBag(cid, function(bag, c)
                if not isElement(c.player) then
                    return
                end
                if not bag then
                    return toast(c.player, "CONTAINER_FULL")
                end
                put(c.player, cid, item.id, bag.id)
            end, { player = player })
        end)
    end, { rate = 5 })

    local function sendInventory(player)
        local cid = charId(player)
        if not cid then
            return
        end
        db.query(CONTAINERS_SQL, { cid, cid }, function(conts, c)
            if not conts or not isElement(c.player) then
                return
            end
            local payload = { inventory = {}, bag = false, capacity = { inv = { used = 0, size = 0 }, bag = false } }
            local byId, ids = {}, {}
            for _, cont in ipairs(conts) do
                if cont.kind == "inventory" then
                    byId[cont.id] = { rows = payload.inventory, cap = payload.capacity.inv }
                    payload.capacity.inv.size = cont.size
                else
                    payload.bag = {}
                    payload.capacity.bag = { used = 0, size = cont.size, uname = cont.uname }
                    byId[cont.id] = { rows = payload.bag, cap = payload.capacity.bag }
                end
                ids[#ids + 1] = string.format("%d", cont.id)
            end
            if #ids == 0 then
                return triggerClientEvent(c.player, "onClientItemsInventory", c.player, payload)
            end
            local sql = "SELECT i.id, i.type_uname AS uname, i.hitpoints AS hp, i.data, i.container_id AS cid, "
                .. "t.size AS isize, t.category FROM items i JOIN item_types t ON t.uname = i.type_uname "
                .. "WHERE i.container_id IN ("
                .. table.concat(ids, ",")
                .. ") ORDER BY i.container_id, i.slot"
            db.query(sql, {}, function(rows, c2)
                if not rows or not isElement(c2.player) then
                    return
                end
                for _, r in ipairs(rows) do
                    local target = byId[r.cid]
                    if target then
                        target.rows[#target.rows + 1] = {
                            id = r.id,
                            uname = r.uname,
                            hp = r.hp,
                            category = r.category,
                            data = hands.decodeData(r.data),
                        }
                        target.cap.used = target.cap.used + (tonumber(r.isize) or 1)
                    end
                end
                triggerClientEvent(c2.player, "onClientItemsInventory", c2.player, payload)
            end, { player = c.player })
        end, { player = player })
    end
    M.sendInventory = sendInventory

    net.handler("onItemsRequestOpenInventory", function(player)
        sendInventory(player)
    end, { rate = 3 })

    net.handler("onItemsRequestTake", function(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        if state.held[player] then
            return toast(player, "HANDS_FULL")
        end
        db.call("container_take", { itemId, cid }, function(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            db.one(
                "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
                { c.itemId },
                function(row, c2)
                    if not row or not isElement(c2.player) then
                        return
                    end
                    row.data = hands.decodeData(row.data)
                    hands.setHeld(c2.player, row)
                    triggerEvent("onItemMoved", c2.player, c2.itemId, "container", "held")
                    sendInventory(c2.player)
                end,
                { player = c.player, itemId = c.itemId }
            )
        end, { player = player, itemId = itemId })
    end, { rate = 5 })

    return M
end
