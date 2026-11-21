-- What wounds do to the body (2026-11-21): counted per part (survival.woundsPerPart order: torso, groin, left arm,
-- right arm, left leg, right leg, head), worse the more a part carries. Legs cap and then take the sprint, and lose
-- the jump from the third wound; torso and groin cap the sprint harder with each wound and take it at the third;
-- arms sway the aim. Adrenaline lifts all of it, as it does hunger's (shared/logic/hunger.lua). client/hunger.lua
-- merges the legs with hunger's, client/medical.lua the aim.

local function count(parts, a, b)
    parts = type(parts) == "table" and parts or {}
    return (tonumber(parts[a]) or 0) + (tonumber(parts[b]) or 0)
end

local function lifted(drugs)
    return type(drugs) == "table" and drugs.Adrenaline
end

-- { sprint, jump, maxMs, cooldownMs }, the shape of hunger.legs
local function legs(parts, drugs)
    if lifted(drugs) then
        return { sprint = true, jump = true }
    end
    local leg, body = count(parts, 5, 6), count(parts, 1, 2)
    if leg >= 2 or body >= 3 then
        return { sprint = false, jump = leg < 3 }
    end
    if leg == 1 then
        return { sprint = true, jump = true, maxMs = 6000, cooldownMs = 6000 }
    end
    if body == 2 then
        return { sprint = true, jump = true, maxMs = 4000, cooldownMs = 8000 }
    end
    if body == 1 then
        return { sprint = true, jump = true, maxMs = 8000, cooldownMs = 5000 }
    end
    return { sprint = true, jump = true }
end

-- the stricter of two legs tables
local function worstLegs(a, b)
    local maxMs = a.maxMs or b.maxMs
    if a.maxMs and b.maxMs then
        maxMs = math.min(a.maxMs, b.maxMs)
    end
    return {
        sprint = a.sprint and b.sprint,
        jump = a.jump and b.jump,
        maxMs = maxMs,
        cooldownMs = maxMs and math.max(a.cooldownMs or 0, b.cooldownMs or 0) or nil,
    }
end

-- the drunk level (upstream units, the client divides by 200) the camera keeps at least while aiming
local function aimDrunk(parts, drugs)
    if lifted(drugs) then
        return 0
    end
    return math.min(6000, count(parts, 3, 4) * 1500)
end

return { legs = legs, worstLegs = worstLegs, aimDrunk = aimDrunk }
