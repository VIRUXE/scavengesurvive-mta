-- The watch (core/ui/watch.pwn): bearing, clock and radio frequency on a black ellipse bottom-left.
local M = {}

-- Ellipse: LD_POOL:ball at x 87, y 338, 108 x 89 units (Normal profile, the 2015 footage). Text rows centred on
-- x 87: bearing y 358 (font 2, 0.30/1.50), time y 372 (0.50/2.00), frequency y 391 (0.30/1.50).
M.GEOMETRY = {
    cx = 87,
    cy = 338 + 89 / 2,
    rx = 108 / 2,
    ry = 89 / 2,
    bearingY = 358,
    timeY = 372,
    freqY = 391,
}
M.DEFAULT_FREQUENCY = 98.12

-- GTA angles go anti-clockwise; the watch shows a compass bearing.
function M.bearing(facingAngle)
    local b = (360 - (facingAngle or 0)) % 360
    return string.format("%.0f DEG", b)
end

function M.clock(hour, minute)
    return string.format("%02d:%02d", hour or 0, minute or 0)
end

function M.frequency(freq)
    return string.format("%.2f", freq or M.DEFAULT_FREQUENCY)
end

-- Text colour: white, or upstream RED (0xE85454) while the player is combat-logging.
function M.colour(combatLogging)
    if combatLogging then
        return 0xE8, 0x54, 0x54
    end
    return 255, 255, 255
end

return M
