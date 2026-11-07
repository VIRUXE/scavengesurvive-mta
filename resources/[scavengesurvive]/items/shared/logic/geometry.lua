local geometry = {}

-- MTA rotation: rz in degrees, forward vector = (-sin(rz), cos(rz))
function geometry.dropPosition(x, y, rz, distance)
    local rad = math.rad(rz)
    return x - math.sin(rad) * distance, y + math.cos(rad) * distance
end

-- An element matrix (getElementMatrix rows: right, forward, up, position) turned so world up becomes the ground
-- normal (nx, ny, sqrt(1 - nx^2 - ny^2)): an item at rest on flat ground then rests on the slope. Rodrigues
-- rotation about up x normal; flat ground (nx = ny = 0) returns the matrix unchanged.
function geometry.tilt(m, nx, ny)
    local s = math.sqrt(nx * nx + ny * ny)
    if s < 1e-6 then
        return m
    end
    local c = math.sqrt(math.max(0, 1 - s * s))
    local kx, ky = -ny / s, nx / s
    local out = {}
    for i = 1, 3 do
        local vx, vy, vz = m[i][1], m[i][2], m[i][3]
        local dot = kx * vx + ky * vy
        -- k x v with k = (kx, ky, 0)
        local cx, cy, cz = ky * vz, -kx * vz, kx * vy - ky * vx
        local x = vx * c + cx * s + kx * dot * (1 - c)
        local y = vy * c + cy * s + ky * dot * (1 - c)
        out[i] = { x, y, vz * c + cz * s, m[i][4] or 0 }
    end
    out[4] = m[4]
    return out
end

function geometry.box(x, y, r)
    return x - r, y - r, x + r, y + r
end

-- A point already in a vehicle's local space (right, forward, up from its centre) against its bounding box
-- (getElementBoundingBox: minX, minY, minZ, maxX, maxY, maxZ) grown by margin on every side
function geometry.insideBox(lx, ly, lz, minX, minY, minZ, maxX, maxY, maxZ, margin)
    return lx >= minX - margin
        and lx <= maxX + margin
        and ly >= minY - margin
        and ly <= maxY + margin
        and lz >= minZ - margin
        and lz <= maxZ + margin
end

-- The drop spots around (x, y), in the order they are tried: the heading first, then 30 degrees to either side in
-- turn, at the asked distance and then farther out
geometry.DROP_SCALES = { 1, 1.6, 2.2 }

-- The first free drop spot around (x, y); blocked(cx, cy) says whether a spot is taken; nil when nothing is free
function geometry.freeSpot(x, y, rz, ahead, blocked)
    for _, scale in ipairs(geometry.DROP_SCALES) do
        for step = 0, 12 do
            local turn = math.ceil(step / 2) * 30 * (step % 2 == 1 and 1 or -1)
            local cx, cy = geometry.dropPosition(x, y, rz + turn, ahead * scale)
            if not blocked(cx, cy) then
                return cx, cy
            end
        end
    end
end

-- Whether (cx, cy) is one of freeSpot's spots around (x, y): its distance within tol metres of a ring and its bearing
-- within tolDeg of a 30 degree step from the heading rz (the server's position and heading lag the client's a little)
function geometry.isDropSpot(x, y, rz, ahead, cx, cy, tol, tolDeg)
    local ox, oy = cx - x, cy - y
    local d = math.sqrt(ox * ox + oy * oy)
    local ring = false
    for _, scale in ipairs(geometry.DROP_SCALES) do
        if math.abs(d - ahead * scale) <= tol then
            ring = true
        end
    end
    if not ring then
        return false
    end
    -- forward (-sin rz, cos rz): the bearing of (ox, oy) in the same convention
    local bearing = math.deg(math.atan2(-ox, oy))
    local off = (bearing - rz) % 30
    return off <= tolDeg or off >= 30 - tolDeg
end

function geometry.polygonWKT(minx, miny, maxx, maxy)
    return string.format(
        "POLYGON((%g %g,%g %g,%g %g,%g %g,%g %g))",
        minx,
        miny,
        maxx,
        miny,
        maxx,
        maxy,
        minx,
        maxy,
        minx,
        miny
    )
end

return geometry
