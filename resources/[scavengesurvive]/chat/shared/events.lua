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
addEvent("voiceAudienceChanged", true) -- how many hear the talking player, sent to them when it changes
addEvent("helpOpened", true) -- the /help window (client/help.lua)
addEvent("chatTipSent", true) -- index of the rotating tip to show (client/help.lua)
-- client-local
addEvent("uiDialogResponded", false)
