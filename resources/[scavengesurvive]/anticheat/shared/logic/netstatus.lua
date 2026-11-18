-- Network interruptions (onPlayerNetworkStatus) per player, kept by serial so the history survives the reconnect
-- that follows a timeout. A run of them inside an hour is what a lag switch (pulling the cable for a few seconds)
-- looks like, so staff get one alert listing each interruption: when, how long, whether it ended in a timeout, how far
-- the player moved across it and what they held or drove.
local netstatus = {}

netstatus.WINDOW_S = 3600 -- interruptions counted over the last hour
netstatus.THRESHOLD = 3 -- this many in the window raises an alert
netstatus.COOLDOWN_S = 1800 -- then at most one alert per player per half hour
netstatus.MAX_KEPT = 20 -- per player, newest last

function netstatus.new(opts)
    opts = opts or {}
    local window = opts.window or netstatus.WINDOW_S
    local threshold = opts.threshold or netstatus.THRESHOLD
    local cooldown = opts.cooldown or netstatus.COOLDOWN_S
    local history, alertedAt = {}, {}
    local self = {}

    local function prune(key, now)
        local list = history[key]
        if not list then
            return {}
        end
        local kept = {}
        for _, e in ipairs(list) do
            if now - e.at < window then
                kept[#kept + 1] = e
            end
        end
        while #kept > netstatus.MAX_KEPT do
            table.remove(kept, 1)
        end
        history[key] = #kept > 0 and kept or nil
        return kept
    end

    -- entry: { at = unix start, ms = duration, timedOut = bool, moved = metres or nil, held = uname or nil,
    -- vehicle = name or nil }. Returns the entries to alert with, or nil.
    function self.record(key, entry, now)
        local list = prune(key, now)
        list[#list + 1] = entry
        history[key] = list
        if #list < threshold then
            return nil
        end
        if alertedAt[key] and now - alertedAt[key] < cooldown then
            return nil
        end
        alertedAt[key] = now
        return list
    end

    function self.recent(key, now)
        return prune(key, now)
    end

    return self
end

local function seconds(ms)
    local s = (tonumber(ms) or 0) / 1000
    return s < 10 and string.format("%.1fs", s) or string.format("%ds", math.floor(s + 0.5))
end

function netstatus.describe(e)
    local what = e.ms and ((e.timedOut and "timed out after " or "lost ") .. seconds(e.ms)) or "timed out"
    local parts = { string.format("<t:%d:T>", e.at), what }
    if e.moved then
        parts[#parts + 1] = string.format("moved %dm", math.floor(e.moved + 0.5))
    end
    if e.vehicle then
        parts[#parts + 1] = "in " .. e.vehicle
    end
    if e.held then
        parts[#parts + 1] = "holding " .. e.held
    end
    return table.concat(parts, " · ")
end

function netstatus.alertText(name, entries)
    local timedOut = 0
    for _, e in ipairs(entries) do
        if e.timedOut then
            timedOut = timedOut + 1
        end
    end
    local lines = {
        string.format(
            ":signal_strength: **%s** lost connection %d× in the last hour%s."
                .. " Possible lag switch: check server.log around these times.",
            name,
            #entries,
            timedOut > 0 and string.format(" (%d timed out)", timedOut) or ""
        ),
    }
    for _, e in ipairs(entries) do
        lines[#lines + 1] = "• " .. netstatus.describe(e)
    end
    return table.concat(lines, "\n")
end

return netstatus
