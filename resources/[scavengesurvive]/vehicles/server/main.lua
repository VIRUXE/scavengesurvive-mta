-- Loot vehicles: rolled once over the seeded vehicle_spawns points, persisted in MariaDB.
-- Fuel drain, engine/lights toggle, door locks (0/1/2), roadside repair, refuelling,
-- locksmith key crafting/usage, crowbar lock-breaking, trunk containers, and trailer hitching.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local budget = loadstring(exports.lib:getModule("budget"), "=lib/budget.lua")()

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

local fuelPumps
do
    local f = fileOpen("shared/logic/fuel-pumps.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    fuelPumps = assert(loadstring(src, "=vehicles/fuel-pumps.lua"))()
end

local FLUSH_MS = 60000
local WRECK_MS = 30000
local SIM_TICK_MS = 1000

local USED_TICK_MS = 300000

local SELECT_VEHICLES = "SELECT v.id, v.spawn_id, v.type_uname, v.model, v.x, v.y, v.z, v.rz, "
    .. "v.health, v.fuel, v.locked, v.damage, v.key_code, v.trailer_id, v.left_spawn, c.id AS container_id, "
    .. "s.x AS spawn_x, s.y AS spawn_y FROM vehicles v LEFT JOIN containers c ON c.owner_vehicle_id = v.id "
    .. "LEFT JOIN vehicle_spawns s ON s.id = v.spawn_id"

local INSERT_VEHICLE = "INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz, "
    .. "health, fuel, locked, damage, key_code, trailer_id) "
    .. "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

local SELECT_SPAWNS = "SELECT id, x, y, z, rz, group_name, type_name, categories, sizes "
    .. "FROM vehicle_spawns WHERE enabled = 1"

local UPDATE_REMAINDER = "UPDATE world_budget SET remainder = ? WHERE category = 'vehicles' AND zone = 'all'"

-- Cooled points with no vehicle still standing on them, in random order
local SELECT_COOLED_SPAWNS = SELECT_SPAWNS
    .. " AND NOT EXISTS (SELECT 1 FROM vehicle_spawn_state st"
    .. " WHERE st.spawn_id = vehicle_spawns.id AND st.next_roll_at > NOW())"
    .. " AND NOT EXISTS (SELECT 1 FROM vehicles v WHERE v.spawn_id = vehicle_spawns.id AND v.left_spawn = 0)"
    .. " ORDER BY RAND() LIMIT ?"

local COOL_SPAWN = "INSERT INTO vehicle_spawn_state (spawn_id, next_roll_at) "
    .. "VALUES (?, DATE_ADD(NOW(), INTERVAL ? SECOND)) ON DUPLICATE KEY UPDATE next_roll_at = VALUES(next_roll_at)"

local SELECT_BUDGET = "SELECT cap, remainder, (SELECT COUNT(*) FROM vehicles) AS alive FROM world_budget "
    .. "WHERE category = 'vehicles' AND zone = 'all'"

local UPSERT_BUDGET = "INSERT INTO world_budget (category, zone, cap, remainder, allowance) "
    .. "VALUES ('vehicles', 'all', ?, 0, 0) ON DUPLICATE KEY UPDATE cap = VALUES(cap), remainder = 0"

-- retires every abandoned vehicle in one statement; RETURNING hands back the ids whose elements go too
local DELETE_ABANDONED = "DELETE FROM vehicles WHERE left_spawn = 1 "
    .. "AND COALESCE(last_used_at, updated_at) < DATE_SUB(NOW(), INTERVAL ? DAY) RETURNING id"

local settings = {}
local types = nil -- spawn.index(...) of the data resource's vehicle types
-- vehicle element -> { id, uname, fuel, locked, keyCode, trailerId, containerId, spawnId, spawnX, spawnY, leftSpawn }
local info = {}
local activeActions = {} -- player -> { actionType, vehicle, timer, extra }
local rolling = false
local refilling = false
local refillTimer = nil
for _, pump in ipairs(fuelPumps) do
    pump.stock = math.random() * pump.stockMax -- upstream frandom(startamount); not persisted
end

local function setting(key, default)
    return tonumber(settings[key]) or default
end

-- Puts a spawn point on cooldown (its vehicle was destroyed or driven away): vehicles.cooldown_hours ± jitter.
local function coolPoint(spawnId)
    if not spawnId then
        return
    end
    local base = setting("vehicles.cooldown_hours", 6) * 3600
    local secs = budget.cooldown(base, setting("vehicles.cooldown_jitter", 0.33), math.random)
    db.exec(COOL_SPAWN, { spawnId, secs })
end

local function playerPositions()
    local out = {}
    for _, p in ipairs(getElementsByType("player")) do
        local x, y = getElementPosition(p)
        out[#out + 1] = { x = x, y = y }
    end
    return out
end

-- Entering a vehicle, opening its trunk, hitching it as a trailer, using its walk-in door or standing in or on it
-- stamps last_used_at (at most once per USED_TICK_MS); the abandon rule only removes vehicles nobody has touched that
-- way for vehicles.abandon_days. A trailer is never entered, so an Airstream lived in would otherwise look abandoned.
local function markUsed(v)
    local i = info[v]
    if not i then
        return
    end
    local now = getTickCount()
    if now - i.usedTick >= USED_TICK_MS then
        i.usedTick = now
        db.exec("UPDATE vehicles SET last_used_at = NOW() WHERE id = ?", { i.id })
    end
end

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "toastShown", player, code)
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
        spawnId = row.spawn_id and tonumber(row.spawn_id) or nil,
        spawnX = row.spawn_x and tonumber(row.spawn_x) or nil,
        spawnY = row.spawn_y and tonumber(row.spawn_y) or nil,
        leftSpawn = (tonumber(row.left_spawn) or 0) > 0,
        damage = row.damage and row.damage ~= "" and row.damage ~= false and fromJSON(row.damage) or {},
        usedTick = 0,
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

-- Rolls one spawn point (a vehicle_spawns row) with the given per-point chance. Returns true when a vehicle is
-- being inserted; cb(vehicle or nil) when the insert is in.
local function spawnAt(s, chance, cb)
    local r = spawn.roll(s, types, chance, math.random)
    if not r then
        return false
    end
    local t = r.type
    local damage = spawn.damage(t.category, math.random)
    local isLocked = spawn.locked(t, damage, math.random)
    local row = {
        spawn_id = s.id,
        spawn_x = s.x,
        spawn_y = s.y,
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
        local v = nil
        if ok and insertId then
            ctx.id = insertId
            v = create(ctx)
        end
        if cb then
            cb(v)
        end
    end, row)
    return true
end

-- Rolls every enabled spawn point once and stores the winners; the result sets the carrying capacity
-- (world_budget 'vehicles'/'all') and puts the used points on cooldown. cb(created) when all inserts are in.
local function rollAll(cb)
    if rolling then
        return false
    end
    rolling = true
    local chance = setting("vehicles.spawn_chance", spawn.DEFAULT_CHANCE)
    db.query(SELECT_SPAWNS, {}, function(rows)
        if not rows then
            rolling = false
            return
        end
        local pending, created = 0, 0
        local function done()
            if pending == 0 then
                rolling = false
                local cap = budget.cap(created, settings["vehicles.cap_multiplier"])
                db.exec(UPSERT_BUDGET, { cap })
                util.log("vehicles", "info", "rolled %d spawn points: %d vehicles, cap %d", #rows, created, cap)
                triggerEvent("vehiclesSpawned", resourceRoot, created)
                if cb then
                    cb(created)
                end
            end
        end
        for _, s in ipairs(rows) do
            local started = spawnAt(s, chance, function(v)
                pending = pending - 1
                if v then
                    created = created + 1
                    coolPoint(info[v].spawnId)
                end
                done()
            end)
            if started then
                pending = pending + 1
            end
        end
        done()
    end)
    return true
end

-- Spawns up to n vehicles on random cooled points clear of players; cb(spawned) when the rolls are in.
local function refillSpawns(n, cb)
    local minDist = setting("world.min_player_distance", 150)
    db.query(SELECT_COOLED_SPAWNS, { n * 8 }, function(rows)
        if not rows then
            return cb(0)
        end
        local spawned = 0
        for _, s in ipairs(budget.pickClear(rows, playerPositions(), minDist, n * 4, math.random)) do
            if spawned >= n then
                break
            end
            local started = spawnAt(s, 100, function(v)
                if v then
                    coolPoint(info[v].spawnId)
                end
            end)
            if started then
                spawned = spawned + 1
            end
        end
        cb(spawned)
    end)
end

-- The ADR 0001 refill tick: retire abandoned vehicles, then spend the refill the deficit earned this interval.
local function refillTick()
    if rolling or refilling then
        return
    end
    refilling = true
    local function finish()
        refilling = false
    end
    db.query(DELETE_ABANDONED, { setting("vehicles.abandon_days", 3) }, function(rows)
        local removed = 0
        for _, r in ipairs(rows or {}) do
            local id = tonumber(r.id)
            for v, i in pairs(info) do
                if i.id == id then
                    forget(v)
                    if isElement(v) then
                        destroyElement(v)
                    end
                end
            end
            removed = removed + 1
        end
        db.query(SELECT_BUDGET, {}, function(brows)
            local b = brows and brows[1]
            if not b then
                -- a world rolled before the budget existed: its current stock becomes the capacity
                local cap = budget.cap(count(), settings["vehicles.cap_multiplier"])
                db.exec(UPSERT_BUDGET, { cap })
                util.log("vehicles", "info", "refill: budget created from the %d vehicles alive, cap %d", count(), cap)
                return finish()
            end
            local cap, alive = tonumber(b.cap) or 0, (tonumber(b.alive) or 0) - removed
            local rate, floor = setting("vehicles.refill_rate", 0.10), setting("vehicles.refill_floor", 0.02)
            local interval = setting("world.refill_interval_s", 300)
            local spawns, remainder = budget.refill(cap, alive, tonumber(b.remainder) or 0, rate, floor, interval)
            local function store(spawned)
                db.exec(UPDATE_REMAINDER, { remainder })
                local line = "refill: cap %d alive %d removed %d spawned %d"
                util.log("vehicles", "info", line, cap, alive, removed, spawned)
                finish()
            end
            if spawns <= 0 then
                return store(0)
            end
            refillSpawns(spawns, store)
        end)
    end)
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
        triggerEvent("vehiclesSpawned", resourceRoot, n)
    end)
end

local function flushAll()
    local rows = {}
    local leaveRadius = setting("vehicles.leave_radius", 100)
    for v, i in pairs(info) do
        if isElement(v) then
            local x, y, z = getElementPosition(v)
            local _, _, rz = getElementRotation(v)
            -- the first time a vehicle is driven away from its point, the point becomes free and cools down
            if not i.leftSpawn and i.spawnX and util.dist2(x, y, i.spawnX, i.spawnY) > leaveRadius then
                i.leftSpawn = true
                db.exec("UPDATE vehicles SET left_spawn = 1 WHERE id = ?", { i.id })
                coolPoint(i.spawnId)
            end
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
        triggerClientEvent(player, "vehicleHoldStopped", player)
    end
    if act.actionType == "repair" and isElement(act.vehicle) then
        setVehicleDoorOpenRatio(act.vehicle, 0, 0, 500) -- close bonnet
    end
    activeActions[player] = nil
end

-- Fuel pumps (upstream world/fuel.pwn): holding interact at a pump with a Petrol Can fills it from the pump's stock.
-- Upstream moved 1.2 L per 100 ms hold tick; one hold here moves the whole amount over the same time.
local CAN_CAPACITY, PUMP_REACH, PUMP_LITRES_PER_TICK, PUMP_TICK_MS = 20.0, 2.0, 1.2, 100

net.handler("fuelPumpInteractRequested", function(player)
    local held = exports.items:getHeld(player)
    if not held or held.uname ~= "GasCan" or isPedDead(player) or activeActions[player] then
        return
    end
    local px, py, pz = getElementPosition(player)
    local pump, best = nil, PUMP_REACH
    for _, candidate in ipairs(fuelPumps) do
        local d = getDistanceBetweenPoints3D(px, py, pz, candidate.x, candidate.y, candidate.z)
        if d < best then
            pump, best = candidate, d
        end
    end
    if not pump then
        return
    end
    local amount = math.max(0, tonumber(held.data and held.data.amount) or CAN_CAPACITY)
    if amount >= CAN_CAPACITY then
        return toast(player, "CANFULL")
    end
    if pump.stock <= 0 then
        return toast(player, "EMPTY")
    end
    local transfer = math.min(CAN_CAPACITY - amount, pump.stock)
    local ms = math.max(500, math.ceil(transfer / PUMP_LITRES_PER_TICK) * PUMP_TICK_MS)
    setPedAnimation(player, "PED", "DRIVE_BOAT", -1, true, false, false, false)
    triggerClientEvent(player, "vehicleHoldStarted", player, "Filling petrol can", ms)
    local timer = setTimer(function(p, canId, outlet)
        activeActions[p] = nil
        if not isElement(p) then
            return
        end
        setPedAnimation(p, nil)
        local current = exports.items:getHeld(p)
        if not current or current.id ~= canId then
            return
        end
        local fuel = math.max(0, tonumber(current.data and current.data.amount) or CAN_CAPACITY)
        local moved = math.min(CAN_CAPACITY - fuel, outlet.stock)
        if moved > 0 then
            outlet.stock = outlet.stock - moved
            exports.items:updateHeldData(p, { amount = fuel + moved })
            toast(p, "REFUELLED")
        end
    end, ms, 1, player, held.id, pump)
    activeActions[player] = { actionType = "pump", timer = timer }
end, { rate = 3 })

-- Entry enforcement: no entering during a roadside hold (repair, refuel, locksmith, lock-break), nor into locked
-- vehicles, nor with a carried item (wheel, box, panel: useCarryAnim) in hand. Upstream dropped the carried item on
-- the spot (OnPlayerEnterVehicle); the port refuses instead so nothing is left behind by accident (#120).
addEventHandler("onVehicleStartEnter", root, function(player)
    if activeActions[player] then
        cancelEvent()
        return
    end
    local held = exports.items:getHeld(player)
    local heldType = held and exports.data:itemType(held.uname)
    if heldType and heldType.useCarryAnim then
        cancelEvent()
        return toast(player, "CARRY_NO_VEHICLE")
    end
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
net.handler("engineToggleRequested", function(player)
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
net.handler("lightsToggleRequested", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v then
        return
    end
    local curr = getVehicleOverrideLights(v)
    setVehicleOverrideLights(v, curr == 2 and 1 or 2)
end, { rate = 3 })

-- Lock toggle from inside the vehicle (/lock or the submission key, any occupant as upstream vehicle/lock.pwn)
net.handler("lockToggleRequested", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v then
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

-- Trailers (upstream vehicle/trailer.pwn): the driver of a vehicle with a hitch toggles it with upstream's KEY_ACTION
-- in a vehicle, LCtrl / Num0, which MTA calls vehicle_secondary_fire. The server picks the trailer and the driver's
-- client hitches or drops it (trailerHitchOrdered), so the driver's own sync carries the change; the record
-- (info.trailerId, vehicles.trailer_id) and the toast follow what the clients report through onTrailerAttach /
-- onTrailerDetach.
local TOW_KEY = "vehicle_secondary_fire"
local TOW_COOLDOWN_MS = 500
local HINT_MS = 500
-- A new driver's client may not have the hitch the server restored (a load, a desync) and its first sync drops it:
-- a detach this soon after a driver got in is that, and the driver's client is told to hitch it again.
local ENTER_GRACE_MS = 3000
local driverSince = {} -- vehicle -> tick its current driver got in
local lastTow = {} -- player -> tick of the last toggle
local hitchDrivers = {} -- player driving a vehicle with a hitch -> the HUD line sent ("hitch", "unhitch" or false)

local function vehicleById(id)
    for v, i in pairs(info) do
        if i.id == id and isElement(v) then
            return v
        end
    end
end

local function setTrailerRecord(truck, trailerId)
    local inf = info[truck]
    inf.trailerId = trailerId
    db.exec("UPDATE vehicles SET trailer_id = ? WHERE id = ?", { trailerId, inf.id, n = 2 })
end

-- Walk-in trailers (vehicle types with door = true, the towable Airstream) carry what lies inside them. While one is
-- hitched, the world items in its room are its cargo: their spot in its frame goes to every client as its
-- "vehicles.cargo" element data ({ id, lx, ly, lz, lrz } rows; items hangs their objects on it), and their stored
-- positions follow it, in one item_world_move call: when it stops somewhere new, every CARGO_STORE_MS on the road,
-- and when it is unhitched or lost. Standing where it was loaded, its cargo is looked for again every CARGO_TICK_MS,
-- so what is dropped, built or taken there in the meantime joins or leaves it.
local CARGO_TICK_MS = 2000
local CARGO_STORE_MS = 60000
local CARGO_MOVED, CARGO_TURNED = 0.3, 3.0 -- metres and degrees from where it was loaded that count as moved
local CARGO_STILL = 0.5 -- m/s under which a trailer counts as standing
local CARGO_SQL = "SELECT i.id, i.type_uname AS uname, i.x, i.y, i.z, i.rz, IFNULL(i.interior, 0) AS interior, "
    .. "IFNULL(i.dimension, 0) AS dimension FROM world_items_pos p JOIN items i ON i.id = p.item_id "
    .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= ?"
local CARGO_SKIP = { PlotPole = true } -- a plot pole's claim is a fixed server shape: it stays where it was planted
local CARGO_HITCH_MS = 5000 -- a cargo found for a hitch that never came is let go after this
-- trailer -> { items = { [id] = { lx, ly, lz, lrz } }, m, x, y, z, rz (the anchor: the trailer where the items'
-- stored positions put them, set when loaded and on every store), storedAt }
local cargo = {}

local function isWalkIn(v)
    local inf = info[v]
    local vt = inf and exports.data:vehicleType(inf.uname)
    return vt and vt.door == true or false
end

-- getElementMatrix rows: right, forward, up, position
local function toLocal(m, x, y, z)
    local dx, dy, dz = x - m[4][1], y - m[4][2], z - m[4][3]
    local lx = dx * m[1][1] + dy * m[1][2] + dz * m[1][3]
    local ly = dx * m[2][1] + dy * m[2][2] + dz * m[2][3]
    local lz = dx * m[3][1] + dy * m[3][2] + dz * m[3][3]
    return lx, ly, lz
end

local function toWorld(m, lx, ly, lz)
    local x = lx * m[1][1] + ly * m[2][1] + lz * m[3][1] + m[4][1]
    local y = lx * m[1][2] + ly * m[2][2] + lz * m[3][2] + m[4][2]
    local z = lx * m[1][3] + ly * m[2][3] + lz * m[3][3] + m[4][3]
    return x, y, z
end

local function publishCargo(trailer)
    local c = cargo[trailer]
    local list = {}
    for id, l in pairs(c and c.items or {}) do
        list[#list + 1] = { id, l[1], l[2], l[3], l[4] }
    end
    setElementData(trailer, "vehicles.cargo", #list > 0 and list or false, "broadcast", "deny")
end

local function setAnchor(c, trailer)
    c.m = getElementMatrix(trailer)
    c.x, c.y, c.z = getElementPosition(trailer)
    local _, _, rz = getElementRotation(trailer)
    c.rz = rz
end

-- the items whose stored positions lie in the trailer's room at its anchor (a trailer creeping on the hitch must not
-- slide them: they are measured against where they were stored, not where it is now)
local function loadCargo(trailer)
    local c = cargo[trailer]
    local m, rz = c.m, c.rz
    local int, dim = getElementInterior(trailer), getElementDimension(trailer)
    db.query(CARGO_SQL, { c.x, c.y, vlogic.CARGO_RADIUS }, function(rows)
        if not rows or cargo[trailer] ~= c or not isElement(trailer) or c.m ~= m then
            return
        end
        local items = {}
        for _, r in ipairs(rows) do
            if not CARGO_SKIP[r.uname] and tonumber(r.interior) == int and tonumber(r.dimension) == dim then
                local lx, ly, lz = toLocal(m, r.x, r.y, r.z)
                if vlogic.inCargoBox(lx, ly, lz) then
                    items[r.id] = { lx, ly, lz, ((tonumber(r.rz) or 0) - rz) % 360 }
                end
            end
        end
        c.items = items
        publishCargo(trailer)
    end)
end

-- the cargo's stored positions where the trailer is now, and every client draws them there again
local function storeCargo(trailer)
    local c = cargo[trailer]
    if not c or not isElement(trailer) then
        return
    end
    if not next(c.items) then
        return setAnchor(c, trailer) -- nothing rides: what is dropped in it from here on is found here
    end
    local m = getElementMatrix(trailer)
    local _, _, rz = getElementRotation(trailer)
    local rows, ids = {}, {}
    for id, l in pairs(c.items) do
        local x, y, z = toWorld(m, l[1], l[2], l[3])
        rows[#rows + 1] = { id = id, x = x, y = y, z = z, rz = (rz + l[4]) % 360 }
        ids[#ids + 1] = id
    end
    c.storedAt = getTickCount()
    setAnchor(c, trailer)
    db.call("item_world_move", { toJSON(rows) }, function(res)
        if not res or not res.ok then
            return util.log("vehicles", "error", "item_world_move failed: %s", res and res.code or "db")
        end
        for _, id in ipairs(ids) do
            exports.items:resendWorldItem(id)
        end
    end)
end

local function startCargo(trailer)
    if not cargo[trailer] and isWalkIn(trailer) then
        cargo[trailer] = { items = {}, storedAt = getTickCount() }
        setAnchor(cargo[trailer], trailer)
        loadCargo(trailer)
    end
end

local function endCargo(trailer)
    if cargo[trailer] then
        storeCargo(trailer)
        cargo[trailer] = nil
        if isElement(trailer) then
            publishCargo(trailer)
        end
    end
end

local function angleOff(a, b)
    local d = math.abs((a - b) % 360)
    return math.min(d, 360 - d)
end

setTimer(function()
    for v in pairs(info) do
        if isElement(v) and not cargo[v] and getVehicleTowingVehicle(v) then
            startCargo(v) -- also the hitches restored at start, which raise no attach event
        end
    end
    for trailer, c in pairs(cargo) do
        if not isElement(trailer) then
            cargo[trailer] = nil
        elseif not getVehicleTowingVehicle(trailer) and getTickCount() - c.storedAt > CARGO_HITCH_MS then
            cargo[trailer] = nil -- the hitch it was found for did not come (the trailer never moved)
            publishCargo(trailer)
        else
            local x, y, z = getElementPosition(trailer)
            local _, _, rz = getElementRotation(trailer)
            local vx, vy, vz = getElementVelocity(trailer)
            local speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 50 -- MTA velocity is per 1/50 s
            local moved = getDistanceBetweenPoints3D(x, y, z, c.x, c.y, c.z) > CARGO_MOVED
                or angleOff(rz, c.rz) > CARGO_TURNED
            if not moved then
                loadCargo(trailer)
            elseif speed < CARGO_STILL then
                storeCargo(trailer) -- stopped somewhere new: the cargo is stored there and anchored there
            elseif getTickCount() - c.storedAt >= CARGO_STORE_MS then
                storeCargo(trailer)
            end
        end
    end
end, CARGO_TICK_MS, 0)

addEventHandler("onResourceStop", resourceRoot, function()
    for trailer in pairs(cargo) do
        storeCargo(trailer)
    end
end)

-- The closest free trailer the truck can take within reach (upstream: both lengths and a metre), or nil.
local function trailerInReach(v, inf)
    local vt = exports.data:vehicleType(inf.uname)
    local px, py, pz = getElementPosition(v)
    local best, bestDist = nil, math.huge
    for otherV, otherInf in pairs(info) do
        local free = otherV ~= v and isElement(otherV) and not getVehicleTowingVehicle(otherV)
        if free and vlogic.canAttachTrailer(vt, exports.data:vehicleType(otherInf.uname)) then
            local tx, ty, tz = getElementPosition(otherV)
            local dist = getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz)
            local reach = vlogic.towReach(getElementModel(v), getElementModel(otherV))
            if dist < reach and dist < bestDist then
                best, bestDist = otherV, dist
            end
        end
    end
    return best
end

local function toggleTrailer(player)
    local v = getPedOccupiedVehicle(player)
    local inf = v and info[v]
    if not inf or getVehicleController(v) ~= player then
        return
    end
    local now = getTickCount()
    if now - (lastTow[player] or 0) < TOW_COOLDOWN_MS then
        return
    end
    lastTow[player] = now
    if getVehicleTowedByVehicle(v) then
        return triggerClientEvent(player, "trailerHitchOrdered", player, v, false)
    end
    local best = trailerInReach(v, inf)
    if best then
        startCargo(best) -- what is inside is found where it stands: the hitch pulls the trailer onto the car's ball
        triggerClientEvent(player, "trailerHitchOrdered", player, v, best)
    end
end

-- The hitch line of a driver's key actions (hud): "unhitch" while towing, "hitch" with a trailer in reach; sent on
-- change.
local function updateHitchHint(player)
    local v = getPedOccupiedVehicle(player)
    local inf = v and info[v]
    local hint = false
    if inf and getVehicleController(v) == player then
        hint = getVehicleTowedByVehicle(v) and "unhitch" or (trailerInReach(v, inf) and "hitch") or false
    end
    if hitchDrivers[player] ~= hint then
        hitchDrivers[player] = hint
        triggerClientEvent(player, "trailerHitchHintChanged", player, hint)
    end
end

local function bindTow(player, v)
    local inf = info[v]
    local vt = inf and exports.data:vehicleType(inf.uname)
    if not (vt and vt.trailerHitch) then
        return
    end
    if not isKeyBound(player, TOW_KEY, "down", toggleTrailer) then
        bindKey(player, TOW_KEY, "down", toggleTrailer)
    end
    hitchDrivers[player] = false
    updateHitchHint(player)
end

local function unbindTow(player)
    if isKeyBound(player, TOW_KEY, "down", toggleTrailer) then
        unbindKey(player, TOW_KEY, "down", toggleTrailer)
    end
    if hitchDrivers[player] then
        triggerClientEvent(player, "trailerHitchHintChanged", player, false)
    end
    hitchDrivers[player] = nil
end

addEventHandler("onVehicleEnter", resourceRoot, function(player, seat)
    if seat ~= 0 then
        return
    end
    bindTow(player, source)
    driverSince[source] = getTickCount()
    -- the recorded trailer goes on in the driver's client too, so its sync carries the hitch from the start
    local inf = info[source]
    local trailer = inf and inf.trailerId and vehicleById(inf.trailerId)
    if trailer then
        triggerClientEvent(player, "trailerHitchOrdered", player, source, trailer)
    end
end)

addEventHandler("onVehicleExit", resourceRoot, function(player, seat)
    if seat == 0 then
        unbindTow(player)
        driverSince[source] = nil
    end
end)

addEventHandler("onPlayerQuit", root, function()
    lastTow[source] = nil
    hitchDrivers[source] = nil
end)

setTimer(function()
    for player in pairs(hitchDrivers) do
        if isElement(player) then
            updateHitchHint(player)
        end
    end
end, HINT_MS, 0)

-- A trailer went on, by the hitch key or a truck backed into one: keep it when the pair fits, as upstream's sync task.
addEventHandler("onTrailerAttach", root, function(truck)
    startCargo(source)
    local inf, tinf = info[truck], info[source]
    if not inf or not tinf or inf.trailerId == tinf.id then
        return
    end
    if vlogic.canAttachTrailer(exports.data:vehicleType(inf.uname), exports.data:vehicleType(tinf.uname)) then
        setTrailerRecord(truck, tinf.id)
        markUsed(source)
        local driver = getVehicleController(truck)
        if driver then
            toast(driver, "TRAILER_ATTACHED")
        end
    end
end)

-- A trailer came off on a client (the hitch key, a jackknife, a crash): with a driver the record goes, as upstream;
-- an unoccupied truck gets its trailer back (someone dragging it away, or desync).
addEventHandler("onTrailerDetach", root, function(truck)
    endCargo(source)
    local inf, tinf = info[truck], info[source]
    if not inf or not tinf or inf.trailerId ~= tinf.id then
        return
    end
    local driver = getVehicleController(truck)
    if driver and getTickCount() - (driverSince[truck] or 0) < ENTER_GRACE_MS then
        return triggerClientEvent(driver, "trailerHitchOrdered", driver, truck, source)
    end
    if driver then
        setTrailerRecord(truck, nil)
        return toast(driver, "TRAILER_DETACHED")
    end
    local trailer = source
    setTimer(function()
        if isElement(truck) and isElement(trailer) and info[truck] and info[truck].trailerId == info[trailer].id then
            attachTrailerToVehicle(truck, trailer)
        end
    end, 50, 1)
end)

-- A walk-in door (vehicle types with door = true, the towable Airstream): the interact key next to it opens or shuts
-- it (vehicles client tryTrailerDoor).
net.handler("trailerDoorToggleRequested", function(player, vehicle)
    local inf = isElement(vehicle) and info[vehicle]
    local vt = inf and exports.data:vehicleType(inf.uname)
    if not (vt and vt.door) or getPedOccupiedVehicle(player) then
        return
    end
    local px, py, pz = getElementPosition(player)
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > vlogic.DOOR_SERVER_REACH then
        return
    end
    local open = getVehicleDoorOpenRatio(vehicle, vlogic.WALK_IN_DOOR) < 0.5
    setVehicleDoorOpenRatio(vehicle, vlogic.WALK_IN_DOOR, open and 1 or 0, 600)
    markUsed(vehicle)
end, { rate = 3 })

-- Someone standing in or on a vehicle (inside an Airstream, on a flatbed) uses it: checked once a minute.
setTimer(function()
    for _, player in ipairs(getElementsByType("player")) do
        local under = not getPedOccupiedVehicle(player) and getPedContactElement(player)
        if under and info[under] then
            markUsed(under)
        end
    end
end, 60000, 0)

-- getVehicleWheelStates order (front-left, rear-left, front-right, rear-right) -> upstream tyre repair message
local TIRE_REPAIRED = { "TIREREPFL", "TIREREPBL", "TIREREPFR", "TIREREPBR" }

-- Roadside interaction: repair, locksmith, lock-breaking, trunk container, refuelling, headlights, wheels
net.handler("vehicleInteractRequested", function(player, vehicle)
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

    -- Case 0: a held Wheel replaces the nearest burst or missing tyre (upstream core/item/wheel.pwn); upstream acts
    -- only within 1 m of a wheel, so at the trunk it falls through and the Wheel can go in the trunk
    if uname == "Wheel" and not vlogic.isRear(angle) then
        local rad = math.rad(vrz or 0)
        local dx, dy = px - vx, py - vy
        local localX = dx * math.cos(rad) + dy * math.sin(rad)
        local localY = -dx * math.sin(rad) + dy * math.cos(rad)
        local frontLeft, rearLeft, frontRight, rearRight = getVehicleWheelStates(vehicle)
        local tires = { frontLeft, rearLeft, frontRight, rearRight }
        local wheel = vlogic.nearestDamagedWheel(localX, localY, tires)
        if not wheel then
            return
        end

        tires[wheel] = 0
        setVehicleWheelStates(vehicle, tires[1], tires[2], tires[3], tires[4])
        inf.damage = type(inf.damage) == "table" and inf.damage or {}
        inf.damage.tires = tires
        db.exec("UPDATE vehicles SET damage = ? WHERE id = ?", { toJSON(inf.damage), inf.id })
        exports.items:destroyItem(held.id, player)
        toast(player, TIRE_REPAIRED[wheel])
        return
    end

    -- Case 1a: Front, Headlight item replaces the first broken light (upstream core/item/headlight.pwn)
    if vlogic.isFront(angle) and uname == "Headlight" then
        local brokenLight = nil
        for light = 0, 3 do
            if getVehicleLightState(vehicle, light) ~= 0 then
                brokenLight = light
                break
            end
        end
        if not brokenLight then
            return
        end

        setVehicleLightState(vehicle, brokenLight, 0)
        inf.damage = type(inf.damage) == "table" and inf.damage or {}
        inf.damage.lights = inf.damage.lights or {}
        for light = 0, 3 do
            inf.damage.lights[light + 1] = getVehicleLightState(vehicle, light)
        end
        db.exec("UPDATE vehicles SET damage = ? WHERE id = ?", { toJSON(inf.damage), inf.id })
        exports.items:destroyItem(held.id, player)
        toast(player, "REPAIRED")
        return
    end

    -- Case 1b: Front (Bonnet) Repair
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
        -- upstream repair.pwn ran the Repair skill through the per-tick health step, so skill made repairs slower;
        -- the port shortens the hold instead
        local ms = exports.character:skillTimeModifier(player, 3000, "Repair")
        triggerClientEvent(player, "vehicleHoldStarted", player, "Repairing", ms)
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
            exports.character:gainSkill(p, "Repair")
            toast(p, "REPAIRED")
        end, ms, 1, player, vehicle)
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
            triggerClientEvent(player, "vehicleHoldStarted", player, "Crafting key", 3000)
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
            triggerClientEvent(player, "vehicleHoldStarted", player, "Breaking lock", 3000)
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
            triggerClientEvent(player, "vehicleHoldStarted", player, "Breaking trunk", 3000)
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
        markUsed(vehicle)
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
        triggerClientEvent(player, "vehicleHoldStarted", player, "Refuelling", 3000)
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

net.handler("holdActionCancelRequested", function(player)
    cancelHoldAction(player)
end, { rate = 5 })

net.handler("trunkCloseRequested", function(player)
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

addEventHandler("onVehicleEnter", resourceRoot, function(player, seat)
    markUsed(source)
    local key = seat == 0 and vlogic.repairTipKey(getElementHealth(source))
    if key then
        exports.ui:showTip(player, exports.data:t(exports.auth:getLanguage(player), key), false, 20000)
    end
end)

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
    for _, t in ipairs(types.list) do
        for property, value in pairs(t.handling or {}) do
            setModelHandling(t.model, property, value)
        end
    end
    db.settings(function(map)
        settings = map
        loadOrRoll()
        if isTimer(refillTimer) then
            killTimer(refillTimer)
        end
        refillTimer = setTimer(refillTick, setting("world.refill_interval_s", 300) * 1000, 0)
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
    endCargo(source) -- what rode in it is left where it blew up
    if not i.leftSpawn then
        coolPoint(i.spawnId)
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
    -- the dev reset: every point is free again and the roll writes a fresh budget row
    db.exec("DELETE FROM vehicle_spawn_state", {})
    db.exec("DELETE FROM vehicles", {}, function(ok)
        if ok then
            rollAll()
        end
    end)
    return true
end
