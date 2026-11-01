-- Felled trees (server/trees.lua): a tree the server fells is taken out of this client's world (removeWorldModel at its
-- GTA placement) and drawn falling as an object of its own model, which is gone once it has landed or sunk; when the
-- tree stands again the model comes back. A joining client is told which trees are down (treesSynced).
local RADIUS = 0.5 -- the placement is exact: nothing else of that model lies this near
local removed = {} -- tree -> { model, x, y, z }
local falling = {} -- tree -> object

local function takeOut(i, model, x, y, z)
    if removed[i] then
        return
    end
    if removeWorldModel(model, RADIUS, x, y, z) then
        removed[i] = { model, x, y, z }
    end
end

local function bringBack(i)
    local r = removed[i]
    if r then
        restoreWorldModel(r[1], RADIUS, r[2], r[3], r[4])
        removed[i] = nil
    end
    if isElement(falling[i]) then
        destroyElement(falling[i])
    end
    falling[i] = nil
end

local function drawFall(i, model, x, y, z, rz, fall)
    local obj = createObject(model, x, y, z, 0, 0, rz)
    if not obj then
        return
    end
    setElementCollisionsEnabled(obj, false)
    falling[i] = obj
    moveObject(obj, fall.ms, x, y, z + fall.dz, fall.rx, fall.ry, 0, "InQuad")
    setTimer(function()
        if falling[i] == obj then
            falling[i] = nil
        end
        if isElement(obj) then
            destroyElement(obj)
        end
    end, fall.ms + 500, 1)
end

addEventHandler("treeFelled", root, function(i, model, x, y, z, rz, fall)
    takeOut(i, model, x, y, z)
    drawFall(i, model, x, y, z, rz, fall)
end)

addEventHandler("treeRestored", root, function(i)
    bringBack(i)
end)

addEventHandler("treesSynced", localPlayer, function(list)
    for _, t in ipairs(list) do
        takeOut(t[1], t[2], t[3], t[4], t[5])
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("treesStateRequested", localPlayer)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for i in pairs(removed) do
        bringBack(i)
    end
end)
