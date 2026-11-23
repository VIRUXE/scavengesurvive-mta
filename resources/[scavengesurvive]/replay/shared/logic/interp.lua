-- Pure sampling of a replay track (docs/superpowers/specs/2026-11-23-replay-design.md, Appendix A): the state of an
-- actor or a vehicle at any time t (milliseconds since the session's start) from its recorded samples.
-- Positions go through a Catmull-Rom spline with the end tangents clamped, so a ghost curves through 5 Hz or 2 s
-- samples without overshooting; headings take the shortest arc; everything else holds the earlier sample's value.
local M = {}

-- Gaps above this between two samples count as "no data": the actor stays where it was instead of sliding across.
M.MAX_GAP_MS = 20000
-- A sparse (2 s character_track) track may legitimately have a long idle gap; the position still holds.
M.SPARSE_GAP_MS = 130000

local floor = math.floor

-- the index of the last sample with s.t <= t (0 before the first one); samples are sorted by t
function M.find(samples, t)
    local lo, hi = 1, #samples
    local found = 0
    while lo <= hi do
        local mid = floor((lo + hi) / 2)
        if samples[mid].t <= t then
            found = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end
    return found
end

function M.angleDelta(a, b)
    return ((b - a + 180) % 360) - 180
end

function M.lerpAngle(a, b, f)
    return (a + M.angleDelta(a, b) * f) % 360
end

local function catmull(p0, p1, p2, p3, f)
    local f2, f3 = f * f, f * f * f
    return 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 + (-p0 + 3 * p1 - 3 * p2 + p3) * f3)
end

-- keep the spline between its two knots (no overshoot above 25% of the span): a long smooth curve is wrong for
-- someone who stopped and turned
local function clampedCatmull(p0, p1, p2, p3, f)
    local v = catmull(p0, p1, p2, p3, f)
    local lo, hi = math.min(p1, p2), math.max(p1, p2)
    local slack = (hi - lo) * 0.25
    if v < lo - slack then
        return lo - slack
    elseif v > hi + slack then
        return hi + slack
    end
    return v
end

-- the interpolated state of a track at t, or nil before its first sample / when it has no samples. Fields that are
-- not numbers (move, anim, weapon, aim, fire, veh, seat, int, dim) come from the earlier sample. `gap` is true when
-- the track has no fresh data around t (the actor holds its last place).
function M.at(samples, t)
    local n = #samples
    if n == 0 then
        return nil
    end
    local i = M.find(samples, t)
    if i == 0 then
        return nil
    end
    local a = samples[i]
    local b = samples[i + 1]
    local out = {}
    for k, v in pairs(a) do
        out[k] = v
    end
    out.sample = a
    if not b then
        out.last = true
        return out
    end
    local span = b.t - a.t
    local limit = (a.sparse or b.sparse) and M.SPARSE_GAP_MS or M.MAX_GAP_MS
    if span <= 0 then
        return out
    end
    local f = (t - a.t) / span
    if span > limit or a.int ~= b.int or a.dim ~= b.dim then
        out.gap = span > limit or nil
        return out -- no blending across a gap or an interior change: stay at a until b is reached
    end
    local p0 = samples[i - 1] or a
    local p3 = samples[i + 2] or b
    -- tangent neighbours that are far away in time belong to another movement: use the knot itself
    if a.t - p0.t > limit then
        p0 = a
    end
    if p3.t - b.t > limit then
        p3 = b
    end
    out.x = clampedCatmull(p0.x, a.x, b.x, p3.x, f)
    out.y = clampedCatmull(p0.y, a.y, b.y, p3.y, f)
    out.z = clampedCatmull(p0.z, a.z, b.z, p3.z, f)
    if a.rz and b.rz then
        out.rz = M.lerpAngle(a.rz, b.rz, f)
    end
    if a.hp and b.hp then
        out.hp = a.hp + (b.hp - a.hp) * f
    end
    if a.rx and b.rx then
        out.rx = M.lerpAngle(a.rx, b.rx, f)
        out.ry = M.lerpAngle(a.ry or 0, b.ry or 0, f)
    end
    if a.sparse and a.rz == nil then
        -- a character_track point has no heading: face where the actor is going
        local dx, dy = b.x - a.x, b.y - a.y
        if dx * dx + dy * dy > 0.04 then
            out.rz = (-math.deg(math.atan2(dx, dy))) % 360
        end
    end
    out.f = f
    return out
end

-- speed in m/s of a track around t (finite difference over the surrounding samples), for choosing walk/run anims
-- on tracks that have no recorded move state
function M.speed(samples, t)
    local i = M.find(samples, t)
    if i == 0 then
        return 0
    end
    local a = samples[i]
    local b = samples[i + 1] or a
    if b == a then
        a = samples[i - 1] or a
    end
    local dt = (b.t - a.t) / 1000
    if dt <= 0 then
        return 0
    end
    local dx, dy = b.x - a.x, b.y - a.y
    return math.sqrt(dx * dx + dy * dy) / dt
end

-- the move state an actor plays: the recorded one, else derived from its speed (character_track has none)
function M.moveState(state, speed)
    if state.move and state.move ~= "" then
        return state.move
    end
    if state.seat and state.veh then
        return "vehicle"
    end
    if speed > 5.5 then
        return "sprint"
    elseif speed > 2.6 then
        return "run"
    elseif speed > 0.4 then
        return "walk"
    end
    return "stand"
end

return M
