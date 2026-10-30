-- The ground under a point and how to lay something flat on it, slope included: blood pools, and anything else
-- that should sit on terrain rather than float over a slope or sink into it. Client-side for below (it raycasts
-- the streamed-in world); matrix is pure.
local surface = {}

-- The first building or object surface straight below (x, y, z), searched from `above` metres over the point to
-- `depth` metres under it, peds and vehicles ignored: hx, hy, hz, nx, ny, nz, or nil where nothing is loaded there.
function surface.below(x, y, z, above, depth)
    local top, bottom = z + (above or 0.5), z - (depth or 3)
    local hit, hx, hy, hz, _, nx, ny, nz = processLineOfSight(x, y, top, x, y, bottom, true, false, false, true)
    if not hit then
        return nil
    end
    return hx, hy, hz, nx, ny, nz
end

-- The element matrix (rows right, forward, up, position, as setElementMatrix takes) of something lying at (x, y, z)
-- on ground with normal (nx, ny, nz), turned `yaw` degrees about that normal and lifted `lift` metres along it. Its
-- local z is the normal and its forward is the flat yaw direction projected onto the ground, falling back to world
-- x on a wall that faces exactly that way.
function surface.matrix(x, y, z, nx, ny, nz, yaw, lift)
    local len = math.sqrt(nx * nx + ny * ny + nz * nz)
    if len < 1e-6 then
        nx, ny, nz, len = 0, 0, 1, 1
    end
    nx, ny, nz = nx / len, ny / len, nz / len
    local rad = math.rad(yaw or 0)
    local fx, fy, fz = -math.sin(rad), math.cos(rad), 0
    local d = fx * nx + fy * ny
    fx, fy, fz = fx - d * nx, fy - d * ny, fz - d * nz
    local fl = math.sqrt(fx * fx + fy * fy + fz * fz)
    if fl < 1e-6 then
        fx, fy, fz = 1 - nx * nx, -nx * ny, -nx * nz
        fl = math.sqrt(fx * fx + fy * fy + fz * fz)
    end
    fx, fy, fz = fx / fl, fy / fl, fz / fl
    -- right = forward x up, so right x forward = up
    local rx, ry, rz = fy * nz - fz * ny, fz * nx - fx * nz, fx * ny - fy * nx
    lift = lift or 0
    return {
        { rx, ry, rz, 0 },
        { fx, fy, fz, 0 },
        { nx, ny, nz, 0 },
        { x + nx * lift, y + ny * lift, z + nz * lift, 1 },
    }
end

return surface
