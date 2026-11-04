-- The SA-MP list dialog in dx: title "(used/size)", rows with a red selected row, scrollbar, two buttons.
-- Level 1 lists the rows the caller gave; the left button on a row with actions opens level 2, a second dialog
-- titled with the row label listing its actions with Accept/Back (inventory-dialog.inc / container-dialog.inc).
-- A row without actions is a navigation row: the left button emits actionId "select" for it. A row may carry
-- colour = { r, g, b } for its label.
-- Emits uiListActionSelected(listId, rowId, actionId) and uiListClosed(listId). One dialog at a time.
return function(ctx)
    local dialog, canvas, c = ctx.dialog, ctx.canvas, ctx.c
    local COL = {
        box = tocolor(0, 0, 0, 215),
        list = tocolor(0, 0, 0, 240),
        selected = tocolor(139, 26, 30, 255),
        text = tocolor(255, 255, 255, 255),
        empty = tocolor(200, 200, 200, 255),
        scroll = tocolor(60, 60, 60, 255),
        thumb = tocolor(150, 150, 150, 255),
    }
    local tr = ctx.tr
    local function defaultButtons()
        return { tr("Options"), tr("Close") }
    end
    local function optionButtons()
        return { tr("Accept"), tr("Back") }
    end
    local state = nil -- { base = dialog state, options = dialog state | nil }
    local M = {}

    local function current()
        return state and (state.options or state.base)
    end

    function M.open(listId, title, rows, buttons)
        state = { base = dialog.new(listId, title, rows, buttons or defaultButtons()) }
        showCursor(true)
        return true
    end

    -- new rows (and title) for the list already open, keeping the selection and scroll; the actions dialog stays
    -- open while its row is still there. false when listId is not the open list.
    function M.update(listId, rows, title)
        if not state or state.base.id ~= listId then
            return false
        end
        local base = state.base
        local selectedId = base.rows[base.selected] and base.rows[base.selected].id
        if title then
            base.title = title
        end
        dialog.setRows(base, rows)
        if selectedId ~= nil and base.rows[base.selected] and base.rows[base.selected].id ~= selectedId then
            for i, r in ipairs(base.rows) do
                if r.id == selectedId and not r.empty then
                    base.selected = i
                    break
                end
            end
        end
        local opts = state.options
        if opts then
            local row
            for _, r in ipairs(base.rows) do
                if r.id == opts.rowId then
                    row = r
                    break
                end
            end
            if row and row.actions and #row.actions > 0 then
                local optRows = {}
                for _, a in ipairs(row.actions) do
                    optRows[#optRows + 1] = { id = a.id, label = a.label }
                end
                dialog.setRows(opts, optRows)
            else
                state.options = nil
            end
        end
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
            state.options = dialog.new(state.base.id, row.label, rows, optionButtons())
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

    local rect, button = ctx.draw.pxRect, ctx.draw.pxButton

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
            local rc = v.row.colour -- optional { r, g, b } (the Skills list colours each level)
            local colour = v.row.empty and COL.empty or (rc and tocolor(rc[1], rc[2], rc[3], 255)) or COL.text
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
        local b = st.buttons or defaultButtons()
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
