-- luacheck: read globals setWorldProperty resetWorldProperty getTime engineRemoveShaderFromWorldTexture getCameraMatrix
-- The grid is dead: no street lamp, traffic light or neon glows, no lamp throws light on the ground, and no window is
-- lit. Only what a player carries or burns lights the night (headlights, flashlights, fires, a Flood Light). Staff
-- on duty (staff.duty element data) see the city lit, and any staff can switch it back on for themselves with
-- /lights (staff moderation.lua) to look at something.
-- A Flood Light (items) registers its light here (setLight / removeLight); the shader draws the MAX_LIGHTS of them
-- nearest the camera in the player's interior and dimension onto the buildings and objects round them.
-- A building lit by its own mains (power: a Generator wired to its box) registers its room (setRoomLight /
-- removeRoomLight); inside the MAX_ROOMS of them in the player's interior and dimension the cap is lifted.
-- Goggles switched on (items: the local player's "items.vision" element data, "nightvision" / "thermalvision") see
-- through it: the shader then shows the buildings as that vision does, to match what GTA's own effect does to
-- everything else.
local PROPERTIES = {
    SpriteBrightness = 0, -- the coronas of every 2DFX light (lamps, traffic lights, signs)
    LightsOnGround = 0, -- the light pools those lamps cast on roads and walls
}
-- brightest a building's baked night colour may be once night has fully fallen (client/blackout.fx)
local NIGHT_CAP = 0.12
-- textures the shader stays off (wildcards as engineRemoveShaderFromWorldTexture takes them): the hud.txd,
-- fonts.txd and fronten*.txd ones, and the procedural weeds (txgrass*), which get their shade and distance fade
-- from the fixed-function texture stages a pixel shader skips (they came out bright and hard-edged) and carry no
-- baked window light to cap anyway
local UNSHADED_TEXTURES = {
    "txgrass*",
    "font1",
    "font2",
    "fist",
    "*icon",
    "radar*",
    "site*",
    "arrow",
    "skipicon",
    "lockon*",
    "back*",
    "mouse",
    "crosshair",
    "fronten*",
    "map*",
    "hud*",
}

-- Near terrain materials from the GTA Scout catalogue. The originals still supply
-- colour, tracks and transitions. Distant LOD textures need no extra grain.
local DIRT_TEXTURES = {
    "bow_church_dirt",
    "bow_church_dirt_to_grass_side_t",
    "crackedgroundb",
    "cw2_mountdirt",
    "cw2_mountdirt2forest",
    "cw2_mountdirt2grass",
    "cw2_mountdirtscree",
    "des_crackeddirt1",
    "des_dirt1",
    "des_dirt2",
    "des_dirt2 trackl",
    "des_dirt2blend",
    "des_dirt2grgrass",
    "des_dirt2stones",
    "des_dirt2track",
    "des_dirt2trackr",
    "des_dirtgravel",
    "des_dirttrack1",
    "des_dirttrack1r",
    "des_dirttrackl",
    "des_dirttrackx",
    "des_scrub1_dirt1",
    "desertgravel256",
    "desertgravelgrass256",
    "desertgravelgrassroad",
    "desertgryard256",
    "desertstones256",
    "desertstones256grass",
    "desmud",
    "desmudgrass",
    "desmudtrail",
    "desmudtrail2",
    "desmudtrail3",
    "desstones_dirt1",
    "dirtblendlit",
    "dirttracksforest",
    "dirttracksgrass256",
    "gm_lacarparkmuckt",
    "grassdead1",
    "grassdead1blnd",
    "laroad_offroad1",
    "sl_sfngrssdrt01",
    "sw_dirt01",
    "sw_rockgrassb1",
    "sw_rockgrassb2",
    "was_scrpyd_ground_muddark",
    "was_scrpyd_ground_muddier",
    "ws_patchygravel",
}

local MAX_LIGHTS = 4 -- client/blackout.fx's Light0 .. Light3
local LIGHT_RANGE = 120 -- metres from the camera a light still counts
local CONE = { 0.6, 0.2 } -- cosines of the half angles where a light is full and where it is gone
local DAY_GAIN = 0.35 -- how much of a light shows by day (none of it is needed then)

local VISIONS = { nightvision = { 1, 0 }, thermalvision = { 0, 1 } }

local on = true
local wanted = true -- false while /lights has the city lit for this player
local shader
local dirtShader
local lights = {} -- id -> { x, y, z, dx, dy, dz, radius, r, g, b, interior, dimension }
local lightsDirty = true
local MAX_ROOMS = 2 -- client/blackout.fx's Room0 .. Room1
local rooms = {} -- id -> { x1, y1, z1, x2, y2, z2, r, g, b, fill, interior, dimension }

local function setLightingValue(name, ...)
    dxSetShaderValue(shader, name, ...)
    if dirtShader then
        dxSetShaderValue(dirtShader, name, ...)
    end
end

-- GTA's own day/night balance for building colours (CCustomBuildingRenderer::UpdateDayNightBalanceParam): night
-- until 06:00, fading out by 07:00, day until 20:00, fading in by 21:00
local function nightBalance()
    local h, m = getTime()
    local t = h * 60 + m
    if t < 360 or t >= 1260 then
        return 1
    elseif t < 420 then
        return (420 - t) / 60
    elseif t < 1200 then
        return 0
    end
    return (t - 1200) / 60
end

-- vision: the local player's "items.vision" (passed in by its change event, which fires before the data changes)
local function updateVision(vision)
    if shader then
        local v = VISIONS[vision] or { 0, 0 }
        if isPedDead(localPlayer) or getElementData(localPlayer, "staff.duty") == true then
            v = { 0, 0 }
        end
        setLightingValue("Vision", v[1], v[2])
    end
end

local function updateCap()
    if shader then
        local night = nightBalance()
        setLightingValue("Cap", on and 1 - (1 - NIGHT_CAP) * night or 1)
        setLightingValue("Gain", DAY_GAIN + (1 - DAY_GAIN) * night)
    end
end

-- the MAX_LIGHTS lights nearest the camera in the player's world go into the shader, the other slots dark
local shown = 0
local function updateLights()
    if not shader then
        return
    end
    local cx, cy, cz = getCameraMatrix()
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local near = {}
    for _, l in pairs(lights) do
        if l.interior == int and l.dimension == dim then
            local d = getDistanceBetweenPoints3D(cx, cy, cz, l.x, l.y, l.z)
            if d <= LIGHT_RANGE + l.radius then
                near[#near + 1] = { l = l, d = d }
            end
        end
    end
    if #near == 0 and shown == 0 and not lightsDirty then
        return
    end
    lightsDirty = false
    table.sort(near, function(a, b)
        return a.d < b.d
    end)
    shown = math.min(#near, MAX_LIGHTS)
    for i = 0, MAX_LIGHTS - 1 do
        local n = near[i + 1]
        local l = n and n.l
        local key = "Light" .. i
        if l then
            setLightingValue(key .. "Pos", l.x, l.y, l.z, l.radius)
            setLightingValue(key .. "Dir", l.dx, l.dy, l.dz, 0)
            setLightingValue(key .. "Col", l.r, l.g, l.b, 1)
        else
            setLightingValue(key .. "Pos", 0, 0, -10000, 0)
            setLightingValue(key .. "Col", 0, 0, 0, 0)
        end
    end
end

-- export: a light a player brought (an id of the caller's own, e.g. "flood:<item id>"), shining from x, y, z along
-- dx, dy, dz up to radius metres in colour r, g, b (0 .. 1), in that interior and dimension
function setLight(id, x, y, z, dx, dy, dz, radius, r, g, b, interior, dimension)
    if type(id) ~= "string" or not tonumber(x) or not tonumber(y) or not tonumber(z) then
        return false
    end
    local len = math.sqrt((dx or 0) ^ 2 + (dy or 0) ^ 2 + (dz or 0) ^ 2)
    if len < 0.001 then
        dx, dy, dz, len = 0, 0, -1, 1
    end
    lights[id] = {
        x = x,
        y = y,
        z = z,
        dx = dx / len,
        dy = dy / len,
        dz = dz / len,
        radius = tonumber(radius) or 10,
        r = tonumber(r) or 1,
        g = tonumber(g) or 1,
        b = tonumber(b) or 1,
        interior = tonumber(interior) or 0,
        dimension = tonumber(dimension) or 0,
    }
    lightsDirty = true
    updateLights()
    return true
end

-- the rooms in the player's interior and dimension go into the shader (the first MAX_ROOMS by id), the rest dark
local function updateRooms()
    if not shader then
        return
    end
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local ids = {}
    for id, r in pairs(rooms) do
        if r.interior == int and r.dimension == dim then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    for i = 0, MAX_ROOMS - 1 do
        local r = rooms[ids[i + 1] or ""]
        local key = "Room" .. i
        if r then
            setLightingValue(key .. "Min", r.x1, r.y1, r.z1, r.fill)
            setLightingValue(key .. "Max", r.x2, r.y2, r.z2, 1)
            setLightingValue(key .. "Col", r.r, r.g, r.b, 1)
        else
            setLightingValue(key .. "Min", 0, 0, -10000, 0)
            setLightingValue(key .. "Max", 0, 0, -10000, 0)
        end
    end
end

-- export: a room lit by its building's mains (an id of the caller's own, e.g. "mains:<site>"): the box x1 .. x2,
-- y1 .. y2, z1 .. z2, the light's colour r, g, b (0 .. 1) and how much it adds (fill), in that interior and dimension
function setRoomLight(id, x1, y1, z1, x2, y2, z2, r, g, b, fill, interior, dimension)
    if type(id) ~= "string" or not tonumber(x1) or not tonumber(x2) then
        return false
    end
    rooms[id] = {
        x1 = math.min(x1, x2),
        y1 = math.min(y1, y2),
        z1 = math.min(z1, z2),
        x2 = math.max(x1, x2),
        y2 = math.max(y1, y2),
        z2 = math.max(z1, z2),
        r = tonumber(r) or 1,
        g = tonumber(g) or 1,
        b = tonumber(b) or 1,
        fill = tonumber(fill) or 0.3,
        interior = tonumber(interior) or 0,
        dimension = tonumber(dimension) or 0,
    }
    updateRooms()
    return true
end

-- export: the room's light is gone
function removeRoomLight(id)
    if rooms[id] then
        rooms[id] = nil
        updateRooms()
    end
    return true
end

-- export: the light is gone
function removeLight(id)
    if lights[id] then
        lights[id] = nil
        lightsDirty = true
        updateLights()
    end
    return true
end

local function apply()
    for name, value in pairs(PROPERTIES) do
        if on then
            setWorldProperty(name, value)
        else
            resetWorldProperty(name)
        end
    end
    updateCap()
end

local function refresh()
    on = wanted and getElementData(localPlayer, "staff.duty") ~= true
    apply()
end

local function loadDirtDetail()
    -- Use the same lighting pass on dirt so it also receives floodlights and vision effects.
    local variant, technique = dxCreateShader("client/blackout.fx", { DIRT_DETAIL = "1" }, -9, 0, false, "world")
    if not variant then
        return
    end
    if technique ~= "lit" then
        destroyElement(variant)
        return
    end
    local detail = dxCreateTexture("files/dirt_detail.dds", "dxt1", true, "wrap")
    if not detail or not dxSetShaderValue(variant, "DirtDetail", detail) then
        destroyElement(variant)
        if detail then
            destroyElement(detail)
        end
        return
    end
    for _, name in ipairs(DIRT_TEXTURES) do
        engineApplyShaderToWorldTexture(variant, name)
    end
    dirtShader = variant
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- lowest priority, so an item's tint or a screen's render target on a single object still wins
    shader = dxCreateShader("client/blackout.fx", -10, 0, false, "world,object")
    if shader then
        engineApplyShaderToWorldTexture(shader, "*")
        -- GTA's own 2D drawing (HUD weapon icons, radar, zone and area names, the pause menu) counts as world
        -- textures too; left in, every one of them went dark at night
        for _, name in ipairs(UNSHADED_TEXTURES) do
            engineRemoveShaderFromWorldTexture(shader, name)
        end
        loadDirtDetail()
        setLightingValue("Cone", CONE[1], CONE[2])
        setTimer(updateCap, 1000, 0)
        setTimer(updateLights, 250, 0)
        -- a change of interior or dimension changes which rooms count
        setTimer(updateRooms, 1000, 0)
        updateRooms()
        updateVision(getElementData(localPlayer, "items.vision"))
    end
    refresh()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    on = false
    apply()
end)

addEventHandler("playerBlackoutChanged", root, function(state)
    wanted = state ~= false
    refresh()
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key, _, value)
    if key == "staff.duty" then
        refresh()
    elseif key == "items.vision" then
        updateVision(value)
    end
end, false)

addEventHandler("onClientPlayerWasted", localPlayer, function()
    updateVision(false)
end)
