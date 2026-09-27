local util = {}
local LEVELS = { error = 1, warn = 2, info = 3 }

function util.clamp(v, lo, hi)
    if v < lo then
        return lo
    end
    if v > hi then
        return hi
    end
    return v
end

function util.round(v, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(v * m + 0.5) / m
end

function util.dist2(x1, y1, x2, y2)
    local dx, dy = x1 - x2, y1 - y2
    return math.sqrt(dx * dx + dy * dy)
end

function util.tableCount(t)
    local n = 0
    for _ in pairs(t) do
        n = n + 1
    end
    return n
end

function util.keys(t)
    local out = {}
    for k in pairs(t) do
        out[#out + 1] = k
    end
    table.sort(out, function(a, b)
        return tostring(a) < tostring(b)
    end)
    return out
end

function util.split(s, sep)
    local out = {}
    for piece in string.gmatch(s, "([^" .. sep .. "]+)") do
        out[#out + 1] = piece
    end
    return out
end

function util.log(tag, level, fmt, ...)
    local msg = "[" .. tag .. "] " .. string.format(fmt, ...)
    outputDebugString(msg, LEVELS[level] or 3)
    outputServerLog(msg)
end

return util
