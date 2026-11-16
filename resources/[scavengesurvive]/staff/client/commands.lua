-- The command reference (/acmds): a CEGUI window listing every command the player's level allows, grouped by
-- level under a section row, with the usage and what the command does in columns and a filter box over name,
-- usage and description. Double-click (or Open in panel) opens the staff panel on that command's form. The
-- server sends the list (staffCommandsShown) on every open, as it does for the panel.
return function(ctx)
    local logic = ctx.logic
    local M = {}
    local win = nil -- { window, filter, grid, openBtn, commands }

    local W, H = 760, 520
    local BTN_W, BTN_H = 150, 28

    local function destroy()
        if win then
            destroyElement(win.window)
            win = nil
            ctx.cursor(-1)
        end
    end

    local function selected()
        local r = guiGridListGetSelectedItem(win.grid)
        if not r or r < 0 then
            return nil
        end
        return guiGridListGetItemData(win.grid, r, 1) or nil
    end

    local function refreshButton()
        guiSetEnabled(win.openBtn, selected() ~= nil)
    end

    local function fill()
        local grid = win.grid
        guiGridListClear(grid)
        local level = nil
        for _, def in ipairs(logic.filterCommands(win.commands, guiGetText(win.filter))) do
            local col = logic.levelColour(def.level)
            if def.level ~= level then
                level = def.level
                local s = guiGridListAddRow(grid)
                local title = string.format("%s (level %d)", def.levelName, def.level)
                guiGridListSetItemText(grid, s, 1, title, true, false)
                guiGridListSetItemColor(grid, s, 1, col[1], col[2], col[3])
            end
            local r = guiGridListAddRow(grid)
            guiGridListSetItemText(grid, r, 1, def.usage, false, false)
            guiGridListSetItemText(grid, r, 2, def.help, false, false)
            guiGridListSetItemData(grid, r, 1, def.name)
        end
        refreshButton()
    end

    local function openInPanel()
        local name = win and selected()
        if not name then
            return
        end
        local commands = win.commands
        destroy()
        ctx.panel.show(commands, name)
    end

    local function open(commands)
        destroy()
        ctx.cursor(1)
        local sw, sh = guiGetScreenSize()
        local window = guiCreateWindow((sw - W) / 2, (sh - H) / 2, W, H, "Staff commands", false)
        guiWindowSetSizable(window, false)
        guiCreateLabel(12, 30, 40, 20, "Filter", false, window)
        local filter = guiCreateEdit(55, 26, W - 67, 24, "", false, window)
        local grid = guiCreateGridList(10, 58, W - 20, H - 128, false, window)
        guiGridListAddColumn(grid, "Command", 0.42)
        guiGridListAddColumn(grid, "What it does", 0.53)
        guiGridListSetSortingEnabled(grid, false)
        local hint = "Double-click a command to open its form in the staff panel (P or /staffpanel)."
        local tip = guiCreateLabel(12, H - 64, W - 24, 18, hint, false, window)
        guiLabelSetColor(tip, 170, 170, 170)
        local openBtn = guiCreateButton(W / 2 - BTN_W - 10, H - 40, BTN_W, BTN_H, "Open in panel", false, window)
        local close = guiCreateButton(W / 2 + 10, H - 40, BTN_W, BTN_H, "Close (Escape)", false, window)
        win = { window = window, filter = filter, grid = grid, openBtn = openBtn, commands = commands }
        fill()
        addEventHandler("onClientGUIChanged", filter, fill, false)
        addEventHandler("onClientGUIClick", grid, refreshButton, false)
        addEventHandler("onClientGUIDoubleClick", grid, openInPanel, false)
        addEventHandler("onClientGUIClick", openBtn, openInPanel, false)
        addEventHandler("onClientGUIClick", close, destroy, false)
        guiBringToFront(filter)
    end

    addEventHandler("staffCommandsShown", root, function(commands)
        if type(commands) == "table" and #commands > 0 then
            open(commands)
        end
    end)

    function M.escape()
        if win then
            destroy()
            return true
        end
        return false
    end

    function M.isOpen()
        return win ~= nil
    end

    return M
end
