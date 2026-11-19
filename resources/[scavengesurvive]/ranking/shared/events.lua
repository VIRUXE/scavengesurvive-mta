-- client to server (handler registered with net.handler in server/main.lua)
addEvent("rankingRequested", true)

-- server to client
addEvent("rankingSynced", true)

-- local (server): raised by character when a death committed
addEvent("characterDied", false)
