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
