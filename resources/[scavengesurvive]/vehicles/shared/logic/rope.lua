-- A towing rope between two vehicles (Rope item, vehicles/server/towing.lua, client/towing.lua): pure maths, no MTA
-- calls. Velocities are in MTA's units (metres per 1/50 s), as getElementVelocity gives them.
local M = {}

M.LENGTH = 5.0 -- metres between the tower's hitch and the towed vehicle's front
-- The two vehicles' centres (3D, so a drop into water counts) within this to tie the rope on: about 11 m from hitch
-- to bumper for two cars, so a car stays on dry land to pull one out of the water; the rope then draws taut to
-- M.LENGTH, the overshoot taken back at no more than M.MAX_BIAS.
M.TIE_REACH = 16.0
M.PENDING_REACH = 21.0 -- a pending tie is dropped once the player walks this far from the tower (past TIE_REACH)
M.PENDING_MS = 60000 -- or after this long
-- The server unties a rope whose two vehicles' centres are further apart than this (a teleport, a respawn, the
-- physics losing it): the rope falls to the ground by the tower.
M.SNAP_DISTANCE = 22.0
M.BETA = 0.25 -- share of the overshoot past the rope's length taken back each frame
M.MAX_BIAS = 0.06 -- the most the overshoot correction adds, MTA units (3 m/s)
-- The rope's give: the separating speed is taken back over about this many seconds instead of in one frame, so a
-- rope going taut tugs the two vehicles together instead of trading their momentum in one blow.
M.GIVE = 0.08
M.YAW_DAMP = 0.9 -- what is left of the towed vehicle's spin about Z per tick when the rope is taut and it swings
M.SEGMENTS = 14 -- pieces the drawn rope is made of

-- How much the separating speed `vrel` (MTA units, positive: the anchors fly apart) has to come down, given the
-- anchors are `dist` metres apart and the frame lasted `dt` seconds: 0 while there is slack or they already close in.
function M.correction(dist, vrel, dt)
    if dist <= M.LENGTH then
        return 0
    end
    dt = math.max(dt, 0.001)
    local bias = math.min(M.MAX_BIAS, M.BETA * (dist - M.LENGTH) / dt / 50)
    local want = vrel + bias
    if want <= 0 then
        return 0
    end
    return want * (1 - math.exp(-dt / M.GIVE))
end

-- The inverse of the mass a pull along (nx, ny, nz) feels at a point (rx, ry) from a body's centre of mass, the
-- spin only about Z (a car on its wheels): 1/m + (r x n).z^2 / I.
function M.inverseMass(mass, inertia, rx, ry, nx, ny)
    local cross = rx * ny - ry * nx
    return 1 / mass + cross * cross / inertia
end

-- The sag of a rope of M.LENGTH hanging between two points `d` metres apart (a parabola: L = d + 8h^2 / 3d).
function M.sag(d)
    if d >= M.LENGTH then
        return 0
    end
    if d < 0.05 then
        return M.LENGTH / 2
    end
    return math.min(M.LENGTH / 2, math.sqrt(3 * d * (M.LENGTH - d) / 8))
end

-- Points along the rope from a to b (tables {x, y, z}), M.SEGMENTS pieces, hanging by M.sag; never below `floorZ`
-- (the ground under the middle) if given.
function M.points(ax, ay, az, bx, by, bz, floorZ)
    local d = math.sqrt((bx - ax) ^ 2 + (by - ay) ^ 2 + (bz - az) ^ 2)
    local h = M.sag(d)
    local out = {}
    for i = 0, M.SEGMENTS do
        local t = i / M.SEGMENTS
        local z = az + (bz - az) * t - 4 * h * t * (1 - t)
        if floorZ and z < floorZ + 0.03 then
            z = floorZ + 0.03
        end
        out[#out + 1] = { ax + (bx - ax) * t, ay + (by - ay) * t, z }
    end
    return out
end

return M
