-- The blood a bleeding character shows (upstream core/char/bleed.pwn, shared/logic/bleeding.lua): while the server
-- flags a player "character.bleeding", every client sprays blood off their chest and drops a blood pool at their feet
-- each second, in a ring of POOLS per player. Everything here is local to this client. Upstream's spray was SA-MP
-- object 18706 carrying the prt_blood particle; MTA's prt_blood effect draws white sparks, so this uses fxAddBlood.
local f = fileOpen("shared/logic/bleeding.lua", true)
local bleeding = assert(loadstring(fileRead(f, fileGetSize(f)), "=character/bleeding.lua"))()
fileClose(f)
local SPRAY_BONE = 3 -- spine, upstream attached the spray to bone 1 (spine) with a few centimetres of offset
local SPRAY_MS = 100
local pools = {} -- player -> { slot, [1..POOLS] = object }
local sprays = {} -- player -> true while their chest sprays

local function poolModel()
    local res = getResourceFromName("models")
    if not res or getResourceState(res) ~= "running" then
        return false
    end
    return exports.models:resolve(bleeding.POOL_MODEL)
end

local function clearPools(player)
    local ring = pools[player]
    if not ring then
        return
    end
    for i = 1, bleeding.POOLS do
        if isElement(ring[i]) then
            destroyElement(ring[i])
        end
    end
    pools[player] = nil
end

local function shows(player)
    return isElementStreamedIn(player)
        and getElementData(player, "character.bleeding") == true
        and not isPedDead(player)
        and not getPedOccupiedVehicle(player)
end

local function dropPool(player, model)
    local ring = pools[player] or { slot = 0 }
    pools[player] = ring
    ring.slot = bleeding.nextSlot(ring.slot, bleeding.POOLS)
    if isElement(ring[ring.slot]) then
        destroyElement(ring[ring.slot])
    end
    local x, y, z = getElementPosition(player)
    local dx, dy, rz = bleeding.poolOffset(math.random)
    local pool = createObject(model, x + dx, y + dy, z - bleeding.POOL_DROP, 0, 0, rz)
    if pool then
        setElementCollisionsEnabled(pool, false)
        setElementInterior(pool, getElementInterior(player))
        setElementDimension(pool, getElementDimension(player))
    end
    ring[ring.slot] = pool
end

setTimer(function()
    local model = poolModel()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        if shows(player) then
            if model then
                dropPool(player, model)
            end
            sprays[player] = true
        else
            sprays[player] = nil
        end
    end
end, bleeding.TICK_MS, 0)

-- a squirt off the chest, forward and down, every SPRAY_MS
setTimer(function()
    for player in pairs(sprays) do
        if isElement(player) and shows(player) then
            local x, y, z = getPedBonePosition(player, SPRAY_BONE)
            local _, _, rz = getElementRotation(player)
            local yaw = math.rad(rz)
            fxAddBlood(x, y, z, -math.sin(yaw) * 0.3, math.cos(yaw) * 0.3, -0.2, 2, 1)
        else
            sprays[player] = nil
        end
    end
end, SPRAY_MS, 0)

addEventHandler("onClientPlayerQuit", root, function()
    clearPools(source)
    sprays[source] = nil
end)

-- the pack is (re)loading or stopping: its model ids are about to change, and a pool is only a few seconds of trail
addEventHandler("sampModelsChanged", root, function()
    for player in pairs(pools) do
        clearPools(player)
    end
end)
