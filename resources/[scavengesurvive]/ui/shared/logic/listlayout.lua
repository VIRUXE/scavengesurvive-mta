local layout = {}
local BASE = { panelW = 420, rowH = 34, actionH = 28, actionW = 110, pad = 8, titleH = 36, closeW = 28 }

function layout.compute(rows, expandedRowId, screenW, screenH, scale)
    local s = scale or 1
    local panelW = BASE.panelW * s
    local rowH, actionH = BASE.rowH * s, BASE.actionH * s
    local pad, titleH = BASE.pad * s, BASE.titleH * s
    local x0 = (screenW - panelW) / 2
    local out = { rows = {}, rowH = rowH, maxVisible = 12 }
    local y = titleH + pad
    for _, r in ipairs(rows) do
        local row = { id = r.id, x = x0 + pad, y = 0, w = panelW - pad * 2, h = rowH, actions = {} }
        row.y = y -- provisional; absolute after panel y known
        y = y + rowH
        if r.id == expandedRowId then
            local ax = row.x
            for _, a in ipairs(r.actions or {}) do
                row.actions[#row.actions + 1] =
                    { id = a.id, label = a.label, x = ax, y = y, w = BASE.actionW * s, h = actionH }
                ax = ax + BASE.actionW * s + pad
            end
            y = y + actionH + pad
        end
        out.rows[#out.rows + 1] = row
    end
    local panelH = y + pad
    local y0 = (screenH - panelH) / 2
    for _, row in ipairs(out.rows) do
        row.y = row.y + y0
        for _, a in ipairs(row.actions) do
            a.y = a.y + y0
        end
    end
    out.panel = { x = x0, y = y0, w = panelW, h = panelH }
    out.title = { x = x0 + pad, y = y0 + pad, h = titleH }
    out.close = { x = x0 + panelW - BASE.closeW * s - pad, y = y0 + pad, w = BASE.closeW * s, h = BASE.closeW * s }
    return out
end

local function inside(r, cx, cy)
    return cx >= r.x and cx <= r.x + r.w and cy >= r.y and cy <= r.y + r.h
end

function layout.hit(c, cx, cy)
    if inside(c.close, cx, cy) then
        return "close"
    end
    for _, row in ipairs(c.rows) do
        for _, a in ipairs(row.actions) do
            if inside(a, cx, cy) then
                return "action", row.id, a.id
            end
        end
        if inside(row, cx, cy) then
            return "row", row.id
        end
    end
    if inside(c.panel, cx, cy) then
        return "panel"
    end
    return nil
end

return layout
