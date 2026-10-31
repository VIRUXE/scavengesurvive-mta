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

-- MTA wheel states are ordered front-left, rear-left, front-right, rear-right.
-- Pick the damaged wheel nearest the player in the vehicle's local XY plane.
function M.nearestDamagedWheel(x, y, tires)
    if type(tires) ~= "table" or #tires ~= 4 then
        return nil
    end
    local positions = { { -1, 1 }, { -1, -1 }, { 1, 1 }, { 1, -1 } }
    local best, bestDistance
    for i, state in ipairs(tires) do
        if state ~= 0 then
            local dx, dy = x - positions[i][1], y - positions[i][2]
            local distance = dx * dx + dy * dy
            if not bestDistance or distance < bestDistance then
                best, bestDistance = i, distance
            end
        end
    end
    return best
end

-- Server-side reach for roadside interaction, from the vehicle's centre. The client asks within 5.5 m (hud keys.lua);
-- the slack covers latency and position sync, a little more on longer vehicles.
local REACH = { small = 6.5, medium = 7.0, large = 8.0 }

function M.maxReachDistance(size)
    return REACH[size] or REACH.medium
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

-- Help tip for a driver getting in (upstream key-actions.pwn _ShowRepairTip): bands inclusive at the top, and
-- anything up to HEALTH_MAX counts as slightly broken; nil above it. Upstream pairs "very broken" with the wrench.
function M.repairTipKey(health)
    local h = health or 1000
    if h <= M.HEALTH_CHUNK_2 then
        return "TUTORVEHVER"
    elseif h <= M.HEALTH_CHUNK_3 then
        return "TUTORVEHBRO"
    elseif h <= M.HEALTH_CHUNK_4 then
        return "TUTORVEHBIT"
    elseif h <= M.HEALTH_MAX then
        return "TUTORVEHSLI"
    end
    return nil
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

-- Model lengths (bounding box along Y, metres) of the hitch vehicles and trailers: the server has no model sizes,
-- upstream read them from GetVehicleModelInfo(VEHICLE_MODEL_INFO_SIZE).
M.MODEL_LENGTH = {
    [403] = 9.00,
    [405] = 5.65,
    [422] = 5.25,
    [470] = 5.18,
    [479] = 5.69,
    [496] = 4.67,
    [500] = 4.67,
    [542] = 6.04,
    [549] = 5.49,
    [554] = 5.85,
    [579] = 5.71,
    [591] = 10.65,
    [610] = 7.56, -- the towable Airstream (house_shell)
    [611] = 2.58,
}

-- A walk-in door (vehicle types with door = true, the towable Airstream): the vehicle's front-left door, which the
-- interact key opens within DOOR_REACH of its hinge (client) and the server accepts within DOOR_SERVER_REACH of the
-- vehicle's centre (it has no component positions).
M.WALK_IN_DOOR = 2
M.DOOR_REACH = 1.8
M.DOOR_SERVER_REACH = 6.0

-- What a walk-in trailer carries while hitched: the world items inside its room, in the vehicle's frame (the towable
-- Airstream: walls at x ±1.06, the end sections reach y -2.6 and 3.95, the floor is z -0.45 and the ceiling 1.8;
-- a little margin for things lying against the walls), looked for within CARGO_RADIUS of its centre.
M.CARGO_BOX = { x = 1.15, y0 = -2.7, y1 = 4.05, z0 = -0.6, z1 = 1.9 }
M.CARGO_RADIUS = 5.5

function M.inCargoBox(lx, ly, lz)
    local b = M.CARGO_BOX
    return math.abs(lx) <= b.x and ly >= b.y0 and ly <= b.y1 and lz >= b.z0 and lz <= b.z1
end

-- Upstream trailer.pwn: a trailer is in reach while the two centres are closer than both lengths and a metre.
function M.towReach(truckModel, trailerModel)
    return (M.MODEL_LENGTH[truckModel] or 5.0) + (M.MODEL_LENGTH[trailerModel] or 5.0) + 1.0
end

return M
