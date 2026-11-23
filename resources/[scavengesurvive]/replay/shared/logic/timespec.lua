-- /replay's time arguments: `<from> [<to>|<length>]` as separate words.
--   from / to   2026-11-18 19:15[:30] | 2026-11-18 (midnight) | 19:15 (from: today, yesterday if still ahead; to: on
--               from's day, the next day if not later) | now |
--               -2h, -30m, -1d (that long ago)
--   length      30m, 2h, 90s (after `from`), only as the second spec
-- With no second spec the range is 30 minutes from `from`; it never reaches past `now`.
-- Pure logic: the caller passes `now` (unix seconds, server local time zone as os.time reads it).
local M = {}

M.DEFAULT_LENGTH = 1800
local UNITS = { s = 1, m = 60, h = 3600, d = 86400 }

local function localTime(y, mo, d, h, mi, s)
    return os.time({ year = y, month = mo, day = d, hour = h or 0, min = mi or 0, sec = s or 0, isdst = false })
end

-- tokens[i] starts a spec: returns the unix time and how many words it used, or nil. `after` (unix) is set for the
-- end of a range: a time with no date then falls on `after`'s day, or the next one when it would not be later.
local function absolute(tokens, i, now, after)
    local t = tokens[i]
    if not t then
        return nil
    end
    local y, mo, d = t:match("^(%d%d%d%d)%-(%d%d?)%-(%d%d?)$")
    if y then
        local h, mi, s = (tokens[i + 1] or ""):match("^(%d%d?):(%d%d):?(%d*)$")
        if h then
            return localTime(tonumber(y), tonumber(mo), tonumber(d), tonumber(h), tonumber(mi), tonumber(s) or 0), 2
        end
        return localTime(tonumber(y), tonumber(mo), tonumber(d)), 1
    end
    local h, mi, s = t:match("^(%d%d?):(%d%d):?(%d*)$")
    if h then
        local day = os.date("*t", after or now)
        local at = localTime(day.year, day.month, day.day, tonumber(h), tonumber(mi), tonumber(s) or 0)
        if after then
            if at <= after then
                at = at + 86400
            end
        elseif at > now then
            at = at - 86400
        end
        return at, 1
    end
    if t:lower() == "now" then
        return now, 1
    end
    local n, unit = t:lower():match("^%-(%d+)([smhd])$")
    if n then
        return now - tonumber(n) * UNITS[unit], 1
    end
    return nil
end

-- `to` words after `from`: returns from, to or nil, message
function M.parseRange(tokens, now)
    local from, used = absolute(tokens, 1, now)
    if not from then
        return nil, "Say when it starts: 2026-11-18 19:15, 19:15, -2h or now."
    end
    local to
    local rest = tokens[used + 1]
    if rest then
        local n, unit = rest:lower():match("^(%d+)([smhd])$")
        if n then
            if tokens[used + 2] then
                return nil, "Too many words after the range."
            end
            to = from + tonumber(n) * UNITS[unit]
        else
            local at, used2 = absolute(tokens, used + 1, now, from)
            if not at then
                return nil, "'" .. rest .. "' is not a time or a length (30m, 2h)."
            end
            if tokens[used + 1 + used2] then
                return nil, "Too many words after the range."
            end
            to = at
        end
    else
        to = from + M.DEFAULT_LENGTH
    end
    if to > now then
        to = now
    end
    if to <= from then
        return nil, "The range is empty or reversed."
    end
    return from, to
end

return M
