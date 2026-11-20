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

-- Climbing trains Strength: every 5th wall climbed (GTA's own climb over a fence or wall) or every 15 m climbed up
-- ladders, never twice within 10 s. The client reports each climb, the server clamps it.
M.CLIMB_SKILL = "Strength"
M.CLIMBS_PER_XP = 5
M.LADDER_M_PER_XP = 15
M.MAX_WALL_RISE, M.MAX_LADDER_RISE = 3.5, 60 -- metres one report may count
M.MIN_WALL_RISE, M.MIN_LADDER_RISE = 0.8, 2
M.CLIMB_COOLDOWN_MS = 10000

function M.new()
    return {
        dist = {},
        time = {},
        jumps = 0,
        knockedOutMs = 0,
        lastXp = nil,
        nextXpAt = {},
        climbs = 0,
        ladderM = 0,
        nextLadderXpAt = M.LADDER_M_PER_XP,
        lastClimbXp = nil,
    }
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

-- One climb report: kind "wall" (metres = the rise) or "ladder" (metres climbed). Returns true when Strength gains.
function M.climb(t, kind, metres, now)
    metres = tonumber(metres)
    if not metres or metres ~= metres or metres <= 0 then
        return false
    end
    local due
    if kind == "wall" then
        if metres < M.MIN_WALL_RISE then
            return false
        end
        t.climbs = t.climbs + 1
        due = t.climbs % M.CLIMBS_PER_XP == 0
    elseif kind == "ladder" then
        if metres < M.MIN_LADDER_RISE then
            return false
        end
        t.ladderM = t.ladderM + math.min(metres, M.MAX_LADDER_RISE)
        due = false
        while t.ladderM >= t.nextLadderXpAt do
            t.nextLadderXpAt = t.nextLadderXpAt + M.LADDER_M_PER_XP
            due = true
        end
    else
        return false
    end
    if not due then
        return false
    end
    -- a crossing during the cooldown is lost, like Endurance's
    if t.lastClimbXp and now - t.lastClimbXp < M.CLIMB_COOLDOWN_MS then
        return false
    end
    t.lastClimbXp = now
    return true
end

-- The velocity multiplier of a running jump for an Endurance value in [0, 1].
function M.boost(endurance)
    local e = math.max(0, math.min(1, tonumber(endurance) or 0))
    return 1 + M.BOOST_PER_POINT * e
end

-- lang:begin
M.LABELS = {
    walking = "Walking",
    running = "Running",
    sprinting = "Sprinting",
    crouching = "Crouching",
    swimming = "Swimming",
    driving = "Driving",
    air = "Falling",
}
-- lang:end

-- metres -> "850 m" / "1.25 km"
function M.distance(metres)
    metres = tonumber(metres) or 0
    if metres < 1000 then
        return string.format("%d m", math.floor(metres + 0.5))
    end
    return string.format("%.2f km", metres / 1000)
end

-- milliseconds -> "0s" / "45s" / "3m 05s" / "1h 02m"
function M.duration(ms)
    local s = math.floor((tonumber(ms) or 0) / 1000)
    if s < 60 then
        return string.format("%ds", s)
    end
    if s < 3600 then
        return string.format("%dm %02ds", math.floor(s / 60), s % 60)
    end
    return string.format("%dh %02dm", math.floor(s / 3600), math.floor(s % 3600 / 60))
end

-- The /mstats window (ui showInfo spec): one row per kind of movement, then jumps and time knocked out. tr(text)
-- puts the labels in the reader's language (the server passes lang.textFor for the player), identity by default.
function M.window(t, tr)
    tr = tr or function(s)
        return s
    end
    local rows = {}
    for _, kind in ipairs(M.KINDS) do
        rows[#rows + 1] = { tr(M.LABELS[kind]), M.distance(t.dist[kind]), M.duration(t.time[kind]) }
    end
    rows[#rows + 1] = { tr("Jumps"), tostring(t.jumps or 0), "", colour = "#33CCFF" }
    rows[#rows + 1] = { tr("Climbs"), tostring(t.climbs or 0), "", colour = "#33CCFF" }
    rows[#rows + 1] = { tr("Ladders"), M.distance(t.ladderM), "", colour = "#33CCFF" }
    rows[#rows + 1] = { tr("Knocked out"), "", M.duration(t.knockedOutMs), colour = "#33CCFF" }
    local header = "#FFFFFF" .. tr("Movement this session (resets when you log in)")
    local columns = { tr("Activity"), tr("Distance"), tr("Time") }
    return { title = tr("Travel stats"), header = header, columns = columns, rows = rows }
end

return M
