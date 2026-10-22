-- Loot vehicles: rolled once over the seeded vehicle_spawns points (upstream rolls at every gamemode start), kept
-- in the `vehicles` table so a restart rebuilds the same vehicles, flushed every minute and on stop. State lives in
-- this file's locals; exports are thin wrappers. Fuel use, locks and trunks are later work (#30).
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local spawn
do
    local f = fileOpen("shared/logic/spawn.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    spawn = assert(loadstring(src, "=vehicles/spawn.lua"))()
end

local FLUSH_MS = 60000
local WRECK_MS = 30000
local SELECT_VEHICLES = "SELECT id, type_uname, model, x, y, z, rz, health, fuel, locked, damage FROM vehicles"
local INSERT_VEHICLE = "INSERT INTO vehicles (spawn_id, type_uname, model, x, y, z, rz, health, fuel, locked, damage)"
    .. " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"

local settings = {}
local types = nil -- spawn.index(...) of the data resource's vehicle types
local info = {} -- vehicle element -> { id, uname, fuel }
local rolling = false

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

-- row: a vehicles table row (NULL arrives as false, JSON as a string)
local function create(row)
    local v = createVehicle(row.model, row.x, row.y, row.z, 0, 0, row.rz)
    if not v then
        util.log("vehicles", "warn", "createVehicle failed for %s (model %d)", row.type_uname, row.model)
        return nil
    end
    setElementHealth(v, math.max(0, math.min(1000, tonumber(row.health) or 1000)))
    setVehicleEngineState(v, false)
    setVehicleLocked(v, tonumber(row.locked) == 1)
    if row.damage and row.damage ~= "" then
        applyDamage(v, fromJSON(row.damage))
    end
    setElementData(v, "vehicles.id", row.id, "broadcast", "deny")
    setElementData(v, "vehicles.type", row.type_uname, "broadcast", "deny")
    setElementData(v, "vehicles.fuel", tonumber(row.fuel) or 0, "broadcast", "deny")
    info[v] = { id = row.id, uname = row.type_uname, fuel = tonumber(row.fuel) or 0 }
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
                        locked = spawn.locked(t, damage, math.random) and 1 or 0,
                        damage = damage and toJSON(damage) or nil,
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
                        n = 11,
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
        for _, row in ipairs(rows) do
            if create(row) then
                n = n + 1
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
                locked = isVehicleLocked(v) and 1 or 0,
            }
        end
    end
    if #rows == 0 then
        return
    end
    -- MTA's toJSON wraps its argument in an outer array; the procedure reads '$[0][*]'
    db.call("vehicle_flush", { toJSON(rows) }, function(res)
        if not res or not res.ok then
            util.log("vehicles", "error", "vehicle_flush failed: %s", res and res.code or "db")
        end
    end)
end

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

-- a wreck stays for a while, then the vehicle is gone for good (its spawn point rolls again on the next respawnAll)
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

-- Dev/staff: drop every loot vehicle and roll all spawn points again.
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
