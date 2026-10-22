-- Toast lines above the HUD: newest on top, four at most, three seconds each.
-- ctx = { sw, sh, scale, font } from client/main.lua.
return function(ctx)
    local toasts = {}
    local M = {}

    function M.show(text, r, g, b)
        table.insert(
            toasts,
            1,
            { text = text, color = tocolor(r or 255, g or 255, b or 255, 230), until_ = getTickCount() + 3000 }
        )
        while #toasts > 4 do
            table.remove(toasts)
        end
        return true
    end

    function M.draw()
        local now = getTickCount()
        local y = ctx.sh * 0.82
        for i = #toasts, 1, -1 do
            local t = toasts[i]
            if t.until_ < now then
                table.remove(toasts, i)
            else
                dxDrawText(
                    t.text,
                    2,
                    y + 2,
                    ctx.sw + 2,
                    y + 2,
                    tocolor(0, 0, 0, 200),
                    ctx.scale,
                    ctx.font,
                    "center",
                    "top",
                    false,
                    false,
                    false,
                    true
                )
                dxDrawText(
                    t.text,
                    0,
                    y,
                    ctx.sw,
                    y,
                    t.color,
                    ctx.scale,
                    ctx.font,
                    "center",
                    "top",
                    false,
                    false,
                    false,
                    true
                )
                y = y - 22 * ctx.scale
            end
        end
    end

    return M
end
