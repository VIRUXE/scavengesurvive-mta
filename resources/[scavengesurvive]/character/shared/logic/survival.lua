local survival = {}
survival.NEW = { hp = 90, food = 80, bleed = 0.0001 }
survival.RESPAWN = { hp = 100, food = 40, bleed = 0 }
survival.IDLE_FOOD_RATE = 0.004
survival.REGEN_PER_FOOD = 0.001925925
survival.MAX_KNOCKOUT_MS = 120000
survival.MIN_KNOCKOUT_MS = 1500

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

-- Wound count for a character loaded from the DB. Only the bleed rate is persisted, and the tick
-- stops bleeding at wounds == 0, so a bleeding character gets one wound back instead of a free cure
-- on relog. A new character's seed bleed (NEW.bleed) is not a wound.
function survival.loadWounds(bleed, isNew)
    if isNew then
        return 0
    end
    return (tonumber(bleed) or 0) > 0 and 1 or 0
end

-- rng() must return a float in [0,1). state.infection = { food, wound } and state.drugs = { [name] = ms } are
-- optional (#94): food infection adds one idle food rate, wound infection halves the regeneration, and the drug
-- effects of bleed.pwn and drugfx.pwn apply once per tick (upstream ran Air and Adrenaline twice, ADR 0007).
function survival.tick(state, movementMult, rng)
    local s = { hp = state.hp, food = state.food, bleed = state.bleed, wounds = state.wounds or 0 }
    local events = {}
    local infection, drugs = state.infection or {}, state.drugs or {}
    local drain = survival.IDLE_FOOD_RATE * movementMult
    if infection.food then
        drain = drain + survival.IDLE_FOOD_RATE
    end
    s.food = clamp(s.food - drain, 0, 100)
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
        s.hp = s.hp + survival.REGEN_PER_FOOD * s.food * (infection.wound and 0.5 or 1.0)
    end
    if drugs.Morphine and rng() < 0.8 then
        s.hp = s.hp + 0.5
    end
    if drugs.Air and rng() < 0.5 then
        s.hp = s.hp - 1.0
    end
    if drugs.Adrenaline then
        s.hp = s.hp + 0.01
    end
    s.hp = clamp(s.hp, 0, 100)
    s.bleed = clamp(s.bleed, 0, 1)
    if s.hp <= 0 then
        events[#events + 1] = "died"
    end
    return s, events
end

function survival.knockoutAdd(remainingMs, addMs)
    local rem = math.max(0, math.floor(tonumber(remainingMs) or 0))
    local add = math.max(0, math.floor(tonumber(addMs) or 0))
    if rem <= 0 and add <= survival.MIN_KNOCKOUT_MS then
        return 0
    end
    return clamp(rem + add, 0, survival.MAX_KNOCKOUT_MS)
end

return survival
