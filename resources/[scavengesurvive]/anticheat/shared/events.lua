-- client to server (handlers registered with net.handler)
addEvent("anticheatFocusChanged", true)

-- server-local, from items (cancellable: the pickup of a hacker trap is vetoed)
addEvent("itemPickupAttempted", false)
