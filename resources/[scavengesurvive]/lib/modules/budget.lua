-- Scarcity budget arithmetic (ADR 0001): a carrying capacity per category, refill proportional to the deficit with
-- a floor, jittered cooldowns and placement away from players. Pure functions; rng() returns a float in [0,1).
local budget = {}

-- Carrying capacity from the size of the first roll.
function budget.cap(initial, multiplier)
    local m = tonumber(multiplier) or 1
    return math.max(0, math.floor((tonumber(initial) or 0) * m + 0.5))
end

-- Spawns owed after one interval of `intervalS` seconds. Nothing accrues at or above capacity, the fractional part
-- carries over in `remainder`, and the result never exceeds the deficit. Returns spawns, remainder.
function budget.refill(cap, alive, remainder, ratePerHour, floorPerHour, intervalS)
    local deficit = cap - alive
    if deficit <= 0 then
        return 0, 0
    end
    local perHour = math.max(deficit * (ratePerHour or 0), cap * (floorPerHour or 0))
    local owed = (remainder or 0) + perHour * intervalS / 3600
    local spawns = math.floor(owed)
    if spawns >= deficit then
        return deficit, 0
    end
    return spawns, owed - spawns
end

-- Seconds a consumed point waits before it may roll again: base × (1 ± jitter).
function budget.cooldown(baseS, jitter, rng)
    local j = tonumber(jitter) or 0
    local factor = 1 + (rng() * 2 - 1) * j
    return math.max(0, math.floor(baseS * factor + 0.5))
end

-- True when no entry of `players` (a list of { x =, y = }) lies within minDist of (x, y).
function budget.clearOfPlayers(x, y, players, minDist)
    local limit = minDist * minDist
    for _, p in ipairs(players) do
        local dx, dy = p.x - x, p.y - y
        if dx * dx + dy * dy < limit then
            return false
        end
    end
    return true
end

-- Up to n points of `points` in random order that are clear of every player.
function budget.pickClear(points, players, minDist, n, rng)
    local order = {}
    for i = 1, #points do
        order[i] = i
    end
    for i = #order, 2, -1 do
        local j = math.floor(rng() * i) + 1
        order[i], order[j] = order[j], order[i]
    end
    local out = {}
    for _, i in ipairs(order) do
        if #out >= n then
            break
        end
        local p = points[i]
        if budget.clearOfPlayers(p.x, p.y, players, minDist) then
            out[#out + 1] = p
        end
    end
    return out
end

return budget
