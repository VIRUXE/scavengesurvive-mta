local toasts = {}
function toast(text, r, g, b)
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
function UI.drawToasts()
    local now = getTickCount()
    local y = UI.sh * 0.82
    for i = #toasts, 1, -1 do
        local t = toasts[i]
        if t.until_ < now then
            table.remove(toasts, i)
        else
            dxDrawText(
                t.text,
                2,
                y + 2,
                UI.sw + 2,
                y + 2,
                tocolor(0, 0, 0, 200),
                UI.scale,
                UI.font,
                "center",
                "top",
                false,
                false,
                false,
                true
            )
            dxDrawText(t.text, 0, y, UI.sw, y, t.color, UI.scale, UI.font, "center", "top", false, false, false, true)
            y = y - 22 * UI.scale
        end
    end
end
