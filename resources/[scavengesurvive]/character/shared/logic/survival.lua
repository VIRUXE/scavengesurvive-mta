local survival = {}
survival.NEW = { hp = 90, food = 80, thirst = 80, bleed = 0.0001 }
survival.RESPAWN = { hp = 100, food = 40, thirst = 40, bleed = 0 }
survival.IDLE_FOOD_RATE = 0.004
survival.IDLE_THIRST_RATE = 0.004
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

-- Wounds (upstream weapon/damage.pwn wnd_Data): every wound the character carries, oldest first, each
-- { part = GTA body part 3-9, bleed, source = the cause, at = unix time }. Healing takes the oldest first
-- (RemovePlayerWounds), the inventory counts them per body part (GetPlayerWoundsPerBodypart), a wound past
-- MAX_WOUNDS kills (PlayerInflictWound) and a new character starts with none. The tick stops bleeding at no wounds.
survival.MAX_WOUNDS = 32
survival.BODYPARTS = { 3, 4, 5, 6, 7, 8, 9 } -- torso, groin, left arm, right arm, left leg, right leg, head

local function bodypart(p)
    p = tonumber(p)
    if p and p >= 3 and p <= 9 and p == math.floor(p) then
        return p
    end
    return 3
end

-- false when the character already carries MAX_WOUNDS (the caller kills them, as upstream did)
function survival.addWound(list, part, bleed, source, at)
    if #list >= survival.MAX_WOUNDS then
        return false
    end
    list[#list + 1] = {
        part = bodypart(part),
        bleed = math.max(0, tonumber(bleed) or 0),
        source = tostring(source or "unknown"):gsub("[^%w_]", ""):sub(1, 16),
        at = math.floor(tonumber(at) or 0),
    }
    return true
end

-- removes the n oldest wounds; returns how many went
function survival.removeWounds(list, n)
    n = math.min(#list, math.max(0, math.floor(tonumber(n) or 0)))
    for _ = 1, n do
        table.remove(list, 1)
    end
    return n
end

-- { count per body part } in BODYPARTS order
function survival.woundsPerPart(list)
    local out, index = {}, {}
    for i, p in ipairs(survival.BODYPARTS) do
        out[i], index[p] = 0, i
    end
    for _, w in ipairs(list) do
        local i = index[w.part]
        if i then
            out[i] = out[i] + 1
        end
    end
    return out
end

-- characters.wounds: [[part, bleed, "source", at], ...]
function survival.encodeWounds(list)
    local parts = {}
    for _, w in ipairs(list) do
        parts[#parts + 1] = string.format('[%d,%.6f,"%s",%d]', w.part, w.bleed, w.source, w.at)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

-- decoded = the column decoded (nil for a new character). A character saved before the column was kept ([] with
-- bleed > 0) gets one torso wound, so its bleeding slows instead of stopping on the first tick.
function survival.decodeWounds(decoded, bleed, isNew)
    local list = {}
    if isNew then
        return list
    end
    if type(decoded) == "table" then
        for _, w in ipairs(decoded) do
            if type(w) == "table" then
                survival.addWound(list, w[1], w[2], w[3], w[4])
            end
        end
    end
    if #list == 0 and (tonumber(bleed) or 0) > 0 then
        survival.addWound(list, 3, bleed, "unknown", 0)
    end
    return list
end

-- The cause of a death in the survival tick: a tick drains HP through bleeding (bleed > 0 at its start), hunger
-- (food < 20), dehydration (thirst < 20) or the Air drug. Bleeding wins when several applied.
function survival.deathCause(bleedBefore, food, thirst)
    if bleedBefore > 0 then
        return "bleeding"
    end
    if food < 20 then
        return "starvation"
    end
    if (thirst or 100) < 20 then
        return "dehydration"
    end
    return "drugs"
end

-- rng() must return a float in [0,1). state.infection = { food, wound } and state.drugs = { [name] = ms } are
-- optional (#94): food infection adds one idle food rate, wound infection halves the regeneration, and the drug
-- effects of bleed.pwn and drugfx.pwn apply once per tick (upstream ran Air and Adrenaline twice, ADR 0007).
function survival.tick(state, movementMult, rng)
    local s = {
        hp = state.hp,
        food = state.food,
        thirst = state.thirst or 80,
        bleed = state.bleed,
        wounds = type(state.wounds) == "table" and #state.wounds or tonumber(state.wounds) or 0,
    }
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
    s.thirst = clamp(s.thirst - survival.IDLE_THIRST_RATE * movementMult, 0, 100)
    if s.thirst < 20 then
        s.hp = s.hp - (20 - s.thirst) / 30
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
