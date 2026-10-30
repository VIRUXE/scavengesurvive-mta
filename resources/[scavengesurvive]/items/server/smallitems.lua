-- Server side of the small item behaviours (#136, shared/logic/smallitems.lua has the rules):
--   Note: Use opens it on the client (write when blank, read / tear when written), the answer comes back as
--     noteWritten / noteTearRequested and is checked against the item the player opened;
--   Sign: the interact key on a sign lying in reach opens its text for editing (signEditRequested), the text comes
--     back as signTextSubmitted and the world item is re-sent so every client draws it;
--   Dice: a drop rolls them on and stores the face that landed up;
--   Locator: used with a Mobile Phone lying there it syncs to it, used alone it says how far that phone is;
--   Stun Gun: used with a Battery it charges, a fist hit with it (weapons resource) knocks the target out;
--   Molotov: a Petrol Can used with an Empty Molotov pours 0.5 L and the bottle becomes a Molotov.
--   Shield: used from the hand it is planted standing in front of the player (weapons stops the shots it covers);
--   HerpDerp: used, one of 25 random animations;
--   Torso (the body a death leaves, #139): a tap of the interact key investigates it (bodyInspectRequested), a Knife
--     used on it holds 3 s and takes one raw Meat, once, within a day.
-- ctx = { db, net, state, type, charId, toast, destroy, destroyWorldItem, world, updateHeldData, decodeData,
--         small, liquids, sendInventory, ownedSql, dropHeld } built by server/main.lua.
return function(ctx)
    local db, net, state = ctx.db, ctx.net, ctx.state
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast
    local small, liquids, decodeData = ctx.small, ctx.liquids, ctx.decodeData
    local SIGN_REACH = 2.5
    local openNotes = {} -- player -> { itemId, fromHand, openContainerId }
    local openSigns = {} -- player -> itemId
    local M = {}

    local function encode(t)
        return toJSON(t, true):sub(2, -2)
    end

    -- the held item's data (batched with the hand's other changes), or an inventory item's row, rewritten in place
    local function writeData(player, itemId, data, fromHand)
        if fromHand then
            return ctx.updateHeldData(player, data)
        end
        db.exec("UPDATE items SET data = ? WHERE id = ?", { encode(data), itemId }, function(ok, c)
            if ok and isElement(c.player) then
                ctx.sendInventory(c.player)
            end
        end, { player = player })
    end

    -- Note ------------------------------------------------------------------------------------------------------

    function M.useNote(player, itemId, data, fromHand, openContainerId)
        openNotes[player] = { itemId = itemId, fromHand = fromHand, openContainerId = openContainerId }
        triggerClientEvent(player, "noteOpened", player, itemId, small.text(data))
    end

    -- the item the player answered about must be the one they opened, and still theirs
    local function withOpenNote(player, itemId, fn)
        local open = openNotes[player]
        itemId = tonumber(itemId)
        local cid = charId(player)
        if not open or not cid or open.itemId ~= itemId then
            return
        end
        openNotes[player] = nil
        local held = state.held[player]
        if held and held.id == itemId then
            return fn(player, cid, itemId, true, held.data)
        end
        local cont = open.openContainerId or -1
        db.one(ctx.ownedSql, { itemId, cid, cid, cid, cont }, function(row, c)
            if not isElement(c.player) or not row or row.uname ~= "Note" then
                return
            end
            fn(c.player, c.cid, c.itemId, false, decodeData(row.data), c.openContainerId)
        end, { player = player, cid = cid, itemId = itemId, openContainerId = open.openContainerId })
    end

    net.handler("noteWritten", function(player, itemId, text)
        withOpenNote(player, itemId, function(pl, _, id, fromHand, data)
            if small.text(data) ~= "" then
                return -- written once, as upstream (a filled note only reads)
            end
            local clean = small.cleanText(text, small.NOTE_MAX)
            if clean == "" then
                return
            end
            writeData(pl, id, { text = clean }, fromHand)
        end)
    end, { rate = 5 })

    net.handler("noteTearRequested", function(player, itemId)
        withOpenNote(player, itemId, function(pl, _, id, fromHand)
            ctx.destroy(id, pl, function(ok)
                if ok and not fromHand then
                    ctx.sendInventory(pl)
                end
            end)
        end)
    end, { rate = 5 })

    -- Sign ------------------------------------------------------------------------------------------------------

    local SIGN_ROW = "SELECT id, data, x, y, z, interior, dimension FROM items WHERE id = ? AND type_uname = 'Sign' "
        .. "AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"

    local function signInReach(player, row)
        if not row then
            return false
        end
        local px, py, pz = getElementPosition(player)
        return getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) <= SIGN_REACH
            and getElementInterior(player) == (row.interior or 0)
            and getElementDimension(player) == (row.dimension or 0)
    end

    net.handler("signEditRequested", function(player, itemId)
        itemId = tonumber(itemId)
        if not charId(player) or not itemId then
            return
        end
        db.one(SIGN_ROW, { itemId }, function(row, c)
            if not isElement(c.player) or not signInReach(c.player, row) then
                return
            end
            openSigns[c.player] = row.id
            triggerClientEvent(c.player, "signEditOpened", c.player, row.id, small.text(decodeData(row.data)))
        end, { player = player })
    end, { rate = 5 })

    net.handler("signTextSubmitted", function(player, itemId, text)
        itemId = tonumber(itemId)
        if not itemId or openSigns[player] ~= itemId then
            return
        end
        openSigns[player] = nil
        local clean = small.cleanText(text, small.SIGN_MAX)
        if clean == "" then
            return
        end
        db.one(SIGN_ROW, { itemId }, function(row, c)
            if not isElement(c.player) or not signInReach(c.player, row) then
                return
            end
            db.exec("UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL", { encode({ text = c.text }), row.id })
            ctx.world.resendEverywhere(row.id)
        end, { player = player, text = clean })
    end, { rate = 5 })

    -- Dice ------------------------------------------------------------------------------------------------------

    -- hands.dropHeld's hook: the dice roll DICE_THROW on from the drop point and land on a random face
    function M.onDropped(_, item, x, y, _, rz)
        if item.uname ~= "Dice" then
            return
        end
        local face = small.rollDice()
        local lx, ly = small.diceLanding(x, y, rz)
        db.exec(
            "UPDATE items SET x = ?, y = ?, rz = ?, data = ? WHERE id = ? AND x IS NOT NULL",
            { lx, ly, math.random(0, 359), encode({ face = face }), item.id },
            function(ok, c)
                if ok then
                    ctx.world.resendEverywhere(c.id)
                end
            end,
            { id = item.id }
        )
    end

    -- Locator ---------------------------------------------------------------------------------------------------

    -- where an item is: in the world, in a hand or inventory (the player), in a world container (its item)
    local WHERE_SQL = "SELECT i.x, i.y, i.z, i.holder_char_id, c.owner_char_id, c.kind, "
        .. "o.x AS ox, o.y AS oy, o.z AS oz, o.holder_char_id AS oholder FROM items i "
        .. "LEFT JOIN containers c ON c.id = i.container_id LEFT JOIN items o ON o.id = c.owner_item_id "
        .. "WHERE i.id = ? AND i.type_uname = 'MobilePhone'"

    local function playerPos(cid)
        local p = cid and exports.character:getPlayerByCharacterId(cid)
        if p and isElement(p) then
            return getElementPosition(p)
        end
        return nil
    end

    local function locate(row)
        if not row then
            return nil
        end
        if row.x then
            return row.x, row.y, row.z
        end
        if row.holder_char_id then
            return playerPos(row.holder_char_id)
        end
        if row.owner_char_id then
            return playerPos(row.owner_char_id)
        end
        if row.ox then
            return row.ox, row.oy, row.oz
        end
        if row.oholder then
            return playerPos(row.oholder)
        end
        return nil -- a trunk or a crate: nothing to trace
    end

    function M.useLocator(player, _, data)
        local phoneId = small.locatorPhone(data)
        if not phoneId then
            return toast(player, "LOCATORDIS")
        end
        db.one(WHERE_SQL, { phoneId }, function(row, c)
            if not isElement(c.player) then
                return
            end
            local x, y, z = locate(row)
            if not x then
                return toast(c.player, "LOCATORDIS")
            end
            local px, py, pz = getElementPosition(c.player)
            toast(c.player, string.format("DISTANCE:%.3f", getDistanceBetweenPoints3D(px, py, pz, x, y, z)))
        end, { player = player })
    end

    -- Shield and HerpDerp (use from the hand) ------------------------------------------------------------------

    function M.useShield(player, itemId)
        local held = state.held[player]
        if not held or held.id ~= itemId then
            return
        end
        setPedAnimation(player, "BOMBER", "BOM_Plant_In", small.SHIELD_PLANT_MS, false, false, true, false)
        setTimer(function(pl, id)
            local cur = isElement(pl) and state.held[pl]
            if cur and cur.id == id then
                ctx.dropHeld(
                    pl,
                    { ahead = small.SHIELD_AHEAD, below = small.SHIELD_DROP, turn = 180, data = { placed = 1 } }
                )
            end
        end, small.SHIELD_PLANT_MS, 1, player, itemId)
    end

    function M.useHerpDerp(player)
        local block, anim = small.herpAnim()
        setPedAnimation(player, block, anim, -1, false, true, true, false)
    end

    -- Held item used with a world item (hands.lua itemPickupRequested): true when a pair here took it ---------

    local function syncLocator(player, _, row)
        ctx.updateHeldData(player, { phone = row.id })
        toast(player, "LOCATORSYNC")
        return true
    end

    local function chargeStunGun(player, _, row)
        ctx.destroyWorldItem(row.id)
        ctx.updateHeldData(player, { charged = 1 })
        toast(player, "STUNGUNCHAR")
        return true
    end

    local function pourMolotov(player, held, row)
        local ok, nextData = small.pourMolotov(liquids, itemType(held.uname), held.data)
        if not ok then
            toast(player, nextData)
            return true
        end
        ctx.updateHeldData(player, nextData)
        ctx.destroyWorldItem(row.id)
        local params = { small.MOLOTOV_TO, 2, nil, row.x, row.y, row.z, row.rz, row.interior, row.dimension }
        params[10], params[11], params.n = nil, nil, 11
        db.call("item_create", params, function(res, c)
            if res and res.ok then
                triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
            end
            if isElement(c.player) then
                ctx.world.syncPlayer(c.player)
            end
        end, { player = player })
        setPedAnimation(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
        toast(player, "MOLOPOURBOT")
        return true
    end

    local BODY_ROW = "SELECT id, data, x, y, z, rz, interior, dimension FROM items WHERE id = ? "
        .. "AND type_uname = 'Torso' AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"
    local HARVEST_REACH = 3.0

    local function bodyInReach(player, row)
        if not row then
            return false
        end
        local px, py, pz = getElementPosition(player)
        return getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) <= HARVEST_REACH
            and getElementInterior(player) == (row.interior or 0)
            and getElementDimension(player) == (row.dimension or 0)
    end

    local function finishHarvest(player, row)
        local d = decodeData(row.data)
        local ok, code = small.bodyCanHarvest(d, getRealTime().timestamp)
        if not ok then
            return toast(player, code)
        end
        d.harvest = 0
        db.exec("UPDATE items SET data = ? WHERE id = ?", { encode(d), row.id }, function(wrote)
            if wrote then
                ctx.world.resendEverywhere(row.id)
            end
        end)
        local params = { "Meat", 3, encode({ cooked = 0 }), row.x, row.y, row.z + small.MEAT_LIFT, row.rz }
        params[8], params[9], params[10], params[11], params.n = row.interior, row.dimension, nil, nil, 11
        db.call("item_create", params, function(res, c)
            if res and res.ok then
                triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
            end
            if isElement(c.player) then
                ctx.world.syncPlayer(c.player)
            end
        end, { player = player })
    end

    local function harvestBody(player, _, row)
        local ok, code = small.bodyCanHarvest(decodeData(row.data), getRealTime().timestamp)
        if not ok then
            toast(player, code)
            return true
        end
        triggerClientEvent(player, "vehicleHoldStarted", player, "Harvesting", small.HARVEST_MS)
        setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", small.HARVEST_MS, true, false, false, false)
        setTimer(function(pl, bodyId)
            if not isElement(pl) then
                return
            end
            setPedAnimation(pl)
            local cur = state.held[pl]
            if not cur or cur.uname ~= "Knife" then
                return
            end
            db.one(BODY_ROW, { bodyId }, function(cur2, c)
                if isElement(c.player) and bodyInReach(c.player, cur2) then
                    finishHarvest(c.player, cur2)
                end
            end, { player = pl })
        end, small.HARVEST_MS, 1, player, row.id)
        return true
    end

    net.handler("bodyInspectRequested", function(player, itemId)
        itemId = tonumber(itemId)
        if not charId(player) or not itemId then
            return
        end
        db.one(BODY_ROW, { itemId }, function(row, c)
            if not isElement(c.player) or not bodyInReach(c.player, row) then
                return
            end
            local name, reason = small.bodyText(decodeData(row.data))
            setPedAnimation(c.player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
            triggerClientEvent(c.player, "bodyInspected", c.player, name, reason)
        end, { player = player })
    end, { rate = 5 })

    local PAIRS = {
        Locator = { MobilePhone = syncLocator },
        StunGun = { Battery = chargeStunGun },
        GasCan = { [small.MOLOTOV_FROM] = pourMolotov },
        Knife = { Torso = harvestBody },
    }

    -- the world item unames a held uname reaches for (hands.lua targetsFor)
    function M.targets(uname)
        local byWorld = PAIRS[uname]
        if not byWorld then
            return nil
        end
        local list = {}
        for worldUname in pairs(byWorld) do
            list[#list + 1] = worldUname
        end
        return list
    end

    function M.interact(player, held, row)
        local fn = held and PAIRS[held.uname] and PAIRS[held.uname][row.uname]
        if not fn then
            return false
        end
        return fn(player, held, row)
    end

    -- Stun gun hit (weapons: a fist hit while holding one): true when the stun gun took the hit ----------------

    function M.meleeHit(attacker, victim)
        local held = state.held[attacker]
        if not held or held.uname ~= "StunGun" then
            return false
        end
        if not small.isCharged(held.data) then
            toast(attacker, "STUNGUNOUTC")
            return true
        end
        ctx.updateHeldData(attacker, { charged = 0 })
        exports.character:knockOutPlayer(victim, small.STUN_KO_MS)
        return true
    end

    addEventHandler("onPlayerQuit", root, function()
        openNotes[source] = nil
        openSigns[source] = nil
    end)

    return M
end
