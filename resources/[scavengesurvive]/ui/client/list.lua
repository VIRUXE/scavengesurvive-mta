local layout
do
    local f = fileOpen("shared/logic/listlayout.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    layout = assert(loadstring(src, "=ui/listlayout.lua"))()
end
local state = nil

local function recompute()
    state.computed = layout.compute(state.rows, state.expanded, UI.sw, UI.sh, UI.scale)
end

function listOpen(listId, title, rows)
    state = { id = listId, title = title, rows = rows, expanded = nil }
    recompute()
    UI.list = state
    showCursor(true)
    return true
end

function listUpdate(listId, rows)
    if not state or state.id ~= listId then
        return false
    end
    state.rows = rows
    recompute()
    return true
end

function listClose()
    if not state then
        return false
    end
    local id = state.id
    state, UI.list = nil, nil
    showCursor(false)
    triggerEvent("onClientUiListClosed", root, id)
    return true
end

function listIsOpen()
    return state ~= nil
end

function UI.drawList()
    local c = state.computed
    dxDrawRectangle(c.panel.x, c.panel.y, c.panel.w, c.panel.h, tocolor(10, 10, 10, 220))
    dxDrawText(
        state.title,
        c.title.x,
        c.title.y,
        c.panel.x + c.panel.w,
        c.title.y + c.title.h,
        tocolor(255, 255, 255),
        UI.scale * 1.1,
        UI.font,
        "left",
        "center"
    )
    dxDrawText(
        "X",
        c.close.x,
        c.close.y,
        c.close.x + c.close.w,
        c.close.y + c.close.h,
        tocolor(255, 90, 90),
        UI.scale,
        UI.font,
        "center",
        "center"
    )
    for i, row in ipairs(c.rows) do
        local r = state.rows[i]
        local bg = (row.id == state.expanded) and tocolor(60, 60, 60, 200) or tocolor(30, 30, 30, 200)
        dxDrawRectangle(row.x, row.y, row.w, row.h - 2, bg)
        dxDrawText(
            r.label,
            row.x + 8,
            row.y,
            row.x + row.w,
            row.y + row.h,
            tocolor(255, 255, 255),
            UI.scale,
            UI.font,
            "left",
            "center"
        )
        dxDrawText(
            r.sub or "",
            row.x,
            row.y,
            row.x + row.w - 8,
            row.y + row.h,
            tocolor(180, 180, 180),
            UI.scale * 0.9,
            UI.font,
            "right",
            "center"
        )
        for _, a in ipairs(row.actions) do
            dxDrawRectangle(a.x, a.y, a.w, a.h, tocolor(80, 120, 80, 220))
            dxDrawText(
                a.label,
                a.x,
                a.y,
                a.x + a.w,
                a.y + a.h,
                tocolor(255, 255, 255),
                UI.scale,
                UI.font,
                "center",
                "center"
            )
        end
    end
end

addEventHandler("onClientClick", root, function(button, pressState, ax, ay)
    if not state or button ~= "left" or pressState ~= "down" then
        return
    end
    local kind, rowId, actionId = layout.hit(state.computed, ax, ay)
    if kind == "close" then
        listClose()
    elseif kind == "row" then
        state.expanded = (state.expanded ~= rowId) and rowId or nil
        recompute()
    elseif kind == "action" then
        triggerEvent("onClientUiListAction", root, state.id, rowId, actionId)
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if state and press and key == "escape" then
        listClose()
        cancelEvent()
    end
end)
