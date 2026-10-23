-- Ladders and ziplines, pure logic. Upstream: Southclaws/samp-ladders (1 m circle at the base, F to grab when
-- between base - 1 and top + 2, climb velocity 0.1 up / 0.07 down / 0.01 idle, auto-exit near the ends after 1 s)
-- and samp-zipline (grab within 2 m of the start or the line, ride 1.2 below the rope with a speed multiplier
-- ramping 0.2 -> 0.5 by 0.01 per 50 ms tick, let go at the 6 m end sphere, when 5 m off the line, or with F).
local F = {}

F.LADDER_RADIUS = 1.0
F.CLIMB_SPEED, F.DESCEND_SPEED, F.IDLE_SPEED = 0.1, 0.07, 0.01
F.LADDER_EXIT_DELAY_MS = 1000
F.ZIP_GRAB_RADIUS, F.ZIP_END_RADIUS, F.ZIP_DROP_DISTANCE = 2.0, 6.0, 5.0
F.ZIP_HANG_BELOW = 1.2
F.ZIP_SPEED_START, F.ZIP_SPEED_MAX, F.ZIP_SPEED_STEP, F.ZIP_EXIT_BOOST = 0.2, 0.5, 0.01, 0.03
F.ZIP_TICK_MS = 50

local function dist2(ax, ay, bx, by)
    return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

-- Index of the ladder whose 1 m base circle holds (x, y) with z inside the usable span, or nil.
function F.ladderAt(ladders, x, y, z)
    for i, l in ipairs(ladders) do
        if dist2(x, y, l[1], l[2]) <= F.LADDER_RADIUS and z < l[4] + 2.0 and z > l[3] - 1.0 then
            return i
        end
    end
    return nil
end

-- Where the player is placed when grabbing: snapped just under the top, just above the base, or where they are.
function F.ladderEnterZ(ladder, z)
    local base, top = ladder[3], ladder[4]
    if math.abs(z - top) < 2.0 then
        return top - 2.0926
    elseif math.abs(z - base) < 2.0 then
        return base + 1.5
    end
    return z
end

-- Vertical velocity for the held direction: "up", "down" or nil (hold on).
function F.ladderVelocity(direction)
    if direction == "up" then
        return F.CLIMB_SPEED
    elseif direction == "down" then
        return -F.DESCEND_SPEED
    end
    return F.IDLE_SPEED
end

-- Upstream leaves the ladder once past the ends, but only after a second on it (the snap moves the player).
function F.ladderShouldExit(ladder, z, msOnLadder)
    if msOnLadder <= F.LADDER_EXIT_DELAY_MS then
        return false
    end
    return (z - ladder[3]) < 0.5 or z >= ladder[4] - 0.5
end

-- Step off: a nudge forward along the facing angle plus a small hop (SA-MP angles, anticlockwise).
function F.ladderExitVelocity(angle)
    local rad = math.rad(-angle)
    return 0.1 * math.sin(rad), 0.1 * math.cos(rad), 0.1
end

-- Unit direction and length of a zipline.
function F.ziplineVector(zl)
    local dx, dy, dz = zl[4] - zl[1], zl[5] - zl[2], zl[6] - zl[3]
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len == 0 then
        return 0, 0, 0, 0
    end
    return dx / len, dy / len, dz / len, len
end

-- Closest point on the rope (as a fraction 0..1 along it) and the distance from (x, y, z) to that point.
function F.ziplineProject(zl, x, y, z)
    local ux, uy, uz, len = F.ziplineVector(zl)
    if len == 0 then
        return 0, math.huge
    end
    local t = ((x - zl[1]) * ux + (y - zl[2]) * uy + (z - zl[3]) * uz) / len
    t = math.max(0, math.min(1, t))
    local px, py, pz = zl[1] + ux * len * t, zl[2] + uy * len * t, zl[3] + uz * len * t
    return t, math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
end

-- Index of the zipline the player may grab from (x, y, z): within 2 m of the start sphere (1 m below the start)
-- or within 2 m of the rope while hanging height is accounted for.
function F.ziplineAt(ziplines, x, y, z)
    for i, zl in ipairs(ziplines) do
        local sx, sy, sz = zl[1], zl[2], zl[3] - 1.0
        if math.sqrt((x - sx) ^ 2 + (y - sy) ^ 2 + (z - sz) ^ 2) <= F.ZIP_GRAB_RADIUS then
            return i
        end
        local t, d = F.ziplineProject(zl, x, y, z + F.ZIP_HANG_BELOW)
        if d <= F.ZIP_GRAB_RADIUS and t < 0.95 then
            return i
        end
    end
    return nil
end

-- Position of the rider for a fraction t along the rope (hanging below it) and the facing angle (SA-MP degrees).
function F.ziplineRiderPos(zl, t)
    local ux, uy, uz, len = F.ziplineVector(zl)
    local x, y, z = zl[1] + ux * len * t, zl[2] + uy * len * t, zl[3] + uz * len * t - F.ZIP_HANG_BELOW
    local angle = (math.deg(math.atan2(-ux, uy))) % 360
    return x, y, z, angle
end

-- Next speed multiplier and the velocity to apply (per tick) along the rope.
function F.ziplineStep(zl, mult)
    mult = math.min(F.ZIP_SPEED_MAX, (mult or F.ZIP_SPEED_START) + F.ZIP_SPEED_STEP)
    local ux, uy, uz = F.ziplineVector(zl)
    return mult, ux * mult, uy * mult, uz * mult
end

-- Let go when the end sphere is reached or the rider drifted off the rope.
function F.ziplineShouldExit(zl, x, y, z)
    if math.sqrt((x - zl[4]) ^ 2 + (y - zl[5]) ^ 2 + (z - zl[6]) ^ 2) <= F.ZIP_END_RADIUS then
        return true, "end"
    end
    local _, d = F.ziplineProject(zl, x, y, z + F.ZIP_HANG_BELOW)
    if d > F.ZIP_DROP_DISTANCE then
        return true, "drift"
    end
    return false
end

return F
