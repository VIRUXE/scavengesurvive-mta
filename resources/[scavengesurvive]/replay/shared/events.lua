-- client to server (handlers registered with net.handler)
addEvent("replayStopRequested", true)
addEvent("replaySeekRequested", true)
addEvent("replaySubjectSwitchRequested", true)
addEvent("replayPoseReported", true) -- the recorder's client half: what the server cannot read (anim, aim, move state)

-- server to client
addEvent("replaySessionStarted", true)
addEvent("replayChunkReceived", true)
addEvent("replaySessionEnded", true)

-- server-local, raised by character/auth (declared there too; re-adding is harmless)
addEvent("playerLoggedOut", false)
addEvent("characterDied", false)
