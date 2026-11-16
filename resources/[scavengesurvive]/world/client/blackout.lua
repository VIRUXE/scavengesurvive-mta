-- luacheck: read globals setWorldProperty resetWorldProperty getTime engineRemoveShaderFromWorldTexture
-- The grid is dead: no street lamp, traffic light or neon glows, no lamp throws light on the ground, and no window is
-- lit. Only what a player carries or burns lights the night (headlights, flashlights, fires). Staff can switch the
-- city back on for themselves with /lights (staff moderation.lua) to look at something.
local PROPERTIES = {
    SpriteBrightness = 0, -- the coronas of every 2DFX light (lamps, traffic lights, signs)
    LightsOnGround = 0, -- the light pools those lamps cast on roads and walls
}
-- brightest a building's baked night colour may be once night has fully fallen (client/blackout.fx)
local NIGHT_CAP = 0.12
-- hud.txd, fonts.txd and fronten*.txd textures (wildcards as engineRemoveShaderFromWorldTexture takes them)
local HUD_TEXTURES = {
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

local on = true
local shader

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
        dxSetShaderValue(shader, "Cap", on and 1 - (1 - NIGHT_CAP) * nightBalance() or 1)
    end
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
        for _, name in ipairs(HUD_TEXTURES) do
            engineRemoveShaderFromWorldTexture(shader, name)
        end
        setTimer(updateCap, 1000, 0)
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
