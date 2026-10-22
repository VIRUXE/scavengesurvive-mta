-- Hands and the worn bag: what a player carries is published as protected element data ("items.held" /
-- "items.bag" = type uname or false); every client draws its own bone-attached objects from it (client/attach.lua).
-- ctx = { db, net, state, geometry, type, charId, toast, world } built by server/main.lua; state.held / state.worn
-- are shared with it. Busted loads this file with fake deps (tests/lua/spec/items_server_spec.lua).
return function(ctx)
    local db, net, state, geometry, world = ctx.db, ctx.net, ctx.state, ctx.geometry, ctx.world
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast
    local VANILLA_MELEE_MAX = 15
    local M = {}

    local function baseWeapon(t)
        local w = t and t.category == "weapon" and t.categoryData and t.categoryData.baseWeapon
        return w and w > 0 and w or nil
    end

    -- The MVP has no ammo or reload model, so a firearm without data.mag is held with a full magazine
    -- (GTA will not fire a weapon given with 0 rounds). Vanilla melee ids always get 1.
    local function ammoFor(t, data)
        local mag = tonumber(data and data.mag)
        if mag and mag > 0 then
            return mag
        end
        local w = baseWeapon(t)
        if w and w <= VANILLA_MELEE_MAX then
            return 1
        end
        local size = tonumber(t and t.categoryData and t.categoryData.magSize)
        return (size and size > 0) and size or 1
    end
    M.ammoFor = ammoFor

    local function decodeData(data)
        if data and data ~= false and data ~= "" then
            return fromJSON(data) or {}
        end
        return {}
    end
    M.decodeData = decodeData

    local function publish(player, key, item)
        if isElement(player) then
            setElementData(player, key, item and item.uname or false, "broadcast", "deny")
        end
    end
    M.publish = publish

    -- item = { id, uname, hp, data } or nil: the bag worn on the back
    function M.setWorn(player, item)
        state.worn[player] = item
        publish(player, "items.bag", item)
    end

    function M.clearHeld(player)
        publish(player, "items.held", nil)
        local item = state.held[player]
        if item and isElement(player) then
            local w = baseWeapon(itemType(item.uname))
            if w then
                takeWeapon(player, w)
            end
        end
        state.held[player] = nil
    end

    -- item = { id, uname, hp, data } or nil; the client only ever sees { id, uname, hp }
    function M.setHeld(player, item)
        M.clearHeld(player)
        if not isElement(player) then
            return
        end
        if item then
            state.held[player] = item
            publish(player, "items.held", item)
            local t = itemType(item.uname)
            local w = baseWeapon(t)
            if w then
                giveWeapon(player, w, ammoFor(t, item.data), true)
            end
        end
        triggerClientEvent(
            player,
            "onClientItemsHeld",
            player,
            item and { id = item.id, uname = item.uname, hp = item.hp } or false
        )
    end

    -- Restores the held item and the worn bag from the DB (spawn and resource restart).
    function M.rebuildCarried(player)
        local cid = charId(player)
        if not cid then
            return
        end
        db.query(
            "SELECT id, type_uname AS uname, hitpoints AS hp, data, holder_kind AS kind FROM items "
                .. "WHERE holder_char_id = ? AND holder_kind IN ('held', 'bag')",
            { cid },
            function(rows, c)
                if not isElement(c.player) or rows == false then
                    return
                end
                local held, bag
                for _, row in ipairs(rows) do
                    row.data = decodeData(row.data)
                    if row.kind == "bag" then
                        bag = row
                    else
                        held = row
                    end
                end
                M.setHeld(c.player, held)
                M.setWorn(c.player, bag)
            end,
            { player = player }
        )
    end

    net.handler("onItemsRequestPickup", function(player)
        local cid = charId(player)
        if not cid then
            return
        end
        if state.held[player] then
            return toast(player, "HANDS_FULL")
        end
        local x, y = getElementPosition(player)
        local r = tonumber(state.settings["items.pickup_radius"]) or 2.0
        local sql = world.findNearestSql(x, y, r, getElementInterior(player), getElementDimension(player))
        db.one(sql, {}, function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            db.call("item_pickup", { row.id, c.charId }, function(res, c2)
                if res and res.ok then
                    world.forgetEverywhere(c2.row.id)
                end
                if not isElement(c2.player) then
                    return
                end
                if not res or not res.ok then
                    return toast(c2.player, res and res.code or "DB_ERROR")
                end
                M.setHeld(
                    c2.player,
                    { id = c2.row.id, uname = c2.row.uname, hp = c2.row.hp, data = decodeData(c2.row.data) }
                )
                triggerEvent("onItemMoved", c2.player, c2.row.id, "world", "held")
            end, { player = c.player, row = row })
        end, { player = player, charId = cid })
    end, { rate = 5 })

    net.handler("onItemsRequestDrop", function(player)
        local cid, item = charId(player), state.held[player]
        if not cid then
            return
        end
        if not item then
            return toast(player, "NOT_HELD")
        end
        local x, y, z = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        local dx, dy = geometry.dropPosition(x, y, rz, 1.0)
        local params = { item.id, cid, dx, dy, z - 0.9, rz, getElementInterior(player), getElementDimension(player) }
        db.call("item_drop", params, function(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            M.setHeld(c.player, nil)
            world.syncPlayer(c.player) -- the dropped item appears without waiting for the next tick
            triggerEvent("onItemMoved", c.player, c.itemId, "held", "world")
        end, { player = player, itemId = item.id })
    end, { rate = 5 })

    return M
end
