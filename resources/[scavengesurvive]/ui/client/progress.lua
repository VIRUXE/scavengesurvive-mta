-- The hold-action bar (core/ui/hold-action.pwn): a progress2 bar at 291,345 of 57.5 x 5.19 units in GREY
-- (0xAFAFAFFF), one at a time, no label. The server times the action; the client only animates the fill.
return function(ctx)
    local draw = ctx.draw
    local progress = nil
    local M = {}

    function M.start(_label, durationMs)
        progress = { start = getTickCount(), duration = math.max(1, tonumber(durationMs) or 1) }
        return true
    end

    function M.cancel()
        progress = nil
        return true
    end

    function M.draw()
        if not progress then
            return
        end
        local frac = (getTickCount() - progress.start) / progress.duration
        if frac >= 1 then
            progress = nil
            return
        end
        draw.progressBar(291, 345, 57.5, 5.19, frac, 0xAF, 0xAF, 0xAF, 0xFF, "center")
    end

    return M
end
