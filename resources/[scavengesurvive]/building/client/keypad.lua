-- 12-key dx Keypad UI (core/ui/keypad.pwn): 3x4 button matrix + yellow bankgothic LCD display.
-- read and closed again: a handle left open keeps the client's cached copy locked, so the next download of a
-- changed defences.lua fails ("Unable to delete old file") and the resource never starts on that client
local defences
do
    local f = fileOpen("shared/logic/defences.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    defences = assert(loadstring(src, "=building/shared/logic/defences.lua"))()
end

local isOpen = false
local currentDefenceId = nil
local isSetupMode = false
local enteredCode = ""
-- a Hack Device at work (world's Area 69, upstream HackKeypadUpdate): the display runs random codes, then shows the
-- one the hack puts in; typing waits until it is done
local hackValue, hackTimer = nil, nil

local function stopHack()
    if isTimer(hackTimer) then
        killTimer(hackTimer)
    end
    hackValue, hackTimer = nil, nil
end

local function playClickSound()
    playSoundFrontEnd(1)
end

local function playSuccessSound()
    playSoundFrontEnd(12)
end

local function playErrorSound()
    playSoundFrontEnd(4)
end

local function close()
    if not isOpen then
        return
    end
    isOpen = false
    currentDefenceId = nil
    isSetupMode = false
    enteredCode = ""
    stopHack()
    showCursor(false)
end

local function submit()
    if not isOpen or not currentDefenceId then
        return
    end
    if string.len(enteredCode) == 0 then
        playErrorSound()
        return
    end
    if isSetupMode then
        triggerServerEvent("keypadInstallRequested", localPlayer, currentDefenceId, enteredCode)
        playSuccessSound()
        close()
    else
        triggerServerEvent("keypadSubmitted", localPlayer, currentDefenceId, enteredCode)
    end
end

local function inputChar(ch)
    if not isOpen or hackTimer then
        return
    end
    if string.len(enteredCode) < 4 then
        enteredCode = enteredCode .. tostring(ch)
        playClickSound()
    else
        playErrorSound()
    end
end

local function backspace()
    if not isOpen then
        return
    end
    if string.len(enteredCode) > 0 then
        enteredCode = string.sub(enteredCode, 1, string.len(enteredCode) - 1)
        playClickSound()
    end
end

local function getLayout()
    local sw, sh = guiGetScreenSize()
    local s = sh / 600
    local w, h = 170 * s, 230 * s
    local x, y = (sw - w) / 2, (sh - h) / 2
    return s, x, y, w, h
end

local function draw()
    if not isOpen then
        return
    end
    local s, x, y, w, h = getLayout()

    -- Outer bezel
    dxDrawRectangle(x, y, w, h, tocolor(25, 25, 28, 240))
    dxDrawLine(x, y, x + w, y, tocolor(120, 120, 130, 255))
    dxDrawLine(x, y + h, x + w, y + h, tocolor(60, 60, 65, 255))
    dxDrawLine(x, y, x, y + h, tocolor(120, 120, 130, 255))
    dxDrawLine(x + w, y, x + w, y + h, tocolor(60, 60, 65, 255))

    -- Header bar
    dxDrawRectangle(x + 2 * s, y + 2 * s, w - 4 * s, 18 * s, tocolor(40, 42, 48, 255))
    local title = isSetupMode and "SET PASSCODE" or "SECURITY KEYPAD"
    dxDrawText(
        title,
        x,
        y + 3 * s,
        x + w,
        y + 20 * s,
        tocolor(200, 200, 210, 255),
        0.9 * s,
        "default-bold",
        "center",
        "center"
    )

    -- LCD screen (yellow/amber bankgothic)
    local lcdX, lcdY, lcdW, lcdH = x + 10 * s, y + 24 * s, w - 20 * s, 36 * s
    dxDrawRectangle(lcdX, lcdY, lcdW, lcdH, tocolor(15, 20, 10, 255))
    dxDrawLine(lcdX, lcdY, lcdX + lcdW, lcdY, tocolor(50, 70, 30, 255))
    dxDrawLine(lcdX, lcdY + lcdH, lcdX + lcdW, lcdY + lcdH, tocolor(50, 70, 30, 255))
    dxDrawLine(lcdX, lcdY, lcdX, lcdY + lcdH, tocolor(50, 70, 30, 255))
    dxDrawLine(lcdX + lcdW, lcdY, lcdX + lcdW, lcdY + lcdH, tocolor(50, 70, 30, 255))

    local displayStr = hackValue and hackValue:gsub("(%d)", "%1 "):sub(1, -2)
        or defences.formatKeypadDisplay(enteredCode)
    dxDrawText(
        displayStr,
        lcdX,
        lcdY,
        lcdX + lcdW,
        lcdY + lcdH,
        tocolor(255, 215, 0, 255),
        1.2 * s,
        "bankgothic",
        "center",
        "center"
    )

    -- 12 Buttons (3 cols x 4 rows)
    local startY = y + 68 * s
    local btnW = (w - 30 * s) / 3
    local btnH = 34 * s
    local gap = 5 * s

    local sw, sh = guiGetScreenSize()
    local cx, cy = getCursorPosition()
    if cx then
        cx, cy = cx * sw, cy * sh
    else
        cx, cy = -1, -1
    end

    local labels = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "C", "0", ">" },
    }

    for row = 1, 4 do
        for col = 1, 3 do
            local bx = x + 10 * s + (col - 1) * (btnW + gap)
            local by = startY + (row - 1) * (btnH + gap)
            local lbl = labels[row][col]
            local hover = cx >= bx and cx <= bx + btnW and cy >= by and cy <= by + btnH

            local bgCol = hover and tocolor(70, 75, 85, 255) or tocolor(45, 48, 55, 255)
            if lbl == "C" then
                bgCol = hover and tocolor(120, 40, 40, 255) or tocolor(80, 30, 30, 255)
            elseif lbl == ">" then
                bgCol = hover and tocolor(40, 120, 50, 255) or tocolor(30, 80, 40, 255)
            end

            dxDrawRectangle(bx, by, btnW, btnH, bgCol)
            dxDrawLine(bx, by, bx + btnW, by, tocolor(100, 105, 115, 255))
            dxDrawLine(bx, by + btnH, bx + btnW, by + btnH, tocolor(20, 20, 25, 255))
            dxDrawLine(bx, by, bx, by + btnH, tocolor(100, 105, 115, 255))
            dxDrawLine(bx + btnW, by, bx + btnW, by + btnH, tocolor(20, 20, 25, 255))

            dxDrawText(
                lbl,
                bx,
                by,
                bx + btnW,
                by + btnH,
                tocolor(240, 240, 245, 255),
                1.1 * s,
                "default-bold",
                "center",
                "center"
            )
        end
    end
