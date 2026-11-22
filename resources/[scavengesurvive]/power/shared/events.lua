-- client to server (handlers registered with net.handler)
addEvent("mainsLeverPulled", true)
addEvent("mainsStateRequested", true)

-- server to client
addEvent("mainsStateChanged", true)

-- server-local: a lever was pulled (site id, on), or every site wants its feed worked out again (nil, nil); items
-- (server/generators.lua) handles it
addEvent("mainsLeverChanged", false)
