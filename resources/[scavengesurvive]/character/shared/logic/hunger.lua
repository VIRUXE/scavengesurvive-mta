-- Hunger and thirst effects (2026-11-16): below START the character feels it, harder towards 0, before and while
-- the survival tick drains HP (below SEVERE, shared/logic/survival.lua). Hunger drains the colour from the screen
-- and darkens its edges, thirst blurs the edges and now and then sways the camera; both cap sprinting (no sprint
-- below SEVERE, no jump below WEAK), sway the aim and show a line and a sound now and then. Upstream food.pwn meant
-- a drunk level below 30 but its Adrenaline test was inverted, so it never showed. Adrenaline lifts everything,
-- Painkill hides the screen effects (as it does the low-HP darkness, medical.hidesDarkness).
-- Poison (the toxic cloud, survival.TOXIC_*) shows on the same screen from TOXIC_START up: a sickly green cast
-- (tint), blurred and darkened edges. No drug hides it.
-- M.tr(text): a line in the reader's language; the client sets it to lib lang.text, identity elsewhere
local M = {}
M.tr = function(s)
    return s
end

M.START = 30
M.SEVERE = 20
M.WEAK = 10
M.TOXIC_START = 15 -- survival.TOXIC_COUGHS: where poison starts to show

-- lang:begin
M.CUES = {
    hunger = { "Your stomach growls", "You feel weak from hunger" },
    thirst = { "Your mouth is dry", "You badly need water" },
}
-- lang:end

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

-- 0 at START or above, 1 at 0
function M.level(v)
    return clamp((M.START - (tonumber(v) or 100)) / M.START, 0, 1)
end

-- 0 at TOXIC_START or below, 1 at 100
function M.toxicLevel(toxic)
    return clamp(((tonumber(toxic) or 0) - M.TOXIC_START) / (100 - M.TOXIC_START), 0, 1)
end

-- { desat, vignette, blur, tint }, each 0..1
function M.screen(food, thirst, drugs, toxic)
    drugs = drugs or {}
    local h, t, p = M.level(food), M.level(thirst), M.toxicLevel(toxic)
    if drugs.Painkill or drugs.Adrenaline then
        h, t = 0, 0
    end
    return {
        desat = math.max(h * 0.85, t * 0.3),
        vignette = math.max(h * 0.8, t * 0.8, p * 0.6),
        blur = math.max(t, p * 0.9),
        tint = p,
    }
end

function M.active(fx)
    return fx.desat > 0 or fx.vignette > 0 or fx.blur > 0 or fx.tint > 0
end

-- The screen moves towards what the needs ask for instead of jumping there: a meal clears it over FADE_MS at most.
M.FADE_MS = 2500

-- fx stepped dtMs towards target; a new table
function M.ease(fx, target, dtMs)
    local step = math.max(0, dtMs) / M.FADE_MS
    local out = {}
    for _, k in ipairs({ "desat", "vignette", "blur", "tint" }) do
        local d = target[k] - fx[k]
        out[k] = fx[k] + clamp(d, -step, step)
    end
    return out
end

-- The camera drunk level (upstream units, the client divides by 200) thirst wants next, or nil to keep the current
-- one: a sway every 40 s at START, every 10 s at 0, lasting 4..8 s. drunk is the current level.
function M.thirstDrunk(thirst, drugs, drunk, sinceMs)
    drugs = drugs or {}
    local t = M.level(thirst)
    if t <= 0 or drugs.Adrenaline or drugs.Painkill then
        return drunk ~= 0 and 0 or nil
    end
    if drunk == 0 then
        if sinceMs < 40000 - 30000 * t then
            return nil
        end
        local level = math.floor(1500 + 3500 * t)
        return level == 2200 and 2201 or level -- 2200 is Morphine's level, which client/medical.lua clears
    end
    return sinceMs >= 4000 + 4000 * t and 0 or nil
end

-- What the legs still do: { sprint, jump, maxMs, cooldownMs }. Between START and SEVERE a sprint lasts maxMs
-- (12 s down to 3 s) and then needs cooldownMs (4 s up to 10 s) off; below SEVERE no sprint, below WEAK no jump.
function M.legs(food, thirst, drugs)
    drugs = drugs or {}
    local worst = math.min(tonumber(food) or 100, tonumber(thirst) or 100)
    if drugs.Adrenaline or worst >= M.START then
        return { sprint = true, jump = true }
    end
    if worst < M.SEVERE then
        return { sprint = false, jump = worst >= M.WEAK }
    end
    local f = (worst - M.SEVERE) / (M.START - M.SEVERE) -- 1 at START, 0 at SEVERE
    return { sprint = true, jump = true, maxMs = 3000 + 9000 * f, cooldownMs = 10000 - 6000 * f }
end

-- The drunk level (upstream units) the camera keeps at least while aiming: the aim sways, up to 6000 (MTA's 30).
function M.aimDrunk(food, thirst, drugs)
    if drugs and drugs.Adrenaline then
        return 0
    end
    return math.floor(math.max(M.level(food), M.level(thirst)) * 6000)
end

-- The cue due now: kind ("hunger" | "thirst") and its line, or nil. Every 90 s at START, every 30 s at 0, for the
-- worse of the two; the stronger line from SEVERE down.
function M.cue(food, thirst, sinceMs)
    local h, t = M.level(food), M.level(thirst)
    local kind, l, v = "hunger", h, tonumber(food) or 100
    if t > h then
        kind, l, v = "thirst", t, tonumber(thirst) or 100
    end
    if l <= 0 or sinceMs < 90000 - 60000 * l then
        return nil
    end
    return kind, M.tr(M.CUES[kind][v < M.SEVERE and 2 or 1])
end

return M
