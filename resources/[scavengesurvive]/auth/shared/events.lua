-- server-local (triggered and handled on one side, or between resources)
addEvent("playerAuthenticated", false)
addEvent("playerLoggedOut", false)

-- client to server (handlers registered with net.handler)
addEvent("loginRequested", true)
addEvent("registrationRequested", true)
addEvent("authPromptDismissed", true)

-- server to client
addEvent("authPromptShown", true)
addEvent("authWelcomeShown", true)
addEvent("whitelistCountdownChanged", true) -- seconds left, or false to hide

-- client-local (raised by ui)
addEvent("uiDialogResponded", false)
