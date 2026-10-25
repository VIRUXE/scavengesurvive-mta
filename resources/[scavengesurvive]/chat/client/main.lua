-- The radio panel (core/ui/radio.pwn) in dx: RADIO title, dial strip, two 0.5 MHz knobs, global/freq toggle,
-- "Frequency: x", power, Close; hover 0xFFFFFF88. Opens with R in a vehicle, /radio or the inventory's Radio row;
-- clicking the frequency opens upstream's input dialog, the mouse wheel over it fine-tunes by 0.01 MHz (port
-- addition). Hit tests run in canvas units.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local canvas = loadFile(":ui/shared/logic/canvas.lua", "=ui/canvas.lua")
local logic = loadFile("shared/logic/chat.lua", "=chat/chat.lua")
local sw, sh = guiGetScreenSize()
local ctx = { canvas = canvas, c = canvas.new(sw, sh) }
local draw = loadFile(":ui/client/draw.lua", "=ui/draw.lua")(ctx)
local c = ctx.c
local P = logic.PANEL

local WHITE = tocolor(255, 255, 255, 255)
local CYAN = tocolor(0, 255, 255, 255) -- textdraw colour 16777215 = 0x00FFFFFF
local RED = tocolor(255, 0, 0, 255) -- -16776961 = 0xFF0000FF
local KNOB = tocolor(0x78, 0, 0, 0xFA)
local HOVER = tocolor(255, 255, 255, 0x88)
local BOX = tocolor(0, 0, 0, 100)

local state = { open = false, freq = logic.FREQ_DEFAULT, mode = logic.MODE.LOCAL, oldMode = logic.MODE.RADIO }
local typing = false -- the frequency dialog is open (and for one short moment after it answers)

local function uiListIsOpen()
    return exports.ui:listIsOpen() == true
end

-- cursor pixels -> canvas units (canvas.x/y map units to pixels with the same scale and offset)
local function cursorUnits()
    if not isCursorShowing() then
        return nil
    end
    local px, py = getCursorPosition()
    if not px then
        return nil
    end
    px, py = px * sw, py * sh
    local x0, y0 = canvas.x(c, 0, "left"), canvas.y(c, 0)
    local unit = canvas.len(c, 1)
    return (px - x0) / unit, (py - y0) / unit
end

local function hovered()
    local ux, uy = cursorUnits()
    if not ux then
        return nil
    end
    return logic.hit(ux, uy)
end

local function open()
    if state.open then
        return
    end
    state.open = true
    showCursor(true)
end

local function close()
    if not state.open then
        return
    end
    if typing then
        exports.ui:dialogClose()
        typing = false
    end
    state.open = false
    showCursor(false)
end

addEventHandler("chatRadioChanged", root, function(freq, mode)
    if mode ~= logic.MODE.LOCAL and state.mode == logic.MODE.LOCAL then
        state.oldMode = mode
    elseif state.mode ~= logic.MODE.LOCAL and mode == logic.MODE.LOCAL then
        state.oldMode = state.mode
    end
    state.freq, state.mode = tonumber(freq) or state.freq, tonumber(mode) or state.mode
end)

-- /help and /chatinfo: upstream's DIALOG_STYLE_MSGBOX with a lone Close button
addEventHandler("chatInfoShown", root, function(title, body)
    exports.ui:dialogOpen("chat:info", "msgbox", title, body, "Close", "")
end)

addEventHandler("chatRadioOpened", root, function()
    open()
end)

-- the inventory's "Radio" row (upstream radio.pwn AddInventoryListItem)
function radioOpen()
    open()
end

-- upstream ShowFrequencyDialog: a number in range retunes, anything else asks again, Cancel leaves it be
local FREQ_BODY = string.format("Enter a frequency between %.1f and %.1f", logic.FREQ_MIN, logic.FREQ_MAX)

local function askFrequency()
    typing = true
    exports.ui:dialogOpen("chat:freq", "input", "Frequency", FREQ_BODY, "Accept", "Cancel")
end

