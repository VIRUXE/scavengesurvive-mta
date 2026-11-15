-- Answers the server's under-map check (server/ground.lua) for the vehicle positions it sends: the server's own
-- coordinates, never this client's copy (GTA may already have put that one back on a road). Per vehicle:
--   "ok"      world collision within BELOW metres under it
--   "under"   nothing under it but a surface over it (the map is above it), with that topmost surface's z
--   "unknown" anything else: nothing above either (collision not loaded, open sky over deep water, mid-air), or
--             a water surface within WATER metres of it (a boat or a sinking car under a bridge must not be lifted
--             onto the bridge). Only that close: GTA's water areas run on under the land along the coasts, so a car
--             under the coastal ground has water far above it too.
--   "sunk"    fully under water: every corner of its bounding box below a water surface, nothing solid between it
--             and that surface, and a bed under it (a car under the coastal ground has none). Half in the water is not.
local BELOW = 60
local TOP = 1500
local WATER = 10
local MAX_DIST = 200 -- 2D from the camera; past it this client's collision may not be loaded
local BED = 200 -- how deep under a sunk vehicle the sea or lake bed is looked for

local function hitZ(x, y, fromZ, toZ)
    -- buildings and objects (map objects are ground too); no vehicles, peds or dummies
    local hit, _, _, hz = processLineOfSight(x, y, fromZ, x, y, toZ, true, false, false, true, false)
    return hit and hz or nil
end

local function sunk(v, x, y, z)
    local x0, y0, z0, x1, y1, z1 = false, 0, 0, 0, 0, 0
    local m = isElement(v) and getElementMatrix(v)
    if m then
        x0, y0, z0, x1, y1, z1 = getElementBoundingBox(v)
    end
    if not x0 then
        return false
    end
    -- the highest corner of its bounding box as this client has it turned, over the server's position
    local r = -math.huge
    for _, cx in ipairs({ x0, x1 }) do
        for _, cy in ipairs({ y0, y1 }) do
            for _, cz in ipairs({ z0, z1 }) do
                r = math.max(r, cx * m[1][3] + cy * m[2][3] + cz * m[3][3])
            end
        end
    end
    local hit, _, _, wz = testLineAgainstWater(x, y, z + r, x, y, TOP)
    return hit and wz > z + r and not hitZ(x, y, z, wz) and hitZ(x, y, z, z - BED) ~= nil
end

local function verdict(v, x, y, z)
    local cx, cy = getCameraMatrix()
    if (x - cx) ^ 2 + (y - cy) ^ 2 > MAX_DIST * MAX_DIST then
        return "unknown"
    end
    if sunk(v, x, y, z) then
        return "sunk"
    end
    if hitZ(x, y, z + 0.5, z - BELOW) then
        return "ok"
    end
    local top = hitZ(x, y, TOP, z + 0.5)
    if not top or testLineAgainstWater(x, y, z - WATER, x, y, z + WATER) then
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
            local what, surface = verdict(v, x, y, z)
            out[#out + 1] = { v, what, surface }
        end
    end
    if #out > 0 then
        triggerServerEvent("vehicleGroundChecked", localPlayer, out)
    end
end)
