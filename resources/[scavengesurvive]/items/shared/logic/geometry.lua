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

-- v turned by angle a (radians) about the unit axis k (Rodrigues)
local function rotateAbout(v, k, a)
    local c, s = math.cos(a), math.sin(a)
    local dot = k[1] * v[1] + k[2] * v[2] + k[3] * v[3]
    local cx, cy, cz = k[2] * v[3] - k[3] * v[2], k[3] * v[1] - k[1] * v[3], k[1] * v[2] - k[2] * v[1]
    return {
        v[1] * c + cx * s + k[1] * dot * (1 - c),
        v[2] * c + cy * s + k[2] * dot * (1 - c),
        v[3] * c + cz * s + k[3] * dot * (1 - c),
    }
end

-- The rigid motion that carries element matrix m0 onto m1 (rows right, forward, up, position) as one screw: a turn
-- of angle about axis k through the point c, plus a slide along k. Driven through motionAt, a defence a Motor moves
-- swings about the line that stays put (its hinge) instead of sliding into its new pose. Returns a table for
-- motionAt; angle 0 when nothing turns (the position is then just slid).
function geometry.motion(m0, m1)
    -- R takes each of m0's axes onto m1's: R = sum_i m1_i (x) m0_i
    local R = {}
    for a = 1, 3 do
        R[a] = {}
        for b = 1, 3 do
            R[a][b] = m1[1][a] * m0[1][b] + m1[2][a] * m0[2][b] + m1[3][a] * m0[3][b]
        end
    end
    local p0 = { m0[4][1], m0[4][2], m0[4][3] }
    local p1 = { m1[4][1], m1[4][2], m1[4][3] }
    local cosA = math.max(-1, math.min(1, (R[1][1] + R[2][2] + R[3][3] - 1) / 2))
    local angle = math.acos(cosA)
    local mo = { m0 = m0, p0 = p0, angle = angle }
    if angle < 1e-3 then
        mo.angle, mo.k, mo.c = 0, { 0, 0, 1 }, { 0, 0, 0 }
        mo.slide = { p1[1] - p0[1], p1[2] - p0[2], p1[3] - p0[3] }
        return mo
    end
    local k
    local sinA = math.sin(angle)
    if sinA > 1e-4 then
        k = { (R[3][2] - R[2][3]) / (2 * sinA), (R[1][3] - R[3][1]) / (2 * sinA), (R[2][1] - R[1][2]) / (2 * sinA) }
    else -- a half turn: the axis from the diagonal
        local j = 1
        for i = 2, 3 do
            if R[i][i] > R[j][j] then
                j = i
            end
        end
        k = { 0, 0, 0 }
        k[j] = math.sqrt(math.max(0, (R[j][j] + 1) / 2))
        for i = 1, 3 do
            if i ~= j then
                k[i] = R[j][i] / (2 * k[j])
            end
        end
    end
    local len = math.sqrt(k[1] * k[1] + k[2] * k[2] + k[3] * k[3])
    k = { k[1] / len, k[2] / len, k[3] / len }
    -- t = p1 - R p0, split along and across the axis; the axis point c solves (I - R) c = t across it
    local Rp0 = {
        R[1][1] * p0[1] + R[1][2] * p0[2] + R[1][3] * p0[3],
        R[2][1] * p0[1] + R[2][2] * p0[2] + R[2][3] * p0[3],
        R[3][1] * p0[1] + R[3][2] * p0[2] + R[3][3] * p0[3],
    }
    local t = { p1[1] - Rp0[1], p1[2] - Rp0[2], p1[3] - Rp0[3] }
    local along = t[1] * k[1] + t[2] * k[2] + t[3] * k[3]
    local slide = { k[1] * along, k[2] * along, k[3] * along }
    local q = { t[1] - slide[1], t[2] - slide[2], t[3] - slide[3] }
    local kq = { k[2] * q[3] - k[3] * q[2], k[3] * q[1] - k[1] * q[3], k[1] * q[2] - k[2] * q[1] }
    local cot = math.cos(angle / 2) / math.sin(angle / 2)
    mo.k, mo.slide = k, slide
    mo.c = { (q[1] + cot * kq[1]) / 2, (q[2] + cot * kq[2]) / 2, (q[3] + cot * kq[3]) / 2 }
    return mo
end

-- the element matrix a fraction s (0..1) of the way through a geometry.motion
function geometry.motionAt(mo, s)
    local a = mo.angle * s
    local out = {}
    for i = 1, 3 do
        local v = rotateAbout(mo.m0[i], mo.k, a)
        out[i] = { v[1], v[2], v[3], mo.m0[i][4] or 0 }
    end
    local c, p0 = mo.c, mo.p0
    local p = rotateAbout({ p0[1] - c[1], p0[2] - c[2], p0[3] - c[3] }, mo.k, a)
    out[4] = {
        p[1] + c[1] + mo.slide[1] * s,
        p[2] + c[2] + mo.slide[2] * s,
        p[3] + c[3] + mo.slide[3] * s,
        mo.m0[4][4] or 1,
    }
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
