-- Character skills (upstream core/char/skills.pwn, finished for the port, #93): a list of named skills per
-- character, each 0..1. A finished action raises its skill, a started action is shortened by up to 50 % of its
-- time. Upstream added a flat 0.001 per action (every caller passed mult = 0) and never saved the list; the port
-- closes RATE x mult of the gap to 1.0 per action, so the first actions count most (Master, 0.9, after ~115 actions
-- at mult 1), and the list is saved as characters.skills, a JSON array of [name, amount] pairs.
local M = {}

M.MAX_SKILLS = 50 -- upstream MAX_PLAYER_SKILLS
M.MAX_NAME = 32 -- upstream MAX_SKILL_NAME
M.RATE = 0.02
M.MAX_TIME_CUT = 0.5

-- Upstream skl_Levels: a skill shows the first level whose bound it is still under; at 0.9 and above upstream read
-- past the end of the table (skl_Levels[5]), the port shows Master.
M.LEVELS = {
    { name = "Novice", bound = 0.1, colour = { 0xFF, 0xFF, 0x00 } },
    { name = "Adequate", bound = 0.2, colour = { 0x33, 0xAA, 0x33 } },
    { name = "Intermediate", bound = 0.33, colour = { 0xFF, 0xAA, 0x00 } },
    { name = "Experienced", bound = 0.66, colour = { 0x33, 0xCC, 0xFF } },
    { name = "Master", bound = 0.9, colour = { 0xFF, 0xC0, 0xCB } },
}

local function clamp01(v)
    v = tonumber(v) or 0
    if v ~= v then
        return 0
    end
    return math.max(0, math.min(1, v))
end

-- Skill names are item type unames ("Workbench") or fixed words ("Repair"); /setskill takes them from staff input.
function M.validName(name)
    return type(name) == "string" and #name >= 1 and #name <= M.MAX_NAME and name:match("^[%w_]+$") ~= nil
end

-- list = decoded characters.skills ({ { name, amount }, ... }) -> { byName = { name = amount }, order = { names } }
function M.fromList(list)
    local s = { byName = {}, order = {} }
    if type(list) ~= "table" then
        return s
    end
    for _, pair in ipairs(list) do
        local name, amount = type(pair) == "table" and pair[1], type(pair) == "table" and pair[2]
        if M.validName(name) and s.byName[name] == nil and #s.order < M.MAX_SKILLS then
            s.byName[name] = clamp01(amount)
            s.order[#s.order + 1] = name
        end
    end
    return s
end

-- The characters.skills column text: [["Repair",0.020000],["Workbench",0.039600]] (names are [%w_] only).
function M.encode(s)
    local parts = {}
    for _, name in ipairs(s.order) do
        parts[#parts + 1] = string.format('["%s",%.6f]', name, s.byName[name])
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function M.value(s, name)
    return s.byName[name] or 0
end

-- Sets a skill outright (/setskill); returns false for a bad name or a full list.
function M.set(s, name, amount)
    if not M.validName(name) then
        return false
    end
    if s.byName[name] == nil then
        if #s.order >= M.MAX_SKILLS then
            return false
        end
        s.order[#s.order + 1] = name
    end
    s.byName[name] = clamp01(amount)
    return s.byName[name]
end

-- A finished action: amount += RATE x mult x (1 - amount). mult defaults to 1; returns the new amount or false.
function M.gain(s, name, mult)
    local a = M.value(s, name)
    return M.set(s, name, a + M.RATE * (tonumber(mult) or 1) * (1 - a))
end

-- A started action's time: ms - ms x 0.5 x amount, rounded (upstream GetPlayerSkillTimeModifier).
function M.timeModifier(s, ms, name)
    return math.floor(ms - ms * M.MAX_TIME_CUT * M.value(s, name) + 0.5)
end

function M.level(amount)
    for i, lvl in ipairs(M.LEVELS) do
        if amount < lvl.bound then
            return lvl, i
        end
    end
    return M.LEVELS[#M.LEVELS], #M.LEVELS
end

-- The inventory's Skills list: { { name, amount, level, colour }, ... } in the order the skills were learned.
function M.rows(s)
    local rows = {}
    for _, name in ipairs(s.order) do
        local lvl = M.level(s.byName[name])
        rows[#rows + 1] = { name = name, amount = s.byName[name], level = lvl.name, colour = lvl.colour }
    end
    return rows
end

return M
