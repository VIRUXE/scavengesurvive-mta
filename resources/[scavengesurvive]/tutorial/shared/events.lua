-- server-local (triggered and handled on one side, or between resources)
addEvent("characterSpawned", false)
addEvent("tutorialCharacterDied", false) -- from character: the tutorial character would have died
addEvent("itemCreated", false)
addEvent("itemMoved", false)
addEvent("itemHolstered", false)
addEvent("characterItemsDropped", false)
addEvent("playerLoggedOut", false)

-- server to client / client-local
addEvent("tutorialOffered", true) -- true while a fresh character may start the tutorial, false when it may not
addEvent("tutorialStarted", true)
addEvent("tutorialEnded", true)
addEvent("inventoryOpened", true)
addEvent("uiListActionSelected", false)
addEvent("uiListActionsOpened", false)
addEvent("uiListClosed", false)
