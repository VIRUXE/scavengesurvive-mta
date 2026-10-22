-- The action text: one centred line per player that every message replaces ("Equipped", "Trunk locked",
-- "Extra 2 slots required"), font 1 0.30/1.50 white with outline, wrapped at 200 units. Upstream shows it at
-- y 350 (action-text include; verified on the footage). ms = 0 keeps it until the next message or hide().
return function(ctx)
    local draw = ctx.draw
    local WHITE = tocolor(255, 255, 255, 255)
    local slot = nil
    local M = {}

    function M.show(text, ms)
        ms = tonumber(ms) or 0
        slot = { text = tostring(text), until_ = ms > 0 and (getTickCount() + ms) or nil }
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
        draw.text({
            text = slot.text,
            x = 320,
            y = 350,
            font = 1,
            lx = 0.3,
            ly = 1.5,
            colour = WHITE,
            align = "center",
            outline = 1,
            width = 200,
        })
    end

    return M
end
