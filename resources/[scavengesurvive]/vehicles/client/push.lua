-- Pushing vehicles (server/push.lua has the rules, shared/logic/push.lua the numbers):
-- - no shove by walking or running into one: an empty vehicle standing (almost) still is frozen on this client while
--   a ped on foot is against it, and let go when nobody is (each client holds it in its own physics, so neither the
--   syncer's nor the runner's game moves it);
-- - "Push" in the interaction list at an empty vehicle's front or rear (empty hands); once the server allows it this
--   client syncs the vehicle and, while the player walks into it, rolls it along its own axis at the push's speed.
--   Walking off its end, turning away, jumping or "Stop pushing" ends it;
-- - every streamed player with "vehicles.pushing" holds both arms out against it (bone rotations each frame, like
--   the carry pose in items).
local vlogic, plogic
do
    local function load(path, name)
        local f = fileOpen(path, true)
        local src = fileRead(f, fileGetSize(f))
        fileClose(f)
        return assert(loadstring(src, name))()
    end
    vlogic = load("shared/logic/vehicle.lua", "=vehicles/vehicle.lua")
    plogic = load("shared/logic/push.lua", "=vehicles/push.lua")
end
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

-- m/s -> GTA velocity units (metres per 1/50 s)
local UNIT = 1 / 50
local HOLD_MARGIN = 0.45 -- metres past the bounding box a ped on foot holds a vehicle still
local RELEASE_MARGIN = 0.9 -- metres past it before the vehicle is let go
local STILL = 2.5 * UNIT -- a vehicle moving faster than this is in motion and is never held

-- The arms reaching forward at chest height, shoulder-wide, the hands turned up with the palms forward (found on
-- the studio set, 2026-11-18): { x, y, z } per GTA bone id, as setElementBoneRotation takes them.
local PUSH_BONES = {
    [21] = { -66.4, 107.8, 68.5 }, -- right clavicle
    [22] = { 53.4, -44.1, -12.0 }, -- right upper arm
    [23] = { 0.0, -30.0, 0.0 }, -- right forearm
    [24] = { -149.1, 3.6, 70.0 }, -- right hand
    [31] = { 61.4, 112.8, -70.3 }, -- left clavicle
    [32] = { -42.7, -41.0, 12.0 }, -- left upper arm
    [33] = { 0.0, -30.0, 0.0 }, -- left forearm
    [34] = { 164.0, 8.0, -70.0 }, -- left hand
}

local held = {} -- vehicle -> true while this client freezes it against a ped
local push = nil -- { vehicle, speed, sign, current } while the local player pushes
local pushers = {} -- streamed player -> the vehicle it pushes (for the pose)

local function isEmpty(v)
    if getVehicleController(v) then
        return false
    end
    return next(getVehicleOccupants(v) or {}) == nil
end

-- A point in a vehicle's frame: lateral, longitudinal, vertical.
local function toLocal(v, x, y, z)
    local m = getElementMatrix(v)
    local dx, dy, dz = x - m[4][1], y - m[4][2], z - m[4][3]
    return dx * m[1][1] + dy * m[1][2] + dz * m[1][3],
        dx * m[2][1] + dy * m[2][2] + dz * m[2][3],
        dx * m[3][1] + dy * m[3][2] + dz * m[3][3]
end

-- How far a point lies outside a vehicle's bounding box (0 inside), and its local coordinates.
local function outside(v, x, y, z)
    local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(v)
    if not minX then
        return math.huge
    end
    local lx, ly, lz = toLocal(v, x, y, z)
    local ox = math.max(minX - lx, 0, lx - maxX)
    local oy = math.max(minY - ly, 0, ly - maxY)
    local oz = math.max(minZ - lz - 1, 0, lz - maxZ - 1) -- a ped's centre sits about a metre above its feet
    return math.max(ox, oy, oz), lx, ly, minX, minY, maxX, maxY
end

local function allFlat(v)
    local a, b, c, d = getVehicleWheelStates(v)
    return a == 2 and b == 2 and c == 2 and d == 2
end

