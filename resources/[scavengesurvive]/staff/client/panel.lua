-- The staff panel (P, /staffpanel): a CEGUI window listing every command the player's level allows, a form built
-- from the chosen command's usage (text fields, choice drop-downs, a player picker filled with who is online) and
-- a Run button that sends the line through staffCommandIssued. The replies land in the chat box as before and are
-- echoed into the panel's output box while it is open. The server sends the command list (staffPanelShown) on
-- every open, so a level change needs no relog.
return function(ctx)
    local logic = ctx.logic
    local M = {}
    local panel = nil -- { window, grid, commands, usage, help, form = { fields, controls }, status, output }

    local W, H = 760, 520
    local LEFT_W = 300
    local FORM_X = LEFT_W + 20
    local FORM_W = W - FORM_X - 12
    local LINES_KEPT = 60

    local function destroyPanel()
        if panel then
            destroyElement(panel.window)
            panel = nil
            ctx.cursor(-1)
        end
    end

    local function setStatus(text, ok)
        guiSetText(panel.status, text)
        if ok then
            guiLabelSetColor(panel.status, 180, 255, 180)
        else
            guiLabelSetColor(panel.status, 255, 160, 160)
        end
    end

    local function onlineNames()
        local names = {}
        for _, p in ipairs(getElementsByType("player")) do
            names[#names + 1] = getPlayerName(p)
        end
        table.sort(names, function(a, b)
            return a:lower() < b:lower()
        end)
        return names
    end

    local function clearForm()
        if panel.form then
            for _, c in ipairs(panel.form.controls) do
                for _, el in pairs(c.elements) do
                    destroyElement(el)
                end
            end
        end
        panel.form = nil
    end

    -- One row per field: a label, then an edit, a drop-down, or an edit with a drop-down of online players
    -- (picking a name copies it into the edit, so an offline account name can still be typed).
    local function buildForm(def)
        clearForm()
        local controls = {}
        local y = 95
        local win = panel.window
        for _, f in ipairs(def.fields) do
            local label = guiCreateLabel(FORM_X, y, 150, 20, f.name .. (f.optional and " (optional)" or ""), false, win)
            local c = { field = f, elements = { label = label } }
            if f.kind == "choice" then
                local combo =
                    guiCreateComboBox(FORM_X + 155, y - 2, FORM_W - 155, 24 * (#f.options + 1), "", false, win)
                for _, opt in ipairs(f.options) do
                    guiComboBoxAddItem(combo, opt)
                end
                c.elements.combo = combo
                c.combo = combo
            else
                local editW = f.kind == "player" and (FORM_W - 155 - 150) or (FORM_W - 155)
                local edit = guiCreateEdit(FORM_X + 155, y - 2, editW, 24, "", false, win)
                c.elements.edit = edit
                c.edit = edit
                if f.kind == "player" then
                    local names = onlineNames()
                    for _, opt in ipairs(f.options) do
                        names[#names + 1] = opt
                    end
                    local x = FORM_X + 155 + editW + 6
                    local combo = guiCreateComboBox(x, y - 2, 144, 24 * math.min(#names + 1, 9), "pick", false, win)
                    for _, n in ipairs(names) do
                        guiComboBoxAddItem(combo, n)
                    end
                    c.elements.combo = combo
                    addEventHandler("onClientGUIComboBoxAccepted", combo, function()
                        local i = guiComboBoxGetSelected(combo)
                        if i and i >= 0 then
                            guiSetText(edit, guiComboBoxGetItemText(combo, i))
                        end
                    end, false)
                end
            end
            controls[#controls + 1] = c
            y = y + 30
        end
        panel.form = { def = def, fields = def.fields, controls = controls }
        guiSetPosition(panel.run, FORM_X, y + 6, false)
        guiSetVisible(panel.run, true)
        guiSetText(panel.run, "Run /" .. def.name)
    end

    local function values()
        local out = {}
        for i, c in ipairs(panel.form.controls) do
            if c.combo then
                local sel = guiComboBoxGetSelected(c.combo)
                out[i] = (sel and sel >= 0) and guiComboBoxGetItemText(c.combo, sel) or ""
            else
                out[i] = guiGetText(c.edit)
            end
        end
        return out
    end

    local function run()
        if not panel or not panel.form then
            return
        end
        local def = panel.form.def
        local args, err = logic.commandArgs(panel.form.fields, values())
        if not args then
            return setStatus(err, false)
        end
        setStatus("/" .. def.name .. (args ~= "" and (" " .. args) or ""), true)
        triggerServerEvent("staffCommandIssued", localPlayer, def.name, args)
    end

    local function selectCommand()
        local r = guiGridListGetSelectedItem(panel.grid)
        local def = r and r >= 0 and panel.commands[r + 1]
        if not def then
            return
        end
        guiSetText(panel.usage, def.usage)
        guiSetText(panel.help, def.help)
        setStatus("", true)
        buildForm(def)
    end

    local function open(commands)
        destroyPanel()
        ctx.cursor(1)
        local sw, sh = guiGetScreenSize()
        local win = guiCreateWindow((sw - W) / 2, (sh - H) / 2, W, H, "Staff panel", false)
        guiWindowSetSizable(win, false)
        local grid = guiCreateGridList(10, 25, LEFT_W, H - 75, false, win)
        guiGridListAddColumn(grid, "Command", 0.5)
        guiGridListAddColumn(grid, "Level", 0.4)
        guiGridListSetSortingEnabled(grid, false)
        for _, def in ipairs(commands) do
            local r = guiGridListAddRow(grid)
            guiGridListSetItemText(grid, r, 1, "/" .. def.name, false, false)
            guiGridListSetItemText(grid, r, 2, def.levelName, false, false)
            local col = logic.levelColour(def.level)
            guiGridListSetItemColor(grid, r, 2, col[1], col[2], col[3])
        end
        local usage = guiCreateLabel(FORM_X, 30, FORM_W, 20, "Pick a command on the left.", false, win)
        guiSetFont(usage, "default-bold-small")
        local help = guiCreateLabel(FORM_X, 50, FORM_W, 40, "", false, win)
        guiLabelSetHorizontalAlign(help, "left", true)
        local runBtn = guiCreateButton(FORM_X, 100, 150, 28, "Run", false, win)
        guiSetVisible(runBtn, false)
        local status = guiCreateLabel(FORM_X, H - 210, FORM_W, 20, "", false, win)
        local output = guiCreateMemo(FORM_X, H - 185, FORM_W, 140, "", false, win)
        guiMemoSetReadOnly(output, true)
        local close = guiCreateButton(10, H - 40, LEFT_W, 28, "Close (Escape)", false, win)
        panel = {
            window = win,
            grid = grid,
            commands = commands,
            usage = usage,
            help = help,
            run = runBtn,
            status = status,
            output = output,
            lines = {},
        }
        addEventHandler("onClientGUIClick", grid, selectCommand, false)
        addEventHandler("onClientGUIClick", runBtn, run, false)
        addEventHandler("onClientGUIClick", close, destroyPanel, false)
    end

    addEventHandler("staffPanelShown", root, function(commands)
        if type(commands) ~= "table" or #commands == 0 then
            return -- not staff: the key does nothing, as /acmds is unknown to players
        end
        open(commands)
    end)

    -- Chat lines while the panel is open (the staff replies among them), colour codes stripped.
    addEventHandler("onClientChatMessage", root, function(text)
        if not panel then
            return
        end
        local lines = panel.lines
        lines[#lines + 1] = tostring(text):gsub("#%x%x%x%x%x%x", "")
        if #lines > LINES_KEPT then
            table.remove(lines, 1)
        end
        guiSetText(panel.output, table.concat(lines, "\n"))
        guiMemoSetCaretIndex(panel.output, #table.concat(lines, "\n"))
    end)

    function M.toggle()
        if panel then
            return destroyPanel()
        end
        if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then
            return
        end
        triggerServerEvent("staffPanelRequested", localPlayer)
    end

    function M.escape()
        if panel then
            destroyPanel()
            return true
        end
        return false
    end

    function M.isOpen()
        return panel ~= nil
    end

    addCommandHandler("staffpanel", M.toggle)
    bindKey("p", "down", "staffpanel")

    return M
end
