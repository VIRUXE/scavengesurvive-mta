-- Travel stats (upstream core/char/travel-stats.pwn, #138): how far and how long a character moves each way,
-- the jumps, and when the Endurance skill earns experience: every 500 m run or sprinted, every 200 m swum,
-- every 10th jump, never twice within 10 s. A jump while running is boosted by the skill.
-- Pure rules; the server classifies the second's movement from what it can see (vehicle, water, crouch, speed)
-- and the client applies the boost.
local M = {}

M.KINDS = { "walking", "running", "sprinting", "crouching", "swimming", "driving", "air" }
M.XP_EVERY = { running = 500, sprinting = 500, swimming = 200 } -- metres per Endurance gain
M.XP_COOLDOWN_MS = 10000
M.JUMPS_PER_XP = 10
M.BOOST_PER_POINT = 1.3 -- velocity x (1 + 1.3 x Endurance) on a running jump
M.MAX_STEP_FOOT, M.MAX_STEP_VEHICLE = 25, 75 -- further than this in one second is a teleport, not travel
-- metres per second on foot: GTA walks at about 1.5, runs at about 4.5 and sprints at about 6.5
M.WALK_SPEED, M.RUN_SPEED, M.SPRINT_SPEED = 0.5, 2.5, 5.5

function M.new()
    return { dist = {}, time = {}, jumps = 0, knockedOutMs = 0, lastXp = nil, nextXpAt = {} }
end

-- The kind of movement a second was, or nil for standing still.
-- m = { inVehicle, inWater, ducked, falling, speed (metres per second) }
function M.classify(m)
    if m.inVehicle then
        return "driving"
    end
    if m.inWater then
        return "swimming"
    end
    if m.falling then
        return "air"
    end
    local speed = m.speed or 0
    if speed < M.WALK_SPEED then
        return nil
    end
    if m.ducked then
        return "crouching"
    end
    if speed >= M.SPRINT_SPEED then
        return "sprinting"
    end
    if speed >= M.RUN_SPEED then
        return "running"
    end
    return "walking"
end

-- Adds a second of movement. Returns true when the Endurance skill gains for it.
function M.record(t, kind, dist, ms, now)
    if not kind then
        return false
    end
    local limit = kind == "driving" and M.MAX_STEP_VEHICLE or M.MAX_STEP_FOOT
    if dist > limit then
        return false
    end
    t.dist[kind] = (t.dist[kind] or 0) + dist
    t.time[kind] = (t.time[kind] or 0) + ms
    local every = M.XP_EVERY[kind]
    if not every then
        return false
    end
    local due = t.nextXpAt[kind] or every
    if t.dist[kind] < due then
        return false
    end
    while due <= t.dist[kind] do
        due = due + every
    end
    t.nextXpAt[kind] = due
    -- a crossing during the cooldown is lost, as upstream's check was
    if t.lastXp and now - t.lastXp < M.XP_COOLDOWN_MS then
        return false
    end
    t.lastXp = now
    return true
end

-- One jump. Returns true on every JUMPS_PER_XP-th.
function M.jump(t)
    t.jumps = t.jumps + 1
    return t.jumps % M.JUMPS_PER_XP == 0
end

-- The velocity multiplier of a running jump for an Endurance value in [0, 1].
function M.boost(endurance)
    local e = math.max(0, math.min(1, tonumber(endurance) or 0))
    return 1 + M.BOOST_PER_POINT * e
end

-- upstream /mstats lines
function M.lines(t)
    local out = {}
    for _, kind in ipairs(M.KINDS) do
        out[#out + 1] = string.format("DIST_%s: %.1f", string.upper(kind), t.dist[kind] or 0)
    end
    for _, kind in ipairs(M.KINDS) do
        out[#out + 1] = string.format("TIME_%s: %d", string.upper(kind), t.time[kind] or 0)
    end
    out[#out + 1] = string.format("TIME_KNOCKED_OUT: %d", t.knockedOutMs or 0)
    out[#out + 1] = string.format("JUMPS: %d", t.jumps or 0)
    return out
end

return M
