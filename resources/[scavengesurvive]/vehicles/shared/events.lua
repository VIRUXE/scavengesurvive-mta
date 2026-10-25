-- server-local (triggered and handled on one side, or between resources)
addEvent("vehiclesSpawned", false)

-- client to server (handlers registered with net.handler)
addEvent("engineToggleRequested", true)
addEvent("lightsToggleRequested", true)
addEvent("lockToggleRequested", true)
addEvent("vehicleInteractRequested", true)
addEvent("fuelPumpInteractRequested", true)
addEvent("holdActionCancelRequested", true)
addEvent("trunkCloseRequested", true)
addEvent("towRequested", true)

-- server to client / client-local
addEvent("vehicleHoldStarted", true)
addEvent("vehicleHoldStopped", true)
addEvent("toastShown", true)
