-- server-local (triggered and handled on one side, or between resources)
addEvent("playerAuthenticated", false)
addEvent("playerLoggedOut", false)
addEvent("playerJoinAnnounced", false) -- player, language code: raised by auth once the language is known

-- client to server (handlers registered with net.handler)
addEvent("loginRequested", true)
addEvent("registrationRequested", true)
addEvent("authPromptDismissed", true)
addEvent("authLanguageChosen", true)
addEvent("authLanguageChanged", true) -- code: picked in the /lang window by a logged-in player
addEvent("authEmailSubmitted", true)
addEvent("authEmailCodeSubmitted", true)

-- server to client
addEvent("authLanguageOffered", true)
addEvent("authPromptShown", true) -- mode, title, body, style ("password" unless given)
addEvent("authWelcomeShown", true)
addEvent("whitelistCountdownChanged", true) -- seconds left, or false to hide

-- client-local (raised by ui)
addEvent("uiDialogResponded", false)
