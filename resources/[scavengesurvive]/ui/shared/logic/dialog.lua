-- The SA-MP list dialog (DIALOG_STYLE_LIST) as pure geometry and state: a centred box with a title, a list of
-- rows with one selected (red) row, a scrollbar, and two buttons. Measured on the 1280x720 footage
-- (docs/ui-reference-samp.md section 2.2) and expressed in 640x480 canvas units.
local dialog = {}

local G = {
    w = 280,
    h = 203,
    titleX = 7,
    titleY = 10,
    listX = 7,
    listY = 23,
    listW = 269,
    listH = 150,
    rowH = 12,
    textPad = 5,
    scrollW = 12,
    btnW = 63,
    btnH = 18,
    btnGap = 17,
    btnY = 180,
}
dialog.G = G
dialog.VISIBLE = math.floor(G.listH / G.rowH)

-- Pixel rectangles for the dialog on a screen of sw x sh with canvas scale s.
function dialog.layout(sw, sh, s)
    local w, h = G.w * s, G.h * s
    local x, y = (sw - w) / 2, (sh - h) / 2
    local list = { x = x + G.listX * s, y = y + G.listY * s, w = G.listW * s, h = G.listH * s }
    local inner = { x = list.x, y = list.y, w = list.w - G.scrollW * s, h = list.h }
    local scroll = { x = list.x + list.w - G.scrollW * s, y = list.y, w = G.scrollW * s, h = list.h }
    local cx = x + w / 2
    return {
        s = s,
        box = { x = x, y = y, w = w, h = h },
        title = { x = x + G.titleX * s, y = y + G.titleY * s },
        list = list,
        inner = inner,
        scroll = scroll,
        scrollUp = { x = scroll.x, y = scroll.y, w = scroll.w, h = scroll.w },
        scrollDown = { x = scroll.x, y = scroll.y + scroll.h - scroll.w, w = scroll.w, h = scroll.w },
        rowH = G.rowH * s,
        textPad = G.textPad * s,
        left = { x = cx - (G.btnW + G.btnGap / 2) * s, y = y + G.btnY * s, w = G.btnW * s, h = G.btnH * s },
        right = { x = cx + (G.btnGap / 2) * s, y = y + G.btnY * s, w = G.btnW * s, h = G.btnH * s },
    }
end

-- Rows: { id = any, label = string, actions = { { id, label } } | nil, empty = bool }. An empty row is shown
-- but cannot be selected. buttons = { left, right } labels.
function dialog.new(listId, title, rows, buttons)
    local st = { id = listId, title = title, rows = rows or {}, selected = 0, scroll = 0, buttons = buttons }
    dialog.setRows(st, rows)
    return st
end

local function selectable(row)
    return row and not row.empty
end

function dialog.setRows(st, rows)
    st.rows = rows or {}
    if not selectable(st.rows[st.selected]) then
        st.selected = 0
        for i, r in ipairs(st.rows) do
            if selectable(r) then
                st.selected = i
                break
            end
        end
    end
    local maxScroll = math.max(0, #st.rows - dialog.VISIBLE)
    st.scroll = math.max(0, math.min(st.scroll, maxScroll))
end

-- Moves the selection by delta rows (keyboard) and scrolls to keep it visible.
function dialog.move(st, delta)
    local n = #st.rows
    if n == 0 then
        return
    end
    local i = st.selected == 0 and (delta > 0 and 0 or n + 1) or st.selected
    for _ = 1, n do
        i = i + (delta > 0 and 1 or -1)
        if i < 1 or i > n then
            return
        end
        if selectable(st.rows[i]) then
            st.selected = i
            break
        end
    end
    if st.selected - 1 < st.scroll then
        st.scroll = st.selected - 1
    elseif st.selected > st.scroll + dialog.VISIBLE then
        st.scroll = st.selected - dialog.VISIBLE
    end
end

function dialog.scrollBy(st, delta)
    local maxScroll = math.max(0, #st.rows - dialog.VISIBLE)
    st.scroll = math.max(0, math.min(st.scroll + delta, maxScroll))
end

-- Rows currently on screen: { index, row, x, y, w, h }
function dialog.visibleRows(st, L)
    local out = {}
    for i = st.scroll + 1, math.min(#st.rows, st.scroll + dialog.VISIBLE) do
        local k = i - st.scroll - 1
        out[#out + 1] =
            { index = i, row = st.rows[i], x = L.inner.x, y = L.inner.y + k * L.rowH, w = L.inner.w, h = L.rowH }
    end
    return out
end

-- Scrollbar thumb rectangle, or nil when every row fits.
function dialog.thumb(st, L)
    local n = #st.rows
    if n <= dialog.VISIBLE then
        return nil
    end
    local track = L.scroll.h - 2 * L.scrollUp.h
    local th = math.max(L.scrollUp.h, track * dialog.VISIBLE / n)
    local ty = L.scrollUp.y + L.scrollUp.h + (track - th) * st.scroll / (n - dialog.VISIBLE)
    return { x = L.scroll.x, y = ty, w = L.scroll.w, h = th }
end

local function inside(r, px, py)
    return px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h
end

-- What a click at (px, py) hits: "row", index | "left" | "right" | "scrollUp" | "scrollDown" | "box" | nil
function dialog.hit(st, L, px, py)
    if inside(L.left, px, py) then
        return "left"
    elseif inside(L.right, px, py) then
        return "right"
    elseif inside(L.scrollUp, px, py) then
        return "scrollUp"
    elseif inside(L.scrollDown, px, py) then
        return "scrollDown"
    end
    for _, v in ipairs(dialog.visibleRows(st, L)) do
        if inside(v, px, py) then
            return "row", v.index
        end
    end
    if inside(L.box, px, py) then
        return "box"
    end
    return nil
end

function dialog.selectedRow(st)
    return st.rows[st.selected]
end

return dialog
