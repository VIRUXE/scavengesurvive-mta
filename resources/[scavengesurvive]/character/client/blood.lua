-- The blood a bleeding character shows (upstream core/char/bleed.pwn, shared/logic/bleeding.lua). The pools are the
-- server's (server/blood.lua picks where each lands, so everyone sees the same trail); this client puts them on the
-- ground under that spot, once the collision there has streamed in. While the server flags a player
-- "character.bleeding" this client also sprays blood off their chest. Upstream's spray was SA-MP object 18706
-- carrying the prt_blood particle; MTA's prt_blood effect draws white sparks, so this uses fxAddBlood.
local f = fileOpen("shared/logic/bleeding.lua", true)
local bleeding = assert(loadstring(fileRead(f, fileGetSize(f)), "=character/bleeding.lua"))()
fileClose(f)
local surface = loadstring(exports.lib:getModule("surface"), "=lib/surface.lua")()
local SPRAY_BONE = 3 -- spine, upstream attached the spray to bone 1 (spine) with a few centimetres of offset
local SPRAY_MS = 100
local trails = {} -- trail id -> { [slot] = { x, y, z, rz, interior, dimension } } as the server sent them
local objects = {} -- trail id -> { [slot] = object }
local spots = {} -- pool object -> its trail entry, to ground it again when it streams in
local sprays = {} -- player -> true while their chest sprays

local function poolModel()
    local res = getResourceFromName("models")
    if not res or getResourceState(res) ~= "running" then
        return false
    end
    return exports.models:resolve(bleeding.POOL_MODEL)
end

-- onto whatever is under the spot (buildings and objects, not peds or cars) and along its slope; left flat at the
-- fallback height while the collision there is not loaded
local function ground(obj, p)
    local hx, hy, hz, nx, ny, nz = surface.below(p[1], p[2], p[3])
    if hx then
        setElementMatrix(obj, surface.matrix(hx, hy, hz, nx, ny, nz, p[4], bleeding.POOL_LIFT))
    end
end

local function destroyPool(id, slot)
    local obj = objects[id] and objects[id][slot]
    if isElement(obj) then
        spots[obj] = nil
        destroyElement(obj)
    end
end

local function placePool(id, slot, p, model)
    destroyPool(id, slot)
    objects[id] = objects[id] or {}
    local obj = model and createObject(model, p[1], p[2], p[3] - bleeding.POOL_DROP, 0, 0, p[4])
    objects[id][slot] = obj or nil
    if obj then
        setElementCollisionsEnabled(obj, false)
        setElementInterior(obj, p[5])
        setElementDimension(obj, p[6])
        spots[obj] = p
        ground(obj, p)
    end
end

local function clearTrail(id)
    for slot in pairs(objects[id] or {}) do
        destroyPool(id, slot)
    end
    objects[id], trails[id] = nil, nil
end

addEventHandler("bloodPoolDropped", resourceRoot, function(id, slot, p)
    trails[id] = trails[id] or {}
    trails[id][slot] = p
    placePool(id, slot, p, poolModel())
end)

addEventHandler("bloodPoolsSynced", resourceRoot, function(all)
    local model = poolModel()
    for _, t in ipairs(all) do
        clearTrail(t.id)
        trails[t.id] = t.pools
        for slot, p in pairs(t.pools) do
            placePool(t.id, slot, p, model)
        end
    end
end)

addEventHandler("bloodPoolsCleared", resourceRoot, function(id)
    clearTrail(id)
end)

addEventHandler("onClientElementStreamIn", resourceRoot, function()
    if spots[source] then
        ground(source, spots[source])
    end
end)

local function shows(player)
    return isElementStreamedIn(player)
        and getElementData(player, "character.bleeding") == true
        and not isPedDead(player)
        and not getPedOccupiedVehicle(player)
end

setTimer(function()
    for _, player in ipairs(getElementsByType("player", root, true)) do
        sprays[player] = shows(player) or nil
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
    sprays[source] = nil
end)

-- the pack (re)loaded or is stopping: its model ids change, so every pool is made again from the trails
addEventHandler("sampModelsChanged", root, function()
    local model = poolModel()
    for id, trail in pairs(trails) do
        for slot, p in pairs(trail) do
            placePool(id, slot, p, model)
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("bloodPoolsRequested", localPlayer)
end)
