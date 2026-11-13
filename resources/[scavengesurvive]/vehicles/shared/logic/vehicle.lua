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
M.HEALTH_CHUNK_4 = 800 -- slightly broken, ratchet
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

-- Ped heading uses the same rotation as vehicles: forward is (-sin(rz), cos(rz)).
function M.facingVehicle(px, py, prz, vx, vy)
    local dx, dy = vx - px, vy - py
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.001 then
        return false
    end
    local heading = math.rad(prz)
    return (-math.sin(heading) * dx + math.cos(heading) * dy) / distance >= math.cos(math.rad(45))
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
        return "Spanner"
    elseif h < M.HEALTH_CHUNK_3 then
        return "Screwdriver"
    elseif h < M.HEALTH_CHUNK_4 then
        return "Hammer"
    elseif h < M.HEALTH_MAX then
        return "Ratchet"
    end
    return nil -- fully repaired
end

-- Help tip for a driver getting in (upstream key-actions.pwn _ShowRepairTip). Derived from repairToolForHealth so the
-- tip always names the tool that works at this health; nil when no tool would do anything (including the 990 cap).
local REPAIR_TIP_KEYS = {
    Spanner = "TUTORVEHVER",
    Screwdriver = "TUTORVEHBRO",
    Hammer = "TUTORVEHBIT",
    Ratchet = "TUTORVEHSLI",
}

function M.repairTipKey(health)
    local tool = M.repairToolForHealth(health)
    return tool and REPAIR_TIP_KEYS[tool]
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

-- GTA SA models with no doors (RC toys left out), checked against gta3.img (no door_*_ok atomic in the dff): bicycles,
-- motorbikes, the quad, boats, the hovercraft and the open cars and utility vehicles. A Lock and Chain locks these,
-- a Locksmith Kit everything else.
M.DOORLESS_MODELS = {
    [481] = true, -- BMX
    [509] = true, -- Bike
    [510] = true, -- Mountain Bike
    [448] = true, -- Pizzaboy
    [461] = true, -- PCJ-600
    [462] = true, -- Faggio
    [463] = true, -- Freeway
    [468] = true, -- Sanchez
    [521] = true, -- FCR-900
    [522] = true, -- NRG-500
    [523] = true, -- HPV1000
    [581] = true, -- BF-400
    [586] = true, -- Wayfarer
    [471] = true, -- Quad
    [430] = true, -- Predator
    [446] = true, -- Squalo
    [452] = true, -- Speeder
    [453] = true, -- Reefer
    [454] = true, -- Tropic
    [472] = true, -- Coastguard
    [473] = true, -- Dinghy
    [484] = true, -- Marquis
    [493] = true, -- Jetmax
    [595] = true, -- Launch
    [539] = true, -- Vortex
    [424] = true, -- BF Injection
    [457] = true, -- Caddy
    [485] = true, -- Baggage
    [486] = true, -- Dozer
    [530] = true, -- Forklift
    [531] = true, -- Tractor
    [568] = true, -- Bandito
    [571] = true, -- Kart
    [572] = true, -- Mower
}

-- a vehicle type flagged not lockable upstream, or a doorless model
function M.isDoorless(model, notLockable)
    return notLockable == true or M.DOORLESS_MODELS[model] == true
end

-- a Lock and Chain's data (either JSON shape): cut once combined with a Locksmith Kit
function M.isCutLock(data)
    local t = type(data) == "table" and (type(data[1]) == "table" and data[1] or data) or {}
    return tonumber(t.cut) == 1
end

-- upstream locksmith.pwn: the Locksmith Kit refuses doorless vehicles; the Lock and Chain (WheelLock) is the lock
-- for them, and the port keeps it to them (upstream let it lock cars too). A Lock and Chain locks once cut: upstream
-- tests the cell the other way round (an uncut one locked, a cut one got LOCKCHNOKEY, "combine it with a Locksmith
-- Kit", which is what cut it), so the port follows the message.
function M.canCraftKey(lockState, itemUname, doorless, currentKeyCode, lockCut)
    if itemUname == "LocksmithKit" then
        if doorless then
            return false, "LOCKNODOORS"
        end
    elseif itemUname == "WheelLock" then
        if not doorless then
            return false, "LOCKCHNDOOR"
        end
        if not lockCut then
            return false, "LOCKCHNOKEY"
        end
    else
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
    [610] = 7.56, -- the towable Airstream (airstream_trailer)
    [611] = 2.58,
}

-- A walk-in door (vehicle types with door = true, the towable Airstream): the vehicle's front-left door, which the
-- interact key opens within DOOR_REACH of its hinge (client) and the server accepts within DOOR_SERVER_REACH of the
-- vehicle's centre (it has no component positions).
M.WALK_IN_DOOR = 2
M.DOOR_REACH = 1.8
M.DOOR_SERVER_REACH = 6.0
-- Vehicles whose front-left door is a walk-in door the same key works, without the trailer's lock, keypad, armour or
-- cargo rules (a type flagged door = true gets all of those, and loses its trunk): the Marquis's cabin door
-- (marquis_cabin).
M.CABIN_DOOR_MODELS = { [484] = true }
-- A boat's door ratio is not synced to clients, so the cabin door's state is element data (0 shut, 1 open) that
-- marquis_cabin turns into a swing of the leaf on every client.
M.CABIN_DOOR_DATA = "vehicles.cabinDoor"
-- the hinge frame of that door in the model (tools/marquis_cabin/cabin.py): not the standard door_lf_dummy, which the game
-- resets on a boat every frame
M.CABIN_DOOR_COMPONENT = "cabin_door"

-- The door's hinge in the vehicle's frame (airstream_trailer/towable.lua `door`; the server has no component
-- positions): a lock tool or key works within DOOR_LOCK_REACH of it, in the XY plane, inside or outside.
M.WALK_IN_HINGE = { x = -1.149, y = 1.460 }
M.DOOR_LOCK_REACH = 2.5

function M.nearWalkInDoor(lx, ly)
    local h = M.WALK_IN_HINGE
    local dx, dy = lx - h.x, ly - h.y
    return dx * dx + dy * dy <= M.DOOR_LOCK_REACH * M.DOOR_LOCK_REACH
end

-- The two propane mounts on a trailer's A-frame (vehicles.gas_bottles keys "l" and "r"), where the tanks of the towable
-- Airstream stand in the vehicle's frame (tools/trailer_shells/towable.py splits them out as the gas_l / gas_r frames):
-- a Gas Bottle goes on, or comes off, within GAS_REACH of one in the XY plane, inside or outside.
M.GAS_MOUNTS = { l = { x = -0.251, y = 4.349 }, r = { x = 0.232, y = 4.331 } }
M.GAS_REACH = 1.7

-- The slot ("l" or "r") of the mount nearest to a point of the vehicle's frame, nil beyond GAS_REACH of both.
function M.nearGasMount(lx, ly)
    local best, bestD = nil, M.GAS_REACH * M.GAS_REACH
    for slot, m in pairs(M.GAS_MOUNTS) do
        local d = (lx - m.x) ^ 2 + (ly - m.y) ^ 2
        if d <= bestD then
            best, bestD = slot, d
        end
    end
    return best
end

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

-- Per-model wheel fasteners; ordinary passenger vehicles default to five.
M.LUG_NUTS = { [496] = 4, [549] = 4, [422] = 6, [554] = 6, [470] = 8,
    [403] = 10, [514] = 10, [515] = 10, [431] = 10, [437] = 10 }
function M.lugNutCount(model)
    return M.LUG_NUTS[model] or 5
end

return M
