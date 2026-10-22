-- Textdraw-like primitives on top of dx: text with outline/shadow (dxDrawText has neither) and boxes, all
-- positioned in canvas units. ctx = { canvas (module), c (canvas instance) }.
return function(ctx)
    local canvas, c = ctx.canvas, ctx.c
    local BLACK = tocolor(0, 0, 0, 255)
    local M = {}
    local FAR = 4096

    -- td = { text, x, y, font = 1, lx = 0.3, ly = 1.5, colour = tocolor, align = "left"|"center"|"right",
    --        outline = 0|1, shadow = 0|1, width (units; wraps when set), anchor (defaults to align),
    --        dx (extra pixel offset, for composing strings of several colours) }
    function M.text(td)
        local fontId = td.font or 1
        local font = canvas.font(fontId)
        local scale = canvas.textScale(c, td.ly or 1.5, fontId)
        local align = td.align or "left"
        local px = canvas.x(c, td.x, td.anchor or align) + (td.dx or 0)
        local py = canvas.y(c, td.y)
        local w = td.width and canvas.len(c, td.width) or 0
        local left, right
        if align == "right" then
            left, right = px - (w > 0 and w or FAR), px
        elseif align == "center" then
            local half = w > 0 and w / 2 or FAR
            left, right = px - half, px + half
        else
            left, right = px, px + (w > 0 and w or FAR)
        end
        local text = td.text
        if fontId == 2 then
            text = string.upper(text) -- GTA's font 2 has capitals only
        end
        local wrap = w > 0
        local d = math.max(1, math.floor(c.s + 0.5))
        if (td.outline or 0) > 0 then
            dxDrawText(text, left - d, py, right - d, py + FAR, BLACK, scale, font, align, "top", false, wrap)
            dxDrawText(text, left + d, py, right + d, py + FAR, BLACK, scale, font, align, "top", false, wrap)
            dxDrawText(text, left, py - d, right, py - d + FAR, BLACK, scale, font, align, "top", false, wrap)
            dxDrawText(text, left, py + d, right, py + d + FAR, BLACK, scale, font, align, "top", false, wrap)
        elseif (td.shadow or 0) > 0 then
            dxDrawText(text, left + d, py + d, right + d, py + d + FAR, BLACK, scale, font, align, "top", false, wrap)
        end
        dxDrawText(text, left, py, right, py + FAR, td.colour, scale, font, align, "top", false, wrap)
    end

    -- Box in canvas units; anchor as for canvas.x.
    function M.box(x, y, w, h, colour, anchor)
        dxDrawRectangle(canvas.x(c, x, anchor), canvas.y(c, y), canvas.len(c, w), canvas.len(c, h), colour)
    end

    -- A progress2 bar: background in the colour's alpha, half-alpha fill, full-colour value.
    function M.progressBar(x, y, w, h, frac, r, g, b, a, anchor)
        local bar = canvas.progressBar(x, y, w, h, frac)
        M.box(bar.back.x, bar.back.y, bar.back.w, bar.back.h, tocolor(0, 0, 0, a), anchor)
        M.box(bar.fill.x, bar.fill.y, bar.fill.w, bar.fill.h, tocolor(r, g, b, math.min(0x66, a / 2)), anchor)
        M.box(bar.value.x, bar.value.y, bar.value.w, bar.value.h, tocolor(r, g, b, a), anchor)
    end

    return M
end
