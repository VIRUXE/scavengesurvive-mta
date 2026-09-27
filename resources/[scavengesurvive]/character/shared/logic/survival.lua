local survival = {}
survival.NEW = { hp = 90, food = 80, bleed = 0.0001 }
survival.RESPAWN = { hp = 100, food = 40, bleed = 0 }
survival.IDLE_FOOD_RATE = 0.004
survival.REGEN_PER_FOOD = 0.001925925

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

function survival.movementMultiplier(speed, inVehicle)
    if inVehicle then
        return 0.2
    end
    if speed <= 0.001 then
        return 1.0
    end
    if speed < 0.09 then
        return 1.2
    end
    if speed < 0.13 then
        return 1.8
    end
    return 2.2
end

-- The wound count is not persisted: a loaded character that is really bleeding keeps one wound, so the tick
-- does not stop the bleed (relog would cure it otherwise). The new-spawn token bleed is not a wound.
function survival.woundsOnLoad(bleed)
    return (tonumber(bleed) or 0) > survival.NEW.bleed and 1 or 0
end

-- rng() must return a float in [0,1)
function survival.tick(state, movementMult, rng)
    local s = { hp = state.hp, food = state.food, bleed = state.bleed, wounds = state.wounds or 0 }
    local events = {}
    s.food = clamp(s.food - survival.IDLE_FOOD_RATE * movementMult, 0, 100)
    if s.food < 20 then
        s.hp = s.hp - (20 - s.food) / 30
    end
    if s.bleed > 0 then
        -- upstream computes the slow-down from HP before this second's bleed damage
        local hpBefore = s.hp
        if rng() < 0.7 then
            s.hp = s.hp - s.bleed
        end
        if s.wounds > 0 then
            local slow = (((100 - hpBefore) / 360) * s.bleed / s.wounds) / 100
            if rng() < 0.5 then
                s.bleed = s.bleed - slow
            end
        else
            s.bleed = 0
        end
        if s.bleed ~= s.bleed or s.bleed < 0 then
            s.bleed = 0
        end
    else
        s.hp = s.hp + survival.REGEN_PER_FOOD * s.food
    end
    s.hp = clamp(s.hp, 0, 100)
    s.bleed = clamp(s.bleed, 0, 1)
    if s.hp <= 0 then
        events[#events + 1] = "died"
    end
    return s, events
end

return survival
