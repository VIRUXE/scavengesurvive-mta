-- The server's list, message and input dialogs as CEGUI windows: a grid list with two buttons (a row with
-- actions opens its action list in the same window, Accept/Back), and a message box with an optional edit
-- (masked for passwords). Enter is the left button, Escape the right one. The answers go back through the
-- staffListActionSelected / staffListClosed / staffDialogResponded events; one list and one dialog at a time.
return function(ctx)
    local M = {}
    local list = nil -- { key, window, grid, left, right, rows, options = { rowId, rows } | nil }
    local dialog = nil -- { key, window, edit, left, right }

    local LIST_W, LIST_H = 460, 400
    local BTN_W, BTN_H = 110, 28

    local function centred(w, h)
        local sw, sh = guiGetScreenSize()
        return (sw - w) / 2, (sh - h) / 2
    end

    local function window(title, w, h)
        local x, y = centred(w, h)
        local win = guiCreateWindow(x, y, w, h, title, false)
        guiWindowSetSizable(win, false)
        return win
    end

    -- Fills the grid with rows ({ id, label, actions, empty, colour }); empty rows are greyed and never selected.
    local function fill(grid, rows)
        guiGridListClear(grid)
        for _, row in ipairs(rows) do
            local r = guiGridListAddRow(grid)
            guiGridListSetItemText(grid, r, 1, tostring(row.label or ""), false, false)
            if row.empty then
                guiGridListSetItemColor(grid, r, 1, 170, 170, 170)
            elseif row.colour then
                guiGridListSetItemColor(grid, r, 1, row.colour[1], row.colour[2], row.colour[3])
            end
        end
    end

    local function selectedRow(st, rows)
        local r = guiGridListGetSelectedItem(st.grid)
        if not r or r < 0 then
            return nil
        end
        local row = rows[r + 1]
        if not row or row.empty then
            return nil
        end
        return row
    end

    local function showBase(st)
        st.options = nil
        guiSetText(st.window, st.title)
        fill(st.grid, st.rows)
        guiSetText(st.left, st.buttons[1])
        guiSetText(st.right, st.buttons[2])
    end

    local function showOptions(st, row)
        local rows = {}
        for _, a in ipairs(row.actions) do
            rows[#rows + 1] = { id = a.id, label = a.label }
        end
        st.options = { rowId = row.id, rows = rows }
        guiSetText(st.window, tostring(row.label))
        fill(st.grid, rows)
        guiSetText(st.left, "Accept")
        guiSetText(st.right, "Back")
    end

    local function destroyList()
        if list then
            destroyElement(list.window)
            list = nil
            ctx.cursor(-1)
        end
    end

    local function listLeft()
        local st = list
        if st.options then
            local row = selectedRow(st, st.options.rows)
            if row then
                triggerServerEvent("staffListActionSelected", localPlayer, st.key, st.options.rowId, row.id)
                showBase(st)
            end
            return
        end
        local row = selectedRow(st, st.rows)
        if not row then
            return
        end
        if row.actions and #row.actions > 0 then
            showOptions(st, row)
        else
            triggerServerEvent("staffListActionSelected", localPlayer, st.key, row.id, "select")
        end
    end

    local function listRight()
        local st = list
        if st.options then
            return showBase(st)
        end
        local key = st.key
        destroyList()
        triggerServerEvent("staffListClosed", localPlayer, key)
    end

    function M.listOpen(key, title, rows, buttons)
        if list then
            destroyElement(list.window)
            list = nil
        else
            ctx.cursor(1)
        end
        local win = window(title, LIST_W, LIST_H)
        local grid = guiCreateGridList(10, 25, LIST_W - 20, LIST_H - 75, false, win)
        guiGridListAddColumn(grid, "", 0.93)
        guiGridListSetSortingEnabled(grid, false)
        local left = guiCreateButton(LIST_W / 2 - BTN_W - 10, LIST_H - 40, BTN_W, BTN_H, "", false, win)
        local right = guiCreateButton(LIST_W / 2 + 10, LIST_H - 40, BTN_W, BTN_H, "", false, win)
        list = {
            key = key,
            title = tostring(title or ""),
            window = win,
            grid = grid,
            left = left,
            right = right,
            rows = rows or {},
            buttons = { tostring(buttons and buttons[1] or "Options"), tostring(buttons and buttons[2] or "Close") },
        }
        showBase(list)
        addEventHandler("onClientGUIClick", left, listLeft, false)
        addEventHandler("onClientGUIClick", right, listRight, false)
        addEventHandler("onClientGUIDoubleClick", grid, listLeft, false)
    end

    -- the server closed the list itself: no staffListClosed goes back
    function M.listDismiss()
        destroyList()
    end

    local function destroyDialog()
        if dialog then
            destroyElement(dialog.window)
            dialog = nil
            ctx.cursor(-1)
        end
    end

    local function answer(accepted)
        local st = dialog
        local text = st.edit and guiGetText(st.edit) or ""
        destroyDialog()
        triggerServerEvent("staffDialogResponded", localPlayer, st.key, accepted, text)
    end

    function M.dialogOpen(key, style, title, body, left, right)
        if dialog then
            destroyElement(dialog.window)
            dialog = nil
        else
            ctx.cursor(1)
        end
        body = tostring(body or "")
        local lines = select(2, body:gsub("\n", "")) + 1 + math.floor(#body / 70)
        local hasEdit = style == "input" or style == "password"
        local w = 480
        local bodyH = math.max(1, lines) * 16 + 10
        local h = 35 + bodyH + (hasEdit and 36 or 0) + 50
        local win = window(title, w, h)
        local label = guiCreateLabel(12, 28, w - 24, bodyH, body, false, win)
        guiLabelSetHorizontalAlign(label, "left", true)
        local edit = nil
        if hasEdit then
            edit = guiCreateEdit(12, 28 + bodyH + 4, w - 24, 28, "", false, win)
            guiEditSetMasked(edit, style == "password")
            guiBringToFront(edit)
        end
        local y = h - 40
        right = tostring(right or "")
        local leftBtn, rightBtn
        if right == "" then
            leftBtn = guiCreateButton(w / 2 - BTN_W / 2, y, BTN_W, BTN_H, tostring(left or "Accept"), false, win)
        else
            leftBtn = guiCreateButton(w / 2 - BTN_W - 10, y, BTN_W, BTN_H, tostring(left or "Accept"), false, win)
            rightBtn = guiCreateButton(w / 2 + 10, y, BTN_W, BTN_H, right, false, win)
        end
        dialog = { key = key, window = win, edit = edit, left = leftBtn, right = rightBtn }
        addEventHandler("onClientGUIClick", leftBtn, function()
            answer(true)
        end, false)
        if rightBtn then
            addEventHandler("onClientGUIClick", rightBtn, function()
                answer(false)
            end, false)
        end
        if edit then
            addEventHandler("onClientGUIAccepted", edit, function()
                answer(true)
            end, false)
        end
    end

    -- Escape: the dialog's right button (or its only button), else the list's right button. True when handled.
    function M.escape()
        if dialog then
            answer(dialog.right == nil)
            return true
        end
        if list then
            listRight()
            return true
        end
        return false
    end

    function M.isOpen()
        return dialog ~= nil or list ~= nil
    end

    return M
end
