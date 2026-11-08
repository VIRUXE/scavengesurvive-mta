-- server-local (triggered and handled on one side, or between resources)
addEvent("characterSpawned", false)
addEvent("tutorialCharacterDied", false) -- from character: the tutorial character would have died
addEvent("itemCreated", false)
addEvent("itemMoved", false)
addEvent("itemHolstered", false)
addEvent("characterItemsDropped", false)
addEvent("playerLoggedOut", false)
addEvent("vehicleTransientSpawned", false)

-- client to server (handlers registered with net.handler)
addEvent("tutorialStateRequested", true) -- the client script started: is this player in the tutorial?

-- server to client / client-local
addEvent("tutorialCompleted", true)
addEvent("tutorialStarted", true)
addEvent("tutorialEnded", true)
addEvent("inventoryOpened", true)
addEvent("uiListActionSelected", false)
addEvent("uiListActionsOpened", false)
addEvent("uiListClosed", false)
