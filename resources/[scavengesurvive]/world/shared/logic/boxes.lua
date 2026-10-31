-- GTA's boxes, crates and bags as items (data/boxes.lua, tools/convert/world_boxes.py): each spot keeps one item of its
-- type. A spot counts as filled while an item of its type lies within M.RADIUS of it, each item filling one spot at
-- most (a pile holds several cartons a box apart). Looked up through a grid, there are thousands of spots.
local M = {}

M.RADIUS = 1.0
local CELL = 4.0

local function cell(x, y)
    return math.floor(x / CELL) .. ":" .. math.floor(y / CELL)
end

-- spots: { { uname, x, y, z, rz, interior }, ... }; rows: the world items of the spots' types, { type_uname, x, y,
-- interior }. Returns the spots no item fills.
function M.missing(spots, rows)
    local grid = {}
    for i, r in ipairs(rows) do
        local x, y = tonumber(r.x), tonumber(r.y)
        if x and y then
            local key = cell(x, y)
            grid[key] = grid[key] or {}
            table.insert(grid[key], { i = i, x = x, y = y, uname = r.type_uname, interior = tonumber(r.interior) or 0 })
        end
    end
    local used, out, r2 = {}, {}, M.RADIUS * M.RADIUS
    for _, s in ipairs(spots) do
        local found
        local cx, cy = math.floor(s[2] / CELL), math.floor(s[3] / CELL)
        for gx = cx - 1, cx + 1 do
            for gy = cy - 1, cy + 1 do
                for _, r in ipairs(grid[gx .. ":" .. gy] or {}) do
                    if not found and not used[r.i] and r.uname == s[1] and r.interior == s[6] then
                        local dx, dy = r.x - s[2], r.y - s[3]
                        if dx * dx + dy * dy <= r2 then
                            found = r.i
                        end
                    end
                end
            end
        end
        if found then
            used[found] = true
        else
            out[#out + 1] = s
        end
    end
    return out
end

-- the spots with no player (positions { x, y }) within `distance`, so no box appears in front of anyone
function M.unwatched(spots, players, distance)
    local out, d2 = {}, distance * distance
    for _, s in ipairs(spots) do
        local seen = false
        for _, p in ipairs(players) do
            local dx, dy = p.x - s[2], p.y - s[3]
            if dx * dx + dy * dy <= d2 then
                seen = true
                break
            end
        end
        if not seen then
            out[#out + 1] = s
        end
    end
    return out
end

-- What the container boxes spawn with, by the `fill` of their type (tools/world_boxes.py `holds`): { min, max,
-- { uname, weight }... }. A bin bag holds rubbish: mostly empties (a liquid item with no data spawns empty), then
-- worn-out odds and ends, now and then something still worth eating. A carton holds what a warehouse keeps: clothes,
-- spare parts, tools, cereal, now and then something useful.
M.FILLS = {
    trash = {
        min = 1,
        max = 3,
        { "CanDrink", 20 },
        { "Bottle", 14 },
        { "MilkCarton", 10 },
        { "MilkBottle", 5 },
        { "Ketchup", 6 },
        { "Mustard", 6 },
        { "Detergent", 4 },
        { "OrangeJuice", 4 },
        { "AppleJuice", 4 },
        { "Wine1", 3 },
        { "Whisky", 2 },
        { "Champagne", 1 },
        { "Bandage", 6 },
        { "Note", 4 },
        { "Boot", 4 },
        { "Clothes", 2 },
        { "ScrapMetal", 3 },
        { "Briquettes", 2 },
        { "Battery", 2 },
        { "Doormat", 1 },
        { "PizzaBox", 2 },
        { "BurgerBox", 2 },
        { "Banana", 2 },
        { "BreadLoaf", 1 },
    },
    junk = {
        min = 1,
        max = 4,
        { "Clothes", 10 },
        { "ScrapMetal", 10 },
        { "Boot", 5 },
        { "Note", 4 },
        { "Battery", 6 },
        { "Briquettes", 5 },
        { "Cereal1", 5 },
        { "Cereal2", 5 },
        { "Bottle", 4 },
        { "Detergent", 3 },
        { "Doormat", 3 },
        { "Bucket", 3 },
        { "PlantPot", 2 },
        { "SeedBag", 2 },
        { "Spanner", 3 },
        { "Flashlight", 3 },
        { "Padlock", 3 },
        { "WheelLock", 2 },
        { "Fusebox", 2 },
        { "Headlight", 2 },
        { "Radio", 2 },
        { "Microphone", 1 },
        { "Motor", 1 },
        { "StarterMotor", 1 },
        { "PowerSupply", 1 },
        { "Bandage", 2 },
        { "AntiSepBandage", 1 },
        { "Pills", 1 },
    },
}

-- min-max rolls of FILLS[fill] that fit `capacity` together, or {} for an unknown fill; sizeOf(uname) is the item
-- size, rng(a, b) an integer in [a, b]
function M.fill(fill, capacity, sizeOf, rng)
    local list = M.FILLS[fill]
    if not list then
        return {}
    end
    local total = 0
    for _, t in ipairs(list) do
        total = total + t[2]
    end
    local out, used = {}, 0
    for _ = 1, rng(list.min, list.max) do
        local r, pick = rng(1, total), nil
        for _, t in ipairs(list) do
            r = r - t[2]
            if r <= 0 then
                pick = t[1]
                break
            end
        end
        local size = sizeOf(pick) or 1
        if used + size <= capacity then
            out[#out + 1] = pick
            used = used + size
        end
    end
    return out
end

-- the distinct item types of the spots, sorted, for the one query that reads them
function M.types(spots)
    local seen, out = {}, {}
    for _, s in ipairs(spots) do
        if not seen[s[1]] then
            seen[s[1]] = true
            out[#out + 1] = s[1]
        end
    end
    table.sort(out)
    return out
end

return M
