-- luacheck: read globals setWorldProperty resetWorldProperty
-- The grid is dead: no street lamp, traffic light or neon glows, and no lamp throws light on the ground. Only what a
-- player carries or burns lights the night (headlights, flashlights, fires). Staff can switch the city back on for
-- themselves with /lights (staff moderation.lua) to look at something.
local PROPERTIES = {
    SpriteBrightness = 0, -- the coronas of every 2DFX light (lamps, traffic lights, signs, windows)
    LightsOnGround = 0, -- the light pools those lamps cast on roads and walls
}

local function apply(on)
    for name, value in pairs(PROPERTIES) do
        if on then
            setWorldProperty(name, value)
        else
            resetWorldProperty(name)
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    apply(true)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    apply(false)
end)

addEventHandler("playerBlackoutChanged", root, function(on)
    apply(on ~= false)
end)
