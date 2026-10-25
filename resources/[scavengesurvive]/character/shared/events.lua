-- server-local (triggered and handled on one side, or between resources)
addEvent("playerAuthenticated", false)
addEvent("playerLoggedOut", false)
addEvent("characterSpawned", false)
addEvent("characterDied", false)
addEvent("characterStatsChanged", false)
addEvent("characterItemsDropped", false)

-- client to server (handlers registered with net.handler)
addEvent("respawnRequested", true)
addEvent("groundSurfaceReported", true)

-- server to client / client-local
addEvent("characterStatsSynced", true)
addEvent("deathScreenShown", true)
addEvent("knockedOut", true)
addEvent("combatWindowChanged", true)
addEvent("groundSurfaceRequested", true)
