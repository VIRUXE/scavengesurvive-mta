-- luacheck: read globals setWorldProperty resetWorldProperty getTime engineRemoveShaderFromWorldTexture getCameraMatrix
-- The grid is dead: no street lamp, traffic light or neon glows, no lamp throws light on the ground, and no window is
-- lit. Only what a player carries or burns lights the night (headlights, flashlights, fires, a Flood Light). Staff
-- can switch the city back on for themselves with /lights (staff moderation.lua) to look at something.
-- A Flood Light (items) registers its light here (setLight / removeLight); the shader draws the MAX_LIGHTS of them
-- nearest the camera in the player's interior and dimension onto the buildings and objects round them.
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

local MAX_LIGHTS = 4 -- client/blackout.fx's Light0 .. Light3
local LIGHT_RANGE = 120 -- metres from the camera a light still counts
local CONE = { 0.6, 0.2 } -- cosines of the half angles where a light is full and where it is gone
local DAY_GAIN = 0.35 -- how much of a light shows by day (none of it is needed then)

local on = true
local shader
local lights = {} -- id -> { x, y, z, dx, dy, dz, radius, r, g, b, interior, dimension }
local lightsDirty = true

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

local function updateCap()
    if shader then
        local night = nightBalance()
        dxSetShaderValue(shader, "Cap", on and 1 - (1 - NIGHT_CAP) * night or 1)
        dxSetShaderValue(shader, "Gain", DAY_GAIN + (1 - DAY_GAIN) * night)
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
            dxSetShaderValue(shader, key .. "Pos", l.x, l.y, l.z, l.radius)
            dxSetShaderValue(shader, key .. "Dir", l.dx, l.dy, l.dz, 0)
            dxSetShaderValue(shader, key .. "Col", l.r, l.g, l.b, 1)
        else
            dxSetShaderValue(shader, key .. "Pos", 0, 0, -10000, 0)
            dxSetShaderValue(shader, key .. "Col", 0, 0, 0, 0)
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
        dxSetShaderValue(shader, "Cone", CONE[1], CONE[2])
        setTimer(updateCap, 1000, 0)
        setTimer(updateLights, 250, 0)
    end
    apply()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    on = false
    apply()
end)

addEventHandler("playerBlackoutChanged", root, function(state)
    on = state ~= false
    apply()
end)
