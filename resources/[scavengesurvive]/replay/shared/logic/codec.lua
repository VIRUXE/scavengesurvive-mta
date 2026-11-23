-- Recorder chunk format (docs/superpowers/specs/2026-11-23-replay-design.md). A chunk is the JSON text
--   {"v":1,"s":[{"d":0,"x":-163512,...},{"d":200,"x":-163498},{"d":5000}, ...]}
-- one object per sample. "d" is the milliseconds since the previous sample (0 for the first), every other key is
-- written only when it changed since the previous sample of the chunk (the first sample carries all of them), so an
-- object holding only "d" is a heartbeat that says "still here, nothing changed". A cleared optional field is 0.
--   x y z  position, centimetres          r     heading, whole degrees       i m   interior, dimension
--   h      health, whole points           mv    move state                   an    "block|name" animation or ""
--   w      weapon id                      a     [x,y,z] aim point, cm        f     1 on a sample that fired a shot
--   vk     vehicle key (db id, or -model) st    seat                         du    1 on staff duty
--   vh     [x,y,z cm, rx,ry,rz deg, health, model] of the vehicle the character drives
-- Pure logic, no MTA calls at file scope.
local M = {}

M.VERSION = 1
-- key order of a written sample; the second field says how the value is written
M.FIELDS = {
    { "x", "n" },
    { "y", "n" },
    { "z", "n" },
    { "r", "n" },
    { "i", "n" },
    { "m", "n" },
    { "h", "n" },
    { "mv", "s" },
    { "an", "s" },
    { "w", "n" },
    { "a", "t" },
    { "f", "n" },
    { "vk", "n" },
    { "st", "n" },
    { "du", "n" },
    { "vh", "t" },
}
-- fields whose cleared state is written as 0 (and read back as nil)
M.CLEARABLE = { a = true, vh = true, vk = true }

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\" }

-- strings come from clients (anim names): anything outside printable ASCII becomes "?" so one bad byte can never make
-- a whole chunk batch invalid JSON / utf8mb4
local function str(s)
    s = tostring(s):gsub("[\128-\255]", "?")
    return '"'
        .. s:gsub('[%c"\\]', function(c)
            return ESC[c] or string.format("\\u%04x", c:byte())
        end)
        .. '"'
end

local function arr(t)
    local out = {}
    for i = 1, #t do
        out[i] = string.format("%d", t[i])
    end
    return "[" .. table.concat(out, ",") .. "]"
end

local function same(kind, a, b)
    if kind ~= "t" then
        return a == b
    end
    if a == nil or b == nil then
        return a == b
    end
    for i = 1, math.max(#a, #b) do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

-- The JSON text of one sample (cur) against the previous one (prev, nil for the first of a chunk); nil when nothing
-- differs and the caller does not want a heartbeat (pass `force` to get {"d":n} anyway).
function M.encodeSample(cur, prev, dtMs, force)
    prev = prev or {}
    local parts = { string.format('"d":%d', dtMs) }
    for _, f in ipairs(M.FIELDS) do
        local key, kind = f[1], f[2]
        local c, p = cur[key], prev[key]
        -- a shot is not a state: the decoder clears it after each sample, so every firing sample carries it, and a
        -- sample without one writes nothing (back-to-back shots would otherwise read as one)
        local changed
        if key == "f" then
            changed = c == 1
        else
            changed = not same(kind, c, p)
        end
        if changed then
            local text
            if c == nil then
                text = M.CLEARABLE[key] and "0" or (kind == "s" and '""' or "0")
            elseif kind == "n" then
                text = string.format("%d", c)
            elseif kind == "s" then
                text = str(c)
            else
                text = arr(c)
            end
            parts[#parts + 1] = str(key) .. ":" .. text
        end
    end
    if #parts == 1 and not force then
        return nil
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

function M.encodeChunk(sampleTexts)
    return '{"v":' .. M.VERSION .. ',"s":[' .. table.concat(sampleTexts, ",") .. "]}"
end

-- chunk table (fromJSON of the text) -> list of full samples { t = ms since the chunk's first sample, x, y, ... }
-- Positions come back in metres, headings in degrees; a cleared field is absent. `decoded` is the parsed table.
function M.decodeChunk(decoded)
    local out = {}
    if type(decoded) ~= "table" or type(decoded.s) ~= "table" then
        return out
    end
    local state, t = {}, 0
    for _, s in ipairs(decoded.s) do
        t = t + (tonumber(s.d) or 0)
        for _, f in ipairs(M.FIELDS) do
            local key = f[1]
            local v = s[key]
            if v ~= nil then
                if M.CLEARABLE[key] and v == 0 then
                    state[key] = nil
                elseif key == "an" and v == "" then
                    state[key] = nil
                else
                    state[key] = v
                end
            end
        end
        local sample = {
            t = t,
            x = state.x and state.x / 100,
            y = state.y and state.y / 100,
            z = state.z and state.z / 100,
            rz = state.r,
            int = state.i or 0,
            dim = state.m or 0,
            hp = state.h,
            move = state.mv,
            anim = state.an,
            weapon = state.w,
            aim = state.a and { state.a[1] / 100, state.a[2] / 100, state.a[3] / 100 } or nil,
            fire = state.f == 1 or nil,
            vkey = state.vk,
            seat = state.vk and state.st or nil,
            duty = state.du == 1 or nil,
        }
        if state.vh then
            local v = state.vh
            sample.vehicle = {
                x = v[1] / 100,
                y = v[2] / 100,
                z = v[3] / 100,
                rx = v[4],
                ry = v[5],
                rz = v[6],
                hp = v[7],
                model = v[8],
            }
        end
        if sample.x then
            out[#out + 1] = sample
        end
        -- a shot belongs to one sample only
        state.f = nil
    end
    return out
end

return M