end

addEventHandler("onClientRender", root, draw)

addEventHandler("onClientClick", root, function(button, state, absX, absY)
    if not isOpen or button ~= "left" or state ~= "down" then
        return
    end
    local s, x, y, w, _ = getLayout()
    local startY = y + 68 * s
    local btnW = (w - 30 * s) / 3
    local btnH = 34 * s
    local gap = 5 * s

    local labels = {
        { "1", "2", "3" },
        { "4", "5", "6" },
        { "7", "8", "9" },
        { "C", "0", ">" },
    }

    for row = 1, 4 do
        for col = 1, 3 do
            local bx = x + 10 * s + (col - 1) * (btnW + gap)
            local by = startY + (row - 1) * (btnH + gap)
            if absX >= bx and absX <= bx + btnW and absY >= by and absY <= by + btnH then
                local lbl = labels[row][col]
                if lbl == "C" then
                    backspace()
                elseif lbl == ">" then
                    submit()
                else
                    inputChar(lbl)
                end
                return
            end
        end
    end
end)

addEventHandler("onClientCharacter", root, function(ch)
    if not isOpen then
        return
    end
    if ch >= "0" and ch <= "9" then
        inputChar(ch)
    end
end)

addEventHandler("onClientKey", root, function(button, press)
    if not isOpen or not press then
        return
    end
    if button == "escape" then
        cancelEvent()
        close()
    elseif button == "backspace" then
        backspace()
    elseif button == "enter" or button == "num_enter" then
        submit()
    elseif string.match(button, "^num_(%d)$") then
        local d = string.match(button, "^num_(%d)$")
        inputChar(d)
    end
end)

addEventHandler("keypadOpened", root, function(defenceId, isSetup)
    currentDefenceId = defenceId
    isSetupMode = (isSetup == true)
    enteredCode = ""
    isOpen = true
    showCursor(true)
end)

addEventHandler("keypadClosed", root, function()
    close()
end)

addEventHandler("keypadHackStarted", root, function(ms, tickMs)
    stopHack()
    hackValue = tostring(math.random(1000, 9998))
    hackTimer = setTimer(function()
        hackValue = tostring(math.random(1000, 9998))
    end, tickMs, math.max(1, math.floor(ms / tickMs)))
end)

addEventHandler("keypadHackEnded", root, function(value)
    if isTimer(hackTimer) then
        killTimer(hackTimer)
    end
    hackTimer, hackValue = nil, tostring(value)
end)

return {
    open = function(defenceId, isSetup)
        currentDefenceId = defenceId
        isSetupMode = isSetup or false
        enteredCode = ""
        isOpen = true
        showCursor(true)
    end,
    close = close,
    isOpen = function()
        return isOpen
    end,
}
