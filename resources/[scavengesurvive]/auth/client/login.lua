local win, edit, btn, label, mode
local function build(m)
    mode = m
    if win then
        destroyElement(win)
        win = nil
    end
    local sw, sh = guiGetScreenSize()
    win = guiCreateWindow((sw - 320) / 2, (sh - 170) / 2, 320, 170, m == "login" and "Login" or "Create account", false)
    guiWindowSetSizable(win, false)
    label = guiCreateLabel(
        10,
        30,
        300,
        40,
        m == "login" and "Welcome back. Enter your password." or "New here. Choose a password (4-32 chars).",
        false,
        win
    )
    edit = guiCreateEdit(10, 80, 300, 30, "", false, win)
    guiEditSetMasked(edit, true)
    btn = guiCreateButton(10, 120, 300, 35, m == "login" and "Log in" or "Register", false, win)
    guiSetInputMode("no_binds_when_editing")
    showCursor(true)
    addEventHandler("onClientGUIClick", btn, function()
        local pw = guiGetText(edit)
        triggerServerEvent(mode == "login" and "onAuthRequestLogin" or "onAuthRequestRegister", localPlayer, pw)
        guiSetEnabled(btn, false)
        setTimer(function()
            if isElement(btn) then
                guiSetEnabled(btn, true)
            end
        end, 2000, 1)
    end, false)
end

addEventHandler("onClientAuthPrompt", root, function(m)
    build(m)
end)
addEventHandler("onClientAuthResult", root, function(ok, message)
    if ok then
        if win then
            destroyElement(win)
            win = nil
        end
        showCursor(false)
        guiSetInputMode("allow_binds")
    elseif label and isElement(label) then
        guiSetText(label, "Failed: " .. tostring(message))
    end
end)
