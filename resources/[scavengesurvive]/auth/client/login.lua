-- The login, register and welcome dialogs, drawn by ui's SA-MP style password and message boxes. The server
-- sends the title and body already in the player's language (authPromptShown); every answer goes back as
-- loginRequested / registrationRequested with the typed password, or authPromptDismissed for Leave.
local prompt
do
    local f = fileOpen("shared/logic/prompt.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    prompt = assert(loadstring(src, "=auth/prompt.lua"))()
end

local welcomeLeft = 0

addEventHandler("authPromptShown", root, function(mode, title, body)
    local id = "auth:" .. tostring(mode)
    exports.ui:dialogOpen(id, "password", title, body, prompt.BUTTONS[1], prompt.BUTTONS[2])
end)

local function showWelcome()
    local label = prompt.welcomeButton(welcomeLeft)
    exports.ui:dialogOpen("auth:welcome", "msgbox", prompt.WELCOME_TITLE, prompt.WELCOME_BODY, label, "")
end

addEventHandler("authWelcomeShown", root, function()
    welcomeLeft = prompt.WELCOME_COUNTDOWN
    showWelcome()
    setTimer(function()
        welcomeLeft = welcomeLeft - 1
        exports.ui:dialogSetButtons("auth:welcome", prompt.welcomeButton(welcomeLeft), "")
    end, 1000, prompt.WELCOME_COUNTDOWN)
end)

addEventHandler("uiDialogResponded", root, function(id, accepted, text)
    local mode = tostring(id):match("^auth:(%a+)$")
    if mode == "login" or mode == "register" then
        if accepted then
            local event = mode == "login" and "loginRequested" or "registrationRequested"
            triggerServerEvent(event, localPlayer, text)
        else
            triggerServerEvent("authPromptDismissed", localPlayer)
        end
    elseif mode == "welcome" and welcomeLeft > 0 then
        showWelcome() -- upstream: the box cannot be left before the countdown ends
    end
end)
