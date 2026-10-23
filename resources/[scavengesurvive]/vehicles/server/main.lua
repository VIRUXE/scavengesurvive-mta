-- Loot vehicles: rolled once over the seeded vehicle_spawns points, persisted in MariaDB.
-- Fuel drain, engine/lights toggle, door locks (0/1/2), roadside repair, refuelling,
-- locksmith key crafting/usage, crowbar lock-breaking, trunk containers, and trailer hitching.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()

local spawn
do
    local f = fileOpen("shared/logic/spawn.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    spawn = assert(loadstring(src, "=vehicles/spawn.lua"))()
end

local vlogic
do
    local f = fileOpen("shared/logic/vehicle.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    vlogic = assert(loadstring(src, "=vehicles/vehicle.lua"))()
end

local FLUSH_MS = 60000
local WRECK_MS = 30000
local SIM_TICK_MS = 1000

local SELECT_VEHICLES = "SELECT v.id, v.spawn_id, v.type_uname, v.model, v.x, v.y, v.z, v.rz, "
    .. "v.health, v.fuel, v.locked, v.damage, v.key_code, v.trailer_id, c.id AS container_id "
    .. "FROM vehicles v LEFT JOIN containers c ON c.owner_vehicle_id = v.id"

local INSERT_VEHICLE = "INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz, "
    .. "health, fuel, locked, damage, key_code, trailer_id) "
    .. "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

local settings = {}
local types = nil -- spawn.index(...) of the data resource's vehicle types
local info = {} -- vehicle element -> { id, uname, fuel, locked, keyCode, trailerId, containerId }
local activeActions = {} -- player -> { actionType, vehicle, timer, extra }
local rolling = false

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "onClientItemsToast", player, code)
    end
end

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function loadTypes()
    local list = {}
    for _, uname in ipairs(exports.data:vehicleTypes()) do
        list[#list + 1] = exports.data:vehicleType(uname)
    end
    return spawn.index(list)
end

local function applyDamage(v, d)
    if type(d) ~= "table" then
        return
    end
    for i, s in ipairs(d.panels or {}) do
        setVehiclePanelState(v, i - 1, s)
    end
    for i, s in ipairs(d.doors or {}) do
        setVehicleDoorState(v, i + 1, s) -- MTA doors 2..5 are the side doors (0 bonnet, 1 boot)
    end
    for i, s in ipairs(d.lights or {}) do
        setVehicleLightState(v, i - 1, s)
    end
    local t = d.tires
    if t and #t == 4 then
        setVehicleWheelStates(v, t[1], t[2], t[3], t[4])
    end
end

-- row: a vehicles table row joined with containers
local function create(row)
    local v = createVehicle(row.model, row.x, row.y, row.z, 0, 0, row.rz)
    if not v then
        util.log("vehicles", "warn", "createVehicle failed for %s (model %d)", row.type_uname, row.model)
        return nil
    end
    setElementHealth(v, math.max(0, math.min(1000, tonumber(row.health) or 1000)))
    setVehicleEngineState(v, false)
    local lockState = tonumber(row.locked) or 0
    setVehicleLocked(v, lockState > 0)
    if row.damage and row.damage ~= "" and row.damage ~= false then
        applyDamage(v, fromJSON(row.damage))
    end
    setElementData(v, "vehicles.id", row.id, "broadcast", "deny")
    setElementData(v, "vehicles.type", row.type_uname, "broadcast", "deny")
    setElementData(v, "vehicles.fuel", tonumber(row.fuel) or 0, "broadcast", "deny")
    setElementData(v, "vehicles.locked", lockState, "broadcast", "deny")

    local cid = row.container_id and tonumber(row.container_id) or nil
    setElementData(v, "vehicles.containerId", cid or false, "broadcast", "deny")

    info[v] = {
        id = row.id,
        uname = row.type_uname,
        fuel = tonumber(row.fuel) or 0,
        locked = lockState,
        keyCode = row.key_code and tonumber(row.key_code) or nil,
        trailerId = row.trailer_id and tonumber(row.trailer_id) or nil,
        containerId = cid,
    }

    -- If the vehicle has trunk capacity but no container row yet, create one
    local vt = exports.data:vehicleType(row.type_uname)
    if vt and (vt.trunkSize or 0) > 0 and not cid then
        db.exec(
            "INSERT INTO containers (kind, size, owner_vehicle_id) VALUES ('vehicle', ?, ?)",
            { vt.trunkSize, row.id },
            function(ok, _, _, insertId)
                if ok and insertId and isElement(v) and info[v] then
                    info[v].containerId = insertId
                    setElementData(v, "vehicles.containerId", insertId, "broadcast", "deny")
                end
            end
        )
    end

    return v
end

local function forget(v)
    info[v] = nil
end

local function count()
    return util.tableCount(info)
end

-- Rolls every enabled spawn point once and stores the winners; cb(created) when all inserts are in.
local function rollAll(cb)
    if rolling then
        return false
    end
    rolling = true
    local chance = tonumber(settings["vehicles.spawn_chance"]) or spawn.DEFAULT_CHANCE
    db.query(
        "SELECT id, x, y, z, rz, group_name, type_name, categories, sizes FROM vehicle_spawns WHERE enabled = 1",
        {},
        function(rows)
            if not rows then
                rolling = false
                return
            end
            local pending, created = 0, 0
            local function done()
                if pending == 0 then
                    rolling = false
                    util.log("vehicles", "info", "rolled %d spawn points: %d vehicles", #rows, created)
                    triggerEvent("onVehiclesSpawned", resourceRoot, created)
                    if cb then
                        cb(created)
                    end
                end
            end
            for _, s in ipairs(rows) do
                local r = spawn.roll(s, types, chance, math.random)
                if r then
                    local t = r.type
                    local damage = spawn.damage(t.category, math.random)
                    local isLocked = spawn.locked(t, damage, math.random)
                    local row = {
                        spawn_id = s.id,
                        type_uname = t.uname,
                        model = t.model,
                        x = s.x,
                        y = s.y,
                        z = s.z,
                        rz = r.rz,
                        health = spawn.health(math.random),
                        fuel = spawn.fuel(t.maxFuel or 0, math.random),
                        locked = isLocked and vlogic.LOCK_DEFAULT or vlogic.LOCK_OPEN,
                        damage = damage and toJSON(damage) or nil,
                        key_code = nil,
                        trailer_id = nil,
                    }
                    pending = pending + 1
                    local params = {
                        row.spawn_id,
                        row.type_uname,
                        row.model,
                        row.x,
                        row.y,
                        row.z,
                        row.rz,
                        row.health,
                        row.fuel,
                        row.locked,
                        row.damage,
                        row.key_code,
                        row.trailer_id,
                        n = 13,
                    }
                    db.exec(INSERT_VEHICLE, params, function(ok, ctx, _, insertId)
                        pending = pending - 1
                        if ok and insertId then
                            ctx.id = insertId
                            if create(ctx) then
                                created = created + 1
                            end
                        end
                        done()
                    end, row)
                end
            end
            done()
        end
    )
    return true
end

local function loadOrRoll()
    db.query(SELECT_VEHICLES, {}, function(rows)
        if not rows then
            return
        end
        if #rows == 0 then
            return rollAll()
        end
        local n = 0
        local pendingTrailers = {}
        for _, row in ipairs(rows) do
            local v = create(row)
            if v then
                n = n + 1
                if row.trailer_id and tonumber(row.trailer_id) then
                    pendingTrailers[v] = tonumber(row.trailer_id)
                end
            end
        end
        -- Re-attach persisted trailers
        for truck, trailerDbId in pairs(pendingTrailers) do
            for otherV, inf in pairs(info) do
                if inf.id == trailerDbId and isElement(truck) and isElement(otherV) then
                    attachTrailerToVehicle(truck, otherV)
                    break
                end
            end
        end
        util.log("vehicles", "info", "%d vehicles rebuilt from the database", n)
        triggerEvent("onVehiclesSpawned", resourceRoot, n)
    end)
end

local function flushAll()
    local rows = {}
    for v, i in pairs(info) do
        if isElement(v) then
            local x, y, z = getElementPosition(v)
            local _, _, rz = getElementRotation(v)
            rows[#rows + 1] = {
                id = i.id,
                x = x,
                y = y,
                z = z,
                rz = rz,
                health = getElementHealth(v),
                fuel = i.fuel,
                locked = i.locked,
            }
        end
    end
    if #rows == 0 then
        return
    end
    db.call("vehicle_flush", { toJSON(rows) }, function(res)
        if not res or not res.ok then
            util.log("vehicles", "error", "vehicle_flush failed: %s", res and res.code or "db")
        end
    end)
end

-- 1-second simulation tick for fuel consumption and low-health stalls
local function tickSimulation()
    for v, inf in pairs(info) do
        if isElement(v) and getVehicleEngineState(v) then
            local vt = exports.data:vehicleType(inf.uname)
            if vt and not vt.noEngine and (vt.maxFuel or 0) > 0 then
                local vx, vy, vz = getElementVelocity(v)
                local speedKmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 150
                local newFuel = vlogic.fuelDrain(inf.fuel, vt.fuelConsumption, speedKmh, 1.0)
                inf.fuel = newFuel
                setElementData(v, "vehicles.fuel", newFuel, "broadcast", "deny")

                local driver = getVehicleController(v)
                if newFuel <= 0 then
                    setVehicleEngineState(v, false)
                    if driver then
                        toast(driver, "NO_FUEL")
                    end
                else
                    local hp = getElementHealth(v)
                    if hp <= vlogic.HEALTH_CHUNK_1 then
                        setVehicleEngineState(v, false)
                        if driver then
                            toast(driver, "ENGINE_BROKEN")
                        end
                    elseif hp <= vlogic.HEALTH_CHUNK_2 and speedKmh > 30 then
                        if vlogic.checkStall(hp, speedKmh, math.random) then
                            setVehicleEngineState(v, false)
                            if driver then
                                toast(driver, "ENGINE_STALL")
                            end
                        end
                    end
                end
            end
        end
    end
end

local function cancelHoldAction(player)
    local act = activeActions[player]
    if not act then
        return
    end
    if isTimer(act.timer) then
        killTimer(act.timer)
    end
    if isElement(player) then
        setPedAnimation(player, nil)
        triggerClientEvent(player, "onClientVehiclesStopHoldAction", player)
    end
    if act.actionType == "repair" and isElement(act.vehicle) then
        setVehicleDoorOpenRatio(act.vehicle, 0, 0, 500) -- close bonnet
    end
    activeActions[player] = nil
end

-- Door lock enforcement: cancel entry on locked vehicles
addEventHandler("onVehicleStartEnter", root, function(player)
    local inf = info[source]
    if inf and inf.locked and inf.locked > 0 then
        cancelEvent()
        if inf.locked == vlogic.LOCK_EXTERNAL then
            toast(player, "LOCKCUSTOML")
        else
            toast(player, "LOCKUSECROW")
        end
    end
end)

-- Engine toggle (driver Y key)
net.handler("onVehiclesRequestEngineToggle", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player then
        return
    end
    local inf = info[v]
    if not inf then
        return
    end
    local vt = exports.data:vehicleType(inf.uname)
    local hp = getElementHealth(v)
    local curr = getVehicleEngineState(v)
    if not curr then
        local ok, err = vlogic.canStartEngine(hp, inf.fuel, vt and vt.noEngine, vt and vt.maxFuel)
        if not ok then
            if err == "DAMAGED" then
                toast(player, "ENGINE_BROKEN")
            elseif err == "NO_FUEL" then
                toast(player, "NO_FUEL")
            end
            return
        end
        setVehicleEngineState(v, true)
    else
        setVehicleEngineState(v, false)
    end
end, { rate = 3 })

-- Lights toggle (occupant N key)
net.handler("onVehiclesRequestLightsToggle", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v then
        return
    end
    local curr = getVehicleOverrideLights(v)
    setVehicleOverrideLights(v, curr == 2 and 1 or 2)
end, { rate = 3 })

-- Lock toggle from inside the vehicle (/lock or bind)
net.handler("onVehiclesRequestLockToggle", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player then
        return
    end
    local inf = info[v]
    if not inf then
        return
    end
    if inf.locked > 0 then
        inf.locked = vlogic.LOCK_OPEN
        setVehicleLocked(v, false)
        toast(player, "UNLOCKED")
    else
        inf.locked = inf.keyCode and vlogic.LOCK_EXTERNAL or vlogic.LOCK_DEFAULT
        setVehicleLocked(v, true)
        toast(player, "LOCKED")
    end
    setElementData(v, "vehicles.locked", inf.locked, "broadcast", "deny")
    db.exec("UPDATE vehicles SET locked = ? WHERE id = ?", { inf.locked, inf.id })
end, { rate = 3 })

-- Trailers attach/detach (/tow)
net.handler("onVehiclesRequestTow", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player then
        return
    end
    local inf = info[v]
    if not inf then
        return
    end
    local vt = exports.data:vehicleType(inf.uname)
    if not vt or not vt.trailerHitch then
        return toast(player, "NO_HITCH")
    end
    local currTrailer = getVehicleTowedByVehicle(v)
    if currTrailer then
        detachTrailerFromVehicle(v)
        inf.trailerId = nil
        db.exec("UPDATE vehicles SET trailer_id = NULL WHERE id = ?", { inf.id })
        return toast(player, "TRAILER_DETACHED")
    end
    local px, py, pz = getElementPosition(v)
    local best, bestDist = nil, 6.5
    for otherV, otherInf in pairs(info) do
        if otherV ~= v and isElement(otherV) then
            local otherVt = exports.data:vehicleType(otherInf.uname)
            if vlogic.canAttachTrailer(vt, otherVt, 0, 0) then
                local tx, ty, tz = getElementPosition(otherV)
                local dist = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
                if dist < bestDist then
                    best, bestDist = otherV, dist
                end
            end
        end
    end
    if not best then
        return toast(player, "NO_TRAILER_NEAR")
    end
    attachTrailerToVehicle(v, best)
    inf.trailerId = info[best].id
    db.exec("UPDATE vehicles SET trailer_id = ? WHERE id = ?", { info[best].id, inf.id })
    toast(player, "TRAILER_ATTACHED")
end, { rate = 3 })

-- Roadside interaction: repair, locksmith, lock-breaking, trunk container, refuelling
net.handler("onVehiclesRequestInteract", function(player, vehicle)
    if not isElement(vehicle) or not info[vehicle] or isPedDead(player) then
        return
    end
    local inf = info[vehicle]
    local vt = exports.data:vehicleType(inf.uname)
    local px, py, pz = getElementPosition(player)
    local vx, vy, vz = getElementPosition(vehicle)
    local dist = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
    if dist > vlogic.maxReachDistance(vt and vt.size) then
        return
    end

    local _, _, vrz = getElementRotation(vehicle)
    local angle = vlogic.angleToVehicle(px, py, vx, vy, vrz)
    local held = exports.items:getHeld(player)
    local uname = held and held.uname
    local hp = getElementHealth(vehicle)

    -- Case 1: Front (Bonnet) Repair
    if vlogic.isFront(angle) and (uname == "Wrench" or uname == "Screwdriver" or uname == "Hammer") then
        local toolNeeded = vlogic.repairToolForHealth(hp)
        if not toolNeeded then
            return toast(player, "VEH_FULL_REPAIR")
        end
        if uname ~= toolNeeded then
            return toast(player, "NEEDANOTOOL")
        end
        cancelHoldAction(player)
        setVehicleDoorOpenRatio(vehicle, 0, 1, 500)
        setPedAnimation(player, "INT_SHOP", "SHOP_CASHIER", -1, true, false, false, false)
        triggerClientEvent(player, "onClientVehiclesHoldAction", player, "Repairing", 3000)
        local timer = setTimer(function(p, veh)
            activeActions[p] = nil
            if not isElement(p) or not isElement(veh) then
                return
            end
            setPedAnimation(p, nil)
            setVehicleDoorOpenRatio(veh, 0, 0, 500)
            local curHp = getElementHealth(veh)
            local nextHp = math.min(vlogic.HEALTH_MAX, curHp + 150)
            setElementHealth(veh, nextHp)
            toast(p, "REPAIRED")
        end, 3000, 1, player, vehicle)
        activeActions[player] = { actionType = "repair", vehicle = vehicle, timer = timer }
        return
    end

    -- Case 2: Driver-side interactions (Key, LocksmithKit, LockBreaker, Crowbar)
    if vlogic.isDriverSide(angle) then
        if uname == "Key" then
            local ok, err = vlogic.canUseKey(held.data, inf.keyCode)
            if not ok then
                return toast(player, err)
            end
            if inf.locked > 0 then
                inf.locked = vlogic.LOCK_OPEN
                setVehicleLocked(vehicle, false)
                toast(player, "UNLOCKED")
            else
                inf.locked = vlogic.LOCK_EXTERNAL
                setVehicleLocked(vehicle, true)
                toast(player, "LOCKED")
            end
            setElementData(vehicle, "vehicles.locked", inf.locked, "broadcast", "deny")
            db.exec("UPDATE vehicles SET locked = ? WHERE id = ?", { inf.locked, inf.id })
            return
        end

        if uname == "LocksmithKit" or uname == "WheelLock" then
            local ok, err = vlogic.canCraftKey(inf.locked, uname, vt and vt.notLockable, inf.keyCode)
            if not ok then
                return toast(player, err)
            end
            cancelHoldAction(player)
            setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
            triggerClientEvent(player, "onClientVehiclesHoldAction", player, "Crafting key", 3000)
            local timer = setTimer(function(p, veh, kitId)
                activeActions[p] = nil
                if not isElement(p) or not isElement(veh) then
                    return
                end
                setPedAnimation(p, nil)
                local cid = charId(p)
                if not cid then
                    return
                end
                local code = math.random(100000, 999999)
                local vinf = info[veh]
                if vinf then
                    vinf.locked = vlogic.LOCK_EXTERNAL
                    vinf.keyCode = code
                    setVehicleLocked(veh, true)
                    setElementData(veh, "vehicles.locked", 1, "broadcast", "deny")
                    db.exec("UPDATE vehicles SET locked = 1, key_code = ? WHERE id = ?", { code, vinf.id })
                end
                exports.items:destroyItem(kitId, p)
                db.call("item_create_held", { "Key", cid }, function(res, c)
                    if res and res.ok and isElement(c.p) then
                        local newKeyId = res.payload.item_id
                        local keyData = { code = code, model = vt and vt.model or 0 }
                        db.exec("UPDATE items SET data = ? WHERE id = ?", { toJSON(keyData), newKeyId })
                        exports.items:setHeld(c.p, { id = newKeyId, uname = "Key", hp = 5, data = keyData })
                        toast(c.p, "KEY_CRAFTED")
                    end
                end, { p = p })
            end, 3000, 1, player, vehicle, held.id)
            activeActions[player] = { actionType = "locksmith", vehicle = vehicle, timer = timer }
            return
        end

        if uname == "Crowbar" or uname == "LockBreaker" then
            local ok, err = vlogic.canBreakLock(inf.locked, uname)
            if not ok then
                return toast(player, err)
            end
            cancelHoldAction(player)
            setPedAnimation(player, "POLICE", "DOOR_KICK", -1, true, false, false, false)
            triggerClientEvent(player, "onClientVehiclesHoldAction", player, "Breaking lock", 3000)
            local timer = setTimer(function(p, veh)
                activeActions[p] = nil
                if not isElement(p) or not isElement(veh) then
                    return
                end
                setPedAnimation(p, nil)
                local vinf = info[veh]
                if vinf then
                    vinf.locked = vlogic.LOCK_OPEN
                    vinf.keyCode = nil
                    setVehicleLocked(veh, false)
                    setElementData(veh, "vehicles.locked", 0, "broadcast", "deny")
                    db.exec("UPDATE vehicles SET locked = 0, key_code = NULL WHERE id = ?", { vinf.id })
                    toast(p, "LOCKBROKEN")
                end
            end, 3000, 1, player, vehicle)
            activeActions[player] = { actionType = "lockbreak", vehicle = vehicle, timer = timer }
            return
        end
    end

    -- Case 3: Rear (Trunk)
    if vlogic.isRear(angle) then
        if (uname == "Crowbar" or uname == "LockBreaker") and inf.locked > 0 then
            local ok, err = vlogic.canBreakLock(inf.locked, uname)
            if not ok then
                return toast(player, err)
            end
            cancelHoldAction(player)
            setPedAnimation(player, "POLICE", "DOOR_KICK", -1, true, false, false, false)
            triggerClientEvent(player, "onClientVehiclesHoldAction", player, "Breaking trunk", 3000)
            local timer = setTimer(function(p, veh)
                activeActions[p] = nil
                if not isElement(p) or not isElement(veh) then
                    return
                end
                setPedAnimation(p, nil)
                local vinf = info[veh]
                if vinf then
                    vinf.locked = vlogic.LOCK_OPEN
                    vinf.keyCode = nil
                    setVehicleLocked(veh, false)
                    setElementData(veh, "vehicles.locked", 0, "broadcast", "deny")
                    db.exec("UPDATE vehicles SET locked = 0, key_code = NULL WHERE id = ?", { vinf.id })
                    toast(p, "LOCKBROKEN")
                end
            end, 3000, 1, player, vehicle)
            activeActions[player] = { actionType = "lockbreak", vehicle = vehicle, timer = timer }
            return
        end

        if inf.locked > 0 then
            return toast(player, "TRUNKLOCKED")
        end
        if not inf.containerId then
            return toast(player, "NO_TRUNK")
        end
        setVehicleDoorOpenRatio(vehicle, 1, 1, 500)
        local tname = string.format("%s Trunk", vt and vt.name or "Vehicle")
        exports.items:openTrunkContainer(player, vehicle, inf.containerId, tname, vt and vt.trunkSize or 40)
        return
    end

    -- Case 4: Refuelling with Petrol Can
    if uname == "GasCan" then
        local maxFuel = vt and vt.maxFuel or 60.0
        if inf.fuel >= maxFuel then
            return toast(player, "TANKFULL")
        end
        local canFuel = tonumber(held.data and held.data.amount) or 20.0
        if canFuel <= 0 then
            return toast(player, "EMPTY")
        end
        cancelHoldAction(player)
        setPedAnimation(player, "PED", "DRIVE_BOAT", -1, true, false, false, false)
        triggerClientEvent(player, "onClientVehiclesHoldAction", player, "Refuelling", 3000)
        local timer = setTimer(function(p, veh, gcan)
            activeActions[p] = nil
            if not isElement(p) or not isElement(veh) then
                return
            end
            setPedAnimation(p, nil)
            local vinf = info[veh]
            if not vinf then
                return
            end
            local curCanFuel = tonumber(gcan.data and gcan.data.amount) or 20.0
            local space = maxFuel - vinf.fuel
            local transfer = math.min(curCanFuel, space, 10.0)
            local nextCanFuel = math.max(0, curCanFuel - transfer)
            local nextVehFuel = vinf.fuel + transfer
            vinf.fuel = nextVehFuel
            setElementData(veh, "vehicles.fuel", nextVehFuel, "broadcast", "deny")
            db.exec("UPDATE vehicles SET fuel = ? WHERE id = ?", { nextVehFuel, vinf.id })
            gcan.data = { amount = nextCanFuel }
            exports.items:updateHeldData(p, gcan.data)
            toast(p, "REFUELLED")
        end, 3000, 1, player, vehicle, held)
        activeActions[player] = { actionType = "refuel", vehicle = vehicle, timer = timer }
        return
    end
end, { rate = 3 })

net.handler("onVehiclesRequestCancelHoldAction", function(player)
    cancelHoldAction(player)
end, { rate = 5 })

net.handler("onVehiclesRequestCloseTrunk", function(player)
    exports.items:closeTrunk(player)
    -- find any vehicle near player whose trunk is open and close it
    local px, py, pz = getElementPosition(player)
    for v in pairs(info) do
        if isElement(v) then
            local vx, vy, vz = getElementPosition(v)
            if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) < 7.0 then
                setVehicleDoorOpenRatio(v, 1, 0, 500)
            end
        end
    end
end, { rate = 3 })

addEventHandler("onPlayerQuit", root, function()
    cancelHoldAction(source)
end)

addEventHandler("onPlayerWasted", root, function()
    cancelHoldAction(source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("vehicles") then
        return
    end
    types = loadTypes()
    db.settings(function(map)
        settings = map
        loadOrRoll()
    end)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    flushAll()
end)

setTimer(flushAll, FLUSH_MS, 0)
setTimer(tickSimulation, SIM_TICK_MS, 0)

-- Wreck destruction: wreck stays for 30s, then removed and deleted from MariaDB
addEventHandler("onVehicleExplode", resourceRoot, function()
    local i = info[source]
    if not i then
        return
    end
    setTimer(function(v, id)
        db.exec("DELETE FROM vehicles WHERE id = ?", { id })
        if isElement(v) then
            forget(v)
            destroyElement(v)
        end
    end, WRECK_MS, 1, source, i.id)
end)

function getVehicleDbId(vehicle)
    local i = info[vehicle]
    return i and i.id or false
end

function countVehicles()
    return count()
end

function getVehicleFuel(vehicle)
    local i = info[vehicle]
    return i and i.fuel or 0
end

function setVehicleFuel(vehicle, amount)
    local i = info[vehicle]
    if i and isElement(vehicle) then
        i.fuel = math.max(0, tonumber(amount) or 0)
        setElementData(vehicle, "vehicles.fuel", i.fuel, "broadcast", "deny")
        return true
    end
    return false
end

function getVehicleLockState(vehicle)
    local i = info[vehicle]
    return i and i.locked or 0
end

function setVehicleLockState(vehicle, stateVal)
    local i = info[vehicle]
    if i and isElement(vehicle) then
        i.locked = tonumber(stateVal) or 0
        setVehicleLocked(vehicle, i.locked > 0)
        setElementData(vehicle, "vehicles.locked", i.locked, "broadcast", "deny")
        return true
    end
    return false
end

function getVehicleKeyCode(vehicle)
    local i = info[vehicle]
    return i and i.keyCode or false
end

function setVehicleKeyCode(vehicle, code)
    local i = info[vehicle]
    if i and isElement(vehicle) then
        i.keyCode = tonumber(code) or nil
        return true
    end
    return false
end

function getVehicleContainerId(vehicle)
    local i = info[vehicle]
    return i and i.containerId or false
end

function respawnAll()
    if rolling then
        return false
    end
    for v in pairs(info) do
        if isElement(v) then
            destroyElement(v)
        end
    end
    info = {}
    db.exec("DELETE FROM vehicles", {}, function(ok)
        if ok then
            rollAll()
        end
    end)
    return true
end
