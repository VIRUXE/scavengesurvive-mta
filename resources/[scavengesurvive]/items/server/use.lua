-- Food is the MVP use-case; treatments held in hand start a hold (server/medical.lua, #94); other categories are
-- handled by other resources through itemUseAttempted (cancel = consumed).
-- Food in hand next to a campfire or barbecue goes onto it instead (upstream OnPlayerUseItemWithItem: the interact
-- key at a world item uses the held item with it).
-- ctx = { medical, db, net, state, type, charId, toast, destroy, sendInventory, decodeData, cooking, cookers, world,
-- clothes } built by server/main.lua.
return function(ctx)
    local db, net, state = ctx.db, ctx.net, ctx.state
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast

    local COOKERS = { "Campfire", "Barbecue" }
    local OWNED_SQL = "SELECT i.type_uname AS uname, i.data FROM items i "
        .. "LEFT JOIN containers c ON c.id = i.container_id LEFT JOIN items owner ON owner.id = c.owner_item_id "
        .. "WHERE i.id = ? AND (i.holder_char_id = ? OR c.owner_char_id = ? OR owner.holder_char_id = ?)"

    local function eat(player, itemId, t, fromHand, data)
        local food = t.categoryData or {}
        local amount = (tonumber(food.biteValue) or 0) * (tonumber(food.maxBites) or 1)
        -- item/food.pwn: uncooked food that can be cooked gives 70 %, and raw meat or fish infects (#94); a campfire
        -- or barbecue cooks it (#95, server/cooking.lua)
        local raw = ctx.cooking.isRaw(t, data)
        if raw then
            amount = amount * 0.7
        end
        -- destroy first: the stat only changes once the item is really gone
        ctx.destroy(itemId, player, function(ok, code)
            if not ok then
                return toast(player, code)
            end
            exports.character:modifyStat(player, "food", amount)
            if raw and food.canRawInfect then
                exports.character:setInfection(player, "food", true)
            end
            toast(player, "ATE")
            if not fromHand then
                ctx.sendInventory(player)
            end
        end)
    end

    local function use(player, itemId, uname, fromHand, data)
        if not triggerEvent("itemUseAttempted", player, itemId, uname) then
            return -- cancelled by a handler that consumed it
        end
        if uname == "Clothes" then
            return ctx.clothes.use(player, itemId, data, fromHand)
        end
        if fromHand and ctx.medical.isTreatment(uname) then
            return ctx.medical.start(player, state.held[player])
        end
        local t = itemType(uname)
        if not t or t.category ~= "food" then
            return
        end
        if not fromHand then
            return eat(player, itemId, t, fromHand, data)
        end
        local x, y = getElementPosition(player)
        local r = tonumber(state.settings["items.pickup_radius"]) or 2.0
        local int, dim = getElementInterior(player), getElementDimension(player)
        local sql = ctx.world.findNearestSql(x, y, r, int, dim, COOKERS)
        db.one(sql, {}, function(row, c)
            if not isElement(c.player) then
                return
            end
            local held = state.held[c.player]
            if not held or held.id ~= c.itemId then
                return
            end
            if row then
                return ctx.cookers.interact(c.player, charId(c.player), held, row)
            end
            eat(c.player, c.itemId, t, true, c.data)
        end, { player = player, itemId = itemId, data = data })
    end

    net.handler("itemUseRequested", function(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        local held = state.held[player]
        if held and held.id == itemId then
            return use(player, itemId, held.uname, true, held.data)
        end
        -- only items the character owns (inventory or worn bag) can be used
        db.one(OWNED_SQL, { itemId, cid, cid, cid }, function(row, c)
            if not isElement(c.player) then
                return
            end
            if not row then
                return toast(c.player, "NOT_OWNER")
            end
            use(c.player, c.itemId, row.uname, false, ctx.decodeData(row.data))
        end, { player = player, itemId = itemId })
    end, { rate = 3 })
end
