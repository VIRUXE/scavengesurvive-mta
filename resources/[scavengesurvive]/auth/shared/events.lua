-- server-local (triggered and handled on one side, or between resources)
addEvent("playerAuthenticated", false)
addEvent("playerLoggedOut", false)

-- client to server (handlers registered with net.handler)
addEvent("loginRequested", true)
addEvent("registrationRequested", true)

-- server to client / client-local
addEvent("authPromptShown", true)
addEvent("authResolved", true)
