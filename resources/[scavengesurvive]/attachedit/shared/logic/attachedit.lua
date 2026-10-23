-- Attachment editor: nudges the nine values of one worn or held attachment (position, rotation, scale) and formats
-- the result as a row for items/shared/logic/apparel.lua. Pure logic: no MTA calls; the state is a plain table the
-- caller owns and passes back in.
local M = {}

-- the attach.lua slots an editor can open
M.SLOTS = { "hat", "mask", "armour", "bag", "holster", "held", "cuffs" }
local IS_SLOT = {}
for _, s in ipairs(M.SLOTS) do
    IS_SLOT[s] = true
end

M.FIELDS = { "x", "y", "z", "rx", "ry", "rz", "sx", "sy", "sz" }
M.KINDS = { "pos", "pos", "pos", "rot", "rot", "rot", "scale", "scale", "scale" }
M.STEPS = { pos = { 0.001, 0.005, 0.02 }, rot = { 1, 5, 15 }, scale = { 0.01, 0.05 } }
M.POS_LIMIT = 2 -- metres from the bone either way
M.SCALE_MIN, M.SCALE_MAX = 0.01, 10

function M.isSlot(slot)
    return IS_SLOT[slot] == true
end

local function wrap(i, n)
    return (i - 1) % n + 1
end

-- round to `places` decimals (default 3); never returns -0
function M.round(v, places)
    local m = 10 ^ (places or 3)
    local r = math.floor(v * m + 0.5) / m
    if r == 0 then
        r = 0
    end
    return r
end

-- keep a value of kind in range: positions within +-POS_LIMIT, scales within [SCALE_MIN, SCALE_MAX], rotations
-- folded into (-360, 360) so a row that came in as 254.87 stays 254.87 until it passes a full turn
function M.clamp(kind, v)
    if kind == "pos" then
        return math.max(-M.POS_LIMIT, math.min(M.POS_LIMIT, v))
    elseif kind == "scale" then
        return math.max(M.SCALE_MIN, math.min(M.SCALE_MAX, v))
    end
    while v >= 360 do
        v = v - 360
    end
    while v <= -360 do
        v = v + 360
    end
    return v
end

-- cfg = items' getAttachConfig(slot): { slot, uname, skin, bone, offsets = { 6 }, scale = { 3 } }
function M.new(cfg)
    local o, s = cfg.offsets or {}, cfg.scale or {}
    local values = {}
    for i = 1, 6 do
        values[i] = tonumber(o[i]) or 0
    end
    for i = 1, 3 do
        values[6 + i] = tonumber(s[i]) or 1
    end
    return {
        slot = cfg.slot,
        uname = cfg.uname,
        skin = cfg.skin,
        bone = cfg.bone,
        values = values,
        field = 1,
        stepIndex = { pos = 1, rot = 1, scale = 1 },
    }
end

function M.kind(state)
    return M.KINDS[state.field]
end

function M.step(state)
    local kind = M.kind(state)
    return M.STEPS[kind][state.stepIndex[kind]]
end

