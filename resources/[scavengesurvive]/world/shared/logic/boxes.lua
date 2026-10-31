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
