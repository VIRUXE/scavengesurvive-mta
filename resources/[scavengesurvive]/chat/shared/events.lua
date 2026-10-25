-- server-local (between resources)
addEvent("characterSpawned", false)
addEvent("playerLoggedOut", false)
addEvent("globalChatSent", false)
-- client to server (handlers registered with net.handler)
addEvent("radioTuneRequested", true)
addEvent("radioFrequencyEntered", true)
addEvent("chatModeRequested", true)
-- server to client
addEvent("chatRadioChanged", true)
addEvent("chatRadioOpened", true)
addEvent("chatInfoShown", true)
-- client-local
addEvent("uiDialogResponded", false)
