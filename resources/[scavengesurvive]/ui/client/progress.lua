-- Hold-progress bar (one at a time) with a label above it.
-- ctx = { sw, sh, scale, font } from client/main.lua.
return function(ctx)
    local progress = nil
    local M = {}

    function M.start(label, durationMs)
        progress = { label = label, start = getTickCount(), duration = durationMs }
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
        local w, h = 260 * ctx.scale, 14 * ctx.scale
        local x, y = (ctx.sw - w) / 2, ctx.sh * 0.72
        dxDrawRectangle(x - 2, y - 2, w + 4, h + 4, tocolor(0, 0, 0, 180))
        dxDrawRectangle(x, y, w * frac, h, tocolor(220, 60, 40, 230))
        dxDrawText(
            progress.label,
            x,
            y - 20 * ctx.scale,
            x + w,
            y,
            tocolor(255, 255, 255, 230),
            ctx.scale,
            ctx.font,
            "center",
            "top"
        )
    end

    return M
end
