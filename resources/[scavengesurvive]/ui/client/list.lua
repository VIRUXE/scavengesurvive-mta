-- The SA-MP list dialog in dx: title "(used/size)", rows with a red selected row, scrollbar, two buttons.
-- Level 1 lists the rows the caller gave; the left button on a row with actions opens level 2, a second dialog
-- titled with the row label listing its actions with Accept/Back (inventory-dialog.inc / container-dialog.inc).
-- A row without actions is a navigation row: the left button emits actionId "select" for it.
-- Emits uiListActionSelected(listId, rowId, actionId) and uiListClosed(listId). One dialog at a time.
return function(ctx)
    local dialog, canvas, c = ctx.dialog, ctx.canvas, ctx.c
    local COL = {
        box = tocolor(0, 0, 0, 215),
        list = tocolor(0, 0, 0, 240),
        selected = tocolor(139, 26, 30, 255),
        text = tocolor(255, 255, 255, 255),
        empty = tocolor(200, 200, 200, 255),
        button = tocolor(45, 45, 45, 255),
        border = tocolor(190, 190, 190, 255),
        scroll = tocolor(60, 60, 60, 255),
        thumb = tocolor(150, 150, 150, 255),
    }
    local DEFAULT_BUTTONS = { "Options", "Close" }
    local OPTION_BUTTONS = { "Accept", "Back" }
    local state = nil -- { base = dialog state, options = dialog state | nil }
    local M = {}

    local function current()
        return state and (state.options or state.base)
    end

    function M.open(listId, title, rows, buttons)
        state = { base = dialog.new(listId, title, rows, buttons or DEFAULT_BUTTONS) }
        showCursor(true)
        return true
    end

    function M.update(listId, rows)
        if not state or state.base.id ~= listId then
            return false
        end
        dialog.setRows(state.base, rows)
        state.options = nil
        return true
    end

    function M.close()
        if not state then
            return false
        end
        local id = state.base.id
        state = nil
        showCursor(false)
        triggerEvent("uiListClosed", root, id)
        return true
    end

    function M.isOpen()
        return state ~= nil
    end

    local function leftButton()
        local st = current()
        local row = dialog.selectedRow(st)
        if not row then
            return
        end
        if state.options then
            triggerEvent("uiListActionSelected", root, state.base.id, state.options.rowId, row.id)
            state.options = nil
            return
        end
        if row.actions and #row.actions > 0 then
            local rows = {}
            for _, a in ipairs(row.actions) do
                rows[#rows + 1] = { id = a.id, label = a.label }
            end
            state.options = dialog.new(state.base.id, row.label, rows, OPTION_BUTTONS)
            state.options.rowId = row.id
        else
            triggerEvent("uiListActionSelected", root, state.base.id, row.id, "select")
        end
    end

    local function rightButton()
        if state.options then
            state.options = nil
        else
            M.close()
        end
    end

    local function rect(r, colour)
        dxDrawRectangle(r.x, r.y, r.w, r.h, colour)
    end

    local function button(r, label)
        rect(r, COL.button)
        dxDrawLine(r.x, r.y, r.x + r.w, r.y, COL.border)
        dxDrawLine(r.x, r.y + r.h, r.x + r.w, r.y + r.h, COL.border)
        dxDrawLine(r.x, r.y, r.x, r.y + r.h, COL.border)
        dxDrawLine(r.x + r.w, r.y, r.x + r.w, r.y + r.h, COL.border)
        local scale = canvas.textScale(c, 1.3, 1)
        dxDrawText(label, r.x, r.y, r.x + r.w, r.y + r.h, COL.text, scale, canvas.font(1), "center", "center")
    end

    function M.draw()
        local st = current()
        if not st then
            return
        end
        local L = dialog.layout(c.sw, c.sh, c.s)
        rect(L.box, COL.box)
        local titleScale = canvas.textScale(c, 1.4, 1)
        dxDrawText(st.title, L.title.x, L.title.y, L.box.x + L.box.w, L.list.y, COL.text, titleScale, canvas.font(1))
        rect(L.list, COL.list)
        local rowScale = canvas.textScale(c, 1.2, 1)
        for _, v in ipairs(dialog.visibleRows(st, L)) do
            if v.index == st.selected then
                rect(v, COL.selected)
            end
            local colour = v.row.empty and COL.empty or COL.text
            dxDrawText(
                v.row.label,
                v.x + L.textPad,
                v.y,
                v.x + v.w,
                v.y + v.h,
                colour,
                rowScale,
                canvas.font(1),
                "left",
                "center",
                true
            )
        end
        rect(L.scroll, COL.scroll)
        local thumb = dialog.thumb(st, L)
        if thumb then
            rect(thumb, COL.thumb)
        end
        local b = st.buttons or DEFAULT_BUTTONS
        button(L.left, b[1])
        button(L.right, b[2])
    end

    addEventHandler("onClientClick", root, function(btn, pressState, ax, ay)
        local st = current()
        if not st or btn ~= "left" or pressState ~= "down" then
            return
        end
        local L = dialog.layout(c.sw, c.sh, c.s)
        local kind, index = dialog.hit(st, L, ax, ay)
        if kind == "row" then
            if not st.rows[index].empty then
                st.selected = index
            end
        elseif kind == "left" then
            leftButton()
        elseif kind == "right" then
            rightButton()
        elseif kind == "scrollUp" then
            dialog.scrollBy(st, -1)
        elseif kind == "scrollDown" then
            dialog.scrollBy(st, 1)
        end
    end)

    addEventHandler("onClientDoubleClick", root, function(btn, ax, ay)
        local st = current()
        if not st or btn ~= "left" then
            return
        end
        local L = dialog.layout(c.sw, c.sh, c.s)
        local kind, index = dialog.hit(st, L, ax, ay)
        if kind == "row" and not st.rows[index].empty then
            st.selected = index
            leftButton()
        end
    end)

    addEventHandler("onClientKey", root, function(key, press)
        local st = current()
        if not st or not press then
            return
        end
        if key == "arrow_u" then
            dialog.move(st, -1)
        elseif key == "arrow_d" then
            dialog.move(st, 1)
        elseif key == "mouse_wheel_up" then
            dialog.scrollBy(st, -1)
        elseif key == "mouse_wheel_down" then
            dialog.scrollBy(st, 1)
        elseif key == "enter" then
            leftButton()
        elseif key == "escape" or key == "backspace" then
            rightButton()
        else
            return
        end
        cancelEvent()
    end)

    return M
end
