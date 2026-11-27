-- The client's part of upstream's static maps, which the server builds (server/build.lua): each SA-MP or port model
-- arrives as an invisible stand-in that this client swaps for its own allocated model (lib standins.lua), now and
-- whenever a model pack (re)loads; a fitted shell door is let go once its model is in, so it swings. Also what only a
-- client can set: the draw distances below and the occlusions the removed world models leave behind.
local standins = loadstring(exports.lib:getModule("standins"), "=lib/standins.lua")()
local placement
do
    local f = fileOpen("shared/logic/placement.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    placement = assert(loadstring(src, "=maps/placement.lua"))()
end

local stats = { standins = 0, ms = 0 }
-- Vanilla buildings whose IDE draw distance (100) is shorter than they are wide: GTA swapped them for their blurry
-- LOD while you stood beside them. Raised on every client, reset on stop.
local DRAW_DISTANCES = {
    [13060] = 300, -- CE_factcomp1, the Blueberry factory complex (360, -97)
    [13077] = 300, -- CE_townware, the Blueberry town warehouse (273, -239)
}

addEventHandler("onClientResourceStart", resourceRoot, function()
    local started = getTickCount()
    for model, dist in pairs(DRAW_DISTANCES) do
        engineSetModelLODDistance(model, dist)
    end
    setOcclusionsEnabled(false) -- removed world models leave their occluders behind otherwise
    stats.standins = standins.track(resourceRoot, function(e, model, id)
        if placement.isSwingDoor(model) then
            setElementFrozen(e, not id)
        end
    end)
    stats.ms = getTickCount() - started
    outputDebugString(("maps: %d stand-ins swapped in %d ms"):format(stats.standins, stats.ms), 3)
    triggerEvent("mapsBuilt", resourceRoot, stats)
    triggerServerEvent("mapRemovalsRequested", localPlayer)
end)

-- the server's removeWorldModel rows (server/build.lua), made again here: the server's own left LODs standing
local removed = {}
addEvent("mapRemovalsSent", true)
addEventHandler("mapRemovalsSent", resourceRoot, function(rows)
    if type(rows) ~= "table" then
        return
    end
    for _, r in ipairs(rows) do
        -- { model, x, y, z, radius } -> model, radius, x, y, z
        if removeWorldModel(r[1], r[5], r[2], r[3], r[4]) then
            removed[#removed + 1] = r
        end
    end
    stats.removals = #removed
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for model in pairs(DRAW_DISTANCES) do
        engineResetModelLODDistance(model)
    end
    for _, r in ipairs(removed) do
        restoreWorldModel(r[1], r[5], r[2], r[3], r[4])
    end
    removed = {}
    setOcclusionsEnabled(true)
end)

function getMapStats()
    return stats
end
