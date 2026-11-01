-- client to server (handlers registered with net.handler)
addEvent("devFlyActiveChanged", true)
addEvent("devChatLineReceived", true)
addEvent("devItemSpawnRequested", true)

-- server to client / client-local
addEvent("devKeyPressed", true)
addEvent("devClientLuaRequested", true)
addEvent("devFlyStateChanged", true)
addEvent("devStudioStateChanged", true)
addEvent("devStudioCamChanged", true)
addEvent("devStudioPoseChanged", true)
addEvent("devItemPickerOpened", true)
addEvent("devItemSpawnAnswered", true)
