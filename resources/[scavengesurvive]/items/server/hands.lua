-- Hands and the worn bag: what a player carries is published as protected element data ("items.held" /
-- "items.bag" = type uname or false; "items.ammo" = loaded ammoItem uname or false); every client draws
-- its own bone-attached objects and bullet tracers from it (client/attach.lua, weapons/client/tracer.lua).
-- ctx = { db, net, state, geometry, ammo, type, defaultAmmo, charId, toast, world } built by server/main.lua;
-- state.held / state.worn are shared with it. Busted loads this file with fake deps.
return function(ctx)
    local db, net, state, geometry, world = ctx.db, ctx.net, ctx.state, ctx.geometry, ctx.world
    local ammo, liquids = ctx.ammo, ctx.liquids
    local itemType, defaultAmmo, charId, toast = ctx.type, ctx.defaultAmmo, ctx.charId, ctx.toast
    local isIncapacitated = ctx.isIncapacitated
    local isBadInteract = ctx.isBadInteract or function()
        return false
    end
    local isKnockedOut = ctx.isKnockedOut
    local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
    local VANILLA_MELEE_MAX = 15
    local RELOAD_COOLDOWN_MS = 1000
    local GIVE_REACH = 1.5 -- metres to the player an item can be handed to
    local lastReload = {}
    local containers, cooking, small, machinesSrv, furnitureSrv, cuffsSrv = nil, nil, nil, nil, nil, nil
    local parachuteSrv = nil
    local M = {}

    -- one event per procedure callback: ok and code come from the db.call result (res == false: the query failed)
    local function logProc(kind, player, res, fields)
        fields.player = player
        fields.ok = res and res.ok or false
        fields.code = res and res.code or "DB_ERROR"
        log.event(kind, fields)
    end

    -- the player's position as the log's pos fields (x y z int dim), when the player is still there
    local function atPlayer(player, fields)
        if isElement(player) then
            local x, y, z = getElementPosition(player)
            fields.x, fields.y, fields.z = math.floor(x), math.floor(y), math.floor(z)
            fields.int, fields.dim = getElementInterior(player), getElementDimension(player)
        end
        return fields
    end

    function M.setContainers(c)
        containers = c
    end

    function M.setCooking(c)
        cooking = c
    end

    -- server/smallitems.lua: held-with-world pairs (Locator + phone, Stun Gun + Tool Battery, can + bottle), dice drops
    function M.setMachines(m)
        machinesSrv = m
    end

    -- server/cuffs.lua: the 3 s handcuffing hold
    function M.setCuffs(c)
        cuffsSrv = c
    end

    function M.setSmall(s)
        small = s
    end

    -- server/parachute.lua: the worn Parachute is GTA's parachute weapon
    function M.setParachute(p)
        parachuteSrv = p
    end

    -- server/furniture.lua (#148): items put on desks and tables or shown in a gun case, the furniture never picked up
    function M.setFurniture(f)
        furnitureSrv = f
    end

    -- server/vending.lua: the snack machines, opened once their glass is broken and never picked up
    local vendingSrv
    function M.setVending(v)
        vendingSrv = v
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
        if ammo and ammo.isLiquidWeapon(t) then -- Chainsaw, Flamer: only the petrol put in runs them
            return ammo.fuelUnits(data)
        end
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
        if not data or data == "" or data == false then
            return {}
        end
        if type(data) == "table" then
            return data
        end
        if type(data) == "string" then
            local t = fromJSON(data)
            return type(t) == "table" and t or {}
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
    M.publishAmmo = publishAmmo

    -- item = { id, uname, hp, data } or nil: the bag worn on the back
    function M.setWorn(player, item)
        state.worn[player] = item
        publish(player, "items.bag", item)
    end

    function M.setGear(player, slot, item)
        if slot == "bag" then
            return M.setWorn(player, item)
        end
        if slot == "parachute" then
            state.parachute[player] = item
            return parachuteSrv and parachuteSrv.apply(player, item)
        end
        if state[slot] then
            if slot == "armour" and item and ctx.armour.ensure(item, math.random) then
                M.queueData(item)
            end
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
        M.setGear(player, "parachute", nil)
    end

    -- Ammo changes on every shot: the latest data of each held item waits here and reaches the DB in one
    -- item_data_flush call (main.lua's timer), or at once when the item leaves the hand, so whoever next loads
    -- it reads the rounds that are left.
    local pendingData = {} -- item id -> encoded data

    -- a weapon's or ammo's data in its fixed form, anything else (a Petrol Can's amount) as MTA JSON
    local function encodeData(data)
        local encoded = ammo and ammo.encodeData(data)
        if encoded or type(data) ~= "table" or next(data) == nil then
            return encoded
        end
        return toJSON(data, true)
    end

    function M.queueData(item)
        pendingData[item.id] = encodeData(item.data)
    end

    -- itemId nil = every pending item; wait = block until written (resource stop)
    function M.flushData(itemId, wait)
        local rows = {}
        for id, data in pairs(pendingData) do
            if not itemId or id == itemId then
                rows[#rows + 1] = { id = id, data = data }
                pendingData[id] = nil
            end
        end
        if #rows == 0 then
            return
        end
        if wait then
            return dbPoll(dbQuery(db.conn, "CALL item_data_flush(?)", toJSON(rows)), -1)
        end
        db.call("item_data_flush", { toJSON(rows) }, function(res, sent)
            if res and res.ok then
                return
            end
            outputDebugString("[items] item_data_flush failed: " .. tostring(res and res.code or "db"), 1)
            log.event("weapon.ammoFlushFailed", { count = #sent, code = res and res.code or "DB_ERROR" }, "warn")
            -- the batch waits for the next flush unless newer data for the item arrived meanwhile
            for _, r in ipairs(sent) do
                if pendingData[r.id] == nil then
                    pendingData[r.id] = r.data
                end
            end
        end, rows)
    end

    -- a procedure about to write the item's data itself supersedes what is waiting
    local function dropPendingData(itemId)
        pendingData[itemId] = nil
    end

    -- ...and when it fails the item's data in hand is still the latest, so it waits again
    local function requeueHeld(player, itemId)
        local cur = state.held[player]
        if cur and cur.id == itemId then
            M.queueData(cur)
        end
    end

    -- Bending animation for pickup and drop (#121). In MTA setPedAnimation runs as a primary task and blocks WASD
    -- (issue #3915), so only timed animations are played here; the carry pose held while walking is a bone pose each
    -- client applies (client/attach.lua, shared/logic/carry.lua). Two-handed types (useCarryAnim) lift and put down
    -- with upstream's CARRY animations (SIF item.inc PlayerPickUpItem / PlayerDropItem).
    local CARRY_LIFT_MS = 400
    local function anim(player, ...)
        if setPedAnimation and isElement(player) then
            setPedAnimation(player, ...)
        end
    end
    local function isCarried(uname)
        local t = itemType(uname)
        return t ~= nil and t.useCarryAnim == true
    end
    -- itemZ: where the item lay; one at waist height (a table) is lifted with liftup105, one on the floor with liftup
    function M.pickupAnim(player, uname, itemZ)
        if not isCarried(uname) then
            return anim(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
        end
        local _, _, pz = getElementPosition(player)
        local name = (itemZ == nil or pz - itemZ < 0.3) and "liftup105" or "liftup"
        anim(player, "CARRY", name, CARRY_LIFT_MS, false, false, true, false)
    end
    function M.dropAnim(player, uname)
        if isCarried(uname) then
            return anim(player, "CARRY", "putdwn", CARRY_LIFT_MS, false, false, true, false)
        end
        anim(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
    end

    function M.clearHeld(player)
        publish(player, "items.held", nil)
        publishAmmo(player, nil)
        local item = state.held[player]
        if item then
            if item.data then
                M.queueData(item)
            end
            M.flushData(item.id)
        end
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
            "heldItemChanged",
            player,
            item and { id = item.id, uname = item.uname, hp = item.hp, data = item.data } or false
        )
    end

    local function syncHeldData(player, item, nextData)
        item.data = nextData
        publishAmmo(player, item)
        M.queueData(item)
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
                "heldItemChanged",
                player,
                { id = item.id, uname = item.uname, hp = item.hp, data = item.data }
            )
        end
    end

    M.syncHeldData = syncHeldData

    -- Restores the held item and the worn bag from the DB (spawn and resource restart).
    function M.rebuildCarried(player)
        local cid = charId(player)
        if not cid then
            return
        end
        db.query(
            "SELECT id, type_uname AS uname, hitpoints AS hp, data, holder_kind AS kind FROM items "
                .. "WHERE holder_char_id = ? AND holder_kind IS NOT NULL",
            { cid },
            function(rows, c)
                if not isElement(c.player) or rows == false then
                    return
                end
                local held, bag
                local gear = { hat = nil, mask = nil, armour = nil, holster = nil, parachute = nil }
                local isGear = { hat = true, mask = true, armour = true, holster = true, parachute = true }
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

    -- The hand in memory and the row in the database disagree (a callback that never ran, a restart mid-move): the
    -- database is right. A refusal that only makes sense the other way round (HANDS_FULL with nothing in the hand,
    -- NOT_HELD with an item in it) reloads the hand and the gear from the rows, at most once a second per player.
    local lastResync = {}
    function M.resyncIf(player, code)
        if not isElement(player) or not charId(player) then
            return false
        end
        local held = state.held[player] ~= nil
        if not ((code == "HANDS_FULL" and not held) or (code == "NOT_HELD" and held)) then
            return false
        end
        local now = getTickCount()
        if lastResync[player] and now - lastResync[player] < 1000 then
            return false
        end
        lastResync[player] = now
        log.event("item.handResynced", { player = player, code = code, held = held }, "warn")
        M.rebuildCarried(player)
        return true
    end

    addEventHandler("onPlayerQuit", root, function()
        lastResync[source] = nil
    end)

    addEventHandler("onPlayerWeaponFire", root, function()
        if not ammo then
            return
        end
        local item = state.held[source]
        if not item then
            return
        end
        local t = itemType(item.uname)
        if ammo.isLiquidWeapon(t) then
            local left = ammo.fuelUnits(item.data) - 1
            if left > 0 then -- the running count only waits for the next flush; the last unit takes the weapon away
                item.data = { mag = left, reserve = 0 }
                M.queueData(item)
                return
            end
            return syncHeldData(source, item, { mag = 0, reserve = 0 })
        end
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

    net.handler("itemReloadRequested", function(player)
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

    net.handler("itemUnloadRequested", function(player)
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
        dropPendingData(item.id)
        db.call("weapon_unload", params, function(res, c)
            logProc("weapon.unloaded", c.player, res, {
                item_id = c.itemId,
                uname = c.uname,
                rounds = c.rounds,
                ammo_uname = c.ammoUname,
                ammo_item_id = res and res.ok and res.payload and res.payload.ammo_item_id or nil,
                character_id = cid,
            })
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                requeueHeld(c.player, c.itemId)
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
                triggerEvent("itemCreated", resourceRoot, res.payload.ammo_item_id)
            end
        end, {
            player = player,
            itemId = item.id,
            uname = item.uname,
            rounds = spawned.data.rounds,
            ammoUname = spawned.uname,
            unloadedState = unloadedState,
        })
    end, { rate = 3 })

    -- a liquid weapon in hand and a Petrol Can on the ground: a litre a press into the weapon (weapon/interact.pwn)
    local function refuelWeaponFromCan(player, held, heldType, row)
        local rowType = itemType(row.uname)
        local amount, liquid = liquids.decode(rowType, decodeData(row.data))
        if liquid ~= heldType.categoryData.liquid then
            return toast(player, "EMPTY")
        end
        local ok, code, nextData, canLeft = ammo.refuel(heldType, held.data, amount)
        if not ok then
            return toast(player, code)
        end
        local canData = toJSON({ amount = canLeft, liquid = liquid }, true)
        local sql = "UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL AND IFNULL(data, '') = ?"
        local was = (row.data and row.data ~= false) and row.data or ""
        db.exec(sql, { canData, row.id, was }, function(done, _, affected)
            if not done or tonumber(affected) ~= 1 or not isElement(player) then
                return
            end
            world.resendEverywhere(row.id)
            local cur = state.held[player]
            if cur and cur.id == held.id then
                syncHeldData(player, cur, nextData)
            end
            if setPedAnimation then
                setPedAnimation(player, "BOMBER", "BOM_Plant_In", -1, false, false, false, false)
            end
        end)
    end

    -- anticheat's hacker traps veto the pickup of the item they planted (cancels itemPickupAttempted)
    local function pickupVetoed(player, itemId)
        triggerEvent("itemPickupAttempted", player, itemId)
        return wasEventCancelled()
    end

    local function tryTransferFromWorld(player, cid, held, heldType, row)
        if pickupVetoed(player, row.id) then
            return
        end
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
        dropPendingData(held.id)
        db.call("item_transfer_world", params, function(res, c)
            logProc("item.transferred", c.player, res, {
                item_id = c.held.id,
                uname = c.held.uname,
                world_item_id = c.worldId,
                world_uname = c.worldUname,
                moved = c.moved,
                held_deleted = c.delHeld,
                world_deleted = c.delWorld,
                character_id = cid,
            })
            if res and res.ok then
                world.forgetEverywhere(c.worldId)
                if c.delWorld then
                    triggerEvent("itemDestroyed", resourceRoot, c.worldId)
                end
            end
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                requeueHeld(c.player, c.held.id)
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            if c.delHeld then
                M.setHeld(c.player, nil)
                triggerEvent("itemDestroyed", resourceRoot, c.held.id)
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
            worldUname = row.uname,
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
        if cuffsSrv and cuffsSrv.tryStart(player, held, target) then
            return true
        end
        if not held and isKnockedOut and isKnockedOut(target) and state.held[target] then
            local tItem = state.held[target]
            local tCid = charId(target)
            if tCid then
                db.call("item_disarm", { cid, tCid, tItem.id }, function(res, c)
                    logProc("item.disarmed", c.player, res, {
                        item_id = c.item.id,
                        uname = c.item.uname,
                        target = c.target,
                        target_character_id = tCid,
                        character_id = cid,
                    })
                    if not isElement(c.player) or not res or not res.ok then
                        return
                    end
                    if isElement(c.target) and state.held[c.target] and state.held[c.target].id == c.item.id then
                        M.setHeld(c.target, nil)
                    end
                    M.setHeld(c.player, c.item)
                    triggerEvent("itemMoved", c.player, c.item.id, "held", "held")
                    toast(c.player, "DISARMED")
                end, { player = player, target = target, item = tItem })
                return true
            end
        end
        return false
    end

    local BARBECUE = { "Barbecue" }
    local TENT = { "TentPack" }
    -- the Petrol Can also fuels the three machines (server/machines.lua, #145)
    local TARGETS = {
        GasCan = { "Barbecue", "ScrapMachine", "RefineMachine", "WaterMachine", "Generator" },
        FireLighter = BARBECUE,
    }

    -- the barbecue list plus whatever the small items reach for (the Petrol Can also fills an Empty Molotov)
    local function withSmallTargets(uname, base)
        local extra = small and small.targets(uname)
        if not extra then
            return base
        end
        local list = {}
        for _, u in ipairs(base or {}) do
            list[#list + 1] = u
        end
        for _, u in ipairs(extra) do
            list[#list + 1] = u
        end
        return list
    end

    local defenceTargets = nil
    local function getDefenceTargets()
        if defenceTargets and #defenceTargets > 0 then
            return defenceTargets
        end
        local list = {}
        local all = exports.data and exports.data:itemTypes()
        if all and #all > 0 then
            for _, u in ipairs(all) do
                local t = itemType(u)
                if t and t.defence then
                    list[#list + 1] = u
                end
            end
            defenceTargets = list
        end
        return list
    end

    -- Crowbar reaches tents and defences; Motor, Keypad, AdvancedKeypad reach defences (building resource)
    local crowbarTargets = nil
    local function targetsFor(uname)
        if ammo and ammo.isLiquidWeapon(itemType(uname)) then
            return { "GasCan" } -- F with a liquid weapon in hand reaches a Petrol Can lying near
        end
        if uname == "Motor" or uname == "Keypad" or uname == "AdvancedKeypad" then
            return getDefenceTargets()
        end
        if uname == "Crowbar" then
            local defs = getDefenceTargets()
            if not crowbarTargets or (#crowbarTargets <= #TENT and #defs > 0) then
                crowbarTargets = { unpack(TENT) }
                for _, u in ipairs(defs) do
                    crowbarTargets[#crowbarTargets + 1] = u
                end
            end
            return crowbarTargets
        end
        return withSmallTargets(uname, TARGETS[uname])
    end

    local function buildingRunning()
        local res = getResourceFromName and getResourceFromName("building")
        return res and getResourceState(res) == "running"
    end

    -- the item data's built-defence state ({ active = true, pose, rx, ry }, building/shared/logic/defences.lua)
    local function builtDefence(data)
        local d = type(data) == "table" and (data.defence or (type(data[1]) == "table" and data[1].defence))
        return type(d) == "table" and d.active == true
    end

    -- Hammer, Screwdriver, Wrench, ...: the tools of the ground recipes (crafting/shared/logic/craft.lua)
    local function isConstructionTool(uname)
        local res = uname and getResourceFromName and getResourceFromName("crafting")
        if not res or getResourceState(res) ~= "running" then
            return false
        end
        return exports.crafting:isConstructionTool(uname) == true
    end

    -- furnitureId (groundCraft): no recipe matching puts the tool on that furniture instead (#148); false when the
    -- crafting resource is not running
    local function runCrafting(action, player, furnitureId)
        local res = getResourceFromName and getResourceFromName("crafting")
        if not res or getResourceState(res) ~= "running" then
            return false
        end
        if action == "deconstruct" then
            exports.crafting:deconstruct(player)
        elseif action == "groundCraft" then
            exports.crafting:groundCraft(player, furnitureId)
        elseif action == "workbenchCraft" then
            exports.crafting:workbenchCraft(player)
        end
        return true
    end

    -- the Workbench each player used a tool on, until crafting answers (built, or workbenchRecipeMissed)
    local workbenchAsked = {}
    addEventHandler("workbenchRecipeMissed", root, function()
        local row = workbenchAsked[source]
        workbenchAsked[source] = nil
        if row and containers and isElement(source) then
            containers.openWorldContainer(source, row)
        end
    end)
    addEventHandler("onPlayerQuit", root, function()
        workbenchAsked[source] = nil
    end)

    -- row = { id, uname, hp, data (JSON text) } of a world item: into the empty hand
    function M.pickup(player, cid, row)
        if pickupVetoed(player, row.id) then
            return
        end
        if furnitureSrv and furnitureSrv.blocksPickup(row.uname) then
            return -- upstream OnPlayerPickUpItem breaks for furniture; a Crowbar takes it down
        end
        if vendingSrv and vendingSrv.is(row.uname) then
            return -- a snack machine stays where it stands
        end
        db.call("item_pickup", { row.id, cid }, function(res, c)
            logProc(
                "item.pickedUp",
                c.player,
                res,
                atPlayer(c.player, { item_id = c.row.id, uname = c.row.uname, character_id = cid })
            )
            if res and res.ok then
                world.forgetEverywhere(c.row.id)
            end
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            M.setHeld(c.player, { id = c.row.id, uname = c.row.uname, hp = c.row.hp, data = decodeData(c.row.data) })
            M.pickupAnim(c.player, c.row.uname, c.row.z)
            triggerEvent("itemMoved", c.player, c.row.id, "world", "held")
        end, { player = player, row = row })
    end

    net.handler("itemPickupRequested", function(player, blocked)
        local cid = charId(player)
        if not cid or isBadInteract(player) then
            return
        end
        if state.lastHolster and state.lastHolster[player] and (getTickCount() - state.lastHolster[player] < 1000) then
            return
        end
        local held = state.held[player]
        if tryPlayerInteraction(player, cid, held) then
            return
        end
        local x, y = getElementPosition(player)
        local r = tonumber(state.settings["items.pickup_radius"]) or 2.0
        local unames = held and targetsFor(held.uname)
        local int, dim = getElementInterior(player), getElementDimension(player)
        local sql = world.findNearestSql(x, y, r, int, dim, unames, world.cleanIds(blocked))
        db.one(sql, {}, function(row, c)
            if not isElement(c.player) then
                return
            end
            local curHeld = state.held[c.player]
            local curUname = curHeld and curHeld.uname
            if not row then
                if curUname == "Crowbar" then
                    runCrafting("deconstruct", c.player)
                elseif curUname == "FireLighter" then
                    runCrafting("groundCraft", c.player)
                elseif curHeld and furnitureSrv then -- none of the item's own targets near: a table may take it
                    furnitureSrv.interactNear(c.player, c.charId, curHeld, c.radius, true)
                end
                return
            end
            local rData = decodeData(row.data)

            -- TentPack interactions
            if row.uname == "TentPack" then
                local isPitched = (rData and (rData.pitched == true or (rData[1] and rData[1].pitched == true)))
                if isPitched then
                    if curUname == "Crowbar" then
                        return containers and containers.dismantleTent(c.player, row.id)
                    else
                        return containers and containers.openWorldContainer(c.player, row)
                    end
                else
                    if curUname == "Hammer" then
                        return containers and containers.pitchTent(c.player, row.id)
                    end
                end
            end
            -- Defences: a Hammer lays one down and a Screwdriver stands one up where it lies; once built it is never
            -- picked up again, a Crowbar takes it down from behind and anything else works its door or keypad
            local rowType = itemType(row.uname)
            if curUname == "MobilePhone" and rowType and rowType.explosive and rowType.explosive.trigger == "RADIO" then
                local expRes = getResourceFromName("explosives")
                if expRes and getResourceState(expRes) == "running" then
                    return exports.explosives:linkPhoneBomb(c.player, curHeld, row)
                end
            end
            if rowType and rowType.explosive and rowType.explosive.trigger == "MOTION" then
                local expRes = getResourceFromName("explosives")
                if expRes and getResourceState(expRes) == "running" then
                    if exports.explosives:checkTripMine(c.player, row) then
                        return
                    end
                end
            end
            if rowType and rowType.defence and buildingRunning() then
                local built = builtDefence(rData)
                if not built and (curUname == "Hammer" or curUname == "Screwdriver") then
                    return exports.building:buildDefence(c.player, row.id)
                elseif built and curUname == "Crowbar" then
                    return exports.building:removeDefence(c.player, row.id)
                elseif built then
                    return exports.building:interactDefence(c.player, row)
                end
            end

            -- a snack machine: its glass holds, or it opens to be emptied (server/vending.lua)
            if vendingSrv and vendingSrv.interact(c.player, c.charId, curHeld, row) then
                return
            end

            if curUname == "Crowbar" then
                return runCrafting("deconstruct", c.player)
            end

            -- Locator on a phone, a Stun Gun on a Tool Battery, a Petrol Can on an empty Molotov (smallitems.lua)
            if small and curHeld and small.interact(c.player, curHeld, row) then
                return
            end

            -- desks, tables and the gun case (server/furniture.lua); a construction tool builds from the parts around
            -- first and goes on the furniture only when nothing can be built
            local onFurniture = furnitureSrv and furnitureSrv.blocksPickup(row.uname)
            if onFurniture and curHeld and isConstructionTool(curUname) then
                if runCrafting("groundCraft", c.player, row.id) then
                    return
                end
            end
            if furnitureSrv and furnitureSrv.interact(c.player, c.charId, curHeld, row) then
                return
            end

            -- campfires and barbecues (server/cooking.lua), and the food they are cooking
            if cooking and cooking.interact(c.player, c.charId, curHeld, row) then
                return
            end

            -- a machine (server/machines.lua): the tap opens its container or says how long the cook has left
            if machinesSrv and machinesSrv.interact(c.player, c.charId, curHeld, row) then
                return
            end

            -- a tool in hand on a Workbench builds what lies inside it (upstream workbench.pwn OnPlayerUseItemWithItem)
            -- (when no recipe takes what lies inside, workbenchRecipeMissed opens the container instead)
            if row.uname == "Workbench" and curHeld and isConstructionTool(curUname) then
                workbenchAsked[c.player] = row
                if runCrafting("workbenchCraft", c.player) then
                    return
                end
                workbenchAsked[c.player] = nil
            end

            -- Safebox world containers
            local t = itemType(row.uname)
            if t and t.category == "safebox" then
                return containers and containers.openWorldContainer(c.player, row)
            end

            -- a construction tool in hand next to the ingredients on the ground builds (crafting, #116)
            if curHeld and isConstructionTool(curUname) then
                return runCrafting("groundCraft", c.player)
            end

            local curType = curHeld and itemType(curHeld.uname) or nil
            if curHeld and row.uname == "GasCan" and ammo and ammo.isLiquidWeapon(curType) and liquids then
                return refuelWeaponFromCan(c.player, curHeld, curType, row)
            end
            if curHeld and (not ammo or (not ammo.isCalibreWeapon(curType) and not ammo.isAmmoItem(curType))) then
                if furnitureSrv then -- the nearest item may lie on a table: the table takes this one too
                    return furnitureSrv.interactNear(c.player, c.charId, curHeld, c.radius)
                end
                return toast(c.player, "HANDS_FULL")
            end

            if curHeld then
                return tryTransferFromWorld(c.player, c.charId, curHeld, curType, row)
            end
            M.pickup(c.player, c.charId, row)
        end, { player = player, charId = cid, radius = r })
    end, { rate = 5 })

    -- a hold of the interact key on a bag or a box lying there (upstream "Hold F to pick up / Press F to open"): the
    -- item goes to the empty hand with whatever lies inside it
    net.handler("itemLongPickupRequested", function(player, worldItemId)
        worldItemId = tonumber(worldItemId)
        local cid = charId(player)
        if not cid or not worldItemId or isBadInteract(player) then
            return
        end
        if state.lastHolster and state.lastHolster[player] and (getTickCount() - state.lastHolster[player] < 1000) then
            return
        end
        if state.held[player] then
            return toast(player, "HANDS_FULL")
        end
        local radius = tonumber(state.settings["items.pickup_radius"]) or 2.0
        local sql = "SELECT i.id, i.type_uname AS uname, i.hitpoints AS hp, i.data, i.x, i.y, i.z, i.interior, "
            .. "i.dimension "
            .. "FROM items i WHERE i.id = ? AND i.container_id IS NULL AND i.holder_char_id IS NULL "
            .. "AND i.holder_kind IS NULL AND i.x IS NOT NULL"
        db.one(sql, { worldItemId }, function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local t = itemType(row.uname)
            if not t or (t.category ~= "bag" and t.category ~= "safebox") then
                return
            end
            local sameInt = (row.interior or 0) == getElementInterior(c.player)
            local sameDim = (row.dimension or 0) == getElementDimension(c.player)
            if not (sameInt and sameDim) then
                return
            end
            local px, py = getElementPosition(c.player)
            if getDistanceBetweenPoints2D(px, py, row.x, row.y) > c.radius then
                return
            end
            M.pickup(c.player, c.charId, row)
        end, { player = player, charId = cid, radius = radius })
    end, { rate = 5 })

    -- opts (placing an item, server/smallitems.lua's shield): { ahead, below, turn, data }, spot = { x, y } (a free
    -- spot beside a vehicle, chosen by the client), or at = { x, y, z, rz }
    -- for a spot of the server's (on a table, server/furniture.lua); a plain drop lands 1 m ahead at the feet with
    -- the player's heading, and clears a placed item's standing pose
    function M.dropHeld(player, opts)
        local cid, item = charId(player), state.held[player]
        if not cid or (isIncapacitated and isIncapacitated(player)) then
            return false, "INCAPACITATED"
        end
        if not item then
            return false, "NOT_HELD"
        end
        opts = opts or {}
        local x, y, z = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        local dx, dy = geometry.dropPosition(x, y, rz, opts.ahead or 1.0)
        local dz, drz = z - (opts.below or 0.9), (rz + (opts.turn or 0)) % 360
        if opts.at then
            dx, dy, dz, drz = opts.at.x, opts.at.y, opts.at.z, opts.at.rz % 360
        elseif opts.spot then
            -- the ped turns to face the free spot, and the item lies with that heading
            dx, dy = opts.spot[1], opts.spot[2]
            drz = (math.deg(math.atan2(x - dx, dy - y)) + (opts.turn or 0)) % 360
            setElementRotation(player, 0, 0, drz, "default", true)
        end
        if opts.data then
            item.data = opts.data
        elseif type(item.data) == "table" and item.data.placed then
            -- 0, not nil: a shield's data is only { placed }, and an emptied table encodes to nothing, so the row
            -- would keep placed = 1 and the dropped shield would stand again
            item.data.placed = 0
        end
        if item.data then
            M.queueData(item)
        end
        M.flushData(item.id)
        local params = { item.id, cid, dx, dy, dz, drz, getElementInterior(player), getElementDimension(player) }
        db.call("item_drop", params, function(res, c)
            logProc("item.dropped", c.player, res, {
                item_id = c.itemId,
                uname = c.uname,
                x = math.floor(c.x),
                y = math.floor(c.y),
                z = math.floor(c.z),
                int = c.int,
                dim = c.dim,
                character_id = cid,
            })
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            M.setHeld(c.player, nil)
            M.dropAnim(c.player, c.uname)
            if small then
                small.onDropped(c.player, { id = c.itemId, uname = c.uname }, c.x, c.y, c.z, c.rz) -- dice roll on
            end
            world.syncPlayer(c.player) -- the dropped item appears without waiting for the next tick
            triggerEvent("itemMoved", c.player, c.itemId, "held", "world")
        end, {
            player = player,
            itemId = item.id,
            uname = item.uname,
            x = dx,
            y = dy,
            z = dz,
            rz = drz,
            int = params[7],
            dim = params[8],
        })
        return true
    end

    -- The nearest other player within hand-over reach, in the same interior and dimension (upstream's player area)
    local function nearestOther(player)
        local px, py, pz = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        local best, bestDist = nil, GIVE_REACH
        for _, p in ipairs(getElementsByType("player")) do
            if p ~= player and getElementInterior(p) == int and getElementDimension(p) == dim then
                local tx, ty, tz = getElementPosition(p)
                local d = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
                if d <= bestDist then
                    best, bestDist = p, d
                end
            end
        end
        return best
    end

    -- Hand the held item to the player next to you (upstream OnPlayerGiveItem / OnPlayerGivenItem): their hands must be
    -- empty and neither of you cuffed, knocked out or mid-holster. The one row changes holder, nothing is dropped.
    function M.giveHeld(player)
        local cid, item = charId(player), state.held[player]
        if not cid or (isIncapacitated and isIncapacitated(player)) or isBadInteract(player) then
            return false, "INCAPACITATED"
        end
        if not item then
            return false, "NOT_HELD"
        end
        local target = nearestOther(player)
        local tcid = target and charId(target)
        if not tcid then
            return false, "NOBODY_NEAR"
        end
        if isBadInteract(target) or (isIncapacitated and isIncapacitated(target)) then
            return false, "TARGET_BUSY"
        end
        local now = getTickCount()
        local lh = state.lastHolster
        if lh and ((lh[player] and now - lh[player] < 1000) or (lh[target] and now - lh[target] < 1000)) then
            return false, "TARGET_BUSY"
        end
        if state.held[target] then
            return false, "TARGET_HANDS_FULL"
        end
        if item.data then
            M.queueData(item)
        end
        M.flushData(item.id)
        db.call("item_give", { item.id, cid, tcid }, function(res, c)
            logProc("item.given", c.player, res, {
                item_id = c.item.id,
                uname = c.item.uname,
                to = c.target,
                to_character_id = tcid,
                character_id = cid,
            })
            if not res or not res.ok then
                return isElement(c.player) and toast(c.player, res and res.code or "DB_ERROR")
            end
            if isElement(c.player) and state.held[c.player] and state.held[c.player].id == c.item.id then
                M.setHeld(c.player, nil)
                anim(c.player, "KISSING", "gift_give", 1800, false, false, false, false)
                toast(c.player, "GAVE_ITEM")
            end
            if isElement(c.target) then
                if not state.held[c.target] then
                    M.setHeld(c.target, { id = c.item.id, uname = c.item.uname, hp = c.item.hp, data = c.item.data })
                else
                    -- the row is theirs (item_give saw an empty hand) while the memory shows another item: the
                    -- database decides what they hold
                    M.rebuildCarried(c.target)
                end
                anim(c.target, "KISSING", "gift_get", 1800, false, false, false, false)
                toast(c.target, "GOT_ITEM")
            end
            triggerEvent("itemMoved", c.player, c.item.id, "held", "held")
        end, { player = player, target = target, item = item })
        return true
    end

    -- A worn hat or mask knocked off (char/headgear-pop.pwn, weapons on a headshot): the one row it is moves to the
    -- ground at the player's feet, the slot empties and the clients around see it lie there.
    function M.popGear(player, slot)
        local cid, item = charId(player), state[slot] and state[slot][player]
        if not cid or not item then
            return false
        end
        local x, y, z = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        db.exec(
            "UPDATE items SET holder_char_id = NULL, holder_kind = NULL, x = ?, y = ?, z = ?, rz = ?, "
                .. "interior = ?, dimension = ? WHERE id = ? AND holder_char_id = ? AND holder_kind = ?",
            { x, y, z - 0.9, rz, getElementInterior(player), getElementDimension(player), item.id, cid, slot },
            function(ok, c)
                log.event("item.dropped", {
                    player = c.player,
                    item_id = c.item.id,
                    uname = c.item.uname,
                    reason = "headgear_popped",
                    slot = c.slot,
                    ok = ok,
                    code = ok and "OK" or "DB_ERROR",
                    x = math.floor(c.x),
                    y = math.floor(c.y),
                    z = math.floor(c.z),
                    character_id = cid,
                })
                if not ok or not isElement(c.player) then
                    return
                end
                if state[c.slot][c.player] and state[c.slot][c.player].id == c.item.id then
                    M.setGear(c.player, c.slot, nil)
                end
                world.syncPlayer(c.player)
                triggerEvent("itemMoved", c.player, c.item.id, c.slot, "world")
            end,
            { player = player, slot = slot, item = item, x = x, y = y, z = z - 0.9 }
        )
        return true
    end

    -- The server has no bounding boxes for vehicles, so with one near the drop the client picks the free spot beside
    -- it (client/main.lua) and answers; no answer within a second drops at the default spot
    local dropSpotPending = {}

    local function dropAt(player, spot)
        local ok, err = M.dropHeld(player, spot and { spot = spot } or nil)
        if not ok and err and isElement(player) then
            toast(player, err)
        end
    end

    local function vehicleNear(player)
        local x, y, z = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        for _, veh in ipairs(getElementsByType("vehicle")) do
            if getElementInterior(veh) == int and getElementDimension(veh) == dim then
                local vx, vy, vz = getElementPosition(veh)
                if (vx - x) ^ 2 + (vy - y) ^ 2 + (vz - z) ^ 2 <= 100 then
                    return true
                end
            end
        end
        return false
    end

    net.handler("itemDropRequested", function(player)
        if dropSpotPending[player] then
            return
        end
        if not vehicleNear(player) then
            return dropAt(player)
        end
        dropSpotPending[player] = setTimer(function()
            dropSpotPending[player] = nil
            if isElement(player) then
                dropAt(player)
            end
        end, 1000, 1)
        triggerClientEvent(player, "itemDropSpotRequested", player)
    end, { rate = 5 })

    net.handler("itemDropSpotChosen", function(player, x, y)
        local timer = dropSpotPending[player]
        if not timer then
            return
        end
        killTimer(timer)
        dropSpotPending[player] = nil
        local px, py = getElementPosition(player)
        local spot
        if type(x) == "number" and type(y) == "number" and x == x and y == y then
            if (x - px) ^ 2 + (y - py) ^ 2 <= 12 then
                spot = { x, y }
            end
        end
        dropAt(player, spot)
    end, { rate = 5 })

    addEventHandler("onPlayerQuit", root, function()
        if dropSpotPending[source] then
            killTimer(dropSpotPending[source])
            dropSpotPending[source] = nil
        end
    end)

    net.handler("itemGiveRequested", function(player)
        local ok, err = M.giveHeld(player)
        if not ok and err and isElement(player) then
            toast(player, err)
        end
    end, { rate = 5 })

    return M
end
