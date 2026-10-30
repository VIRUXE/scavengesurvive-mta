-- client to server (handlers registered with net.handler)
addEvent("combineRequested", true)
addEvent("craftHoldCancelled", true)

-- server to client
addEvent("craftHoldStarted", true)
addEvent("craftHoldStopped", true)
addEvent("combineFinished", true)
addEvent("toastShown", true)

-- client-local
addEvent("uiListActionSelected", false)

-- server-local
addEvent("characterDied", false)
addEvent("itemCreated", false)
addEvent("itemDestroyed", false)
