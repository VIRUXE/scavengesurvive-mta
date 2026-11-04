-- Inventory and worn-bag containers: put away, take, and the inventory list sent to the client.
-- ctx = { db, net, state, type, charId, toast, hands, apparel } built by server/main.lua; state.held is shared with it.
return function(ctx)
    local db, net, state, hands = ctx.db, ctx.net, ctx.state, ctx.hands
    local itemType, charId, toast = ctx.type, ctx.charId, ctx.toast
    local apparel = ctx.apparel
    local small = ctx.small
    local world = ctx.world
    local refreshPlayer = ctx.refreshPlayer
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")() -- titles in the player's language
    local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
    local isIncapacitated = ctx.isIncapacitated
    local isBadInteract = ctx.isBadInteract or function()
        return false
    end
    -- player -> { vehicle, containerId, title, size, worldItemId, pos = {x, y, z} }; any number of players may have
    -- the same container open, and every change one of them makes is pushed to the others (refreshViewers)
    local activeContainer = {}
    local lastHolster = {}
    state.lastHolster = lastHolster
    local M = {}

    -- one event per procedure callback: ok and code come from the db.call result (res == false: the query failed);
    -- withPos adds the player's position (x y z int dim) while the player is still there
    local function logProc(kind, player, res, fields, withPos)
        fields.player = player
        fields.ok = res and res.ok or false
        fields.code = res and res.code or "DB_ERROR"
        if withPos and isElement(player) then
            local x, y, z = getElementPosition(player)
            fields.x, fields.y, fields.z = math.floor(x), math.floor(y), math.floor(z)
            fields.int, fields.dim = getElementInterior(player), getElementDimension(player)
        end
        log.event(kind, fields)
    end

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

    local sendInventory
    local clothesRef = ctx.clothes

    local machinesRef, liquidsRef = nil, nil
    function M.setMachines(m, l)
        machinesRef, liquidsRef = m, l
    end

    function M.setClothes(c)
        clothesRef = c
    end

    -- server/parachute.lua: Y with the Parachute in hand puts it on (upstream KEY_YES)
    local parachuteRef
    function M.setParachute(p)
        parachuteRef = p
    end

    function M.openContainerId(player)
        local cont = activeContainer[player]
        if not cont then
            return nil
        end
        if cont.vehicle and not isElement(cont.vehicle) then
            activeContainer[player] = nil
            return nil
        end
        if cont.heldItemId then
            local held = state.held[player]
            if not held or held.id ~= cont.heldItemId then
                activeContainer[player] = nil
                return nil
            end
        elseif cont.pos then
            local px, py, pz = getElementPosition(player)
            if getDistanceBetweenPoints3D(px, py, pz, cont.pos.x, cont.pos.y, cont.pos.z) > 4.0 then
                activeContainer[player] = nil
                return nil
            end
        end
        return cont.containerId
    end

    -- a machine's container takes only what the machine works on (upstream OnItemAddToContainer, MACHITEMTYP):
    -- true when the item may go into the side container the player has open
    local function machineAccepts(player, containerId, uname, data)
        local cont = activeContainer[player]
        if not cont or not cont.machine or cont.containerId ~= containerId or not machinesRef then
            return true
        end
        local ok, needs = machinesRef.accepts(cont.machine, itemType(uname), data, liquidsRef)
        if not ok then
            toast(player, lang.formatFor(player, machinesRef.TEXT.MACHITEMTYP, lang.textFor(player, needs)))
        end
        return ok
    end

    -- carried two-handed items (Wheel, boxes, panels) never go in the inventory or a bag (upstream backpack.pwn
    -- OnPlayerAddToInventory, IsItemTypeCarry); trunks and other containers still take them
    local function isCarry(uname)
        local t = itemType(uname)
        return t and t.useCarryAnim or false
    end

    local function put(player, cid, itemId, containerId, onFull)
        local held = state.held[player]
        if held and held.id == itemId and not machineAccepts(player, containerId, held.uname, held.data) then
            return
        end
        if held and held.id == itemId then
            if held.data and hands.queueData then
                hands.queueData(held)
            end
            if hands.flushData then
                hands.flushData(itemId)
            end
        end
        db.call("container_put", { itemId, cid, containerId }, function(res, c)
            logProc("item.putAway", c.player, res, {
                item_id = c.itemId,
                uname = c.uname,
                container_id = containerId,
                character_id = cid,
            }, true)
            if not isElement(c.player) then
                return
            end
            if res and res.ok then
                hands.setHeld(c.player, nil)
                triggerEvent("itemMoved", c.player, c.itemId, "held", "container")
                if activeContainer[c.player] then
                    sendInventory(c.player)
                end
                return toast(c.player, "PUT_AWAY")
            end
            if res and res.code == "CONTAINER_FULL" and onFull then
                return onFull()
            end
            toast(c.player, res and res.code or "DB_ERROR")
        end, { player = player, itemId = itemId, uname = held and held.id == itemId and held.uname or nil })
    end

    local function wearBag(player, cid, item)
        -- a bag goes where the parachute pack sits: one worn blocks the other (parachute.lua refuses the reverse)
        if state.parachute[player] then
            return toast(player, "BAGPARAWORN")
        end
        -- bag_wear refuses a second bag with BAG_SLOT_USED instead of tripping uq_items_holder_kind (1062 in the log)
        db.call("bag_wear", { item.id, cid }, function(res, c)
            logProc("item.worn", c.player, res, {
                item_id = c.item.id,
                uname = c.item.uname,
                slot = "bag",
                character_id = cid,
            })
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            hands.setHeld(c.player, nil)
            hands.setWorn(c.player, c.item)
            triggerEvent("itemMoved", c.player, c.item.id, "held", "bag")
            toast(c.player, "BAG_WORN")
        end, { player = player, item = item })
    end

    net.handler("itemPutAwayRequested", function(player, target)
        local cid, item = charId(player), state.held[player]
        if not cid then
            return
        end
        local now = getTickCount()
        if lastHolster[player] and (now - lastHolster[player] < 1000) then
            return
        end
        if getPedOccupiedVehicle(player) then
            return
        end
        if isIncapacitated and isIncapacitated(player) then
            return
        end
        local staffRes = getResourceFromName and getResourceFromName("staff")
        if staffRes and getResourceState(staffRes) == "running" and exports.staff:isOnDuty(player) then
            return
        end

        if not item then
            if activeContainer[player] and activeContainer[player].containerId then
                return
            end
            local holstered = state.holster and state.holster[player]
            if not holstered then
                return toast(player, "NOT_HELD")
            end
            lastHolster[player] = now
            local anim = apparel and apparel.holsterAnim(holstered.uname)
                or { block = "PED", anim = "PHONE_IN", time = 300 }
            setPedAnimation(player, anim.block, anim.anim, anim.time, false, false, false, false)
            setTimer(function(pl, hItem)
                if not isElement(pl) or charId(pl) ~= cid then
                    return
                end
                db.call("item_unwear", { cid, "holster" }, function(res, c)
                    logProc("item.unworn", c.player, res, {
                        item_id = c.hItem.id,
                        uname = c.hItem.uname,
                        slot = "holster",
                        character_id = cid,
                    })
                    if not isElement(c.player) then
                        return
                    end
                    if not res or not res.ok then
                        return toast(c.player, res and res.code or "DB_ERROR")
                    end
                    hands.setGear(c.player, "holster", nil)
                    c.hItem.data = hands.decodeData(c.hItem.data)
                    hands.setHeld(c.player, c.hItem)
                    toast(c.player, "EQUIPPED")
                end, { player = pl, hItem = hItem })
            end, anim.time, 1, player, holstered)
            return
        end

        if (target == "bag" or target == "inventory") and isCarry(item.uname) then
            return toast(player, "TOO_BIG")
        end
        if target == "bag" then
            return wornBag(cid, function(bag, c)
                if not isElement(c.player) then
                    return
                end
                if not bag then
                    return toast(c.player, "CONTAINER_FULL")
                end
                put(c.player, cid, item.id, bag.id, function()
                    toast(c.player, "CONTAINER_FULL")
                end)
            end, { player = player })
        elseif target == "trunk" then
            local openId = M.openContainerId(player)
            if openId then
                return put(player, cid, item.id, openId, function()
                    toast(player, "CONTAINER_FULL")
                end)
            end
            return
        elseif target == "inventory" then
            local inv = exports.character:getInventoryContainerId(player)
            if not inv then
                return
            end
            return put(player, cid, item.id, inv, function()
                toast(player, "INVENTORY_FULL")
            end)
        end

        local t = itemType(item.uname)
        if t and t.category == "bag" then
            return wearBag(player, cid, item)
        end
        if item.uname == "Parachute" and parachuteRef then
            return parachuteRef.equip(player, item.id)
        end

        local openId = M.openContainerId(player)
        if openId then
            return put(player, cid, item.id, openId, function()
                toast(player, "CONTAINER_FULL")
            end)
        end

        local slot = apparel and apparel.slotFor(item.uname)
        if slot == "holster" then
            lastHolster[player] = now
            local anim = apparel.holsterAnim(item.uname) or { block = "PED", anim = "PHONE_IN", time = 300 }
            setPedAnimation(player, anim.block, anim.anim, anim.time, false, false, false, false)
            setTimer(function(pl, heldItem)
                if not isElement(pl) or charId(pl) ~= cid then
                    return
                end
                if not state.held[pl] or state.held[pl].id ~= heldItem.id then
                    return
                end
                if heldItem.data and hands.queueData then
                    hands.queueData(heldItem)
                end
                if hands.flushData then
                    hands.flushData(heldItem.id)
                end
                local openContainerId = M.openContainerId(pl)
                db.call("item_wear", { heldItem.id, cid, "holster", openContainerId, n = 4 }, function(res, c)
                    logProc("item.worn", c.player, res, {
                        item_id = c.heldItem.id,
                        uname = c.heldItem.uname,
                        slot = "holster",
                        swapped_id = res and res.ok and res.payload and res.payload.swapped_id or nil,
                        character_id = cid,
                    })
                    if not isElement(c.player) then
                        return
                    end
                    if not res or not res.ok then
                        return toast(c.player, res and res.code or "DB_ERROR")
                    end
                    c.heldItem.data = hands.decodeData(c.heldItem.data)
                    hands.setGear(c.player, "holster", c.heldItem)
                    local swId = res.payload and res.payload.swapped_id
                    if swId then
                        db.one(
                            "SELECT id, type_uname AS uname, hitpoints AS hp, data, holder_kind AS kind "
                                .. "FROM items WHERE id = ?",
                            { swId },
                            function(swRow, c2)
                                if swRow and isElement(c2.player) then
                                    swRow.data = hands.decodeData(swRow.data)
                                    if swRow.kind == "held" then
                                        hands.setHeld(c2.player, swRow)
                                    elseif state.held[c2.player] and state.held[c2.player].id == c.heldItem.id then
                                        hands.setHeld(c2.player, nil)
                                    end
                                end
                            end,
                            { player = c.player }
                        )
                    else
                        hands.setHeld(c.player, nil)
                    end
                    toast(c.player, "EQUIPPED")
                end, { player = pl, heldItem = heldItem })
            end, anim.time, 1, player, item)
            return
        end

        if isCarry(item.uname) then
            return toast(player, "TOO_BIG")
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

    -- how: nil after a change the player made (everyone else viewing their side container is refreshed too),
    -- "opened" when they just opened it (nothing changed for the others), "viewer" for a refresh pushed to a player
    -- who has a container open that someone else changed (the client only updates a list already showing)
    sendInventory = function(player, how)
        local cid = charId(player)
        if not cid then
            return
        end
        db.query(CONTAINERS_SQL, { cid, cid }, function(conts, c)
            if not conts or not isElement(c.player) then
                return
            end
            local payload = {
                inventory = {},
                bag = false,
                trunk = false,
                capacity = { inv = { used = 0, size = 0 }, bag = false, trunk = false },
            }
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
            local tr = activeContainer[c.player]
            if tr and tr.containerId then
                local valid = true
                if tr.vehicle and not isElement(tr.vehicle) then
                    valid = false
                elseif tr.heldItemId then
                    local h = state.held[c.player]
                    valid = h ~= nil and h.id == tr.heldItemId
                elseif tr.pos then
                    local px, py, pz = getElementPosition(c.player)
                    local d = getDistanceBetweenPoints3D(px, py, pz, tr.pos.x, tr.pos.y, tr.pos.z)
                    if d > 4.0 then
                        valid = false
                    end
                end
                if not valid then
                    activeContainer[c.player] = nil
                else
                    payload.trunk = {}
                    payload.capacity.trunk = { used = 0, size = tr.size or 40, uname = tr.title or "Container" }
                    payload.trunkContainerId = tr.containerId
                    payload.containerWorldItemId = not tr.carryable and tr.worldItemId or false
                    byId[tr.containerId] = { rows = payload.trunk, cap = payload.capacity.trunk }
                    ids[#ids + 1] = string.format("%d", tr.containerId)
                end
            end
            local function attachGearAndHeld(p, pl)
                p.gear = {
                    hat = state.hat and state.hat[pl] or false,
                    mask = state.mask and state.mask[pl] or false,
                    armour = state.armour and state.armour[pl] or false,
                    holster = state.holster and state.holster[pl] or false,
                }
                p.held = state.held and state.held[pl] or false
            end
            payload.refresh = c.how == "viewer" or nil
            if #ids == 0 then
                attachGearAndHeld(payload, c.player)
                return triggerClientEvent(c.player, "inventoryOpened", c.player, payload)
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
                local triggered = false
                local expRes = getResourceFromName("explosives")
                local hasExplosives = expRes and getResourceState(expRes) == "running"
                for _, r in ipairs(rows) do
                    local target = byId[r.cid]
                    local itData = hands.decodeData(r.data)
                    if target then
                        target.rows[#target.rows + 1] = {
                            id = r.id,
                            uname = r.uname,
                            hp = r.hp,
                            category = r.category,
                            data = itData,
                        }
                        target.cap.used = target.cap.used + (tonumber(r.isize) or 1)
                    end
                    if
                        hasExplosives
                        and c2.how ~= "viewer"
                        and not triggered
                        and target
                        and target.rows ~= payload.inventory
                    then
                        local rType = itemType(r.uname)
                        if rType and rType.explosive and rType.explosive.trigger == "MOTION" then
                            if itData and itData.armed == 1 then
                                triggered = true
                                exports.explosives:detonateItem(r.id)
                            end
                        end
                    end
                end
                if triggered then
                    return
                end
                attachGearAndHeld(payload, c2.player)
                triggerClientEvent(c2.player, "inventoryOpened", c2.player, payload)
                if not c2.how and payload.trunkContainerId then
                    M.refreshViewers(payload.trunkContainerId, c2.player)
                end
            end, { player = c.player, how = c.how })
        end, { player = player, how = how })
    end
    M.sendInventory = function(player)
        return sendInventory(player)
    end

    -- every other player with containerId open is sent its contents again
    function M.refreshViewers(containerId, except)
        containerId = tonumber(containerId)
        if not containerId then
            return
        end
        for p, cont in pairs(activeContainer) do
            if p ~= except and cont.containerId == containerId and isElement(p) then
                sendInventory(p, "viewer")
            end
        end
    end

    -- the container is gone (picked up, packed, destroyed): whoever had it open is back to their own inventory
    local function closeViewers(matches)
        local closed = {}
        for p, cont in pairs(activeContainer) do
            if matches(cont) then
                activeContainer[p] = nil -- clearing an existing key while traversing is allowed
                closed[#closed + 1] = p
            end
        end
        for _, p in ipairs(closed) do
            if isElement(p) then
                sendInventory(p, "viewer")
            end
        end
    end

    M.closeViewers = function(containerId)
        containerId = tonumber(containerId)
        if containerId then
            closeViewers(function(cont)
                return cont.containerId == containerId
            end)
        end
    end

    -- contents changed outside any viewer's own action (an explosive gone off inside, a workbench emptied by a
    -- craft): everyone viewing it is refreshed once, 100 ms after the last change, not once per item
    local changedSoon = {} -- container id -> timer
    function M.containerChanged(containerId)
        containerId = tonumber(containerId)
        if not containerId then
            return
        end
        if changedSoon[containerId] and isTimer(changedSoon[containerId]) then
            killTimer(changedSoon[containerId])
        end
        changedSoon[containerId] = setTimer(function()
            changedSoon[containerId] = nil
            M.refreshViewers(containerId)
        end, 100, 1)
    end

    -- a vehicle blown up or removed (wreck cleanup, abandoned, respawn): its trunk closes for whoever had it open
    local function closeVehicle()
        if getElementType(source) ~= "vehicle" then
            return
        end
        local veh = source
        closeViewers(function(cont)
            return cont.vehicle == veh
        end)
    end
    addEventHandler("onVehicleExplode", root, closeVehicle)
    addEventHandler("onElementDestroy", root, closeVehicle)

    local function closeWorldItem(itemId)
        itemId = tonumber(itemId)
        if itemId then
            closeViewers(function(cont)
                return cont.worldItemId == itemId
            end)
        end
    end
    addEventHandler("itemMoved", root, function(itemId, from)
        if from == "world" then
            closeWorldItem(itemId)
        end
    end)
    addEventHandler("itemDestroyed", root, closeWorldItem)

    -- the number of players with this vehicle's trunk open (vehicles resource: the lid shuts when none is left)
    function M.trunkViewers(vehicle)
        local n = 0
        for p, cont in pairs(activeContainer) do
            if cont.vehicle == vehicle and isElement(p) then
                n = n + 1
            end
        end
        return n
    end

    function M.openTrunk(player, vehicle, containerId, trunkTitle, trunkSize)
        if isBadInteract(player) then
            return
        end
        activeContainer[player] = {
            vehicle = vehicle,
            containerId = containerId,
            title = trunkTitle,
            size = trunkSize,
        }
        sendInventory(player, "opened")
    end

    function M.closeTrunk(player)
        activeContainer[player] = nil
    end

    -- The Locker shows its open twin while anyone has it open (item/locker.pwn, #143): every client gets
    -- lockerToggled when the first player opens it and when the last one leaves it (the side container closed,
    -- walked off, another one opened), watched twice a second.
    local LOCKER = "Locker"
    local lockerBy = {} -- player -> locker item id they have open
    local lockerOpenBy = {} -- locker item id -> number of players
    local function lockerLeave(player)
        local id = lockerBy[player]
        if not id then
            return
        end
        lockerBy[player] = nil
        lockerOpenBy[id] = (lockerOpenBy[id] or 1) - 1
        if lockerOpenBy[id] <= 0 then
            lockerOpenBy[id] = nil
            triggerClientEvent(root, "lockerToggled", resourceRoot, id, false)
        end
    end
    local function lockerEnter(player, id)
        if lockerBy[player] == id then
            return
        end
        lockerLeave(player)
        lockerBy[player] = id
        lockerOpenBy[id] = (lockerOpenBy[id] or 0) + 1
        if lockerOpenBy[id] == 1 then
            triggerClientEvent(root, "lockerToggled", resourceRoot, id, true)
        end
    end
    setTimer(function()
        for player, id in pairs(lockerBy) do
            local cont = isElement(player) and activeContainer[player]
            if not cont or cont.worldItemId ~= id or M.openContainerId(player) == nil then
                lockerLeave(player)
            end
        end
    end, 500, 0)
    addEventHandler("onPlayerQuit", root, function()
        lockerLeave(source)
    end)

    -- opts (server/machines.lua): kind, size, title and machine (its kind) for a container the type does not describe
    function M.openWorldContainer(player, itemRow, opts)
        if not isElement(player) or not itemRow or isBadInteract(player) then
            return
        end
        local cid = charId(player)
        if not cid then
            return
        end
        local uname = itemRow.uname
        if uname == LOCKER and itemRow.x then
            -- port deviation (#143): the door has to face the player; one already counted in keeps it open
            if lockerBy[player] ~= itemRow.id then
                local px, py = getElementPosition(player)
                local _, _, prz = getElementRotation(player)
                if not small.lockerFacing(itemRow.x, itemRow.y, itemRow.rz, px, py, prz) then
                    return toast(player, "LOCKERFRONT")
                end
            end
            lockerEnter(player, itemRow.id)
        end
        local isTent = (uname == "TentPack")
        local t = itemType(uname)
        local isBag = t and t.category == "bag"
        opts = opts or {}
        local csize = opts.size
            or (isTent and 16 or (t and t.categoryData and (t.categoryData.bag_size or t.categoryData.size) or 8))
        local ckind = opts.kind or (isTent and "tent" or (isBag and "bag" or "safebox"))
        local title = opts.title or (isTent and lang.textFor(player, "Tent") or lang.itemName(uname, player))
        local pos = itemRow.x and itemRow.y and itemRow.z and { x = itemRow.x, y = itemRow.y, z = itemRow.z }
        -- a bag or box is picked up with a hold of the interact key, contents and all (upstream), not from its list
        local carryable = (isBag or (t and t.category == "safebox")) and not opts.machine or false

        db.one(
            "SELECT id, size, kind FROM containers WHERE owner_item_id = ? "
                .. "AND kind IN ('bag', 'safebox', 'tent', 'supply') LIMIT 1",
            { itemRow.id },
            function(cRow, c)
                if not isElement(c.player) then
                    return
                end
                if cRow then
                    activeContainer[c.player] = {
                        containerId = cRow.id,
                        title = c.title,
                        size = cRow.size,
                        worldItemId = c.pos and c.itemRow.id or nil,
                        heldItemId = not c.pos and c.itemRow.id or nil,
                        pos = c.pos,
                        machine = c.machine,
                        carryable = c.carryable,
                    }
                    sendInventory(c.player, "opened")
                else
                    -- two players opening it for the first time at once: the second insert hits
                    -- uq_containers_owner_item and gets the first one's id back instead of failing
                    db.exec(
                        "INSERT INTO containers (kind, size, owner_item_id) VALUES (?, ?, ?) "
                            .. "ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)",
                        { c.ckind, c.csize, c.itemRow.id },
                        function(ok, _, _, insertId)
                            if not isElement(c.player) then
                                return
                            end
                            local newId = ok and tonumber(insertId)
                            if newId then
                                activeContainer[c.player] = {
                                    containerId = newId,
                                    title = c.title,
                                    size = c.csize,
                                    worldItemId = c.pos and c.itemRow.id or nil,
                                    heldItemId = not c.pos and c.itemRow.id or nil,
                                    pos = c.pos,
                                    machine = c.machine,
                                    carryable = c.carryable,
                                }
                                sendInventory(c.player, "opened")
                            end
                        end
                    )
                end
            end,
            {
                player = player,
                title = title,
                ckind = ckind,
                csize = csize,
                itemRow = itemRow,
                pos = pos,
                machine = opts.machine,
                carryable = carryable,
            }
        )
    end

    -- "Open satchel": the bag in hand shows its contents as the side container (upstream itemtype/backpack.pwn
    -- _DisplayBagDialog). Bags on the ground still need hold-to-pick-up and container_put/take access (#108).
    net.handler("itemBagOpenRequested", function(player, worldItemId)
        if worldItemId ~= nil then
            worldItemId = tonumber(worldItemId)
            if not worldItemId or not charId(player) then
                return
            end
            local radius = tonumber(state.settings["items.pickup_radius"]) or 2.0
            db.one(
                "SELECT i.id, i.type_uname AS uname, i.x, i.y, i.z, i.interior, i.dimension "
                    .. "FROM items i JOIN world_items_pos p ON p.item_id = i.id "
                    .. "WHERE i.id = ? AND i.container_id IS NULL AND i.holder_char_id IS NULL "
                    .. "AND i.holder_kind IS NULL AND i.x IS NOT NULL",
                { worldItemId },
                function(row, c)
                    if not isElement(c.player) or not row then
                        return
                    end
                    local t = itemType(row.uname)
                    if not t or (t.category ~= "bag" and t.category ~= "safebox") then
                        return
                    end
                    if
                        (row.interior or 0) ~= getElementInterior(c.player)
                        or (row.dimension or 0) ~= getElementDimension(c.player)
                    then
                        return
                    end
                    local px, py = getElementPosition(c.player)
                    if getDistanceBetweenPoints2D(px, py, row.x, row.y) > radius then
                        return
                    end
                    M.openWorldContainer(c.player, row)
                end,
                { player = player }
            )
            return
        end
        local bag = state.held[player]
        local t = bag and itemType(bag.uname)
        if t and (t.category == "bag" or t.category == "safebox") then
            M.openWorldContainer(player, bag)
        end
    end, { rate = 5 })

    -- A supply crate or weapons cache (loot resource): a container with no item behind it, shown like a trunk
    -- and closed when the player walks more than 4 m from (x, y, z).
    function M.openSupplyContainer(player, containerId, title, size, x, y, z)
        if not isElement(player) or not charId(player) or not tonumber(containerId) then
            return false
        end
        activeContainer[player] = {
            containerId = tonumber(containerId),
            title = title or "Container",
            size = tonumber(size) or 32,
            pos = { x = x, y = y, z = z },
        }
        sendInventory(player, "opened")
        return true
    end

    function M.closeContainer(player)
        activeContainer[player] = nil
    end

    net.handler("containerPickupRequested", function(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        if state.held[player] then
            return toast(player, "HANDS_FULL")
        end
        local cont = activeContainer[player]
        if not cont or cont.worldItemId ~= itemId or not M.openContainerId(player) then
            return
        end
        -- the emptiness check and the delete are one statement: another viewer putting something in at the same
        -- moment either lands first (nothing is deleted) or finds the container gone, never cascaded away with it
        local sql = "DELETE FROM containers WHERE id = ? AND NOT EXISTS (SELECT 1 FROM items WHERE container_id = ?)"
        db.exec(sql, { cont.containerId, cont.containerId }, function(ok, c, affected)
            if not isElement(c.player) then
                return
            end
            if not ok or (tonumber(affected) or 0) == 0 then
                return toast(c.player, "CONTAINER_NOT_EMPTY")
            end
            db.call("item_pickup", { c.itemId, c.cid }, function(res, c2)
                logProc("item.pickedUp", c2.player, res, {
                    item_id = c2.itemId,
                    source = "container",
                    character_id = c2.cid,
                }, true)
                if not isElement(c2.player) then
                    return
                end
                if res and res.ok then
                    if world then
                        world.forgetEverywhere(c2.itemId)
                    end
                    activeContainer[c2.player] = nil
                    db.one(
                        "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
                        { c2.itemId },
                        function(iRow, c3)
                            if iRow and isElement(c3.player) then
                                hands.setHeld(c3.player, {
                                    id = iRow.id,
                                    uname = iRow.uname,
                                    hp = iRow.hp,
                                    data = hands.decodeData(iRow.data),
                                })
                                triggerEvent("itemMoved", c3.player, iRow.id, "world", "held")
                                sendInventory(c3.player)
                            end
                        end,
                        { player = c2.player }
                    )
                    toast(c2.player, "PICKED_UP")
                else
                    toast(c2.player, res and res.code or "DB_ERROR")
                end
            end, { player = c.player, itemId = c.itemId, cid = c.cid })
        end, { player = player, itemId = itemId, cid = cid })
    end, { rate = 3 })

    -- Pitching and packing a TentPack. Reached from hands.lua (interact on the world item while holding a
    -- Hammer or Crowbar) and from the remote events below; both paths re-check the held tool, the distance
    -- and the row before the 3 s hold completes.
    local function pitchTent(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        local held = state.held[player]
        if not held or held.uname ~= "Hammer" then
            return
        end
        local px, py, pz = getElementPosition(player)
        db.one(
            "SELECT id, type_uname AS uname, data, x, y, z FROM items "
                .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
            { itemId },
            function(row, c)
                if not isElement(c.player) or not row or row.uname ~= "TentPack" then
                    return
                end
                local d = getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z)
                if d > 3.0 then
                    return
                end
                local label = lang.textFor(c.player, "Pitching tent")
                triggerClientEvent(c.player, "vehicleHoldStarted", c.player, label, 3000)
                setTimer(function(pl, itId, rx, ry, rz)
                    if not isElement(pl) then
                        return
                    end
                    local curHeld = state.held[pl]
                    if not curHeld or curHeld.uname ~= "Hammer" then
                        return
                    end
                    local curPx, curPy, curPz = getElementPosition(pl)
                    if getDistanceBetweenPoints3D(curPx, curPy, curPz, rx, ry, rz) > 3.5 then
                        return
                    end
                    db.exec("UPDATE items SET data = '{\"pitched\":true}' WHERE id = ?", { itId })
                    db.exec(
                        "INSERT INTO containers (kind, size, owner_item_id) VALUES ('tent', 16, ?) "
                            .. "ON DUPLICATE KEY UPDATE size = 16",
                        { itId }
                    )
                    if world then
                        world.resendEverywhere(itId)
                    end
                    if refreshPlayer then
                        refreshPlayer(pl)
                    end
                    toast(pl, "TENT_PITCHED")
                end, 3000, 1, c.player, row.id, row.x, row.y, row.z)
            end,
            { player = player }
        )
    end

    local function dismantleTent(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        local held = state.held[player]
        if not held or held.uname ~= "Crowbar" then
            return
        end
        local px, py, pz = getElementPosition(player)
        db.one(
            "SELECT i.id, i.type_uname AS uname, i.data, i.x, i.y, i.z, c.id AS cont_id "
                .. "FROM items i LEFT JOIN containers c ON c.owner_item_id = i.id "
                .. "WHERE i.id = ? AND i.container_id IS NULL AND i.holder_char_id IS NULL",
            { itemId },
            function(row, c)
                if not isElement(c.player) or not row or row.uname ~= "TentPack" then
                    return
                end
                local d = getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z)
                if d > 3.0 then
                    return
                end
                local function startDismantle()
                    local label = lang.textFor(c.player, "Packing tent")
                    triggerClientEvent(c.player, "vehicleHoldStarted", c.player, label, 3000)
                    setTimer(function(pl, itId, cId, rx, ry, rz)
                        if not isElement(pl) then
                            return
                        end
                        local curHeld = state.held[pl]
                        if not curHeld or curHeld.uname ~= "Crowbar" then
                            return
                        end
                        local curPx, curPy, curPz = getElementPosition(pl)
                        if getDistanceBetweenPoints3D(curPx, curPy, curPz, rx, ry, rz) > 3.5 then
                            return
                        end
                        -- someone may have opened it or put something in during the hold: the container (whatever
                        -- its id by now) goes only while empty, and a tent that still holds something stays up
                        db.exec(
                            "DELETE FROM containers WHERE owner_item_id = ? "
                                .. "AND NOT EXISTS (SELECT 1 FROM items i WHERE i.container_id = containers.id)",
                            { itId },
                            function(ok)
                                if not ok then
                                    return
                                end
                                db.one("SELECT id FROM containers WHERE owner_item_id = ?", { itId }, function(left, c3)
                                    if left then
                                        return isElement(c3.player) and toast(c3.player, "TENT_NOT_EMPTY")
                                    end
                                    db.exec("UPDATE items SET data = NULL WHERE id = ?", { itId })
                                    closeViewers(function(cont)
                                        return cont.worldItemId == itId or (cId and cont.containerId == cId)
                                    end)
                                    if world then
                                        world.resendEverywhere(itId)
                                    end
                                    if isElement(c3.player) then
                                        if refreshPlayer then
                                            refreshPlayer(c3.player)
                                        end
                                        toast(c3.player, "TENT_PACKED")
                                    end
                                end, { player = pl })
                            end
                        )
                    end, 3000, 1, c.player, row.id, row.cont_id, row.x, row.y, row.z)
                end
                if row.cont_id then
                    db.one(
                        "SELECT COUNT(*) AS cnt FROM items WHERE container_id = ?",
                        { row.cont_id },
                        function(cntRow, c2)
                            if not isElement(c2.player) then
                                return
                            end
                            if cntRow and (cntRow.cnt or 0) > 0 then
                                return toast(c2.player, "TENT_NOT_EMPTY")
                            end
                            startDismantle()
                        end,
                        { player = c.player }
                    )
                else
                    startDismantle()
                end
            end,
            { player = player }
        )
    end

    M.pitchTent, M.dismantleTent = pitchTent, dismantleTent
    net.handler("tentPitchRequested", pitchTent, { rate = 3 })
    net.handler("tentDismantleRequested", dismantleTent, { rate = 3 })

    addEventHandler("onPlayerQuit", root, function()
        activeContainer[source] = nil
    end)

    net.handler("inventoryOpenRequested", function(player)
        if isBadInteract(player) then
            return
        end
        sendInventory(player, "opened")
    end, { rate = 3 })

    -- an item in the character's inventory or worn bag, or in the side container they have open
    local TAKE_REACH_SQL = "SELECT i.id FROM items i JOIN containers c ON c.id = i.container_id "
        .. "LEFT JOIN items owner ON owner.id = c.owner_item_id "
        .. "WHERE i.id = ? AND (c.owner_char_id = ? OR owner.holder_char_id = ? OR i.container_id = ?)"
    local take
    net.handler("itemTakeRequested", function(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId or isBadInteract(player) then
            return
        end
        if state.held[player] then
            return toast(player, "HANDS_FULL")
        end
        local openId = M.openContainerId(player)
        db.one(TAKE_REACH_SQL, { itemId, cid, cid, openId or -1 }, function(reach, c0)
            if not isElement(c0.player) then
                return
            end
            if not reach then
                return toast(c0.player, "NOT_IN_CONTAINER")
            end
            take(c0.player, cid, itemId)
        end, { player = player })
    end, { rate = 5 })

    take = function(player, cid, itemId)
        db.call("container_take", { itemId, cid }, function(res, c)
            if not res or not res.ok then
                logProc("item.taken", c.player, res, { item_id = c.itemId, character_id = cid }, true)
            end
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
                    -- the one event of a successful take waits for the row, which names the item type
                    logProc("item.taken", c2.player, res, {
                        item_id = c2.itemId,
                        uname = row and row.uname or nil,
                        container_id = res.payload and res.payload.container_id or nil,
                        character_id = cid,
                    }, true)
                    if not row or not isElement(c2.player) then
                        return
                    end
                    row.data = hands.decodeData(row.data)
                    hands.setHeld(c2.player, row)
                    triggerEvent("itemMoved", c2.player, c2.itemId, "container", "held")
                    sendInventory(c2.player)
                end,
                { player = c.player, itemId = c.itemId }
            )
        end, { player = player, itemId = itemId })
    end

    net.handler("itemContainerMoveRequested", function(player, itemId, target)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId or (target ~= "bag" and target ~= "trunk" and target ~= "inventory") then
            return
        end
        if isBadInteract(player) then
            return
        end
        local sideContId = M.openContainerId(player)
        local function executeMove(dstContainerId, uname)
            local allowedOpenId = sideContId
            if allowedOpenId and M.openContainerId(player) ~= allowedOpenId then
                allowedOpenId = nil
            end
            db.call("container_move", { itemId, cid, dstContainerId, allowedOpenId, n = 4 }, function(res, c)
                logProc("item.containerMoved", c.player, res, {
                    item_id = itemId,
                    uname = uname,
                    container_id = dstContainerId,
                    from_container_id = res and res.ok and res.payload and res.payload.from_container_id or nil,
                    direction = target,
                    character_id = cid,
                })
                if not isElement(c.player) then
                    return
                end
                if not res or not res.ok then
                    return toast(c.player, res and res.code or "DB_ERROR")
                end
                sendInventory(c.player)
            end, { player = player })
        end

        if target == "bag" or target == "inventory" then
            return db.one("SELECT type_uname AS uname FROM items WHERE id = ?", { itemId }, function(r, c)
                if not isElement(c.player) or not r then
                    return
                end
                if isCarry(r.uname) then
                    return toast(c.player, "TOO_BIG")
                end
                if target == "inventory" then
                    local inv = exports.character:getInventoryContainerId(c.player)
                    return inv and executeMove(inv, r.uname)
                end
                wornBag(cid, function(bag, c2)
                    if not isElement(c2.player) or not bag then
                        return
                    end
                    executeMove(bag.id, r.uname)
                end, { player = c.player })
            end, { player = player })
        end
        if target == "trunk" then
            if not sideContId then
                return
            end
            local cont = activeContainer[player]
            if cont and cont.machine then
                return db.one("SELECT type_uname AS uname, data FROM items WHERE id = ?", { itemId }, function(r, c)
                    if not isElement(c.player) or not r then
                        return
                    end
                    if machineAccepts(c.player, sideContId, r.uname, hands.decodeData(r.data)) then
                        executeMove(sideContId, r.uname)
                    end
                end, { player = player })
            end
            executeMove(sideContId)
        end
    end, { rate = 5 })

    -- wears an item (inventory Wear action; F with it held, items use.lua); swaps what the slot holds
    function M.wear(player, itemId)
        local cid = charId(player)
        itemId = tonumber(itemId)
        if not cid or not itemId then
            return
        end
        local openContainerId = M.openContainerId(player)
        db.one(
            "SELECT id, type_uname AS uname, hitpoints AS hp, data, container_id FROM items WHERE id = ?",
            { itemId },
            function(row, c)
                if not row or not isElement(c.player) then
                    return
                end
                local cl = clothesRef or ctx.clothes
                if row.uname == "Clothes" and cl then
                    local allowedOpenContainerId = c.openContainerId
                    if allowedOpenContainerId and M.openContainerId(c.player) ~= allowedOpenContainerId then
                        allowedOpenContainerId = nil
                    end
                    local fromHand = state.held[c.player] and state.held[c.player].id == row.id or false
                    return cl.use(c.player, row.id, hands.decodeData(row.data), fromHand, allowedOpenContainerId)
                end
                local slot = apparel and apparel.slotFor(row.uname)
                if not slot then
                    return toast(c.player, "NOT_WEARABLE")
                end
                local allowedOpenContainerId = c.openContainerId
                if allowedOpenContainerId and M.openContainerId(c.player) ~= allowedOpenContainerId then
                    allowedOpenContainerId = nil
                end
                local curHeld = state.held[c.player]
                if curHeld and curHeld.id == c.itemId then
                    if curHeld.data and hands.queueData then
                        hands.queueData(curHeld)
                    end
                    if hands.flushData then
                        hands.flushData(c.itemId)
                    end
                end
                db.call("item_wear", { c.itemId, c.cid, slot, allowedOpenContainerId, n = 4 }, function(res, c2)
                    logProc("item.worn", c2.player, res, {
                        item_id = c2.row.id,
                        uname = c2.row.uname,
                        slot = slot,
                        swapped_id = res and res.ok and res.payload and res.payload.swapped_id or nil,
                        character_id = c.cid,
                    })
                    if not isElement(c2.player) then
                        return
                    end
                    if not res or not res.ok then
                        return toast(c2.player, res and res.code or "DB_ERROR")
                    end
                    c2.row.data = hands.decodeData(c2.row.data)
                    hands.setGear(c2.player, slot, c2.row)
                    local swId = res.payload and res.payload.swapped_id
                    if swId then
                        db.one(
                            "SELECT id, type_uname AS uname, hitpoints AS hp, data, holder_kind AS kind "
                                .. "FROM items WHERE id = ?",
                            { swId },
                            function(swRow, c3)
                                if swRow and isElement(c3.player) then
                                    swRow.data = hands.decodeData(swRow.data)
                                    if swRow.kind == "held" then
                                        hands.setHeld(c3.player, swRow)
                                    elseif state.held[c3.player] and state.held[c3.player].id == c2.row.id then
                                        hands.setHeld(c3.player, nil)
                                    end
                                end
                                sendInventory(c2.player)
                            end,
                            { player = c2.player }
                        )
                    else
                        if state.held[c2.player] and state.held[c2.player].id == c2.row.id then
                            hands.setHeld(c2.player, nil)
                        end
                        sendInventory(c2.player)
                    end
                    toast(c2.player, "EQUIPPED")
                end, { player = c.player, row = row })
            end,
            { player = player, itemId = itemId, cid = cid, openContainerId = openContainerId }
        )
    end

    net.handler("itemWearRequested", M.wear, { rate = 5 })

    net.handler("itemUnwearRequested", function(player, slot)
        local cid = charId(player)
        if not cid or not slot or type(slot) ~= "string" then
            return
        end
        local worn = state[slot] and state[slot][player]
        if type(worn) ~= "table" then
            worn = nil -- the slot name is the client's: state.lastHolster holds ticks, not items
        end
        db.call("item_unwear", { cid, slot }, function(res, c)
            logProc("item.unworn", c.player, res, {
                item_id = res and res.ok and res.payload and res.payload.item_id or nil,
                uname = worn and worn.uname,
                slot = slot,
                destination = res and res.ok and res.payload and res.payload.destination or nil,
                character_id = cid,
            })
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            hands.setGear(c.player, slot, nil)
            local itId = res.payload and res.payload.item_id
            local dest = res.payload and res.payload.destination
            if dest == "held" and itId then
                db.one(
                    "SELECT id, type_uname AS uname, hitpoints AS hp, data FROM items WHERE id = ?",
                    { itId },
                    function(itRow, c2)
                        if itRow and isElement(c2.player) then
                            itRow.data = hands.decodeData(itRow.data)
                            hands.setHeld(c2.player, itRow)
                        end
                        sendInventory(c.player)
                    end,
                    { player = c.player }
                )
            else
                sendInventory(c.player)
            end
            toast(c.player, "REMOVED")
        end, { player = player })
    end, { rate = 5 })

    return M
end
