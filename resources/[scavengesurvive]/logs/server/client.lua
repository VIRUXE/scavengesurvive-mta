-- Client reports (logs/client/main.lua) as client.* log lines. info level: a hostile client must not be able to flood
-- the console, and the rate limit of net.handler caps what reaches Loki.
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, tonumber(v) or 0))
end

net.handler("clientErrorReported", function(player, message, level, file, line)
    if type(message) ~= "string" then
        return
    end
    log.event(level == 1 and "client.scriptError" or "client.scriptWarning", {
        player = player,
        msg = message:sub(1, 300),
        file = tostring(file):sub(1, 120),
        line = clamp(line, 0, 1e6),
    })
end, { rate = 2 })

net.handler("clientSampleReported", function(player, fps, ping, objects)
    log.event("client.sampled", {
        player = player,
        fps = clamp(fps, 0, 10000),
        ping = clamp(ping, 0, 100000),
        streamed_objects = clamp(objects, 0, 1e6),
    })
end, { rate = 1 })
