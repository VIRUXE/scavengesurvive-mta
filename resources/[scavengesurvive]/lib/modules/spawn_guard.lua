-- Ignore loading coordinates only while establishing the first post-spawn position.
-- maxWaitMs bounds anticheat grace; loot can wait indefinitely for a real position.
local spawnGuard = {}
function spawnGuard.new(maxWaitMs)
    local states = {}
    local guard = {}
    function guard.reset(player, now)
        states[player] = { since = now, ready = false }
    end
    function guard.forget(player)
        states[player] = nil
    end
    function guard.ready(player, now, x, y, z)
        if type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then
            return false
        end
        if x ~= x or y ~= y or z ~= z then
            return false
        end
        if not states[player] then
            guard.reset(player, now)
        end
        local state = states[player]
        if state.ready then
            return true
        end
        local elapsed = now - state.since
        if elapsed < 1000 then
            return false
        end
        -- Z can drift below zero while an unspawned ped falls at the origin.
        local atOrigin = math.abs(x) < 0.01 and math.abs(y) < 0.01
        if not atOrigin or (maxWaitMs and elapsed >= maxWaitMs) then
            state.ready = true
        end
        return state.ready
    end
    return guard
end
return spawnGuard
