local spatial = loadstring(exports.lib:getModule("spatial"), "=lib/spatial.lua")()
-- Loot vehicles: rolled once over the seeded vehicle_spawns points, persisted in MariaDB.
-- Fuel drain, engine/lights toggle, door locks (0/1/2), roadside repair, refuelling,
-- locksmith key crafting/usage, crowbar lock-breaking, trunk containers, and trailer hitching.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local budget = loadstring(exports.lib:getModule("budget"), "=lib/budget.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

-- adds the pos fields (x y z int dim zone) of an element to a log line
local function logAt(fields, element)
    if isElement(element) then
        local x, y, z = getElementPosition(element)
        fields.x, fields.y, fields.z = x, y, z
        fields.int, fields.dim = getElementInterior(element), getElementDimension(element)
        local ok, zone = pcall(function()
            return exports.maps:getZoneAt(x, y)
        end)
        fields.zone = ok and zone or nil
    end
    return fields
end

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

local battery
do
    local f = fileOpen("shared/logic/battery.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    battery = assert(loadstring(src, "=vehicles/battery.lua"))()
end

local starter
do
    local f = fileOpen("shared/logic/starter.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    starter = assert(loadstring(src, "=vehicles/starter.lua"))()
end

local fuelPumps
do
    local f = fileOpen("shared/logic/fuel-pumps.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    fuelPumps = assert(loadstring(src, "=vehicles/fuel-pumps.lua"))()
end

local carmour
do
    local f = fileOpen("shared/logic/carmour.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    carmour = assert(loadstring(src, "=vehicles/carmour.lua"))()
end

-- where defences go on a vehicle: the placement rules and the Airstream's shell and every defence's frame
local carmourPlace, carmourGeo
do
    local f = fileOpen("shared/logic/carmour_place.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    carmourPlace = assert(loadstring(src, "=vehicles/carmour_place.lua"))()
    f = fileOpen("shared/data/carmour_geometry.lua", true)
    src = fileRead(f, fileGetSize(f))
    fileClose(f)
    carmourGeo = carmourPlace.load(assert(loadstring(src, "=vehicles/carmour_geometry.lua"))())
end

local carmourSrv -- server/carmour.lua, built once the roadside helpers it needs exist
local bodySrv -- Bobcat salvage part installation
local gasSrv -- server/gasbottles.lua, built with it

local FLUSH_MS = 60000
local WRECK_MS = 30000
local SIM_TICK_MS = 1000

local USED_TICK_MS = 300000

local GLOVEBOX_LOOT = "vehicle_glovebox" -- loot table of a fresh vehicle's glovebox (small items only)

local SELECT_VEHICLES = "SELECT v.id, v.spawn_id, v.type_uname, v.model, v.x, v.y, v.z, v.rz, "
    .. "v.health, v.fuel, v.locked, v.damage, v.carmour, v.gas_bottles, v.key_code, v.keypad_code, "
    .. "v.trailer_id, v.left_spawn, v.battery, v.battery_since, v.starter, "
    .. "c.id AS container_id, g.id AS glovebox_id, "
    .. "s.x AS spawn_x, s.y AS spawn_y FROM vehicles v "
    .. "LEFT JOIN containers c ON c.owner_vehicle_id = v.id AND c.kind = 'vehicle' "
    .. "LEFT JOIN containers g ON g.owner_vehicle_id = v.id AND g.kind = 'glovebox' "
    .. "LEFT JOIN vehicle_spawns s ON s.id = v.spawn_id"

local INSERT_VEHICLE = "INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz, "
    .. "health, fuel, locked, damage, key_code, trailer_id, battery, battery_since, starter) "
    .. "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

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

-- a vehicle's log line: its database id, model and position next to the given fields
local function vehicleLine(vehicle, fields)
    local i = info[vehicle]
    fields.vehicle_id = i and i.id
    if isElement(vehicle) then
        fields.model = getElementModel(vehicle)
    end
    return logAt(fields, vehicle)
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

local function unixNow()
    return getRealTime().timestamp
end

-- the battery's level now; nil: none installed
local function batteryLevel(inf)
    return battery.current(inf.battery, inf.batterySince, unixNow())
end

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "toastShown", player, code)
    end
end

-- The battery's whole percent for the driver's dashboard (hud), false with none fitted; sent only when it changes.
local function publishBattery(v, inf)
    if not isElement(v) or not inf then
        return
    end
    local level = inf.bay and batteryLevel(inf)
    local shown = level and math.floor(level + 0.5) or false
    if inf.batteryShown ~= shown then
        inf.batteryShown = shown
        setElementData(v, "vehicles.battery", shown, "broadcast", "deny")
    end
end

-- The dashboard's performances (hud/client/dashboard.lua): the key turned (code false: it started, else why not) or
-- the engine died under the driver (NO_FUEL, DAMAGED, STALL, BATTERY_FLAT, NO_BATTERY).
local function engineCranked(player, v, code)
    if isElement(player) then
        triggerClientEvent(player, "engineCranked", v, code or false)
    end
end

local function engineStalled(v, code)
    local driver = getVehicleController(v)
    if driver then
        triggerClientEvent(driver, "engineStalled", v, code)
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

local wheelFreezeTimers = {}
local function updateWheelFreeze(v)
    if isTimer(wheelFreezeTimers[v]) then
        killTimer(wheelFreezeTimers[v])
    end
    wheelFreezeTimers[v] = nil
    local frontLeft, rearLeft, frontRight, rearRight = getVehicleWheelStates(v)
    if frontLeft == 2 and rearLeft == 2 and frontRight == 2 and rearRight == 2 then
        wheelFreezeTimers[v] = setTimer(function()
            wheelFreezeTimers[v] = nil
            if not isElement(v) then
                return
            end
            local fl, rl, fr, rr = getVehicleWheelStates(v)
            if fl == 2 and rl == 2 and fr == 2 and rr == 2 then
                setElementFrozen(v, true)
            end
        end, 2000, 1)
    else
        setElementFrozen(v, false)
    end
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
    if d.hood ~= nil then
        setVehicleDoorState(v, 0, d.hood, false)
    end
    if d.tailgate ~= nil then
        setVehicleDoorState(v, 1, d.tailgate, false)
    end
    for i, s in ipairs(d.lights or {}) do
        setVehicleLightState(v, i - 1, s)
    end
    local t = d.tires
    if t and #t == 4 then
        setVehicleWheelStates(v, t[1], t[2], t[3], t[4])
        updateWheelFreeze(v)
    end
end

-- row: a vehicles table row joined with containers; fresh: a vehicle that has just spawned (its glovebox is stocked)
local function create(row, fresh)
    local v = createVehicle(row.model, row.x, row.y, row.z, 0, 0, row.rz)
    if not v then
        log.event("vehicle.createFailed", { vehicle_id = row.id, uname = row.type_uname, model = row.model }, "warn")
        return nil
    end
    setElementHealth(v, math.max(0, math.min(vlogic.HEALTH_MAX, tonumber(row.health) or vlogic.HEALTH_MAX)))
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
    local gid = row.glovebox_id and tonumber(row.glovebox_id) or nil

    info[v] = {
        id = row.id,
        uname = row.type_uname,
        fuel = tonumber(row.fuel) or 0,
        locked = lockState,
        keyCode = row.key_code and tonumber(row.key_code) or nil,
        keypad = row.keypad_code or nil, -- a walk-in door's keypad: "" installed, no code yet; "1234" its code
        trailerId = row.trailer_id and tonumber(row.trailer_id) or nil,
        containerId = cid,
        gloveboxId = gid,
        spawnId = row.spawn_id and tonumber(row.spawn_id) or nil,
        spawnX = row.spawn_x and tonumber(row.spawn_x) or nil,
        spawnY = row.spawn_y and tonumber(row.spawn_y) or nil,
        leftSpawn = (tonumber(row.left_spawn) or 0) > 0,
        damage = row.damage and row.damage ~= "" and row.damage ~= false and fromJSON(row.damage) or {},
        usedTick = 0,
        bay = false,
        battery = row.battery and tonumber(row.battery) or nil,
        batterySince = row.battery_since and tonumber(row.battery_since) or unixNow(),
        -- starts the starter motor has left (0: dead); a row from before starters were tracked gets a fresh one
        starter = row.starter and tonumber(row.starter) or starter.freshLife(math.random),
    }
    local bayType = exports.data:vehicleType(row.type_uname)
    info[v].bay = battery.hasBay(row.model, bayType, vlogic.DOORLESS_MODELS)
    setElementData(v, "vehicles.bay", info[v].bay, "broadcast", "deny")
    publishBattery(v, info[v])

    carmourSrv.load(v, row.carmour)
    gasSrv.load(v, row.gas_bottles)
    bodySrv.restore(v, info[v]) -- body parts fitted by hand and not yet tightened

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

    -- a cab has a glovebox (vehicle types: glovebox = its size) reached from the front seats; its row is made like the
    -- trunk's, and a vehicle that has just spawned gets a few small items in it
    if vt and (vt.glovebox or 0) > 0 then
        setElementData(v, "vehicles.glovebox", true, "broadcast", "deny")
        if not gid then
            db.exec(
                "INSERT INTO containers (kind, size, owner_vehicle_id) VALUES ('glovebox', ?, ?)",
                { vt.glovebox, row.id },
                function(ok, _, _, insertId)
                    if ok and insertId and isElement(v) and info[v] then
                        info[v].gloveboxId = insertId
                        if fresh then
                            exports.loot:stockGlovebox(insertId, GLOVEBOX_LOOT, math.random(0, 2))
                        end
                    end
                end
            )
        end
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
        battery = battery.spawnLevel(math.random),
        battery_since = unixNow(),
        starter = starter.spawnLife(math.random),
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
        row.battery,
        row.battery_since,
        row.starter,
        n = 16,
    }
    db.exec(INSERT_VEHICLE, params, function(ok, ctx, _, insertId)
        local v = nil
        if ok and insertId then
            ctx.id = insertId
            v = create(ctx, true)
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
                log.event("vehicle.rolled", { spawns = #rows, created = created, cap = cap })
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
                    log.event("vehicle.spawned", vehicleLine(v, { uname = info[v].uname, reason = "refill" }))
                    triggerEvent("vehicleRefillSpawned", v)
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
                    log.event("vehicle.removed", vehicleLine(v, { uname = i.uname, reason = "abandoned" }))
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
                log.event("vehicle.refillTicked", { cap = cap, alive = alive, removed = removed, spawned = spawned })
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
        log.event("vehicle.loaded", { count = n })
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
                battery = i.battery,
                since = i.battery and i.batterySince or nil,
                x = x,
                y = y,
                z = z,
                rz = rz,
                damage = bodySrv and not bodySrv.busy(v) and toJSON(bodySrv.snapshot(v), true):sub(2, -2) or nil,
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
        if isElement(v) then
            bodySrv.scan(v, inf) -- a body part a crash knocked off drops as an item
        end
        if
            isElement(v)
            and inf.bay
            and inf.battery
            and not getVehicleEngineState(v)
            and getVehicleOverrideLights(v) == 2
        then
            -- headlights left on with the engine off flatten the battery; a flat one puts them out
            local level = battery.lightsDrain(batteryLevel(inf), 1.0)
            inf.battery, inf.batterySince = level, unixNow()
            if level <= 0 then
                setVehicleOverrideLights(v, 1)
            end
        end
        if isElement(v) and inf.bay and inf.battery and inf.acc and not getVehicleEngineState(v) then
            -- the key left in ACC with the engine off drains the battery on top of any headlights
            inf.battery, inf.batterySince = battery.accDrain(batteryLevel(inf), 1.0), unixNow()
            publishBattery(v, inf)
        end
        if isElement(v) and getVehicleEngineState(v) then
            local vt = exports.data:vehicleType(inf.uname)
            if inf.bay and inf.battery then
                local vx, vy, vz = getElementVelocity(v)
                local kmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 150
                inf.battery = battery.recharge(batteryLevel(inf), 1.0, kmh)
                inf.batterySince = unixNow()
            end
            if vt and not vt.noEngine and (vt.maxFuel or 0) > 0 then
                local vx, vy, vz = getElementVelocity(v)
                local speedKmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 150
                local newFuel = vlogic.fuelDrain(inf.fuel, vt.fuelConsumption, speedKmh, 1.0)
                inf.fuel = newFuel
                setElementData(v, "vehicles.fuel", newFuel, "broadcast", "deny")

                local driver = getVehicleController(v)
                if newFuel <= 0 then
                    setVehicleEngineState(v, false)
                    engineStalled(v, "NO_FUEL")
                    if driver then
                        toast(driver, "NO_FUEL")
                    end
                else
                    local hp = getElementHealth(v)
                    if hp <= vlogic.HEALTH_CHUNK_1 then
                        setVehicleEngineState(v, false)
                        engineStalled(v, "DAMAGED")
                        if driver then
                            toast(driver, "ENGINE_BROKEN")
                        end
                    elseif hp <= vlogic.HEALTH_CHUNK_2 and speedKmh > 30 then
                        if vlogic.checkStall(hp, speedKmh, math.random) then
                            setVehicleEngineState(v, false)
                            engineStalled(v, "STALL")
                            if driver then
                                toast(driver, "ENGINE_STALL")
                            end
                        end
                    end
                end
            end
        end
        publishBattery(v, inf)
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
    triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Filling petrol can"), ms)
    -- the pump comes in as an upvalue: a table passed as a setTimer argument arrives as a copy, and the stock
    -- taken from a copy never leaves the pump
    local canId, outlet = held.id, pump
    local timer = setTimer(function(p)
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
    end, ms, 1, player)
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

-- The key's ACC position (dash and accessories on, engine off): a tap of Y toggles it, a hold cranks through it.
-- Kept in memory and in element data for the dashboard; it drains the battery slowly (battery.accDrain).
local function setAcc(v, inf, on)
    on = on and true or false
    if inf.acc == on then
        return
    end
    inf.acc = on
    setElementData(v, "vehicles.acc", on, "broadcast", "deny")
end

net.handler("accessoryToggleRequested", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v or getVehicleController(v) ~= player or getVehicleEngineState(v) then
        return
    end
    local inf = info[v]
    if not inf then
        return
    end
    local on = not inf.acc
    setAcc(v, inf, on)
    log.event("vehicle.accToggled", vehicleLine(v, { player = player, acc = on }))
    if on then
        engineCranked(player, v, "ACC")
    end
end, { rate = 3 })

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
        setAcc(v, inf, true) -- cranking goes through ACC: a start that fails leaves the key there
        -- the battery first: without one, or with a flat one, the starter never turns and nothing else shows
        if inf.bay then
            local started, why = battery.canStart(batteryLevel(inf))
            if not started then
                engineCranked(player, v, why)
                -- a flat battery is already shown by the dashboard volt meter: no toast for it
                if why ~= "BATTERY_FLAT" then
                    toast(player, why)
                end
                return
            end
            -- the starter draws current on every turn, whether or not the engine catches
            inf.battery, inf.batterySince = battery.crankDrain(batteryLevel(inf)), unixNow()
            publishBattery(v, inf)
        end
        local ok, err = vlogic.canStartEngine(hp, inf.fuel, vt and vt.noEngine, vt and vt.maxFuel)
        if not ok then
            engineCranked(player, v, err)
            if err == "DAMAGED" then
                toast(player, "ENGINE_BROKEN")
            elseif err == "NO_FUEL" then
                toast(player, "NO_FUEL")
            end
            return
        end
        if inf.bay then
            -- every start wears the starter motor; once its life is spent it only clicks
            local cranked, left, bad = starter.crank(inf.starter)
            if not cranked then
                engineCranked(player, v, bad)
                return toast(player, bad)
            end
            inf.starter = left
            db.exec("UPDATE vehicles SET starter = ? WHERE id = ?", { left, inf.id })
            if left == 0 then
                log.event("vehicle.starterFailed", vehicleLine(v, { player = player }))
            end
        end
        setVehicleEngineState(v, true)
        engineCranked(player, v, false)
    else
        setVehicleEngineState(v, false)
        setAcc(v, inf, false) -- the engine switched off by hand takes the key fully off
    end
end, { rate = 3 })

-- A dead battery gives the headlights a faint double flicker, then they stay off.
local flickering = {}
local function flickerLights(v)
    if flickering[v] then
        return
    end
    flickering[v] = true
    local r, g, b = getVehicleHeadLightColor(v)
    setVehicleHeadLightColor(v, 60, 50, 30)
    local step = 0
    setTimer(function()
        step = step + 1
        if not isElement(v) then
            flickering[v] = nil
            return
        end
        setVehicleOverrideLights(v, step % 2 == 1 and 2 or 1)
        if step >= 4 then
            flickering[v] = nil
            setVehicleHeadLightColor(v, r, g, b)
        end
    end, 120, 4)
end

-- Lights toggle (occupant N key)
net.handler("lightsToggleRequested", function(player)
    local v = getPedOccupiedVehicle(player)
    if not v then
        return
    end
    local curr = getVehicleOverrideLights(v)
    local inf = info[v]
    local engineOn = getVehicleEngineState(v)
    if curr ~= 2 and inf and inf.bay and not engineOn then
        -- with the engine off the lights run off the battery: none or a flat one gives nothing
        local ok, why = battery.canLight(batteryLevel(inf))
        if not ok then
            if why == "BATTERY_FLAT" then
                flickerLights(v)
                triggerClientEvent(player, "lightsFlickered", v) -- the relay click
            else
                toast(player, why)
            end
            return
        end
    end
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
    log.event("vehicle.lockToggled", vehicleLine(v, { player = player, locked = inf.locked, via = "inside" }))
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
-- and when it has come off the hitch (dropped, or torn off in a crash) and stands still. Standing where it was
-- loaded, its cargo is looked for again every CARGO_TICK_MS, so what is dropped, built or taken there in the meantime
-- joins or leaves it. A walk-in trailer that blows up takes everything inside it along.
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
-- stored positions put them, set when loaded and on every store), storedAt, hitched (it has been on a hitch) }
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
    db.query(
        CARGO_SQL .. " AND " .. spatial.bounds(c.x, c.y, vlogic.CARGO_RADIUS),
        { c.x, c.y, vlogic.CARGO_RADIUS },
        function(rows)
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
        end
    )
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

-- a walk-in trailer blew up: its cargo (whose stored positions may lag behind it) and whatever lies in its room as it
-- stands are destroyed, boxes with what they hold
local function destroyCargo(trailer)
    if not isWalkIn(trailer) then
        return
    end
    local c = cargo[trailer]
    cargo[trailer] = nil
    local gone, lost = {}, 0
    for id in pairs(c and c.items or {}) do
        gone[id] = true
        lost = lost + 1
        exports.items:destroyWorldItem(id, "exploded", true)
    end
    publishCargo(trailer)
    local m = getElementMatrix(trailer)
    local x, y = getElementPosition(trailer)
    local int, dim = getElementInterior(trailer), getElementDimension(trailer)
    db.query(
        CARGO_SQL .. " AND " .. spatial.bounds(x, y, vlogic.CARGO_RADIUS),
        { x, y, vlogic.CARGO_RADIUS },
        function(rows)
            for _, r in ipairs(rows or {}) do
                local here = tonumber(r.interior) == int and tonumber(r.dimension) == dim
                if
                    here
                    and not gone[r.id]
                    and not CARGO_SKIP[r.uname]
                    and vlogic.inCargoBox(toLocal(m, r.x, r.y, r.z))
                then
                    exports.items:destroyWorldItem(r.id, "exploded", true)
                end
            end
        end
    )
    return lost
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
        local towed = isElement(trailer) and getVehicleTowingVehicle(trailer)
        c.hitched = c.hitched or towed and true
        local speed = 0
        if isElement(trailer) then
            local vx, vy, vz = getElementVelocity(trailer)
            speed = math.sqrt(vx * vx + vy * vy + vz * vz) * 50 -- MTA velocity is per 1/50 s
        end
        if not isElement(trailer) then
            cargo[trailer] = nil
        elseif not towed and not c.hitched and getTickCount() - c.storedAt > CARGO_HITCH_MS then
            cargo[trailer] = nil -- the hitch it was found for did not come (the trailer never moved)
            publishCargo(trailer)
        elseif not towed and c.hitched and speed < CARGO_STILL then
            endCargo(trailer) -- off the hitch and at rest: the cargo is stored where it ended up
        else
            local x, y, z = getElementPosition(trailer)
            local _, _, rz = getElementRotation(trailer)
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

-- Who got in or out of which vehicle, for staff questions like "which Huntley did he use".
local function logSeat(vehicle, player, seat, action)
    local i = info[vehicle]
    if not i then
        return
    end
    local x, y, z = getElementPosition(vehicle)
    local kind = action == "enter" and "vehicle.entered" or "vehicle.exited"
    log.event(kind, vehicleLine(vehicle, { player = player, seat = seat }))
    local cols = "vehicle_id, character_id, name, seat, action, x, y, z"
    local sql = "INSERT INTO vehicle_events (" .. cols .. ") VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
    db.exec(sql, { i.id, charId(player) or nil, getPlayerName(player), seat, action, x, y, z })
end

addEventHandler("onVehicleEnter", resourceRoot, function(player, seat)
    logSeat(source, player, seat, "enter")
end)

addEventHandler("onVehicleExit", resourceRoot, function(player, seat)
    logSeat(source, player, seat, "exit")
end)

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
    if cargo[source] then
        cargo[source].hitched = true
    end
    local inf, tinf = info[truck], info[source]
    if not inf or not tinf then
        return
    end
    -- the tower pulls the trailer's armour whether the hitch is new or a known one put back (a restart, a re-hitch)
    carmourSrv.refreshTow(source)
    if inf.trailerId == tinf.id then
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
-- an unoccupied truck gets its trailer back (someone dragging it away, or desync). The cargo rides on until the
-- trailer stands still (the cargo timer): stored now, a trailer torn off in a crash would leave it mid-tumble.
addEventHandler("onTrailerDetach", root, function(truck)
    carmourSrv.towEnded(truck)
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

-- Locking a walk-in vehicle (a Key turn, a finished Locksmith Kit hold) shuts its door; any other vehicle has none.
local function shutWalkInDoor(vehicle)
    local inf = info[vehicle]
    local vt = inf and exports.data:vehicleType(inf.uname)
    if vt and vt.door and getVehicleDoorOpenRatio(vehicle, vlogic.WALK_IN_DOOR) > 0 then
        setVehicleDoorOpenRatio(vehicle, vlogic.WALK_IN_DOOR, 0, 600)
        markUsed(vehicle)
    end
end

-- A Keypad on a walk-in door (the towable Airstream): installed by a hold at the door, the owner then sets a 4 digit
-- code on the same keypad UI as a defence's (building client). The door stays locked; the right code opens it (it
-- locks again once it is shut), anyone inside opens it freely. A Lock Breaker takes the keypad out with the lock.
local BREAK_LOCK_SQL = "UPDATE vehicles SET locked = 0, key_code = NULL, keypad_code = NULL WHERE id = ?"
local KEYPAD_HOLD_MS = 6000
local KEYPAD_COOLDOWN_MS = 2000
local function breakDoorLock(vehicle, player)
    local vinf = info[vehicle]
    if not vinf then
        return
    end
    vinf.locked = vlogic.LOCK_OPEN
    vinf.keyCode = nil
    setVehicleLocked(vehicle, false)
    setElementData(vehicle, "vehicles.locked", 0, "broadcast", "deny")
    vinf.keypad = nil
    db.exec(BREAK_LOCK_SQL, { vinf.id })
    log.event("vehicle.lockToggled", vehicleLine(vehicle, { player = player, locked = 0, via = "broken" }))
end

local pendingKeypad = {} -- player -> the vehicle whose keypad prompt is open (setup or entry)
local lastKeypadTry = {} -- player -> tick of the last wrong code
local keypadTries = {} -- player -> { vehicle, wrong codes since the last right one }

local function nearDoorOf(player, vehicle)
    if not isElement(vehicle) or not info[vehicle] or getPedOccupiedVehicle(player) then
        return false
    end
    local px, py, pz = getElementPosition(player)
    local vx, vy, vz = getElementPosition(vehicle)
    return getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= vlogic.DOOR_SERVER_REACH
end

net.handler("vehicleKeypadSetupSubmitted", function(player, vehicle, code)
    if pendingKeypad[player] ~= vehicle or not nearDoorOf(player, vehicle) then
        return
    end
    pendingKeypad[player] = nil
    local inf = info[vehicle]
    if inf.keypad ~= "" then
        return
    end
    local digits = tostring(code or ""):match("^%d%d?%d?%d?$")
    if not digits or digits == "" then
        return
    end
    inf.keypad = string.format("%04d", tonumber(digits))
    inf.locked = vlogic.LOCK_EXTERNAL
    setVehicleLocked(vehicle, true)
    shutWalkInDoor(vehicle)
    setElementData(vehicle, "vehicles.locked", inf.locked, "broadcast", "deny")
    db.exec("UPDATE vehicles SET locked = 1, keypad_code = ? WHERE id = ?", { inf.keypad, inf.id })
    toast(player, "KEYPAD_INSTALLED")
end, { rate = 3 })

net.handler("vehicleKeypadSubmitted", function(player, vehicle, code)
    if pendingKeypad[player] ~= vehicle or not nearDoorOf(player, vehicle) then
        return
    end
    local inf = info[vehicle]
    if not inf.keypad or inf.keypad == "" then
        pendingKeypad[player] = nil
        return
    end
    local now = getTickCount()
    if now - (lastKeypadTry[player] or 0) < KEYPAD_COOLDOWN_MS then
        return
    end
    local digits = tostring(code or ""):match("^%d%d?%d?%d?$")
    if digits and string.format("%04d", tonumber(digits)) == inf.keypad then
        pendingKeypad[player] = nil
        lastKeypadTry[player] = nil
        triggerClientEvent(player, "keypadClosed", player)
        setVehicleDoorOpenRatio(vehicle, vlogic.WALK_IN_DOOR, 1, 600)
        markUsed(vehicle)
        local tries = keypadTries[player]
        local attempts = (tries and tries.vehicle == vehicle and tries.n or 0) + 1
        keypadTries[player] = nil
        log.event("vehicle.keypadOpened", vehicleLine(vehicle, { player = player, attempts = attempts }))
        return
    end
    lastKeypadTry[player] = now
    toast(player, "WRONG_PASSCODE")
    local tries = keypadTries[player]
    if not tries or tries.vehicle ~= vehicle then
        tries = { vehicle = vehicle, n = 0 }
        keypadTries[player] = tries
    end
    tries.n = tries.n + 1
    log.event("vehicle.keypadFailed", vehicleLine(vehicle, { player = player, attempts = tries.n }))
end, { rate = 3 })

addEventHandler("onPlayerQuit", root, function()
    pendingKeypad[source] = nil
    lastKeypadTry[source] = nil
    keypadTries[source] = nil
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
    if open and inf.locked > 0 then
        -- a locked door opens from inside only: nobody is trapped in the room
        local lx, ly, lz = toLocal(getElementMatrix(vehicle), px, py, pz)
        if not vlogic.inCargoBox(lx, ly, lz) then
            if inf.keypad and inf.keypad ~= "" then
                pendingKeypad[player] = vehicle
                return triggerClientEvent(player, "vehicleKeypadOpened", player, vehicle, false)
            end
            return toast(player, inf.locked == vlogic.LOCK_EXTERNAL and "LOCKCUSTOML" or "LOCKUSECROW")
        end
    end
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

-- Car batteries: the bonnet opens with a tap (Case 1c below); under it a hold takes the battery out into the empty
-- hands (vehicleBatteryRequested) and a Car Battery in hand is fitted. Both are a 3 s hold in front of the car.
local BATTERY_HOLD_MS = 3000
local FIT_BATTERY_SQL = "UPDATE vehicles SET battery = ?, battery_since = ? WHERE id = ?"

-- An EMP flattens an installed battery immediately; removing it later must return a flat one too.
function flattenVehicleBattery(vehicle)
    local inf = info[vehicle]
    if not isElement(vehicle) or not inf or not inf.bay or not inf.battery then
        return false
    end
    inf.battery, inf.batterySince = 0, unixNow()
    if getVehicleEngineState(vehicle) then
        engineStalled(vehicle, "BATTERY_FLAT")
    end
    setVehicleEngineState(vehicle, false)
    setVehicleOverrideLights(vehicle, 1)
    publishBattery(vehicle, inf)
    -- The normal vehicle flush persists this charge, including on a clean resource/server stop.
    return true
end

-- the engine is reachable: a car's bonnet stands open or has been taken off (door state 4); a vehicle without one
-- (bikes, boats, the doorless utility models) always is
local function engineReachable(vehicle)
    local inf = info[vehicle]
    if not (inf and inf.bay) then
        return true
    end
    return getVehicleDoorState(vehicle, 0) == 4 or getVehicleDoorOpenRatio(vehicle, 0) > 0.5
end

local function atBonnet(player, vehicle)
    local inf = info[vehicle]
    if not (isElement(vehicle) and inf and inf.bay) or isPedDead(player) or getPedOccupiedVehicle(player) then
        return false
    end
    local px, py, pz = getElementPosition(player)
    local vx, vy, vz = getElementPosition(vehicle)
    local _, _, vrz = getElementRotation(vehicle)
    local near = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) <= vlogic.maxReachDistance("medium")
    return near and vlogic.isFront(vlogic.angleToVehicle(px, py, vx, vy, vrz))
end

local function fitBattery(player, vehicle, held)
    cancelHoldAction(player)
    setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
    triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Fitting battery"), BATTERY_HOLD_MS)
    local timer = setTimer(function(p, veh, itemId)
        activeActions[p] = nil
        if not isElement(p) or not isElement(veh) then
            return
        end
        setPedAnimation(p, nil)
        local vinf = info[veh]
        local cur = exports.items:getHeld(p)
        local open = engineReachable(veh)
        if not vinf or vinf.battery or vinf.locked > 0 or not open or not cur or cur.id ~= itemId then
            return
        end
        if not atBonnet(p, veh) then
            return
        end
        local stored = type(cur.data) == "table" and (type(cur.data[1]) == "table" and cur.data[1] or cur.data) or {}
        vinf.battery = math.max(0, math.min(100, tonumber(stored.charge) or battery.SPAWN_MIN))
        vinf.batterySince = unixNow()
        local args = { vinf.battery, vinf.batterySince, vinf.id }
        db.exec(FIT_BATTERY_SQL, args)
        publishBattery(veh, vinf)
        exports.items:destroyItem(itemId, p)
        toast(p, "BATTERY_FITTED")
        log.event("vehicle.partInstalled", vehicleLine(veh, { player = p, part = "battery", item_id = itemId }))
    end, BATTERY_HOLD_MS, 1, player, vehicle, held.id)
    activeActions[player] = { actionType = "battery", vehicle = vehicle, timer = timer }
end

local function removeBattery(player, vehicle)
    cancelHoldAction(player)
    setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
    triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Removing battery"), BATTERY_HOLD_MS)
    local timer = setTimer(function(p, veh)
        activeActions[p] = nil
        if not isElement(p) or not isElement(veh) then
            return
        end
        setPedAnimation(p, nil)
        local vinf = info[veh]
        local open = engineReachable(veh)
        local cid = charId(p)
        if not vinf or not vinf.battery or vinf.locked > 0 or not open or not cid or exports.items:getHeld(p) then
            return
        end
        if not atBonnet(p, veh) then
            return
        end
        local level = batteryLevel(vinf)
        vinf.battery, vinf.batterySince = nil, unixNow()
        db.exec("UPDATE vehicles SET battery = NULL WHERE id = ?", { vinf.id })
        publishBattery(veh, vinf)
        if getVehicleEngineState(veh) then
            engineStalled(veh, "NO_BATTERY")
            setVehicleEngineState(veh, false)
        end
        db.call("item_create_held", { "Battery", cid }, function(res, c)
            if res and res.ok and isElement(c.p) then
                local newId = res.payload.item_id
                local data = { charge = level }
                db.exec("UPDATE items SET data = ? WHERE id = ?", { toJSON(data), newId })
                exports.items:setHeld(c.p, { id = newId, uname = "Battery", hp = 2, data = data })
                toast(c.p, string.format("BATTERY_LEVEL:%d", math.floor(level + 0.5)))
                log.event("vehicle.partRemoved", vehicleLine(c.v, { player = c.p, part = "battery", item_id = newId }))
            elseif not (res and res.ok) then
                local code = res and res.code or "DB_ERROR"
                local line = vehicleLine(c.v, { player = c.p, part = "battery", ok = false, code = code })
                log.event("vehicle.partRemoved", line, "warn")
            end
        end, { p = p, v = veh })
    end, BATTERY_HOLD_MS, 1, player, vehicle)
    activeActions[player] = { actionType = "battery", vehicle = vehicle, timer = timer }
end

-- Starter motors: one wears out after a random number of engine starts (shared/logic/starter.lua) and a few cars
-- spawn with a dead one. A Starter Motor in hand at the open bonnet of a car whose starter is dead replaces it: a hold
-- in front of the car with the engine off; the dead one is scrap and goes nowhere.
local STARTER_HOLD_MS = 6000

local function replaceStarter(player, vehicle, held)
    cancelHoldAction(player)
    setPedAnimation(player, "INT_SHOP", "SHOP_CASHIER", -1, true, false, false, false)
    local ms = exports.character:skillTimeModifier(player, STARTER_HOLD_MS, "Repair")
    triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Replacing starter motor"), ms)
    local timer = setTimer(function(p, veh, itemId)
        activeActions[p] = nil
        if not isElement(p) or not isElement(veh) then
            return
        end
        setPedAnimation(p, nil)
        local vinf = info[veh]
        local cur = exports.items:getHeld(p)
        local open = engineReachable(veh)
        if not vinf or vinf.locked > 0 or not open or not cur or cur.id ~= itemId then
            return
        end
        if not starter.isBad(vinf.starter) or getVehicleEngineState(veh) or not atBonnet(p, veh) then
            return
        end
        -- the new starter goes in only once the held one is really gone
        exports.items:destroyItem(itemId, p, function(gone, code)
            local line = vehicleLine(veh, { player = p, part = "starter_motor", item_id = itemId })
            if not gone then
                line.ok, line.code = false, code or "DESTROY_FAILED"
                return log.event("vehicle.partInstalled", line, "warn")
            end
            local now = isElement(veh) and info[veh]
            if not now then
                return log.event("vehicle.partInstalled", line, "warn")
            end
            now.starter = starter.freshLife(math.random)
            db.exec("UPDATE vehicles SET starter = ? WHERE id = ?", { now.starter, now.id })
            if isElement(p) then
                exports.character:gainSkill(p, "Repair")
                toast(p, "STARTER_FITTED")
            end
            log.event("vehicle.partInstalled", line)
        end, "used")
    end, ms, 1, player, vehicle, held.id)
    activeActions[player] = { actionType = "starter", vehicle = vehicle, timer = timer }
end

net.handler("vehicleBatteryRequested", function(player, vehicle)
    local inf = info[vehicle]
    if not atBonnet(player, vehicle) or exports.items:getHeld(player) or activeActions[player] then
        return
    end
    if inf.locked > 0 then
        return toast(player, "BONNET_LOCKED")
    end
    if not engineReachable(vehicle) then
        return toast(player, "BONNET_SHUT")
    end
    if not inf.battery then
        return toast(player, "NO_BATTERY_IN")
    end
    removeBattery(player, vehicle)
end, { rate = 3 })

-- A Wrench held a moment at a body part takes it off the vehicle (server/bodyparts.lua)
net.handler("vehiclePartRemoveRequested", function(player, vehicle)
    if not isElement(vehicle) or not info[vehicle] or isPedDead(player) then
        return
    end
    bodySrv.remove(player, vehicle)
end, { rate = 3 })

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
    -- a walk-in vehicle (the towable Airstream) has its lock at the door, not on a driver side, and no trunk
    local walkIn = vt and vt.door == true
    local atDoor = false
    if walkIn then
        local dlx, dly = toLocal(getElementMatrix(vehicle), px, py, pz)
        atDoor = vlogic.nearWalkInDoor(dlx, dly)
    end
    local held = exports.items:getHeld(player)
    local uname = held and held.uname
    local hp = getElementHealth(vehicle)

    if bodySrv.isPart(uname) then
        return bodySrv.install(player, vehicle, held)
    end

    -- Case W: the Welder's torch welds the nearest attached panel on (server/carmour.lua); the Welder itself has to
    -- be laid down first; an Angle Grinder grinds a welded panel off, pass by pass; a Crowbar pries an attached,
    -- unwelded panel off before it reaches for the door's lock
    if carmourSrv.hasTorch(player) then
        return carmourSrv.weld(player, vehicle)
    end
    if uname == "Welder" and carmourSrv.hasSlots(vehicle) then
        return toast(player, "WELD_TORCH")
    end
    if uname == "Grinder" and carmourSrv.hasSlots(vehicle) then
        return carmourSrv.grind(player, vehicle)
    end
    if uname == "Crowbar" and carmourSrv.canPry(player, vehicle) then
        return carmourSrv.pry(player, vehicle)
    end
    if uname == "Crowbar" and not atDoor and carmourSrv.weldedNear(player, vehicle) then
        return toast(player, "PRY_WELDED")
    end

    -- Case G: a Gas Bottle in hand goes onto a free A-frame mount of a trailer, empty hands take one off
    if vt and vt.trailer and vt.door and (uname == "GasBottle" or not held) then
        local mlx, mly = toLocal(getElementMatrix(vehicle), px, py, pz)
        local mount = vlogic.nearGasMount(mlx, mly)
        if mount then
            return gasSrv.interact(player, vehicle, mount, held or nil)
        end
    end

    -- Wheels need a tyre wrench in hand; a replacement wheel is laid beside the vehicle.
    -- (at the rear it falls through to the trunk, Case 3)
    if uname == "Wheel" and not vlogic.isRear(angle) then
        return toast(player, "WHEEL_LAY")
    end
    if uname == "Wrench" and not vlogic.isFront(angle) and not vlogic.isRear(angle) then
        if
            activeActions[player]
            or bodySrv.busy(vehicle)
            or inf.locked > 0
            or getPedOccupiedVehicle(player)
            or getVehicleEngineState(vehicle)
        then
            return
        end
        local lx, ly = toLocal(getElementMatrix(vehicle), px, py, pz)
        local wheel = vlogic.nearestDamagedWheel(lx, ly, { 2, 2, 2, 2 })
        local positions = { { -1, 1 }, { -1, -1 }, { 1, 1 }, { 1, -1 } }
        local pos = positions[wheel]
        if (lx - pos[1]) ^ 2 + (ly - pos[2]) ^ 2 > 2.25 then
            return
        end
        local tires = { getVehicleWheelStates(vehicle) }
        local removing = tires[wheel] ~= 2
        local action = { actionType = "wheel", vehicle = vehicle }
        activeActions[player] = action
        local count = vlogic.lugNutCount(getElementModel(vehicle))
        local duration = exports.character:skillTimeModifier(player, count * 1000, "Repair")
        local started = getTickCount()
        local label = removing and lang.formatFor(player, "Removing wheel: %d lug nuts", count)
            or lang.formatFor(player, "Installing wheel: %d lug nuts", count)
        triggerClientEvent(player, "vehicleHoldStarted", player, label, duration)
        setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
        action.timer = setTimer(function()
            local cur = isElement(player) and exports.items:getHeld(player)
            if
                not isElement(vehicle)
                or not info[vehicle]
                or not cur
                or cur.id ~= held.id
                or getPedOccupiedVehicle(player)
                or getVehicleEngineState(vehicle)
                or inf.locked > 0
                or getElementDimension(player) ~= getElementDimension(vehicle)
                or getElementInterior(player) ~= getElementInterior(vehicle)
                or isPedDead(player)
            then
                return cancelHoldAction(player)
            end
            local x, y, z = getElementPosition(player)
            local vx1, vy1, vz1 = getElementVelocity(vehicle)
            if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > 0.8 or vx1 * vx1 + vy1 * vy1 + vz1 * vz1 > 0.0001 then
                return cancelHoldAction(player)
            end
            if getTickCount() - started < duration then
                return
            end
            cancelHoldAction(player)
            local current = { getVehicleWheelStates(vehicle) }
            if current[wheel] ~= tires[wheel] then
                return
            end
            local function fitted()
                current[wheel] = removing and 2 or 0
                setVehicleWheelStates(vehicle, unpack(current))
                if not removing then
                    -- Reassert the wheel dummy's visibility client-side as well as repairing its MTA wheel state.
                    triggerClientEvent(root, "vehicleWheelInstalled", vehicle, wheel)
                end
                updateWheelFreeze(vehicle)
                inf.damage = bodySrv.snapshot(vehicle)
                db.exec("UPDATE vehicles SET damage = ? WHERE id = ?", { toJSON(inf.damage), inf.id })
                exports.character:gainSkill(player, "Repair")
            end
            if removing then
                db.exec(
                    "INSERT INTO items (type_uname, x, y, z, rz, interior, dimension) VALUES ('Wheel', ?, ?, ?, 0, ?, ?)",
                    { x, y, z - 0.8, getElementInterior(player), getElementDimension(player) },
                    function(ok, _, _, id)
                        if ok and isElement(vehicle) then
                            fitted()
                            exports.items:resendWorldItem(tonumber(id))
                        end
                    end
                )
            else
                db.query(
                    "SELECT id FROM items WHERE type_uname = 'Wheel' AND interior = ? AND dimension = ? AND POW(x - ?, 2) + POW(y - ?, 2) + POW(z - ?, 2) < 9 LIMIT 1",
                    { getElementInterior(player), getElementDimension(player), x, y, z },
                    function(rows)
                        if rows and rows[1] and isElement(vehicle) then
                            db.exec(
                                "DELETE FROM items WHERE id = ? AND holder_char_id IS NULL AND container_id IS NULL",
                                { rows[1].id },
                                function(ok, _, affected)
                                    if ok and tonumber(affected) == 1 then
                                        exports.items:forgetWorldItem(tonumber(rows[1].id))
                                        if isElement(vehicle) then
                                            fitted()
                                        end
                                    end
                                end
                            )
                        end
                    end
                )
            end
        end, 100, 0)
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
        inf.damage = bodySrv.snapshot(vehicle)
        db.exec("UPDATE vehicles SET damage = ? WHERE id = ?", { toJSON(inf.damage), inf.id })
        exports.items:destroyItem(held.id, player)
        toast(player, "REPAIRED")
        return
    end

    -- Case 1c: the bonnet of an unlocked car opens and shuts with empty hands; a Car Battery in hand is fitted while
    -- it is open (taking one out is the hold, vehicleBatteryRequested)
    if vlogic.isFront(angle) and inf.bay and (not held or uname == "Battery") then
        if inf.locked > 0 then
            return toast(player, "BONNET_LOCKED")
        end
        local gone = getVehicleDoorState(vehicle, 0) == 4 -- bonnet taken off: nothing to open or shut
        local open = engineReachable(vehicle)
        if not held then
            if gone then
                return
            end
            if not open then
                local _, _, prz = getElementRotation(player)
                if not vlogic.facingVehicle(px, py, prz, vx, vy) then
                    return
                end
            end
            setVehicleDoorOpenRatio(vehicle, 0, open and 0 or 1, 500)
            markUsed(vehicle)
            return
        end
        if not open then
            return toast(player, "BONNET_SHUT")
        end
        if inf.battery then
            return toast(player, "BATTERY_ALREADY")
        end
        return fitBattery(player, vehicle, held)
    end

    -- Case 1d: a Starter Motor in hand replaces a dead one under the open bonnet
    if vlogic.isFront(angle) and inf.bay and uname == "StarterMotor" then
        if inf.locked > 0 then
            return toast(player, "BONNET_LOCKED")
        end
        if not engineReachable(vehicle) then
            return toast(player, "BONNET_SHUT")
        end
        if getVehicleEngineState(vehicle) then
            return toast(player, "STARTER_ENGINE_ON")
        end
        if not starter.isBad(inf.starter) then
            return toast(player, "STARTER_OK")
        end
        if activeActions[player] or not atBonnet(player, vehicle) then
            return
        end
        return replaceStarter(player, vehicle, held)
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
        -- a car with a bonnet is repaired under it: the player opens it first (an empty-handed tap, Case 1c)
        if not engineReachable(vehicle) then
            return toast(player, inf.locked > 0 and "BONNET_LOCKED" or "BONNET_SHUT")
        end
        cancelHoldAction(player)
        setPedAnimation(player, "INT_SHOP", "SHOP_CASHIER", -1, true, false, false, false)
        -- upstream repair.pwn ran the Repair skill through the per-tick health step, so skill made repairs slower;
        -- the port shortens the hold instead
        local ms = exports.character:skillTimeModifier(player, 3000, "Repair")
        triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Repairing"), ms)
        local timer = setTimer(function(p, veh)
            activeActions[p] = nil
            if not isElement(p) or not isElement(veh) then
                return
            end
            setPedAnimation(p, nil)
            if not engineReachable(veh) then
                return toast(p, "BONNET_SHUT") -- shut on them mid-repair
            end
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
    if (walkIn and atDoor) or (not walkIn and vlogic.isDriverSide(angle)) then
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
                shutWalkInDoor(vehicle)
                toast(player, "LOCKED")
            end
            setElementData(vehicle, "vehicles.locked", inf.locked, "broadcast", "deny")
            db.exec("UPDATE vehicles SET locked = ? WHERE id = ?", { inf.locked, inf.id })
            local line = vehicleLine(vehicle, { player = player, locked = inf.locked, via = "key", item_id = held.id })
            log.event("vehicle.lockToggled", line)
            return
        end

        if uname == "LocksmithKit" or uname == "WheelLock" then
            local doorless = vlogic.isDoorless(getElementModel(vehicle), vt and vt.notLockable)
            local ok, err = vlogic.canCraftKey(inf.locked, uname, doorless, inf.keyCode, vlogic.isCutLock(held.data))
            if not ok then
                return toast(player, err)
            end
            cancelHoldAction(player)
            setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
            triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Crafting key"), 3000)
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
                -- the kit (or the cut lock) has to be in the hand still: one dropped during the hold would
                -- otherwise stay there and a key come out of nothing
                local cur = exports.items:getHeld(p)
                if not cur or cur.id ~= kitId then
                    return
                end
                local code = math.random(100000, 999999)
                local vinf = info[veh]
                if vinf then
                    vinf.locked = vlogic.LOCK_EXTERNAL
                    vinf.keyCode = code
                    setVehicleLocked(veh, true)
                    shutWalkInDoor(veh)
                    setElementData(veh, "vehicles.locked", 1, "broadcast", "deny")
                    db.exec("UPDATE vehicles SET locked = 1, key_code = ? WHERE id = ?", { code, vinf.id })
                    local line = vehicleLine(veh, { player = p, locked = 1, via = "locksmith", item_id = kitId })
                    log.event("vehicle.lockToggled", line)
                end
                -- the key is cut only once the kit is really gone
                exports.items:destroyItem(kitId, p, function(gone)
                    if not gone or not isElement(p) then
                        return
                    end
                    db.call("item_create_held", { "Key", cid }, function(res, c)
                        if res and res.ok and isElement(c.p) then
                            local newKeyId = res.payload.item_id
                            local keyData = { code = code, model = vt and vt.model or 0 }
                            db.exec("UPDATE items SET data = ? WHERE id = ?", { toJSON(keyData), newKeyId })
                            exports.items:setHeld(c.p, { id = newKeyId, uname = "Key", hp = 5, data = keyData })
                            toast(c.p, "KEY_CRAFTED")
                        end
                    end, { p = p })
                end, "used")
            end, 3000, 1, player, vehicle, held.id)
            activeActions[player] = { actionType = "locksmith", vehicle = vehicle, timer = timer }
            return
        end

        if walkIn and (uname == "Keypad" or uname == "AdvancedKeypad") then
            if inf.keypad then
                return toast(player, "KEYPAD_ALREADY")
            end
            cancelHoldAction(player)
            setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
            local ms = exports.character:skillTimeModifier(player, KEYPAD_HOLD_MS, "Construction")
            triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Installing keypad"), ms)
            local timer = setTimer(function(p, veh, kitId)
                activeActions[p] = nil
                if not isElement(p) or not isElement(veh) then
                    return
                end
                setPedAnimation(p, nil)
                local vinf = info[veh]
                local cur = exports.items:getHeld(p)
                if not vinf or vinf.keypad or not cur or cur.id ~= kitId or not nearDoorOf(p, veh) then
                    return
                end
                vinf.keypad = ""
                db.exec("UPDATE vehicles SET keypad_code = '' WHERE id = ?", { vinf.id })
                exports.items:destroyItem(kitId, p)
                exports.character:gainSkill(p, "Construction")
                log.event("vehicle.keypadInstalled", vehicleLine(veh, { player = p, item_id = kitId }))
                pendingKeypad[p] = veh
                triggerClientEvent(p, "vehicleKeypadOpened", p, veh, true)
            end, ms, 1, player, vehicle, held.id)
            activeActions[player] = { actionType = "keypad", vehicle = vehicle, timer = timer }
            return
        end

        if uname == "Crowbar" or uname == "LockBreaker" then
            if carmourSrv.armoured(vehicle) then
                return toast(player, "DOORARMOURED")
            end
            local ok, err = vlogic.canBreakLock(inf.locked, uname)
            if not ok then
                return toast(player, err)
            end
            cancelHoldAction(player)
            setPedAnimation(player, "POLICE", "DOOR_KICK", -1, true, false, false, false)
            triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Breaking lock"), 3000)
            local timer = setTimer(function(p, veh)
                activeActions[p] = nil
                if not isElement(p) or not isElement(veh) then
                    return
                end
                setPedAnimation(p, nil)
                if info[veh] then
                    breakDoorLock(veh, p)
                    toast(p, "LOCKBROKEN")
                end
            end, 3000, 1, player, vehicle)
            activeActions[player] = { actionType = "lockbreak", vehicle = vehicle, timer = timer }
            return
        end
    end

    -- Case 3: Rear (Trunk)
    if vlogic.isRear(angle) and not walkIn then
        -- Reach the trunk from beside the vehicle, not while standing on a car.
        local contact = getPedContactElement(player)
        if isElement(contact) and getElementType(contact) == "vehicle" then
            return
        end
        local _, _, prz = getElementRotation(player)
        if getPedOccupiedVehicle(player) or not vlogic.facingVehicle(px, py, prz, vx, vy) then
            return
        end
        if (uname == "Crowbar" or uname == "LockBreaker") and inf.locked > 0 then
            local ok, err = vlogic.canBreakLock(inf.locked, uname)
            if not ok then
                return toast(player, err)
            end
            cancelHoldAction(player)
            setPedAnimation(player, "POLICE", "DOOR_KICK", -1, true, false, false, false)
            triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Breaking trunk"), 3000)
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
                    vinf.keypad = nil
                    db.exec(BREAK_LOCK_SQL, { vinf.id })
                    log.event("vehicle.lockToggled", vehicleLine(veh, { player = p, locked = 0, via = "broken" }))
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
        -- the trunk stays open once opened, like the bonnet: empty hands shut an open one (unless someone is still
        -- looking in it), and a carried Wheel only goes into one already open
        local trunkOpen = getVehicleDoorOpenRatio(vehicle, 1) > 0.5
        if uname == "Wheel" and not trunkOpen then
            return toast(player, "TRUNK_SHUT")
        end
        if not held and trunkOpen then
            if exports.items:trunkViewers(vehicle) == 0 then
                setVehicleDoorOpenRatio(vehicle, 1, 0, 500)
                markUsed(vehicle)
            end
            return
        end
        setVehicleDoorOpenRatio(vehicle, 1, 1, 500)
        markUsed(vehicle)
        local tname = lang.formatFor(player, "%s Trunk", vt and vt.name or lang.textFor(player, "Vehicle"))
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
        triggerClientEvent(player, "vehicleHoldStarted", player, lang.textFor(player, "Refuelling"), 3000)
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
            log.event("vehicle.refuelled", vehicleLine(veh, { player = p, litres = transfer, fuel = nextVehFuel }))
        end, 3000, 1, player, vehicle, held)
        activeActions[player] = { actionType = "refuel", vehicle = vehicle, timer = timer }
        return
    end
end, { rate = 3 })

net.handler("holdActionCancelRequested", function(player)
    cancelHoldAction(player)
end, { rate = 5 })

-- The glovebox: the interact key from a front seat (driver or front passenger) opens the container in the dash.
net.handler("gloveboxOpenRequested", function(player)
    local vehicle = getPedOccupiedVehicle(player)
    local inf = vehicle and info[vehicle]
    if not inf or isPedDead(player) or getPedOccupiedVehicleSeat(player) > 1 then
        return
    end
    if not inf.gloveboxId then
        return toast(player, "NO_GLOVEBOX")
    end
    local vt = exports.data:vehicleType(inf.uname)
    markUsed(vehicle)
    local title = lang.formatFor(player, "%s Glovebox", vt and vt.name or lang.textFor(player, "Vehicle"))
    exports.items:openGlovebox(player, vehicle, inf.gloveboxId, title, vt and vt.glovebox or 4)
    log.event("vehicle.gloveboxOpened", vehicleLine(vehicle, { player = player, container_id = inf.gloveboxId }))
end, { rate = 3 })

-- closing the trunk window leaves the trunk itself open (an empty-handed tap at the rear shuts it, Case 3)
net.handler("trunkCloseRequested", function(player)
    exports.items:closeTrunk(player)
end, { rate = 3 })

addEventHandler("onVehicleEnter", resourceRoot, function(player, seat)
    markUsed(source)
    -- a driver getting in shuts a trunk left open, unless someone is still looking in it
    if seat == 0 and getVehicleDoorOpenRatio(source, 1) > 0 and exports.items:trunkViewers(source) == 0 then
        setVehicleDoorOpenRatio(source, 1, 0, 500)
    end
    publishBattery(source, info[source]) -- a parked battery drains unseen: the dashboard gets today's level
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

local overlay
do
    local f = fileOpen("server/overlay.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    overlay = assert(loadstring(src, "=vehicles/server/overlay.lua"))()({ db = db })
end

addEventHandler("onResourceStart", resourceRoot, function()
    -- MTA starts the engine whenever a driver gets in, skipping the Y-key checks (battery, fuel, damage, starter wear):
    -- the engine only starts from engineToggleRequested
    setWorldSpecialPropertyEnabled("vehicle_engine_autostart", false)
    if not db.connect("vehicles") then
        return
    end
    overlay.start()
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
    local lost = destroyCargo(source) -- what was inside a walk-in trailer goes up with it
    log.event("vehicle.exploded", vehicleLine(source, { uname = i.uname, cargo = lost or 0 }))
    if not i.leftSpawn then
        coolPoint(i.spawnId)
    end
    setTimer(function(v, id)
        db.exec("DELETE FROM vehicles WHERE id = ?", { id })
        if isElement(v) then
            log.event("vehicle.removed", vehicleLine(v, { uname = i.uname, reason = "exploded" }))
            forget(v)
            destroyElement(v)
        end
    end, WRECK_MS, 1, source, i.id)
end)

local function loadCarmour()
    local f = fileOpen("server/carmour.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    local make = assert(loadstring(src, "=vehicles/server/carmour.lua"))()
    local ctx = { db = db, info = info, toast = toast, activeActions = activeActions, carmour = carmour }
    ctx.log, ctx.vehicleLine = log, vehicleLine
    ctx.place, ctx.geo, ctx.cancelHoldAction, ctx.breakLock = carmourPlace, carmourGeo, cancelHoldAction, breakDoorLock
    return make(ctx)
end

carmourSrv = loadCarmour()

-- a held defence attached where the player aims at a vehicle: the camera ray in the vehicle's frame
net.handler("carmourAttachRequested", function(player, vehicle, o, d)
    if isElement(vehicle) and getElementType(vehicle) == "vehicle" then
        carmourSrv.attach(player, vehicle, o, d)
    end
end, { rate = 4 })

-- empty hands take the torch off a Welder lying near; N or F away from a vehicle puts it back
net.handler("weldTorchGrabRequested", function(player, welderId)
    carmourSrv.grabTorch(player, welderId)
end, { rate = 4 })

net.handler("weldTorchStowRequested", function(player)
    carmourSrv.stowTorch(player)
end, { rate = 4 })

-- empty hands at a Gas Cylinder lying near a Welder hook it up to the Welder, or unhook it
net.handler("weldCylinderHookRequested", function(player, cylinderId)
    carmourSrv.hookCylinder(player, cylinderId)
end, { rate = 4 })

local function loadGasBottles()
    local f = fileOpen("server/gasbottles.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    local make = assert(loadstring(src, "=vehicles/server/gasbottles.lua"))()
    local ctx = { db = db, info = info, toast = toast, activeActions = activeActions }
    ctx.cancelHoldAction, ctx.vlogic, ctx.toLocal = cancelHoldAction, vlogic, toLocal
    return make(ctx)
end

gasSrv = loadGasBottles()

-- The gas on a trailer's A-frame mounts, { l = { gas = kg, hp = n }, r = ... } with a key per occupied mount (false
-- for a vehicle without mounts): what a stove or heater draws from
function getGasBottles(vehicle)
    return gasSrv.get(vehicle)
end

-- Explosives: the blast's damage to a vehicle's armour (panels first, then the walk-in door's hitpoint); the number
-- of panels it shed
function damageCarmour(vehicle, dmg)
    return carmourSrv.damage(vehicle, dmg)
end

-- true while at least one panel is welded on: the vehicle takes no damage and cannot blow up
function isArmoured(vehicle)
    return carmourSrv.armoured(vehicle)
end

function hasCarmourSlots(vehicle)
    return carmourSrv.hasSlots(vehicle)
end

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
    local removed = 0
    for v in pairs(info) do
        if isElement(v) then
            destroyElement(v)
            removed = removed + 1
        end
    end
    log.event("vehicle.removed", { reason = "staff", count = removed })
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

-- Shares the roadside action/cancellation lifecycle; the item and saved panel change commit together.
do
    local f = fileOpen("shared/logic/bodyparts.lua", true)
    local logic = fileRead(f, fileGetSize(f))
    fileClose(f)
    local bp = assert(loadstring(logic, "=vehicles/bodyparts_logic.lua"))()
    f = fileOpen("server/bodyparts.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    local ctx = { bp = bp, db = db, util = util, info = info, activeActions = activeActions }
    ctx.log, ctx.vehicleLine = log, vehicleLine
    ctx.cancel, ctx.toLocal, ctx.toWorld, ctx.toast = cancelHoldAction, toLocal, toWorld, toast
    bodySrv = assert(loadstring(src, "=vehicles/bodyparts.lua"))()(ctx)
end
