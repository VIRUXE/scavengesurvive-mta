-- The replay interface. CEGUI (like the staff tools) for the control window: play/pause, speed, camera mode, skip
-- idle, go-to-time, subject switch, the event list (click a row to jump there) and Stop. dx only for what CEGUI
-- cannot do: the REPLAY banner and the scrubbable timeline bar with coloured event ticks. Tab toggles the mouse
-- cursor (so the free camera keeps the mouse); the window and the input mode are undone on close.
-- ctx = { timeline, actions = { playPause, faster, slower, setCamera, setSkipIdle, gotoTime, setSubject, jumpTo, stop,
-- scrub }, kindColor(kind) -> r, g, b, wall(t) -> "HH:MM:SS" }
return function(ctx)
    local timeline = ctx.timeline
    local act = ctx.actions
    local M = {}

    local W, H = 340, 620
    local MAX_ROWS = 700
    local ui = nil -- { window, controls..., session, cursor, savedInput, lastText }
    local cursorOn = false

    local function label(parent, x, y, w, text)
        return guiCreateLabel(x, y, w, 20, text, false, parent)
    end

    local function button(parent, x, y, w, text, fn)
        local b = guiCreateButton(x, y, w, 26, text, false, parent)
        addEventHandler("onClientGUIClick", b, function(btn)
            if btn == "left" then
                fn()
            end
        end, false)
        return b
    end

    function M.isOpen()
        return ui ~= nil
    end

    function M.cursorOn()
        return cursorOn
    end

    function M.setCursor(on)
        cursorOn = on and true or false
        showCursor(cursorOn)
        if ui then
            guiSetAlpha(ui.window, cursorOn and 1 or 0.55)
            if not cursorOn then
                guiSetInputMode("allow_binds")
            else
                guiSetInputMode("no_binds_when_editing")
            end
        end
        ctx.onCursor(cursorOn)
    end

    function M.toggleCursor()
        M.setCursor(not cursorOn)
    end

    -- rebuild the event list (also when a chunk brings new events)
    function M.setEvents(events)
        if not ui then
            return
        end
        guiGridListClear(ui.grid)
        local n = math.min(#events, MAX_ROWS)
        local step = #events > MAX_ROWS and (#events / MAX_ROWS) or 1
        for i = 1, n do
            local e = events[math.floor((i - 1) * step) + 1]
            local row = guiGridListAddRow(ui.grid)
            guiGridListSetItemText(ui.grid, row, 1, ctx.wall(e.t), false, false)
            guiGridListSetItemText(ui.grid, row, 2, tostring(e.label or e.kind), false, false)
            guiGridListSetItemData(ui.grid, row, 1, e.t)
            local r, g, b = ctx.kindColor(e.kind)
            guiGridListSetItemColor(ui.grid, row, 1, r, g, b)
            guiGridListSetItemColor(ui.grid, row, 2, r, g, b)
        end
    end

    -- the subjects the viewer can follow: { { char, name } }
    function M.setSubjects(list, current)
        if not ui then
            return
        end
        guiComboBoxClear(ui.subject)
        local selected = -1
        for _, s in ipairs(list) do
            local idx = guiComboBoxAddItem(ui.subject, s.name .. "  #" .. tostring(s.char))
            if s.char == current then
                selected = idx
            end
            ui.subjects[idx] = s.char
        end
        guiComboBoxSetSelected(ui.subject, selected)
    end

    function M.open(session)
        if ui then
            M.close()
        end
        local _, sh = guiGetScreenSize()
        local win = guiCreateWindow(12, math.max(60, sh * 0.5 - H / 2), W, H, "Replay", false)
        guiWindowSetSizable(win, false)
        ui = { window = win, session = session, subjects = {}, savedInput = guiGetInputMode(), lastText = "" }
        ui.time = label(win, 12, 26, W - 24, "00:00:00")
        guiSetFont(ui.time, "default-bold-small")
        ui.play = button(win, 10, 50, 90, "Play", act.playPause)
        button(win, 106, 50, 30, "-", act.slower)
        ui.speed = guiCreateLabel(140, 55, 50, 20, "1x", false, win)
        button(win, 192, 50, 30, "+", act.faster)
        button(win, 228, 50, 100, "Stop", act.stop)

        label(win, 12, 86, 60, "Camera")
        local x = 74
        for _, m in ipairs({ "follow", "top", "side", "free" }) do
            local name = m
            button(win, x, 82, 60, name:sub(1, 1):upper() .. name:sub(2), function()
                act.setCamera(name)
            end)
            x = x + 63
        end
        ui.skip = guiCreateCheckBox(12, 114, 150, 20, "Skip idle", false, false, win)
        addEventHandler("onClientGUIClick", ui.skip, function(btn)
            if btn == "left" then
                act.setSkipIdle(guiCheckBoxGetSelected(ui.skip))
            end
        end, false)

        label(win, 12, 142, 60, "Go to")
        ui.gotoEdit = guiCreateEdit(74, 138, 150, 24, "", false, win)
        local function go()
            act.gotoTime(guiGetText(ui.gotoEdit))
        end
        button(win, 230, 138, 98, "Go", go)
        addEventHandler("onClientGUIAccepted", ui.gotoEdit, go, false)

        label(win, 12, 172, 60, "Follow")
        ui.subject = guiCreateComboBox(74, 168, W - 86, 120, "", false, win)
        addEventHandler("onClientGUIComboBoxAccepted", ui.subject, function()
            local idx = guiComboBoxGetSelected(ui.subject)
            if idx and idx >= 0 and ui.subjects[idx] then
                act.setSubject(ui.subjects[idx])
            end
        end, false)

        ui.grid = guiCreateGridList(10, 200, W - 20, H - 250, false, win)
        guiGridListAddColumn(ui.grid, "Time", 0.3)
        guiGridListAddColumn(ui.grid, "Event", 0.62)
        guiGridListSetSortingEnabled(ui.grid, false)
        addEventHandler("onClientGUIClick", ui.grid, function(btn)
            if btn ~= "left" then
                return
            end
            local row = guiGridListGetSelectedItem(ui.grid)
            if row and row >= 0 then
                local t = guiGridListGetItemData(ui.grid, row, 1)
                if tonumber(t) then
                    act.jumpTo(tonumber(t))
                end
            end
        end, false)
        ui.hint = guiCreateLabel(
            12,
            H - 42,
            W - 24,
            36,
            "Tab: mouse   Space: play   [ ]: speed   Arrows: step   PgUp/PgDn: event   C: camera   Backspace: stop",
            false,
            win
        )
        guiLabelSetColor(ui.hint, 170, 170, 170)
        guiLabelSetHorizontalAlign(ui.hint, "left", true)
        M.setSubjects({}, nil)
        guiSetAlpha(win, 0.55)
    end

    function M.close()
        if not ui then
            return
        end
        local saved = ui.savedInput
        if isElement(ui.window) then
            destroyElement(ui.window)
        end
        ui = nil
        if cursorOn then
            showCursor(false)
            cursorOn = false
            ctx.onCursor(false)
        end
        guiSetInputMode(saved or "allow_binds")
    end

    -- the window's changing texts, a few times a second
    function M.refresh(clock, wallText, playing, speed)
        if not ui then
            return
        end
        local text = wallText .. "   " .. timeline.format(clock.t) .. " / " .. timeline.format(clock.duration)
        if text ~= ui.lastText then
            ui.lastText = text
            guiSetText(ui.time, text)
        end
        guiSetText(ui.play, playing and "Pause" or "Play")
        guiSetText(ui.speed, string.format("%gx", speed))
        guiCheckBoxSetSelected(ui.skip, clock.skipIdle)
    end

    -- timeline geometry
    local function bar()
        local sw, sh = guiGetScreenSize()
        local x1, x2 = sw * 0.14, sw * 0.86
        return x1, sh - 64, x2 - x1, 22
    end

    local scrubbing = false

    function M.drawBanner(text)
        local sw = guiGetScreenSize()
        local w = 420
        dxDrawRectangle(sw / 2 - w / 2, 8, w, 28, tocolor(150, 20, 20, 210))
        dxDrawText(
            "REPLAY  -  " .. text,
            sw / 2 - w / 2,
            8,
            sw / 2 + w / 2,
            36,
            tocolor(255, 255, 255, 255),
            1.1,
            "default-bold",
            "center",
            "center",
            true
        )
    end

    function M.drawTimeline(clock, events, idle)
        local x, y, w, h = bar()
        dxDrawRectangle(x - 4, y - 18, w + 8, h + 36, tocolor(0, 0, 0, 150))
        dxDrawRectangle(x, y, w, h, tocolor(40, 40, 40, 230))
        local d = math.max(1, clock.duration)
        if clock.skipIdle then
            for _, span in ipairs(idle or {}) do
                dxDrawRectangle(
                    x + w * span.from / d,
                    y,
                    math.max(1, w * (span.to - span.from) / d),
                    h,
                    tocolor(70, 70, 70, 200)
                )
            end
        end
        for _, e in ipairs(events) do
            local r, g, b = ctx.kindColor(e.kind)
            dxDrawRectangle(x + w * e.t / d - 1, y + 2, 2, h - 4, tocolor(r, g, b, 235))
        end
        local px = x + w * clock.t / d
        dxDrawRectangle(px - 2, y - 6, 4, h + 12, tocolor(255, 255, 255, 255))
        dxDrawText(timeline.format(0), x, y + h + 2, x + 80, y + h + 18, tocolor(210, 210, 210, 255), 0.9, "default")
        dxDrawText(
            timeline.format(clock.duration),
            x + w - 80,
            y + h + 2,
            x + w,
            y + h + 18,
            tocolor(210, 210, 210, 255),
            0.9,
            "default",
            "right"
        )
        dxDrawText(
            ctx.wall(clock.t),
            x,
            y - 18,
            x + w,
            y - 2,
            tocolor(255, 255, 255, 255),
            1.0,
            "default-bold",
            "center"
        )
    end

    local function overBar(cx, cy)
        local x, y, w, h = bar()
        return cx >= x and cx <= x + w and cy >= y - 8 and cy <= y + h + 8, x, w
    end

    addEventHandler("onClientClick", root, function(btn, state, cx, cy)
        if not ui or not cursorOn or btn ~= "left" then
            return
        end
        if state == "down" then
            local inside, x, w = overBar(cx, cy)
            if inside then
                scrubbing = true
                act.scrub((cx - x) / w)
            end
        else
            scrubbing = false
        end
    end)

    addEventHandler("onClientCursorMove", root, function(_, _, cx, cy)
        if ui and cursorOn and scrubbing then
            local _, x, w = overBar(cx, cy)
            act.scrub(math.max(0, math.min(1, (cx - x) / w)))
        end
    end)

    return M
end
