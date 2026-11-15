-- Answers the server's under-map check (server/ground.lua) for the vehicle positions it sends: the server's own
-- coordinates, never this client's copy (GTA may already have put that one back on a road). Per vehicle:
--   "ok"      world collision within BELOW metres under it
--   "under"   nothing under it but a surface over it (the map is above it), with that topmost surface's z
--   "unknown" anything else: nothing above either (collision not loaded, open sky over deep water, mid-air), or
--             water over it (a car sunk in deep water under a bridge must not be lifted onto the bridge)
local BELOW = 60
local TOP = 1500
local MAX_DIST = 200 -- 2D from the camera; past it this client's collision may not be loaded

local function hitZ(x, y, fromZ, toZ)
    -- buildings and objects (map objects are ground too); no vehicles, peds or dummies
    local hit, _, _, hz = processLineOfSight(x, y, fromZ, x, y, toZ, true, false, false, true, false)
    return hit and hz or nil
end

local function verdict(x, y, z)
    local cx, cy = getCameraMatrix()
    if (x - cx) ^ 2 + (y - cy) ^ 2 > MAX_DIST * MAX_DIST then
        return "unknown"
    end
    if hitZ(x, y, z + 0.5, z - BELOW) then
        return "ok"
    end
    local top = hitZ(x, y, TOP, z + 0.5)
    if not top or testLineAgainstWater(x, y, z, x, y, TOP) then
        return "unknown"
    end
    return "under", top
end

addEventHandler("vehicleGroundCheckRequested", resourceRoot, function(list)
    if type(list) ~= "table" then
        return
    end
    local out = {}
    for _, e in ipairs(list) do
        local v, x, y, z = e[1], tonumber(e[2]), tonumber(e[3]), tonumber(e[4])
        if x and y and z then
            local what, surface = verdict(x, y, z)
            out[#out + 1] = { v, what, surface }
        end
    end
    if #out > 0 then
        triggerServerEvent("vehicleGroundChecked", localPlayer, out)
    end
end)
