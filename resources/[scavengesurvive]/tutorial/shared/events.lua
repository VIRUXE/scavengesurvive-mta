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
addEvent("tutorialStepChanged", true) -- the step the player is on: index, hint key, the item the hint names
addEvent("toastShown", true) -- from vehicles and items: a short code for what just happened or was refused
addEvent("lugnutsStarted", true) -- from vehicles: the lug nut view opened on a wheel
addEvent("inventoryOpened", true)
addEvent("uiListActionSelected", false)
addEvent("uiListActionsOpened", false)
addEvent("uiListClosed", false)
