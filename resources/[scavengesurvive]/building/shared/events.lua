-- client to server (handlers registered with net.handler)
addEvent("buildingInteractRequested", true)
addEvent("keypadSubmitted", true)
addEvent("keypadInstallRequested", true)
addEvent("lockBreakRequested", true)
addEvent("deviceHackRequested", true)

-- server to client / client-local
addEvent("keypadOpened", true)
addEvent("keypadClosed", true)
addEvent("doorStateChanged", true)
addEvent("toastShown", true)
addEvent("vehicleHoldStarted", true)

-- server-local
addEvent("characterDied", false)
