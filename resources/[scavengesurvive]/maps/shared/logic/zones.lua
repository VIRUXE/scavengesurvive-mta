-- Zone polygon geometry and point-in-polygon lookup (upstream pyss/pyss/utility/regions.py).
-- Pure logic: no MTA calls at file scope so busted can load it directly.
local zones = {}

zones.ORDER = { "ls", "sf", "lv", "rc", "fc", "bc", "tr" }
zones.FLOOR_Z = -1000 -- MTA createColPolygon defaults to floor Z = 0; extend below sea/tunnel level

function zones.signedArea(pts)
    local n = #pts
    if n < 3 then
        return 0
    end
    local last = (pts[1][1] == pts[n][1] and pts[1][2] == pts[n][2]) and (n - 1) or n
    if last < 3 then
        return 0
    end
    local area = 0
    for i = 1, last do
        local j = (i % last) + 1
        area = area + (pts[i][1] * pts[j][2] - pts[j][1] * pts[i][2])
    end
    return area * 0.5
end

-- Strips a duplicate closing vertex and ensures counter-clockwise winding (required by MTA createColPolygon).
function zones.normalize(pts)
    local n = #pts
    if n > 1 and pts[1][1] == pts[n][1] and pts[1][2] == pts[n][2] then
        n = n - 1
    end
    local out = {}
    for i = 1, n do
        out[i] = { pts[i][1], pts[i][2] }
    end
    if #out >= 3 and zones.signedArea(out) < 0 then
        local rev = {}
        for i = #out, 1, -1 do
            rev[#rev + 1] = out[i]
        end
        out = rev
    end
    return out
end

function zones.centroid(pts)
    local norm = zones.normalize(pts)
    local n = #norm
    if n == 0 then
        return 0, 0
    end
    local area = zones.signedArea(norm)
    if math.abs(area) < 1e-6 then
        local sx, sy = 0, 0
        for i = 1, n do
            sx, sy = sx + norm[i][1], sy + norm[i][2]
        end
        return sx / n, sy / n
    end
    local cx, cy = 0, 0
    for i = 1, n do
        local j = (i % n) + 1
        local x0, y0 = norm[i][1], norm[i][2]
        local x1, y1 = norm[j][1], norm[j][2]
        local cross = x0 * y1 - x1 * y0
        cx = cx + (x0 + x1) * cross
        cy = cy + (y0 + y1) * cross
    end
    local factor = 1 / (area * 6)
    return cx * factor, cy * factor
end

-- Returns { cx, cy, x1, y1, x2, y2, ... } for createColPolygon(unpack(args)).
function zones.colPolygonArgs(pts)
    local norm = zones.normalize(pts)
    local cx, cy = zones.centroid(norm)
    local args = { cx, cy }
    for i = 1, #norm do
        args[#args + 1] = norm[i][1]
        args[#args + 1] = norm[i][2]
    end
    return args
end

-- Ray-casting point-in-polygon matching upstream pyss/pyss/utility/regions.py:is_point_in_poly.
function zones.contains(pts, x, y)
    if type(pts) ~= "table" or #pts < 3 or type(x) ~= "number" or type(y) ~= "number" then
        return false
    end
    local n = #pts
    if pts[1][1] == pts[n][1] and pts[1][2] == pts[n][2] then
        n = n - 1
    end
    if n < 3 then
        return false
    end
    for i = 1, n do
        if pts[i][1] == x and pts[i][2] == y then
            return true
        end
        local j = (i % n) + 1
        local p1, p2 = pts[i], pts[j]
        if p1[2] == p2[2] and p1[2] == y and x > math.min(p1[1], p2[1]) and x < math.max(p1[1], p2[1]) then
            return true
        end
    end
    local inside = false
    local p1x, p1y = pts[1][1], pts[1][2]
    for i = 1, n do
        local idx = (i % n) + 1
        local p2x, p2y = pts[idx][1], pts[idx][2]
        if y > math.min(p1y, p2y) and y <= math.max(p1y, p2y) and x <= math.max(p1x, p2x) then
            local xinters = p1x
            if p1y ~= p2y then
                xinters = (y - p1y) * (p2x - p1x) / (p2y - p1y) + p1x
            end
            if p1x == p2x or x <= xinters then
                inside = not inside
            end
        end
        p1x, p1y = p2x, p2y
    end
    return inside
end

function zones.findAt(polygons, x, y)
    x, y = tonumber(x), tonumber(y)
    if not x or not y or type(polygons) ~= "table" then
        return false
    end
    for _, name in ipairs(zones.ORDER) do
        local poly = polygons[name]
        if poly and zones.contains(poly, x, y) then
            return name
        end
    end
    return false
end

return zones
