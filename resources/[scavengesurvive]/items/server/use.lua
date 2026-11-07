-- Food is the MVP use-case; treatments held in hand start a hold (server/medical.lua, #94); other categories are
-- handled by other resources through itemUseAttempted (cancel = consumed).
-- Uncooked food in hand next to a campfire or barbecue goes onto it instead (upstream OnPlayerUseItemWithItem: the
-- interact key at a world item uses the held item with it); cooked food, or food that cannot be cooked, is eaten even
-- there (upstream's campfire took any food back onto the fire).
-- ctx = { medical, drinking, db, net, state, type, charId, toast, destroy, sendInventory, decodeData, cooking,
-- cookers, world, clothes, small, parachute, garden, ownedSql, apparel, wear, openSide } built by server/main.lua.
return function(ctx)
    local db, net, state = ctx.db, ctx.net, ctx.state
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast

    local COOKERS = { "Campfire", "Barbecue" }
    local OWNED_SQL = ctx.ownedSql

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
        end, "used")
    end

    -- Food used straight out of an open box, bag or snack machine: grabbed and eaten in one go. item_destroy only
    -- deletes what the character carries, so it comes out first (container_take into an empty hand, else
    -- container_move into the inventory), and the container's owner hears of the take (a machine empties its coil).
    -- Food the character already carries (inventory, worn bag) is eaten where it is.
    local function eatFromSide(player, itemId, t, data, openContainerId)
        local cid = charId(player)
        local side = ctx.openSide(player)
        local function eaten(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            if side and side.onChange and side.containerId == openContainerId then
                side.onChange()
            end
            eat(c.player, itemId, t, false, data)
        end
        db.one("SELECT container_id FROM items WHERE id = ?", { itemId }, function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            if tonumber(row.container_id) ~= tonumber(openContainerId) then
                return eat(c.player, itemId, t, false, data) -- in the inventory or bag already
            end
            if not state.held[c.player] then
                return db.call("container_take", { itemId, cid, openContainerId, n = 3 }, eaten, c)
            end
            local inv = exports.character:getInventoryContainerId(c.player)
            if not inv then
                return toast(c.player, "HANDS_FULL")
            end
            db.call("container_move", { itemId, cid, inv, openContainerId, n = 4 }, eaten, c)
        end, { player = player })
    end

    local function use(player, itemId, uname, fromHand, data, openContainerId)
        if not triggerEvent("itemUseAttempted", player, itemId, uname) then
            return -- cancelled by a handler that consumed it
        end
        if uname == "Clothes" then
            return ctx.clothes.use(player, itemId, data, fromHand, openContainerId)
        end
        if uname == "Note" then
            return ctx.small.useNote(player, itemId, data, fromHand, openContainerId)
        end
        if uname == "Locator" then
            return ctx.small.useLocator(player, itemId, data)
        end
        local wearSlot = ctx.apparel.slotFor(uname)
        if fromHand and (wearSlot == "hat" or wearSlot == "mask" or wearSlot == "armour") then
            return ctx.wear(player, itemId)
        end
        if uname == "Shield" and fromHand then
            return ctx.small.useShield(player, itemId)
        end
        if uname == "Parachute" and fromHand then
            return ctx.parachute.equip(player, itemId)
        end
        if uname == "HerpDerp" then
            return ctx.small.useHerpDerp(player)
        end
        if fromHand and ctx.medical.isTreatment(uname) then
            return ctx.medical.start(player, state.held[player])
        end
        local t = itemType(uname)
        if fromHand and t and t.category == "liquid" then
            -- a Plant Pot within reach is watered first (upstream OnPlayerUseItemWithItem came before the drink);
            -- otherwise the hand drinks (upstream drinks from the hand only)
            local x, y = getElementPosition(player)
            local reach = tonumber(state.settings["items.pickup_radius"]) or 2.0
            local int, dim = getElementInterior(player), getElementDimension(player)
            local sql = ctx.world.findNearestSql(x, y, reach, int, dim, { "PlantPot" })
            return db.one(sql, {}, function(pot, c)
                if not isElement(c.player) then
                    return
                end
                local held = state.held[c.player]
                if not held or (pot and ctx.garden.interact(c.player, held, pot)) then
                    return
                end
                ctx.drinking.start(c.player, held)
            end, { player = player })
        end
        if not t or t.category ~= "food" then
            return
        end
        if not fromHand and openContainerId then
            return eatFromSide(player, itemId, t, data, openContainerId)
        end
        if not fromHand or not ctx.cooking.isRaw(t, data) then
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
        if not cid or not itemId or ctx.isBadInteract(player) then
            return
        end
        local held = state.held[player]
        if held and held.id == itemId then
            return use(player, itemId, held.uname, true, held.data)
        end
        -- Items in the currently open side container can also be used (for example a ground bag).
        local openContainerId = ctx.openContainerId(player)
        db.one(OWNED_SQL, { itemId, cid, cid, cid, openContainerId or -1 }, function(row, c)
            if not isElement(c.player) then
                return
            end
            if
                row
                and openContainerId
                and tonumber(row.container_id) == tonumber(openContainerId)
                and ctx.openContainerId(c.player) ~= openContainerId
            then
                row = nil
            end
            if not row then
                return toast(c.player, "NOT_OWNER")
            end
            use(c.player, c.itemId, row.uname, false, ctx.decodeData(row.data), openContainerId)
        end, { player = player, itemId = itemId, openContainerId = openContainerId })
    end, { rate = 3 })
end
