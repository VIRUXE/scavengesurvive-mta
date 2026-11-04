-- Relays this client's script errors and a performance sample to the server log, so "it lags for me" and "the UI
-- broke" reports have a record. Rate limited here and again by net.handler on the server.
local SAMPLE_MS = 300000
local ERROR_GAP_MS = 1000
local MAX_ERRORS = 50

local frames = 0
local lastError = -math.huge
local sentErrors = 0

addEventHandler("onClientRender", root, function()
    frames = frames + 1
end)

-- one per second and 50 per session, so an error raised by the report itself cannot loop
addEventHandler("onClientDebugMessage", root, function(message, level, file, line)
    if (level ~= 1 and level ~= 2) or sentErrors >= MAX_ERRORS then
        return
    end
    local now = getTickCount()
    if now - lastError < ERROR_GAP_MS then
        return
    end
    lastError = now
    sentErrors = sentErrors + 1
    triggerServerEvent(
        "clientErrorReported",
        localPlayer,
        tostring(message),
        level,
        tostring(file or ""),
        tonumber(line) or 0
    )
end)

setTimer(function()
    local fps = math.floor(frames / (SAMPLE_MS / 1000) + 0.5)
    frames = 0
    local streamed = #getElementsByType("object", root, true)
    triggerServerEvent("clientSampleReported", localPlayer, fps, getPlayerPing(localPlayer), streamed)
end, SAMPLE_MS, 0)