local function release(v)
    held[v] = nil
    -- the server freezes a vehicle on four flat tyres (server/main.lua updateWheelFreeze): leave that one be
    if isElement(v) and not allFlat(v) then
        setElementFrozen(v, false)
    end
end

local function holdable(v)
    if
        not isEmpty(v)
        or getElementData(v, "vehicles.pushedBy")
        or isElementAttached(v)
        or getVehicleTowingVehicle(v)
    then
        return false
    end
    local vx, vy, vz = getElementVelocity(v)
    return held[v] or (vx * vx + vy * vy + vz * vz) < STILL * STILL
end

-- No shoving by running into a vehicle: hold the empty, still ones a ped on foot is touching.
local function holdParked()
    local touched = {}
    for _, ped in ipairs(getElementsByType("player", root, true)) do
        if not isPedInVehicle(ped) and not isPedDead(ped) then
            local x, y, z = getElementPosition(ped)
            for _, v in ipairs(getElementsWithinRange(x, y, z, 8, "vehicle")) do
                if isElementStreamedIn(v) and holdable(v) then
                    local margin = held[v] and RELEASE_MARGIN or HOLD_MARGIN
                    if outside(v, x, y, z) <= margin then
                        touched[v] = true
                    end
                end
            end
        end
    end
    for v in pairs(held) do
        if not touched[v] or not isElement(v) then
            release(v)
        end
    end
    for v in pairs(touched) do
        if not held[v] then
            held[v] = not isElementFrozen(v) or nil -- one the server froze stays the server's
            if held[v] then
                setElementFrozen(v, true)
            end
        end
    end
end

local function endPush(tell)
    if not push then
        return
    end
    push = nil
    setPedControlState(localPlayer, "walk", false)
    if tell then
        triggerServerEvent("vehiclePushEnded", localPlayer)
    end
end

-- The local push, once per frame: keep the player facing the vehicle and roll it while they lean in.
local function drivePush(dt)
    local v = push.vehicle
    if
        not isElement(v)
        or isPedInVehicle(localPlayer)
        or isPedDead(localPlayer)
        or getElementData(localPlayer, "character.knockedOut")
        or getPedControlState(localPlayer, "jump")
        or getPedControlState(localPlayer, "aim_weapon")
        or not isEmpty(v)
    then
        return endPush(true)
    end
    local x, y, z = getElementPosition(localPlayer)
    local _, lx, ly, minX, minY, maxX, maxY = outside(v, x, y, z)
    if not minX then
        return endPush(true)
    end
    local gap = push.sign > 0 and (minY - ly) or (ly - maxY)
    if gap < -0.6 or gap > plogic.REACH or lx < minX - 0.4 or lx > maxX + 0.4 then
        return endPush(true)
    end
    setPedControlState(localPlayer, "walk", true) -- a pushing ped keeps to a walk
    if not isElementSyncer(v) then
        return
    end
    if isElementFrozen(v) and not held[v] then
        return
    end
    local leaning = getPedControlState(localPlayer, "forwards") and gap < 0.7
    local target = leaning and push.speed or 0
    local step = plogic.ACCEL * dt
    push.current = math.max(math.min(target, push.current + step), push.current - step * 2)
    if push.current <= 0.01 and not leaning then
        push.current = 0
        return -- the vehicle's own brakes hold it
    end
    local m = getElementMatrix(v)
    local fx, fy = m[2][1], m[2][2]
    local len = math.sqrt(fx * fx + fy * fy)
    if len < 0.01 then
        return
    end
    local s = push.sign * push.current * UNIT / len
    local _, _, vz = getElementVelocity(v)
    setElementVelocity(v, fx * s, fy * s, vz)
end

addEventHandler("onClientPreRender", root, function(msSinceLast)
    holdParked()
    if push then
        drivePush(math.min(msSinceLast, 100) / 1000)
    end
end)

addEventHandler("vehiclePushStarted", root, function(speed, sign)
    if held[source] then
        release(source)
    end
    push = { vehicle = source, speed = tonumber(speed) or 1, sign = sign == -1 and -1 or 1, current = 0 }
    -- turned once to face along the vehicle, towards it; from then on the player steers the walk
    local _, _, rz = getElementRotation(source)
    setElementRotation(localPlayer, 0, 0, push.sign > 0 and rz or rz + 180, "default", true)
end)

