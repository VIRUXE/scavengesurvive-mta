local progress = nil
function progressStart(label, durationMs)
    progress = { label = label, start = getTickCount(), duration = durationMs }
    return true
end
function progressCancel()
    progress = nil
    return true
end
function UI.drawProgress()
    if not progress then
        return
    end
    local frac = (getTickCount() - progress.start) / progress.duration
    if frac >= 1 then
        progress = nil
        return
    end
    local w, h = 260 * UI.scale, 14 * UI.scale
    local x, y = (UI.sw - w) / 2, UI.sh * 0.72
    dxDrawRectangle(x - 2, y - 2, w + 4, h + 4, tocolor(0, 0, 0, 180))
    dxDrawRectangle(x, y, w * frac, h, tocolor(220, 60, 40, 230))
    dxDrawText(
        progress.label,
        x,
        y - 20 * UI.scale,
        x + w,
        y,
        tocolor(255, 255, 255, 230),
        UI.scale,
        UI.font,
        "center",
        "top"
    )
end
