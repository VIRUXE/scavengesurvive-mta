-- The vehicle panel (core/vehicle/vehicle.pwn + core/player/player.pwn): six right-aligned Bank Gothic rows
-- bottom-right while driving. Colours and thresholds are upstream's defines.
local M = {}

-- Right edge x 620 (name 621), rows top-down; font 2 0.25/1.60, name 0.35/1.80.
M.ROWS = { doors = 341, engine = 356, damage = 371, fuel = 386, speed = 401, name = 415 }

local CHUNKS = {
    { 300, { 0xFF, 0x00, 0x00 } }, -- VEHICLE_HEALTH_CHUNK_1: wrecked
    { 450, { 0xFF, 0x77, 0x00 } }, -- CHUNK_2: broken
    { 650, { 0xFF, 0xFF, 0x00 } }, -- CHUNK_3: a bit broken
    { 800, { 0x80, 0x80, 0x00 } }, -- CHUNK_4: slightly broken
}
M.MAX_HEALTH = 990
M.ACTIVE = { 0x80, 0x80, 0x00 } -- VEHICLE_UI_ACTIVE (engine on, doors unlocked)
M.INACTIVE = { 0xFF, 0x00, 0x00 } -- VEHICLE_UI_INACTIVE

function M.damageColour(health)
    for _, c in ipairs(CHUNKS) do
        if health <= c[1] then
            return c[2]
        end
    end
    return CHUNKS[#CHUNKS][2]
end

function M.stateColour(active)
    return active and M.ACTIVE or M.INACTIVE
end

function M.fuelText(fuel, maxFuel)
    return string.format("%.2fL/%.2f", fuel or 0, maxFuel or 0)
end

-- Upstream: |velocity| * 150 shown as "%.0fkm/h" (font 2 renders it as KM/H).
function M.speedText(vx, vy, vz)
    local v = math.sqrt((vx or 0) ^ 2 + (vy or 0) ^ 2 + (vz or 0) ^ 2) * 150
    return string.format("%.0fkm/h", v)
end

return M