addEventHandler("vehiclePushStopped", localPlayer, function()
    endPush(false)
end)

-- The pose: arms out against the vehicle, unless a scripted animation or a vehicle has the ped.
local function track(player, value)
    pushers[player] = isElement(value) and value or nil
end

addEventHandler("onClientElementDataChange", root, function(key, _, value)
    if key == "vehicles.pushing" and getElementType(source) == "player" then
        track(source, value)
    elseif key == "vehicles.pushedBy" and value and getElementType(source) == "vehicle" and held[source] then
        release(source) -- the pusher's game needs it loose
    end
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "player" then
        track(source, getElementData(source, "vehicles.pushing"))
    end
end)

addEventHandler("onClientPlayerQuit", root, function()
    pushers[source] = nil
end)

addEventHandler("onClientPedsProcessed", root, function()
    for player in pairs(pushers) do
        if
            isElement(player)
            and (player == localPlayer or isElementStreamedIn(player))
            and not isPedInVehicle(player)
            and not isPedDead(player)
            and not getPedAnimation(player)
        then
            for bone, rot in pairs(PUSH_BONES) do
                setElementBoneRotation(player, bone, rot[1], rot[2], rot[3])
            end
            updateElementRpHAnim(player)
        else
            pushers[player] = nil
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, p in ipairs(getElementsByType("player", root, true)) do
        track(p, getElementData(p, "vehicles.pushing"))
    end
    track(localPlayer, getElementData(localPlayer, "vehicles.pushing"))
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for v in pairs(held) do
        release(v)
    end
end)

-- The interaction list's entries: "Push" at an empty vehicle's front or rear, "Stop pushing" while pushing.
function pushActions(heldUname)
    if heldUname or isPedInVehicle(localPlayer) then
        return {}
    end
    if push and isElement(push.vehicle) then
        return {
            {
                id = "vehicle:push:stop",
                label = lang.text("Stop pushing"),
                event = "vehiclePushEnded",
                target = push.vehicle,
            },
        }
    end
    local actions = {}
    local px, py, pz = getElementPosition(localPlayer)
    for _, v in ipairs(getElementsWithinRange(px, py, pz, 8, "vehicle")) do
        if
            isElementStreamedIn(v)
            and getElementData(v, "vehicles.id")
            and plogic.TYPES[getVehicleType(v)]
            and isEmpty(v)
            and not getElementData(v, "vehicles.pushedBy")
            and getElementDimension(v) == getElementDimension(localPlayer)
            and getPedContactElement(localPlayer) ~= v
            and outside(v, px, py, pz) <= plogic.REACH
        then
            local handling = getVehicleHandling(v)
            local canPush = plogic.canPushMass(getElementModel(v), handling and handling.mass)
            local vx, vy = getElementPosition(v)
            local _, _, rz = getElementRotation(v)
            local angle = vlogic.angleToVehicle(px, py, vx, vy, rz)
            if plogic.side(angle) then
                local vehicleType = exports.data:vehicleType(getElementData(v, "vehicles.type"))
                local name = vehicleType and lang.text(vehicleType.name) or getVehicleName(v)
                local id = "vehicle:" .. tostring(getElementData(v, "vehicles.id")) .. ":"
                if canPush then
                    actions[#actions + 1] = {
                        id = id .. "push",
                        label = lang.text("Push") .. " · " .. name,
                        event = "vehiclePushRequested",
                        target = v,
                    }
                end
                -- at the rear the interact key alone would have opened the trunk: it joins the list (as with towing)
                if vlogic.isRear(angle) and getElementData(v, "vehicles.containerId") then
                    actions[#actions + 1] = {
                        id = id .. "trunk",
                        label = lang.text("Open trunk") .. " · " .. name,
                        event = "vehicleInteractRequested",
                        target = v,
                        action = "trunk_open",
                    }
                end
            end
        end
    end
    return actions
end
