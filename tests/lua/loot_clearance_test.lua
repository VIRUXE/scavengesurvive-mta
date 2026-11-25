-- Run from the repo root: lua tests/lua/loot_clearance_test.lua
local base = "resources/[scavengesurvive]/loot/shared/"
local roll = dofile(base .. "logic/roll.lua")
local settle = dofile(base .. "logic/settle.lua")
local panel = { 0.06, 0, 0, 0, 0, 3, 1.6, 0.12 }
local small = { 0.05, 0, 0, 1, 0, 0.1, 0.1, 0.1 }
local ground = { z = 0, s = { { { 0, 0, 0, 0, 0 } } } }

local function wall(x1, _, _, x2)
    return (x1 < -0.25) == (x2 < -0.25)
end

local function floor()
    return 0, 0, 0, 1
end

local function place(rest, clear, below, placed)
    local world = { below = below, clear = clear }
    return roll.placeWorldItem(0, 0, ground, 1, 1, rest, 0, 0, placed, world, settle.boxClear)
end

local placed = {}
local x, y, z, rz = place(panel, wall, floor, placed)
assert(x and x > 0.55 and #placed == 1, "move the panel clear and record the moved footprint")
assert(settle.boxClear(panel, x, y, z, rz, 0, 0, wall), "the selected panel heading clears the wall")
local sx, sy = place(small, wall, floor, {})
assert(sx == 0 and sy == 0, "the small item keeps its authored position")

local function slotOnly(x, y)
    if x == 0 and y == 0 then
        return floor()
    end
    return -1, 0, 0, 1
end

local _, _, _, heading = place(panel, function(x1, _, _, x2)
    return math.abs(x1) < 1 and math.abs(x2) < 1
end, slotOnly, {})
assert(heading == 90, "rotate to fit on the original floor")

local crowded = { roll.footprint(0, 0, 0, 0, panel) }
local function open()
    return true
end
assert(place(panel, open, slotOnly, crowded) == 0 and #crowded == 2, "retain a world-clear pose amid crowded loot")

local blocked = {}
local function solid()
    return false
end
assert(not place(panel, solid, floor, blocked) and #blocked == 0, "an obstructed candidate never reserves a footprint")
assert(
    roll.placeItem(0, 0, ground, 1, 1, panel, 0, math.random, blocked) ~= nil and #blocked == 1,
    "the measured-slot fallback still places the item when the world search is exhausted"
)
print("loot clearance regression checks passed")
