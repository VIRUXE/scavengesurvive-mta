-- server-local (triggered and handled on one side, or between resources)
addEvent("playerAuthenticated", false)
addEvent("playerLoggedOut", false)
addEvent("characterDied", false)

-- client to server (handlers registered with net.handler)
addEvent("staffListActionSelected", true)
addEvent("staffListClosed", true)
addEvent("spectateRequested", true)

-- server to client / client-local
addEvent("staffListOpened", true)
addEvent("staffListDismissed", true)
addEvent("spectateChanged", true)
addEvent("nametagsChanged", true)
addEvent("uiListActionSelected", false)
addEvent("uiListClosed", false)
