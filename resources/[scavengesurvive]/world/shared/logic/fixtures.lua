-- Fixed world items: the items upstream's zone files create on every start (CreateItem in world/zones/*.pwn: the
-- workbenches, the scrapyard's Scrap and Refine Machine, a barbecue), generated into data/features.lua `fixtures`.
-- The port keeps world items in MariaDB, so on start only the ones that are gone (taken down, picked up and carried
-- off) are made again.
local M = {}

-- a fixture still counts as there while an item of its type lies this close to its spot (a nudged workbench)
M.RADIUS = 2.0

-- fixtures: { { uname, x, y, z, rz, zone }, ... }; rows: the world items of those types, { type_uname, x, y }.
-- Returns the fixtures with no item of their type within M.RADIUS, each row used for one fixture at most.
function M.missing(fixtures, rows)
    local used, out = {}, {}
    for _, f in ipairs(fixtures) do
        local found
        for i, r in ipairs(rows) do
            if not used[i] and r.type_uname == f[1] then
                local dx, dy = (tonumber(r.x) or 0) - f[2], (tonumber(r.y) or 0) - f[3]
                if dx * dx + dy * dy <= M.RADIUS * M.RADIUS then
                    found = i
                    break
                end
            end
        end
        if found then
            used[found] = true
        else
            out[#out + 1] = f
        end
    end
    return out
end

-- the distinct item types of the fixtures, sorted, for the one query that reads them
function M.types(fixtures)
    local seen, out = {}, {}
    for _, f in ipairs(fixtures) do
        if not seen[f[1]] then
            seen[f[1]] = true
            out[#out + 1] = f[1]
        end
    end
    table.sort(out)
    return out
end

return M