addEventHandler("uiDialogResponded", root, function(id, accepted, text)
    if id ~= "chat:freq" then
        return
    end
    -- the Enter, Escape or click that answered the dialog must not reach the panel underneath this frame
    setTimer(function()
        typing = false
    end, 50, 1)
    if not accepted then
        return
    end
    local f = logic.parseFreq(text)
    if not f then
        return askFrequency()
    end
    triggerServerEvent("radioFrequencyEntered", localPlayer, f)
end)

local function label(td)
    td.font = td.font or 1
    td.ly = td.ly or 1.5
    td.align = "center"
    td.anchor = "left"
    td.shadow = td.shadow or 1
    draw.text(td)
end

addEventHandler("onClientRender", root, function()
    if not state.open then
        return
    end
    local hover = hovered()
    draw.box(P.box.x, P.box.y, P.box.w, P.box.h, BOX, "left")
    draw.box(P.close.x, P.close.y, P.close.w, P.close.h, BOX, "left")
    for _, name in ipairs(logic.HOTSPOTS) do
        local r = P[name]
        if name == "knobL" or name == "knobR" then
            draw.box(r.x, r.y, r.w, r.h, KNOB, "left")
        end
        if hover == name then
            draw.box(r.x, r.y, r.w, r.h, HOVER, "left")
        end
    end
    label({ text = "RADIO", x = P.title.x, y = P.title.y, lx = 0.5, colour = WHITE, outline = 1, shadow = 0 })
    label({
        text = "-l-l-l-l-l-l-l-l-l-l-l-l-l-l-l-l-l-l-l-",
        x = P.strip.x,
        y = P.strip.y,
        lx = 0.3,
        ly = 1.0,
        colour = WHITE,
        shadow = 0,
    })
    label({ text = "<", x = P.knobL.x + 15, y = P.knobL.y + 6, lx = 0.5, colour = WHITE, outline = 1, shadow = 0 })
    label({ text = ">", x = P.knobR.x + 15, y = P.knobR.y + 6, lx = 0.5, colour = WHITE, outline = 1, shadow = 0 })
    label({ text = logic.modeLabel(state.mode, state.oldMode), x = P.mode.cx, y = P.mode.y, lx = 0.3, colour = CYAN })
    label({ text = string.format("Frequency: %.2f", state.freq), x = P.freq.cx, y = P.freq.y, lx = 0.3, colour = CYAN })
    label({ text = logic.powerLabel(state.mode), x = P.power.cx, y = P.power.y, lx = 0.4, colour = RED })
    label({ text = "Close", x = P.close.cx, y = P.close.y, lx = 0.3, colour = WHITE })
end)

addEventHandler("onClientClick", root, function(button, pressState)
    if not state.open or typing or button ~= "left" or pressState ~= "down" then
        return
    end
    local hit = hovered()
    if hit == "knobL" then
        triggerServerEvent("radioTuneRequested", localPlayer, -logic.KNOB_STEP)
    elseif hit == "knobR" then
        triggerServerEvent("radioTuneRequested", localPlayer, logic.KNOB_STEP)
    elseif hit == "mode" then
        triggerServerEvent("chatModeRequested", localPlayer, logic.toggleMode(state.mode))
    elseif hit == "power" then
        local newMode = logic.togglePower(state.mode, state.oldMode)
        triggerServerEvent("chatModeRequested", localPlayer, newMode)
    elseif hit == "freq" then
        askFrequency()
    elseif hit == "close" then
        close()
    end
end)

addEventHandler("onClientKey", root, function(key, press)
    if not state.open or typing or not press then
        return
    end
    if key == "escape" then
        close()
        cancelEvent()
    elseif key == "mouse_wheel_up" or key == "mouse_wheel_down" then
        if hovered() == "freq" then
            local delta = key == "mouse_wheel_up" and logic.FINE_STEP or -logic.FINE_STEP
            triggerServerEvent("radioTuneRequested", localPlayer, delta)
            cancelEvent()
        end
    end
end)

-- R opens the radio in a vehicle (hud shows "R Open radio" there); on foot R stays the reload key.
local function radioKey()
    if isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() or uiListIsOpen() then
        return
    end
    if state.open then
        return close()
    end
    if getPedOccupiedVehicle(localPlayer) then
        open()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("r", "down", radioKey)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("r", "down", radioKey)
    close()
end)
