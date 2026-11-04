-- Vehicle starter motor: how many engine starts one lasts and whether a car spawns with a dead one.
-- Pure logic: no MTA calls at file scope. A starter's life is the number of starts it has left; 0 is a dead starter.
local M = {}

M.LIFE_MIN = 60 -- starts a fresh starter motor lasts at least
M.LIFE_MAX = 400 -- and at most
M.SPAWN_BAD_CHANCE = 0.02 -- share of spawned vehicles whose starter motor is already dead

-- a fresh starter motor's life, rolled once when it goes in
function M.freshLife(rng)
    rng = rng or math.random
    return M.LIFE_MIN + math.floor(rng() * (M.LIFE_MAX - M.LIFE_MIN + 1))
end

-- the starter motor of a newly spawned vehicle: very rarely dead, otherwise fresh
function M.spawnLife(rng)
    rng = rng or math.random
    if rng() < M.SPAWN_BAD_CHANCE then
        return 0
    end
    return M.freshLife(rng)
end

-- nil (a row from before starter motors were tracked) counts as fresh
function M.isBad(life)
    return life ~= nil and life <= 0
end

-- one attempt to crank the engine: ok, and the life left afterwards
function M.crank(life)
    if M.isBad(life) then
        return false, 0, "STARTER_BAD"
    end
    return true, math.max(0, (life or M.LIFE_MAX) - 1)
end

return M
