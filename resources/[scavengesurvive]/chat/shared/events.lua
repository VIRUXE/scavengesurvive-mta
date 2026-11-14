-- server-local (between resources)
addEvent("characterSpawned", false)
addEvent("playerLoggedOut", false)
addEvent("playerJoinAnnounced", false) -- player, language code: raised by auth once the language is known
addEvent("globalChatSent", false)
-- client to server (handlers registered with net.handler)
addEvent("radioTuneRequested", true)
addEvent("radioFrequencyEntered", true)
addEvent("chatModeRequested", true)
-- server to client
addEvent("chatRadioChanged", true)
addEvent("chatRadioOpened", true)
addEvent("chatVoiceBlocked", true)
-- client-local
addEvent("uiDialogResponded", false)
