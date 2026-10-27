local focus = {}

focus.DEFAULT_PING_LIMIT = 400
focus.DEFAULT_MAX_TAB_OUT_TIME = 60

-- Determines whether a player should be kicked for being unfocused / idle.
-- Returns boolean (should kick), elapsed_ms
function focus.shouldKick(idleKickEnabled, maxTabOutTime, minimizedAt, now, onDuty)
    if not idleKickEnabled then
        return false
    end
    if onDuty then
        return false
    end
    if not minimizedAt then
        return false
    end
    local limit = tonumber(maxTabOutTime) or focus.DEFAULT_MAX_TAB_OUT_TIME
    if limit <= 0 then
        return false
    end
    local elapsed = (now or 0) - minimizedAt
    if elapsed >= limit * 1000 then
        return true, elapsed
    end
    return false, elapsed
end

return focus