function M.selectField(state, n)
    state.field = wrap(n, #M.FIELDS)
end

function M.moveField(state, delta)
    M.selectField(state, state.field + delta)
end

-- cycles the step of the selected field's kind (position, rotation, scale each keep their own)
function M.cycleStep(state, delta)
    local kind = M.kind(state)
    state.stepIndex[kind] = wrap(state.stepIndex[kind] + (delta or 1), #M.STEPS[kind])
end

-- adds dir * step to the selected field; values are kept at 6 decimals so repeated nudges do not drift
function M.nudge(state, dir)
    local i = state.field
    state.values[i] = M.round(M.clamp(M.KINDS[i], state.values[i] + dir * M.step(state)), 6)
end

-- the nine values split back into items' setAttachPreview arguments
function M.split(values)
    return { values[1], values[2], values[3], values[4], values[5], values[6] }, { values[7], values[8], values[9] }
end

-- offsets { 6 } and scale { 3 } back into the nine values (missing scale = 1)
function M.join(offsets, scale)
    local v = {}
    for i = 1, 6 do
        v[i] = offsets and offsets[i]
    end
    for i = 1, 3 do
        v[6 + i] = scale and scale[i] or 1
    end
    return v
end

local function num(v)
    local s = string.format("%.3f", M.round(v, 3))
    s = s:gsub("0+$", "")
    if s:sub(-1) == "." then
        s = s .. "0"
    end
    return s
end

-- "{ x, y, z, rx, ry, rz, sx, sy, sz }" with 3 decimals, trailing zeros dropped
function M.formatRow(values)
    local parts = {}
    for i = 1, 9 do
        parts[i] = num(values[i] or 0)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- a row ready to paste into OVERRIDES[uname] in apparel.lua: "[skin] = { ... }, -- uname slot"
function M.formatEntry(uname, skin, slot, values)
    return string.format("[%s] = %s, -- %s %s", tostring(skin), M.formatRow(values), tostring(uname), tostring(slot))
end

-- key name -> editor action: { "field", n } | { "move", d } | { "nudge", d } | { "step", d } | { "save" } |
-- { "cancel" }, or nil for a key the editor leaves alone
local KEYS = {
    arrow_u = { "move", -1 },
    arrow_d = { "move", 1 },
    arrow_l = { "nudge", -1 },
    arrow_r = { "nudge", 1 },
    ["-"] = { "nudge", -1 },
    ["="] = { "nudge", 1 },
    num_sub = { "nudge", -1 },
    num_add = { "nudge", 1 },
    pgdn = { "nudge", -1 },
    pgup = { "nudge", 1 },
    ["0"] = { "step", 1 },
    num_0 = { "step", 1 },
    backspace = { "step", -1 },
    enter = { "save" },
    num_enter = { "save" },
    escape = { "cancel" },
}
for n = 1, 9 do
    KEYS[tostring(n)] = { "field", n }
    KEYS["num_" .. n] = { "field", n }
end

function M.keyAction(key)
    return KEYS[key]
end

-- applies a key to the state; returns "changed" (values moved), "ui" (selection or step moved), "save", "cancel",
-- or nil when the key is not the editor's
function M.handleKey(state, key)
    local a = KEYS[key]
    if not a then
        return nil
    end
    local verb = a[1]
    if verb == "field" then
        M.selectField(state, a[2])
    elseif verb == "move" then
        M.moveField(state, a[2])
    elseif verb == "step" then
        M.cycleStep(state, a[2])
    elseif verb == "nudge" then
        M.nudge(state, a[2])
        return "changed"
    else
        return verb
    end
    return "ui"
end

-- on-screen lines: header, then one line per field with the selected one marked
function M.describe(state)
    local lines = {
        string.format(
            "attachedit  slot=%s  %s  skin=%s  bone=%s",
            tostring(state.slot),
            tostring(state.uname),
            tostring(state.skin),
            tostring(state.bone)
        ),
        string.format("step %s (%s)", num(M.step(state)), M.kind(state)),
    }
    for i, name in ipairs(M.FIELDS) do
        lines[#lines + 1] =
            string.format("%s %d %-2s %s", i == state.field and ">" or " ", i, name, num(state.values[i]))
    end
    lines[#lines + 1] = "1-9/up/down field  left/right +/- pgup/pgdn nudge  0/backspace step  enter save  esc cancel"
    return lines
end

-- rcon / command words after the slot: { "off" } | { "get" } | 6 or 9 numbers.
-- Returns { action = "off" | "get" } or { action = "set", offsets, scale }, or nil and a usage message.
function M.parseArgs(words)
    local first = words[1]
    if first == "off" or first == "get" then
        return { action = first }
    end
    if #words ~= 6 and #words ~= 9 then
        return nil, "expected off, get, or x y z rx ry rz [sx sy sz]"
    end
    local v = {}
    for i, w in ipairs(words) do
        v[i] = tonumber(w)
        if not v[i] then
            return nil, string.format("'%s' is not a number", tostring(w))
        end
        v[i] = M.clamp(M.KINDS[i], v[i])
    end
    return {
        action = "set",
        offsets = { v[1], v[2], v[3], v[4], v[5], v[6] },
        scale = { v[7] or 1, v[8] or 1, v[9] or 1 },
    }
end

-- nine numbers from a client report; nil unless every one is a finite number
function M.checkValues(values)
    if type(values) ~= "table" then
        return nil
    end
    local out = {}
    for i = 1, 9 do
        local v = tonumber(values[i])
        if not v or v ~= v or v == math.huge or v == -math.huge then
            return nil
        end
        out[i] = v
    end
    return out
end

return M
