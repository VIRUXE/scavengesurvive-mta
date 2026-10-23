-- Hands and the worn bag: what a player carries is published as protected element data ("items.held" /
-- "items.bag" = type uname or false; "items.ammo" = loaded ammoItem uname or false); every client draws
-- its own bone-attached objects and bullet tracers from it (client/attach.lua, weapons/client/tracer.lua).
-- ctx = { db, net, state, geometry, ammo, type, defaultAmmo, charId, toast, world } built by server/main.lua;
-- state.held / state.worn are shared with it. Busted loads this file with fake deps.
return function(ctx)
    local db, net, state, geometry, world = ctx.db, ctx.net, ctx.state, ctx.geometry, ctx.world
    local ammo = ctx.ammo
    local itemType, defaultAmmo, charId, toast = ctx.type, ctx.defaultAmmo, ctx.charId, ctx.toast
    local isIncapacitated = ctx.isIncapacitated
    local isKnockedOut, isPlayerCuffed, setPlayerCuffed = ctx.isKnockedOut, ctx.isPlayerCuffed, ctx.setPlayerCuffed
    local VANILLA_MELEE_MAX = 15
    local RELOAD_COOLDOWN_MS = 1000
    local lastReload = {}
    local containers = nil
    local M = {}

    function M.setContainers(c)
        containers = c
    end

    local function baseWeapon(t)
        local w = t and t.category == "weapon" and t.categoryData and t.categoryData.baseWeapon
        return w and w > 0 and w or nil
    end

    local function defAmmoFor(t)
        if defaultAmmo and t and t.categoryData and t.categoryData.calibre then
            return defaultAmmo(t.categoryData.calibre)
        end
        return nil
    end

    -- A firearm with explicit data.mag uses that count (0 when unloaded); without data.mag it defaults
    -- to a full magazine (backwards compatibility for /additem and legacy items). Vanilla melee ids always get 1.
    local function ammoFor(t, data)
        if data and data.mag ~= nil then
            return math.max(0, math.floor(tonumber(data.mag) or 0))
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

    local function publishAmmo(player, item)
        if isElement(player) then
            local loaded = item and item.data and item.data.ammoItem or false
            setElementData(player, "items.ammo", loaded, "broadcast", "deny")
        end
    end

    -- item = { id, uname, hp, data } or nil: the bag worn on the back
    function M.setWorn(player, item)
        state.worn[player] = item
        publish(player, "items.bag", item)
    end

    function M.setGear(player, slot, item)
        if slot == "bag" then
            return M.setWorn(player, item)
        end
        if state[slot] then
            state[slot][player] = item
            publish(player, "items." .. slot, item)
        end
    end

    function M.clearGear(player)
        local gearSlots = { "hat", "mask", "armour", "holster" }
        for _, slot in ipairs(gearSlots) do
            if state[slot] then
                state[slot][player] = nil
                publish(player, "items." .. slot, nil)
            end
        end
    end

    function M.clearHeld(player)
        publish(player, "items.held", nil)
        publishAmmo(player, nil)
        local item = state.held[player]
        if item and isElement(player) then
            local w = baseWeapon(itemType(item.uname))
            if w then
                takeWeapon(player, w)
            end
        end
        state.held[player] = nil
    end

    -- item = { id, uname, hp, data } or nil; client receives { id, uname, hp, data }
    function M.setHeld(player, item)
        M.clearHeld(player)
        if not isElement(player) then
            return
        end
        if item then
            local t = itemType(item.uname)
            if ammo and ammo.isCalibreWeapon(t) then
                local defA = defAmmoFor(t)
                local ws = ammo.weaponState(t, item.data, defA)
                if ws.mag == 0 and ws.reserve > 0 then
                    local _, reloaded = ammo.reload(t, ws, defA)
                    ws = reloaded
                end
                item.data = ws
            end
            state.held[player] = item
            publish(player, "items.held", item)
            publishAmmo(player, item)
            local w = baseWeapon(t)
            if w then
                local rounds = ammoFor(t, item.data)
                if rounds > 0 then
                    giveWeapon(player, w, rounds, true)
                    if setWeaponAmmo then
                        setWeaponAmmo(player, w, rounds, rounds)
                    end
                else
                    takeWeapon(player, w)
                    toast(player, "WEAPNOAMMOL")
                end
            end
        end
        triggerClientEvent(
            player,
            "onClientItemsHeld",
            player,
            item and { id = item.id, uname = item.uname, hp = item.hp, data = item.data } or false
        )
    end

    local function syncHeldData(player, item, nextData)
        item.data = nextData
        publishAmmo(player, item)
        if ammo then
            db.exec("UPDATE items SET data = ? WHERE id = ?", { ammo.encodeData(nextData), item.id })
        end
        local t = itemType(item.uname)
        local w = baseWeapon(t)
        if w and isElement(player) then
            local rounds = ammoFor(t, nextData)
            if rounds > 0 then
                giveWeapon(player, w, rounds, true)
                if setWeaponAmmo then
                    setWeaponAmmo(player, w, rounds, rounds)
                end
            else
                takeWeapon(player, w)
                toast(player, "WEAPNOAMMOL")
            end
        end
        if isElement(player) then
            triggerClientEvent(
                player,
                "onClientItemsHeld",
                player,
                { id = item.id, uname = item.uname, hp = item.hp, data = item.data }
            )
        end
    end

    -- Restores the held item and the worn bag from the DB (spawn and resource restart).
    function M.rebuildCarried(player)
        local cid = charId(player)
        if not cid then
            return
        end
        db.query(
            "SELECT id, type_uname AS uname, hitpoints AS hp, data, holder_kind AS kind FROM items "
                .. "WHERE holder_char_id = ? AND holder_kind IN ('held', 'bag', 'hat', 'mask', 'armour', 'holster')",
            { cid },
            function(rows, c)
                if not isElement(c.player) or rows == false then
                    return
                end
                local held, bag
                local gear = { hat = nil, mask = nil, armour = nil, holster = nil }
                local isGear = { hat = true, mask = true, armour = true, holster = true }
                for _, row in ipairs(rows) do
                    row.data = decodeData(row.data)
                    if row.kind == "bag" then
                        bag = row
                    elseif row.kind == "held" then
                        held = row
                    elseif isGear[row.kind] then
                        gear[row.kind] = row
                    end
                end
                M.setHeld(c.player, held)
                M.setWorn(c.player, bag)
                for slot, item in pairs(gear) do
                    M.setGear(c.player, slot, item)
                end
            end,
            { player = player }
        )
    end

    addEventHandler("onPlayerWeaponFire", root, function()
        if not ammo then
            return
        end
        local item = state.held[source]
        if not item then
            return
        end
        local t = itemType(item.uname)
        if not ammo.isCalibreWeapon(t) then
            return
        end
        local ok, nextData, autoReloaded = ammo.fire(t, item.data, defAmmoFor(t))
        if not ok then
            return
        end
        if autoReloaded and setPedAnimation then
            setPedAnimation(source, "COLT45", "colt45_reload", -1, false, false, false, false)
        end
        syncHeldData(source, item, nextData)
    end)

    net.handler("onItemsRequestReload", function(player)
        if not ammo or (isIncapacitated and isIncapacitated(player)) then
            return
        end
        local item = state.held[player]
        if not item then
            return
        end
        local now = getTickCount()
        if lastReload[player] and now - lastReload[player] < RELOAD_COOLDOWN_MS then
            return
        end
        local t = itemType(item.uname)
        if not ammo.isCalibreWeapon(t) then
            return
        end
        local ok, nextData = ammo.reload(t, item.data, defAmmoFor(t))
        if not ok then
            return
        end
        lastReload[player] = now
        if setPedAnimation then
            setPedAnimation(player, "COLT45", "colt45_reload", -1, false, false, false, false)
        end
        syncHeldData(player, item, nextData)
    end, { rate = 3 })

    net.handler("onItemsRequestUnload", function(player)
        if not ammo or (isIncapacitated and isIncapacitated(player)) then
            return
        end
        local cid, item = charId(player), state.held[player]
        if not cid or not item then
            return
        end
        local t = itemType(item.uname)
        if not ammo.isCalibreWeapon(t) then
            return
        end
        local ok, unloadedState, spawned = ammo.unload(t, item.data, defAmmoFor(t))
        if not ok then
            return toast(player, unloadedState)
        end
        local x, y, z = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        local dx, dy = geometry.dropPosition(x, y, rz, 0.5)
        local params = {
            cid,
            item.id,
            ammo.encodeData(unloadedState),
            spawned.uname,
            ammo.encodeData(spawned.data),
            dx,
            dy,
            z - 0.9,
            rz,
            getElementInterior(player),
            getElementDimension(player),
        }
        db.call("weapon_unload", params, function(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            local cur = state.held[c.player]
            if cur and cur.id == c.itemId then
                syncHeldData(c.player, cur, c.unloadedState)
            end
            if setPedAnimation then
                setPedAnimation(c.player, "COLT45", "colt45_reload", -1, false, false, false, false)
            end
            world.syncPlayer(c.player)
            if res.payload and res.payload.ammo_item_id then
                triggerEvent("onItemCreated", resourceRoot, res.payload.ammo_item_id)
            end
        end, { player = player, itemId = item.id, unloadedState = unloadedState })
    end, { rate = 3 })

    local function tryTransferFromWorld(player, cid, held, heldType, row)
        local worldType = itemType(row.uname)
        if not ammo or (not ammo.isCalibreWeapon(worldType) and not ammo.isAmmoItem(worldType)) then
            return toast(player, "HANDS_FULL")
        end
        local worldData = decodeData(row.data)
        local defA = defAmmoFor(heldType) or defAmmoFor(worldType)
        local ok, code, nextHeld, nextWorld, moved, delWorld, delHeld =
            ammo.interactTransfer(heldType, held.data, worldType, worldData, defA)
        if not ok then
            return toast(player, code)
        end
        if moved <= 0 then
            return toast(player, "HANDS_FULL")
        end
        local params = {
            cid,
            held.id,
            row.id,
            ammo.encodeData(nextHeld),
            ammo.encodeData(nextWorld),
            delWorld and 1 or 0,
            delHeld and 1 or 0,
        }
        db.call("item_transfer_world", params, function(res, c)
            if res and res.ok then
                world.forgetEverywhere(c.worldId)
                if c.delWorld then
                    triggerEvent("onItemDestroyed", resourceRoot, c.worldId)
                end
            end
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            if c.delHeld then
                M.setHeld(c.player, nil)
                triggerEvent("onItemDestroyed", resourceRoot, c.held.id)
            else
                M.setHeld(c.player, { id = c.held.id, uname = c.held.uname, hp = c.held.hp, data = c.nextHeld })
            end
            if not c.delWorld then
                world.syncPlayer(c.player)
            end
            if setPedAnimation then
                setPedAnimation(c.player, "COLT45", "colt45_reload", -1, false, false, false, false)
            end
            toast(c.player, string.format("AMTRANS:%d", c.moved))
        end, {
            player = player,
            held = held,
            worldId = row.id,
            nextHeld = nextHeld,
            delWorld = delWorld,
            delHeld = delHeld,
            moved = moved,
        })
    end

    local function findNearbyPlayer(player, maxDist)
        if not getElementsByType or not getDistanceBetweenPoints3D then
            return nil
        end
        local px, py, pz = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        local best, bestDist = nil, maxDist
        for _, p in ipairs(getElementsByType("player")) do
            if
                p ~= player
                and charId(p)
                and not isPedDead(p)
                and getElementInterior(p) == int
                and getElementDimension(p) == dim
            then
                local tx, ty, tz = getElementPosition(p)
                local d = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
                if d <= bestDist then
                    best, bestDist = p, d
                end
            end
        end
        return best
    end

    local function tryPlayerInteraction(player, cid, held)
        local target = findNearbyPlayer(player, 2.0)
        if not target then
            return false
        end
        if
            held
            and held.uname == "HandCuffs"
            and ctx.destroy
            and setPlayerCuffed
            and isPlayerCuffed
            and not isPlayerCuffed(target)
            and not state.held[target]
        then
            ctx.destroy(held.id, player, function(ok)
                if ok and isElement(target) then
                    setPlayerCuffed(target, true)
                    if isElement(player) then
                        toast(player, "CUFFED")
                    end
                end
            end)
            return true
        end
        if not held and isPlayerCuffed and setPlayerCuffed and isPlayerCuffed(target) then
            db.call("item_create_held", { "HandCuffs", cid }, function(res, c)
                if not isElement(c.player) or not res or not res.ok then
                    return
                end
                if isElement(c.target) then
                    setPlayerCuffed(c.target, false)
                end
                M.setHeld(c.player, { id = res.payload.item_id, uname = "HandCuffs", hp = 5, data = {} })
                triggerEvent("onItemCreated", resourceRoot, res.payload.item_id)
                toast(c.player, "UNCUFFED")
            end, { player = player, target = target })
            return true
        end
        if not held and isKnockedOut and isKnockedOut(target) and state.held[target] then
            local tItem = state.held[target]
            local tCid = charId(target)
            if tCid then
                db.call("item_disarm", { cid, tCid, tItem.id }, function(res, c)
                    if not isElement(c.player) or not res or not res.ok then
                        return
                    end
                    if isElement(c.target) and state.held[c.target] and state.held[c.target].id == c.item.id then
                        M.setHeld(c.target, nil)
                    end
                    M.setHeld(c.player, c.item)
                    triggerEvent("onItemMoved", c.player, c.item.id, "held", "held")
                    toast(c.player, "DISARMED")
                end, { player = player, target = target, item = tItem })
                return true
            end
        end
        return false
    end

    net.handler("onItemsRequestPickup", function(player)
        local cid = charId(player)
        if not cid or (isIncapacitated and isIncapacitated(player)) then
            return
        end
        local held = state.held[player]
        if tryPlayerInteraction(player, cid, held) then
            return
        end
        local x, y = getElementPosition(player)
        local r = tonumber(state.settings["items.pickup_radius"]) or 2.0
        local sql = world.findNearestSql(x, y, r, getElementInterior(player), getElementDimension(player))
        db.one(sql, {}, function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local curHeld = state.held[c.player]
            local curUname = curHeld and curHeld.uname
            local rData = decodeData(row.data)

            -- TentPack interactions
            if row.uname == "TentPack" then
                local isPitched = (rData and (rData.pitched == true or (rData[1] and rData[1].pitched == true)))
                if isPitched then
                    if curUname == "Crowbar" then
                        return triggerEvent("onItemsRequestDismantleTent", c.player, row.id)
                    else
                        return containers and containers.openWorldContainer(c.player, row)
                    end
                else
                    if curUname == "Hammer" then
                        return triggerEvent("onItemsRequestPitchTent", c.player, row.id)
                    end
                end
            end

            -- Safebox world containers
            local t = itemType(row.uname)
            if t and t.category == "safebox" then
                return containers and containers.openWorldContainer(c.player, row)
            end

            -- Defences
            local isDefence = (
                row.uname == "Door"
                or row.uname == "MetalGate"
                or row.uname == "CrateDoor"
                or row.uname == "LargeFrame"
            )
            if isDefence and curUname ~= "Crowbar" then
                local bRes = getResourceFromName("building")
                if bRes and getResourceState(bRes) == "running" then
                    return exports.building:interactDefence(c.player, row)
                end
            end

            local curType = curHeld and itemType(curHeld.uname) or nil
            if curHeld and (not ammo or (not ammo.isCalibreWeapon(curType) and not ammo.isAmmoItem(curType))) then
                return toast(c.player, "HANDS_FULL")
            end

            if curHeld then
                return tryTransferFromWorld(c.player, c.charId, curHeld, curType, row)
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
        if not cid or (isIncapacitated and isIncapacitated(player)) then
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
