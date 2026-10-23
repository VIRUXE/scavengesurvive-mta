-- Vehicle logic: fuel drain, engine stall, repair tools, lock states, key matching and trailer hitches.
-- Pure logic: no MTA calls at file scope.
local M = {}

M.LOCK_OPEN = 0
M.LOCK_EXTERNAL = 1
M.LOCK_DEFAULT = 2

M.HEALTH_MIN = 250
M.HEALTH_CHUNK_1 = 300 -- wrecked, won't start
M.HEALTH_CHUNK_2 = 450 -- broken, screwdriver / stall chance
M.HEALTH_CHUNK_3 = 650 -- a bit broken, hammer
M.HEALTH_CHUNK_4 = 800 -- slightly broken, wrench
M.HEALTH_MAX = 990 -- maximum field repair health

-- Calculate angle relative to vehicle heading.
-- 0 deg = front, 90 deg = passenger/right, 180 deg = rear/trunk, 270 deg = driver/left.
function M.angleToVehicle(px, py, vx, vy, vrz)
    local rad = math.rad(vrz or 0)
    local sinR, cosR = math.sin(rad), math.cos(rad)
    local dx, dy = px - vx, py - vy
    local localX = dx * cosR + dy * sinR
    local localY = -dx * sinR + dy * cosR
    local angle = math.deg(math.atan2(localX, localY))
    if angle < 0 then
        angle = angle + 360
    end
    return angle
end

function M.isFront(angle)
    return angle < 25 or angle > 335
end

function M.isRear(angle)
    return angle > 155 and angle < 205
end

function M.isDriverSide(angle)
    return angle > 225 and angle < 315
end

-- Upstream: fuel -= ((fuelcons / 100) * (((speed / 60) / 60) / 10) + 0.0001) per tick (1s)
function M.fuelDrain(fuel, consumptionRate, speedKmh, dtSeconds)
    if (fuel or 0) <= 0 then
        return 0
    end
    local dt = dtSeconds or 1
    local rate = consumptionRate or 15
    local speed = speedKmh or 0
    local speedDrain = (rate / 100) * (speed / 36000)
    local drain = (speedDrain + 0.0001) * dt
    return math.max(0, (fuel or 0) - drain)
end

function M.canStartEngine(health, fuel, noEngine, maxFuel)
    if noEngine or (maxFuel or 0) <= 0 then
        return true
    end
    if (health or 0) < M.HEALTH_CHUNK_1 then
        return false, "DAMAGED"
    end
    if (fuel or 0) <= 0 then
        return false, "NO_FUEL"
    end
    return true
end

-- Low-health engine stall check: between 300 and 450 HP at speed > 30 km/h
function M.checkStall(health, speedKmh, rng)
    local h = health or 1000
    if h <= M.HEALTH_CHUNK_1 then
        return true
    end
    if h <= M.HEALTH_CHUNK_2 and (speedKmh or 0) > 30 then
        local chance = 20 - ((h - M.HEALTH_CHUNK_1) / 7.5) -- chance from 20% down to 0% at 450
        if (rng or math.random)() * 100 < chance then
            return true
        end
    end
    return false
end

-- Required tool for repairing bonnet at current health
function M.repairToolForHealth(health)
    local h = health or 1000
    if h < M.HEALTH_CHUNK_2 then
        return "Wrench"
    elseif h < M.HEALTH_CHUNK_3 then
        return "Screwdriver"
    elseif h < M.HEALTH_CHUNK_4 then
        return "Hammer"
    elseif h < M.HEALTH_MAX then
        return "Wrench"
    end
    return nil -- fully repaired
end

function M.canBreakLock(lockState, itemUname)
    if lockState == M.LOCK_OPEN then
        return false, "NOT_LOCKED"
    end
    if itemUname == "Crowbar" then
        if lockState == M.LOCK_EXTERNAL then
            return false, "LOCKBREAKNO"
        end
        return true
    elseif itemUname == "LockBreaker" then
        return true
    end
    return false, "NEED_TOOL"
end

function M.canCraftKey(lockState, itemUname, notLockable, currentKeyCode)
    if notLockable then
        return false, "LOCKNODOORS"
    end
    if itemUname ~= "LocksmithKit" and itemUname ~= "WheelLock" then
        return false, "NEED_TOOL"
    end
    if (currentKeyCode or 0) ~= 0 or lockState == M.LOCK_EXTERNAL then
        return false, "LOCKALREADY"
    end
    return true
end

function M.canUseKey(keyData, vehicleKeyCode)
    if not vehicleKeyCode or vehicleKeyCode == 0 then
        return false, "LOCKVNOLOCK"
    end
    local code = type(keyData) == "table" and keyData.code or tonumber(keyData)
    if not code or code == 0 then
        return false, "LOCKKEYNCUT"
    end
    if code ~= vehicleKeyCode then
        return false, "LOCKKEYNFIT"
    end
    return true
end

function M.canAttachTrailer(truckType, trailerType, distance, maxDist)
    if not truckType or not trailerType then
        return false
    end
    if not truckType.trailerHitch then
        return false
    end
    if not trailerType.trailer then
        return false
    end
    if truckType.trailerHitch ~= trailerType.size then
        return false
    end
    if distance and maxDist and distance > maxDist then
        return false
    end
    return true
end

return M
