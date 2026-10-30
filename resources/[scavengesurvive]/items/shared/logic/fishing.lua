-- Fishing (upstream core/item/fishingrod.pwn, #141): the cast distance from how long the key was held, the spot
-- the line lands on, the wait, the odds (better with the Fishing skill) and the delay before the fish is landed.
-- Pure rules; the server checks the spot is water and runs the timers.
local M = {}

M.MAX_CAST_MS = 10000 -- MAX_FISHING_DISTANCE: the hold is capped here, 100 ms of hold = 1 m of line
M.MIN_WAIT_MS, M.MAX_WAIT_MS = 30000, 120000
M.MISS_PER_MILLE = 700 -- 1000 - FISHING_CHANCE: the skill's time modifier shortens this
M.ROD = "FishRod"
M.CATCH = "RawFish"

function M.castDistance(heldMs)
    local ms = math.max(0, math.min(M.MAX_CAST_MS, tonumber(heldMs) or 0))
    return ms / 100
end

-- where the line lands: dist metres ahead of a player at (x, y) facing rz
function M.castPoint(x, y, rz, dist)
    local rad = math.rad(rz or 0)
    return x - dist * math.sin(rad), y + dist * math.cos(rad)
end

-- how long until the line moves, before the skill shortens it (randInt(a, b) inclusive)
function M.waitMs(randInt)
    return (randInt or math.random)(M.MIN_WAIT_MS, M.MAX_WAIT_MS)
end

-- upstream: random(1000) < 1000 - SkillTimeModifier(700, "Fishing"); roll in 0..999, missPerMille the modified 700
function M.caught(roll, missPerMille)
    return roll < 1000 - (tonumber(missPerMille) or M.MISS_PER_MILLE)
end

-- the fish is landed this long after the tug: 100 ms per metre of line
function M.catchDelayMs(dist)
    return math.floor((tonumber(dist) or 0) + 0.5) * 100
end

return M
