-- client to server (handlers registered with net.handler)
addEvent("attachEditSaveRequested", true)
addEvent("attachEditConfigReported", true)

-- server to client
addEvent("attachEditToggled", true)
addEvent("attachEditPreviewChanged", true)
addEvent("attachEditConfigRequested", true)
