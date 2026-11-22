-- A weather only this player sees (staff /weather window): the server sends the id on a set, an expiry and after
-- every world weather change, since the global setWeather reaches this client too.
-- luacheck: read globals setWeather
addEventHandler("playerWeatherChanged", root, function(id)
    if type(id) == "number" then
        setWeather(id)
    end
end)

-- No weather indoors. GTA keeps the weather out of a place only through map cull zones or interior ids, which the
-- enterable shells, the map's buildings and what players build cannot carry: rain fell through roofs and the fog of
-- a foggy day drifted through rooms. While the camera has a roof over it and walls around it (rays against the
-- world's collision, so any enclosed place counts) the rain, the fog, the sandstorm and the heat haze are switched
-- off on this client, and handed back to the weather once it is out in the open again.
-- The haze of a foggy day is distance fog that starts behind the camera, so its start is pushed out to just short of
-- the far clip; past it the whole screen takes the fog's colour. The far clip is not steady: looking down raises it
-- by up to 650 m and it falls back about 10 m a frame (CTimeCycle::CalcColoursForPoint, m_FogReduction), so the fog
-- start follows it every frame and keeps more than a frame's fall of room.
-- luacheck: read globals setWorldProperty resetWorldProperty setHeatHaze resetHeatHaze setFogDistance resetFogDistance
-- luacheck: read globals getFarClipDistance
local SHELTER_CHECK_MS = 250
local ROOF = 25 -- metres up to look for a roof
local WALL = 20 -- metres around to look for walls
local RAYS = 8 -- rays around, evenly spread
local WALLS_NEEDED = 6 -- of them that must hit: a doorway or two may stand open
local LEAVE_CHECKS = 2 -- checks in the open before the weather returns (a ray slipping through a gap)
local INDOOR_OFF = { "Foggyness", "Fog", "RainFog", "Sandstorm" } -- world properties held at 0 indoors
local FOG_START = 0.9 -- of the far clip distance: where the fog starts indoors
local FOG_ROOM = 25 -- metres more short of the far clip: two frames of its fall
local sheltered, open = false, 0

local function blocked(x, y, z, dx, dy, dz)
    return not isLineOfSightClear(x, y, z, x + dx, y + dy, z + dz, true, false, false, true, true, false, false)
end

local function underRoof()
    if getElementInterior(localPlayer) ~= 0 then
        return false -- the game keeps the weather out of its own interiors
    end
    local x, y, z = getCameraMatrix()
    if not blocked(x, y, z, 0, 0, ROOF) then
        return false
    end
    local walls = 0
    for i = 1, RAYS do
        local a = i * 2 * math.pi / RAYS
        if blocked(x, y, z, math.cos(a) * WALL, math.sin(a) * WALL, 0) then
            walls = walls + 1
        end
    end
    return walls >= WALLS_NEEDED
end

local function fogOut()
    setFogDistance(math.max(0, getFarClipDistance() * FOG_START - FOG_ROOM))
end

local function shelter(on)
    if on == sheltered then
        return
    end
    sheltered = on
    if on then
        setRainLevel(0)
        fogOut()
        addEventHandler("onClientPreRender", root, fogOut)
        setHeatHaze(0)
        for _, property in ipairs(INDOOR_OFF) do
            setWorldProperty(property, 0)
        end
    else
        resetRainLevel()
        resetHeatHaze()
        removeEventHandler("onClientPreRender", root, fogOut)
        resetFogDistance()
        for _, property in ipairs(INDOOR_OFF) do
            resetWorldProperty(property)
        end
    end
end

setTimer(function()
    if underRoof() then
        open = 0
        shelter(true)
    else
        open = open + 1
        if open >= LEAVE_CHECKS then
            shelter(false)
        end
    end
end, SHELTER_CHECK_MS, 0)

-- Exported: whether this client's camera is under a roof with walls around it right now (the toxic resource keeps
-- its outdoor fog out of such places).
function isSheltered()
    return sheltered
end

addEventHandler("onClientResourceStop", resourceRoot, function()
    shelter(false)
end)
