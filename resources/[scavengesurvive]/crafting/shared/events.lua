-- client to server (handlers registered with net.handler)
addEvent("combineRequested", true)
addEvent("groundCraftRequested", true)
addEvent("deconstructRequested", true)
addEvent("workbenchCraftRequested", true)

-- server to client / client-local
addEvent("craftHoldStarted", true)
addEvent("craftHoldStopped", true)
addEvent("toastShown", true)

-- server-local
addEvent("characterDied", false)
addEvent("workbenchRecipeMissed", false)
