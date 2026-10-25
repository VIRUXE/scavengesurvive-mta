-- The help tip (upstream ui/tool-tip.pwn): one green paragraph at 150, 350, font 1 0.30/1.50 with outline,
-- wrapped at 370 units (text size 520), and an optional blue footer one blank line below it (upstream's
-- "~n~~n~~b~Type /tooltips ..."). dxDrawText drops word wrap for colour codes, so the footer is its own text.
return function(ctx)
    local canvas, c, draw = ctx.canvas, ctx.c, ctx.draw
    local GREEN = tocolor(0, 255, 0, 255)
    local BLUE = tocolor(50, 60, 127, 255) -- GTA HUD_COLOUR_BLUE, what ~b~ draws
    local X, Y, WIDTH, LX, LY = 150, 350, 370, 0.3, 1.5
    local slot = nil
    local M = {}

    -- lines the body wraps to at this resolution, from dxGetTextSize with the same font, scale and width
    local function bodyLines(text)
        local font = canvas.font(1)
        local scaleY = canvas.textScale(c, LY, 1)
        local scaleX = scaleY * canvas.xScale(1, LX, LY)
        local _, h = dxGetTextSize(text, canvas.len(c, WIDTH), scaleX, scaleY, font, true)
        local line = dxGetFontHeight(scaleY, font)
        return math.max(1, math.floor((h or line) / line + 0.5))
    end

    function M.show(text, footer, ms)
        ms = tonumber(ms) or 0
        text = tostring(text)
        slot = { text = text, footer = footer, until_ = ms > 0 and (getTickCount() + ms) or nil }
        if footer then
            local pitch = canvas.lineHeight(c, LY) / c.s
            slot.footerY = Y + (bodyLines(text) + 1) * pitch
        end
        return true
    end

    function M.hide()
        slot = nil
        return true
    end

    function M.draw()
        if not slot then
            return
        end
        if slot.until_ and getTickCount() > slot.until_ then
            slot = nil
            return
        end
        local td = { text = slot.text, x = X, y = Y, font = 1, lx = LX, ly = LY, outline = 1, width = WIDTH }
        td.colour = GREEN
        draw.text(td)
        if slot.footer then
            td.text, td.y, td.colour = slot.footer, slot.footerY, BLUE
            draw.text(td)
        end
    end

    return M
end
