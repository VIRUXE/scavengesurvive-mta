-- server-local (triggered and handled on one side, or between resources)
addEvent("playerZoneEntered", false)
addEvent("playerZoneLeft", false)

-- client to server (handlers registered with net.handler)
-- mapRemovalsRequested

-- server to client (registered on the client in client/main.lua)
-- mapRemovalsSent

-- client-local
addEvent("mapsBuilt", false)
addEvent("customModelsChanged", false)
