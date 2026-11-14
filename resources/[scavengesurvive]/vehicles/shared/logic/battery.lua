-- Vehicle battery: the level a parked car loses, what running recharges, when the engine refuses to start.
-- Pure logic: no MTA calls at file scope. Levels are percent; times are unix seconds.
local M = {}

M.GRACE_S = 24 * 3600 -- a battery loses nothing for this long after the engine last ran
M.DRAIN_PER_H = 1.0 -- percent lost per hour after the grace
M.RECHARGE_PER_S = 10 / 60 -- percent gained per second of driving (full in about ten minutes)
M.IDLE_RECHARGE_FACTOR = 0.25 -- an engine left running while standing still charges at this share of that
M.DRIVING_KMH = 5 -- above this the car counts as driven
M.LIGHTS_DRAIN_PER_H = 12.0 -- percent lost per hour by headlights left on with the engine off, from the first second
M.ACC_DRAIN_PER_H = 3.0 -- percent lost per hour by the key left in ACC (dash and accessories on) with the engine off
M.CRANK_DRAIN = 2.0 -- percent one turn of the starter takes, whether the engine catches or not
M.START_MIN = 10 -- under this the engine will not turn over
M.SPAWN_MIN = 15
M.SPAWN_MISSING_CHANCE = 0.35 -- share of spawned vehicles with no battery in the bay
-- Capacity in amp-hours. Every rate above is for a DEFAULT_CAPACITY battery; a smaller one drains and charges
-- faster in percent, a bigger one slower. NULL capacity (rows and items from before capacities) is the default.
M.DEFAULT_CAPACITY = 60
M.CAPACITIES = { 35, 40, 45, 45, 55, 55, 60, 60, 70, 80, 95 } -- spawn weights: small worn batteries are common

-- a capacity as stored (number, numeric string, nil or false) -> amp-hours
function M.capacityOf(cap)
    cap = tonumber(cap)
    if not cap or cap <= 0 then
        return M.DEFAULT_CAPACITY
    end
    return cap
end

-- percent-per-unit rates scale with how small the battery is
local function scale(cap)
    return M.DEFAULT_CAPACITY / M.capacityOf(cap)
end

-- the level now of a battery stored at `stored` percent at `since`; nil: no battery
function M.current(stored, since, now, cap)
    if not stored then
        return nil
    end
    local idle = math.max(0, (now or 0) - (since or now or 0) - M.GRACE_S)
    return math.max(0, stored - idle / 3600 * M.DRAIN_PER_H * scale(cap))
end

-- the alternator: driving charges at the full rate, an engine idling at a quarter of it
function M.recharge(level, dt, speedKmh, cap)
    local rate = M.RECHARGE_PER_S * scale(cap)
    if (speedKmh or 0) <= M.DRIVING_KMH then
        rate = rate * M.IDLE_RECHARGE_FACTOR
    end
    return math.min(100, (level or 0) + rate * (dt or 1))
end

-- headlights burning with the engine off
function M.lightsDrain(level, dt, cap)
    return math.max(0, (level or 0) - M.LIGHTS_DRAIN_PER_H * scale(cap) / 3600 * (dt or 1))
end

-- the key left in ACC with the engine off
function M.accDrain(level, dt, cap)
    return math.max(0, (level or 0) - M.ACC_DRAIN_PER_H * scale(cap) / 3600 * (dt or 1))
end

-- one turn of the key to START: the starter motor's draw
function M.crankDrain(level, cap)
    return math.max(0, (level or 0) - M.CRANK_DRAIN * scale(cap))
end

function M.spawnLevel(rng)
    return M.SPAWN_MIN + (rng or math.random)() * (100 - M.SPAWN_MIN)
end

function M.spawnCapacity(rng)
    return M.CAPACITIES[math.floor((rng or math.random)() * #M.CAPACITIES) + 1]
end

-- a newly spawned vehicle's battery: charge, capacity; nil, nil when the bay is empty
function M.spawnBattery(rng)
    rng = rng or math.random
    if rng() < M.SPAWN_MISSING_CHANCE then
        return nil, nil
    end
    return M.spawnLevel(rng), M.spawnCapacity(rng)
end

-- a vehicle with an engine and a bonnet over it: bikes, boats and the open utility models (doorless) have none
function M.hasBay(model, vt, noBonnet)
    if not vt or vt.noEngine or (vt.maxFuel or 0) <= 0 then
        return false
    end
    return not (noBonnet and noBonnet[model])
end

-- headlights with the engine off: any charge left will light them, a dead battery gives nothing
function M.canLight(level)
    if not level then
        return false, "NO_BATTERY"
    end
    if level <= 0 then
        return false, "BATTERY_FLAT"
    end
    return true
end

function M.canStart(level)
    if not level then
        return false, "NO_BATTERY"
    end
    if level < M.START_MIN then
        return false, "BATTERY_FLAT"
    end
    return true
end

return M
