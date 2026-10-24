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
        local scaleY = canvas.textScale(c, td.ly or 1.5, fontId)
        local scaleX = scaleY * canvas.xScale(fontId, td.lx, td.ly)
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
        local function at(ox, oy, colour)
            dxDrawText(
                text,
                left + ox,
                py + oy,
                right + ox,
                py + oy + FAR,
                colour,
                scaleX,
                scaleY,
                font,
                align,
                "top",
                false,
                wrap
            )
        end
        if (td.outline or 0) > 0 then
            at(-d, 0, BLACK)
            at(d, 0, BLACK)
            at(0, -d, BLACK)
            at(0, d, BLACK)
        elseif (td.shadow or 0) > 0 then
            at(d, d, BLACK)
        end
        at(0, 0, td.colour)
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

    -- Pixel-space helpers for the dialog widgets (the rectangles come from dialog.layout / dialog.boxLayout).
    function M.pxRect(r, colour)
        dxDrawRectangle(r.x, r.y, r.w, r.h, colour)
    end

    function M.pxFrame(r, colour)
        dxDrawLine(r.x, r.y, r.x + r.w, r.y, colour)
        dxDrawLine(r.x, r.y + r.h, r.x + r.w, r.y + r.h, colour)
        dxDrawLine(r.x, r.y, r.x, r.y + r.h, colour)
        dxDrawLine(r.x + r.w, r.y, r.x + r.w, r.y + r.h, colour)
    end

    local BUTTON = tocolor(45, 45, 45, 255)
    local BORDER = tocolor(190, 190, 190, 255)
    local WHITE = tocolor(255, 255, 255, 255)
    -- An SA-MP dialog button: dark fill, 1 px light border, centred font 1 label.
    function M.pxButton(r, label)
        M.pxRect(r, BUTTON)
        M.pxFrame(r, BORDER)
        local scale = canvas.textScale(c, 1.3, 1)
        dxDrawText(label, r.x, r.y, r.x + r.w, r.y + r.h, WHITE, scale, canvas.font(1), "center", "center")
    end

    return M
end
