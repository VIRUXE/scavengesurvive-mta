-- The SA-MP message, input and password dialogs in dx (DIALOG_STYLE_MSGBOX / _INPUT / _PASSWORD): the list
-- dialog's chrome with a colour-coded body, an optional one-line field (masked for passwords, Ctrl+V pastes) and the
-- Accept/Leave pair, or a lone centred button when the right label is empty. Enter and Escape are the two
-- buttons. Emits uiDialogResponded(id, accepted, text) after closing itself, so the handler may open the next
-- one. One dialog at a time; the list widget is separate.
return function(ctx)
    local dialog, canvas, c, draw = ctx.dialog, ctx.canvas, ctx.c, ctx.draw
    local COL = {
        box = tocolor(0, 0, 0, 215),
        field = tocolor(0, 0, 0, 240),
        text = tocolor(255, 255, 255, 255),
        border = tocolor(190, 190, 190, 255),
    }
    local SAMPLE = "abcdefghijklmnopqrstuvwxyz ABCDEFGHIJKLMNOPQRSTUVWXYZ 0123456789 .,:;!?()"
    local state = nil
    local M = {}

    local function charUnits()
        local scale = canvas.textScale(c, 1.2, 1)
        return dxGetTextWidth(SAMPLE, scale, canvas.font(1)) / #SAMPLE / c.s
    end

    local function measure(st)
        st.lines, st.longest = dialog.bodyMetrics(st.body)
        local titleLen = select(2, dialog.bodyMetrics(st.title))
        st.width = dialog.boxWidth(math.max(st.longest, titleLen), charUnits())
    end

    local function layout(st)
        return dialog.boxLayout(c.sw, c.sh, c.s, st.style, st.lines, st.width, st.right ~= "")
    end

    function M.open(id, style, title, body, left, right)
        if style ~= "msgbox" and style ~= "input" and style ~= "password" then
            return false
        end
        local previous = state
        state = { id = id, style = style, title = tostring(title or ""), body = tostring(body or ""), text = "" }
        state.left = tostring(left or "Accept")
        state.right = tostring(right or "")
        measure(state)
        if previous then
            state.inputMode = previous.inputMode
        else
            state.inputMode = guiGetInputMode()
            showCursor(true)
            guiSetInputMode("no_binds")
        end
        return true
    end

    function M.setBody(id, body)
        if not state or state.id ~= id then
            return false
        end
        state.body = tostring(body or "")
        measure(state)
        return true
    end

    function M.setButtons(id, left, right)
        if not state or state.id ~= id then
            return false
        end
        state.left = tostring(left or "Accept")
        state.right = tostring(right or "")
        return true
    end

    function M.close()
        if not state then
            return false
        end
        local mode = state.inputMode
        state = nil
        showCursor(false)
        guiSetInputMode(mode or "allow_binds")
        return true
    end

    function M.isOpen()
        return state ~= nil
    end

    local function respond(accepted)
        local st = state
        M.close()
        triggerEvent("uiDialogResponded", root, st.id, accepted, st.text)
    end

    function M.draw()
        local st = state
        if not st then
            return
        end
        local L = layout(st)
        draw.pxRect(L.box, COL.box)
        local titleScale = canvas.textScale(c, 1.4, 1)
        local font = canvas.font(1)
        local right = L.box.x + L.box.w
        dxDrawText(st.title, L.title.x, L.title.y, right, L.body.y, COL.text, titleScale, font)
        local bodyScale = canvas.textScale(c, 1.2, 1)
        local bx, by = L.body.x + L.textPad, L.body.y + L.textPad
        local bw, bh = L.body.x + L.body.w, L.body.y + L.body.h
        dxDrawText(st.body, bx, by, bw, bh, COL.text, bodyScale, font, "left", "top", false, false, false, true)
        if L.field then
            draw.pxRect(L.field, COL.field)
            draw.pxFrame(L.field, COL.border)
            local shown = st.style == "password" and dialog.masked(st.text) or st.text
            if getTickCount() % 1000 < 500 then
                shown = shown .. "|"
            end
            local fx, fy = L.field.x + L.textPad, L.field.y
            local fw, fh = L.field.x + L.field.w, L.field.y + L.field.h
            dxDrawText(shown, fx, fy, fw, fh, COL.text, bodyScale, font, "left", "center", true)
        end
        draw.pxButton(L.left, st.left)
        if L.right then
            draw.pxButton(L.right, st.right)
        end
    end

    addEventHandler("onClientCharacter", root, function(ch)
        local st = state
        if not st or not (st.style == "input" or st.style == "password") then
            return
        end
        st.text = dialog.typed(st.text, ch, dialog.MAX_INPUT)
    end)

    addEventHandler("onClientPaste", root, function(clip)
        local st = state
        if not st or not (st.style == "input" or st.style == "password") then
            return
        end
        st.text = dialog.pasted(st.text, clip, dialog.MAX_INPUT)
        cancelEvent()
    end)

    addEventHandler("onClientKey", root, function(key, press)
        local st = state
        if not st or not press then
            return
        end
        if key == "backspace" then
            st.text = dialog.backspace(st.text)
        elseif key == "enter" or key == "num_enter" then
            respond(true)
        elseif key == "escape" then
            respond(false)
        else
            return
        end
        cancelEvent()
    end)

    addEventHandler("onClientClick", root, function(btn, pressState, ax, ay)
        local st = state
        if not st or btn ~= "left" or pressState ~= "down" then
            return
        end
        local kind = dialog.boxHit(layout(st), ax, ay)
        if kind == "left" then
            respond(true)
        elseif kind == "right" then
            respond(false)
        end
    end)

    return M
end
