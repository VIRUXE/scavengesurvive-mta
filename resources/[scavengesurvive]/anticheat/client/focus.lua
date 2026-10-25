-- MTA only exposes minimize/restore state to the local client. Report transitions so the server
-- can apply ScavengeSurvive's max-tab-out-time policy; the server validates that the sender is self.
local function sendFocus(isFocused)
    triggerServerEvent("anticheatFocusChanged", localPlayer, isFocused)
end

addEventHandler("onClientMinimize", root, function()
    sendFocus(false)
end)

addEventHandler("onClientRestore", root, function()
    sendFocus(true)
end)

addEventHandler("onClientMTAFocusChange", root, function(windowFocused)
    sendFocus(windowFocused == true)
end)
