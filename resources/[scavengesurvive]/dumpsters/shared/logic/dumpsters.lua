-- Dumpsters (tools/dumpster_spots.py, shared/spots.lua): geometry of a spot and what one holds. Pure, no MTA calls.
-- A spot is { x, y, floor z, heading }; the body is 2.32 x 1.33 m, 1.5 m high, long side along the heading's X axis.
local M = {}

M.HALF_X, M.HALF_Y, M.HEIGHT = 1.16, 0.665, 1.5
M.OPEN_REACH = 1.6 -- metres from the body's walls at which the interact key opens it (server allows +1)
M.CAPACITY = 12 -- container slots
M.LID_OPEN_PITCH = -105 -- degrees about the hinge on the back wall
M.LID_MS = 650

-- lang:begin
M.TITLE = "Dumpster"
M.HINT = "Open dumpster"
-- lang:end

-- distance from (px, py, pz) to the dumpster's box, 0 inside it (the lid side can be climbed on, so z is clamped too)
function M.distance(spot, px, py, pz)
    local dx, dy = px - spot[1], py - spot[2]
    local h = math.rad(spot[4])
    local c, s = math.cos(h), math.sin(h)
    -- an object's rz turns it counter-clockwise (90 faces west): its local X axis is (cos h, sin h) in the world
    local lx = dx * c + dy * s
    local ly = -dx * s + dy * c
    local ex = math.max(math.abs(lx) - M.HALF_X, 0)
    local ey = math.max(math.abs(ly) - M.HALF_Y, 0)
    local ez = math.max(spot[3] - pz, pz - (spot[3] + M.HEIGHT + 1.0), 0)
    return math.sqrt(ex * ex + ey * ey + ez * ez)
end

-- the spot index nearest to the point within `reach`, or nil
function M.nearest(spots, px, py, pz, reach)
    local best, bestD = nil, reach
    for i, s in ipairs(spots) do
        if math.abs(s[1] - px) < 5 and math.abs(s[2] - py) < 5 then
            local d = M.distance(s, px, py, pz)
            if d <= bestD then
                best, bestD = i, d
            end
        end
    end
    return best
end

-- What a dumpster holds: { min, max, { uname, weight }... }, mostly empties and food waste.
M.FILL = {
    min = 2,
    max = 6,
    { "CanDrink", 20 },
    { "Bottle", 14 },
    { "MilkCarton", 10 },
    { "MilkBottle", 5 },
    { "Ketchup", 5 },
    { "Mustard", 5 },
    { "Detergent", 4 },
    { "OrangeJuice", 3 },
    { "AppleJuice", 3 },
    { "Wine1", 2 },
    { "Whisky", 2 },
    { "Bandage", 5 },
    { "Note", 5 },
    { "Boot", 5 },
    { "Clothes", 4 },
    { "ScrapMetal", 5 },
    { "Briquettes", 2 },
    { "Battery", 2 },
    { "Doormat", 2 },
    { "PizzaBox", 4 },
    { "BurgerBox", 4 },
    { "Banana", 3 },
    { "BreadLoaf", 2 },
    { "RedApple", 2 },
    { "Pills", 1 },
}

-- rolls of FILL that fit M.CAPACITY together; sizeOf(uname) is the item size, rng(a, b) an integer in [a, b]
function M.fill(sizeOf, rng)
    local total = 0
    for _, t in ipairs(M.FILL) do
        total = total + t[2]
    end
    local out, used = {}, 0
    for _ = 1, rng(M.FILL.min, M.FILL.max) do
        local r, pick = rng(1, total), nil
        for _, t in ipairs(M.FILL) do
            r = r - t[2]
            if r <= 0 then
                pick = t[1]
                break
            end
        end
        local size = sizeOf(pick) or 1
        if used + size <= M.CAPACITY then
            out[#out + 1] = pick
            used = used + size
        end
    end
    return out
end

return M
