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
    local isBadInteract = ctx.isBadInteract or function()
        return false
    end
    local isKnockedOut, isPlayerCuffed, setPlayerCuffed = ctx.isKnockedOut, ctx.isPlayerCuffed, ctx.setPlayerCuffed
    local VANILLA_MELEE_MAX = 15
    local RELOAD_COOLDOWN_MS = 1000
    local lastReload = {}
    local containers, cooking, small, machinesSrv, furnitureSrv = nil, nil, nil, nil, nil
    local M = {}

    function M.setContainers(c)
        containers = c
    end

    function M.setCooking(c)
        cooking = c
    end

    -- server/smallitems.lua: held-with-world pairs (Locator + phone, Stun Gun + Battery, can + bottle), dice drops
    function M.setMachines(m)
        machinesSrv = m
    end

    function M.setSmall(s)
        small = s
    end

    -- server/furniture.lua (#148): items put on desks and tables or shown in a gun case, the furniture never picked up
    function M.setFurniture(f)
        furnitureSrv = f
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

    -- Bending animation for pickup and drop (#121). Note: in MTA, setPedAnimation runs as a primary task and
    -- blocks player WASD movement (issue #3915); two-handed carried items (useCarryAnim: Wheel, boxes, panels)
    -- cannot hold CARRY crry_prtial without freezing player movement (875e85b), so they hang in hand while moving.
    local function anim(player, ...)
        if setPedAnimation and isElement(player) then
            setPedAnimation(player, ...)
        end
    end
    function M.pickupAnim(player, _uname)
        anim(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
    end
    function M.dropAnim(player, _uname)
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
        dropPendingData(held.id)
        db.call("item_transfer_world", params, function(res, c)
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
                triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
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
        GasCan = { "Barbecue", "ScrapMachine", "RefineMachine", "WaterMachine" },
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
        if furnitureSrv and furnitureSrv.blocksPickup(row.uname) then
            return -- upstream OnPlayerPickUpItem breaks for furniture; a Crowbar takes it down
        end
        db.call("item_pickup", { row.id, cid }, function(res, c)
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
            M.pickupAnim(c.player, c.row.uname)
            triggerEvent("itemMoved", c.player, c.row.id, "world", "held")
        end, { player = player, row = row })
    end

    net.handler("itemPickupRequested", function(player)
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
        local sql = world.findNearestSql(x, y, r, getElementInterior(player), getElementDimension(player), unames)
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

            if curUname == "Crowbar" then
                return runCrafting("deconstruct", c.player)
            end

            -- a Locator on a phone, a Stun Gun on a Battery, a Petrol Can on an Empty Molotov (server/smallitems.lua)
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

    -- opts (placing an item, server/smallitems.lua's shield): { ahead, below, turn, data }, or at = { x, y, z, rz }
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
        if opts.data then
            item.data = opts.data
        elseif type(item.data) == "table" and item.data.placed then
            item.data.placed = nil
        end
        if item.data then
            M.queueData(item)
        end
        M.flushData(item.id)
        local x, y, z = getElementPosition(player)
        local _, _, rz = getElementRotation(player)
        local dx, dy = geometry.dropPosition(x, y, rz, opts.ahead or 1.0)
        local dz, drz = z - (opts.below or 0.9), (rz + (opts.turn or 0)) % 360
        if opts.at then
            dx, dy, dz, drz = opts.at.x, opts.at.y, opts.at.z, opts.at.rz % 360
        end
        local params = { item.id, cid, dx, dy, dz, drz, getElementInterior(player), getElementDimension(player) }
        db.call("item_drop", params, function(res, c)
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
        end, { player = player, itemId = item.id, uname = item.uname, x = dx, y = dy, z = dz, rz = drz })
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
                if not ok or not isElement(c.player) then
                    return
                end
                if state[c.slot][c.player] and state[c.slot][c.player].id == c.item.id then
                    M.setGear(c.player, c.slot, nil)
                end
                world.syncPlayer(c.player)
                triggerEvent("itemMoved", c.player, c.item.id, c.slot, "world")
            end,
            { player = player, slot = slot, item = item }
        )
        return true
    end

    net.handler("itemDropRequested", function(player)
        local ok, err = M.dropHeld(player)
        if not ok and err and isElement(player) then
            toast(player, err)
        end
    end, { rate = 5 })

    return M
end
