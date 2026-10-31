-- Pure detection-field logic (upstream admin/detfield*.pwn): a field is a polygon of {x, y} points with a Z band,
-- and a player's first step into it is reported once until they leave. No MTA calls at file scope.
local fields = {}

-- Even-odd rule: a horizontal ray from (x, y) crosses an odd number of edges when the point is inside.
function fields.insidePolygon(x, y, points)
    local hit = false
    local j = #points
    for i = 1, #points do
        local a, b = points[i], points[j]
        if (a[2] > y) ~= (b[2] > y) and x < (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) + a[1] then
            hit = not hit
        end
        j = i
    end
    return hit
end

function fields.contains(field, x, y, z)
    if z < field.min_z or z > field.max_z then
        return false
    end
    return fields.insidePolygon(x, y, field.points)
end

-- Builds a field from an anticheat_fields row and its decoded points; nil when the row is not a usable
-- four-point polygon (rows are written by /field add, but the table can be edited by hand).
function fields.fromRow(row, points)
    if type(points) ~= "table" or #points ~= 4 then
        return nil
    end
    local clean = {}
    for i = 1, 4 do
        local p = points[i]
        local px, py = type(p) == "table" and tonumber(p[1]), type(p) == "table" and tonumber(p[2])
        if not px or not py then
            return nil
        end
        clean[i] = { px, py }
    end
    local minZ, maxZ = tonumber(row.min_z), tonumber(row.max_z)
    if not minZ or not maxZ or minZ >= maxZ then
        return nil
    end
    return { id = tonumber(row.id), name = row.name, points = clean, min_z = minZ, max_z = maxZ }
end

-- The fields a position lies in, keyed by id, and the ones among them that `previous` (last call's result for
-- the same player) did not hold: those are the entries to log.
function fields.scan(list, previous, x, y, z)
    local active, entered = {}, {}
    for _, field in ipairs(list) do
        if fields.contains(field, x, y, z) then
            active[field.id] = true
            if not (previous and previous[field.id]) then
                entered[#entered + 1] = field
            end
        end
    end
    return active, entered
end

return fields
