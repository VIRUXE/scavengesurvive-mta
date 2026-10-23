-- Client-side vehicles: hold-action progress bars, cancel checks, and commands (/tow, /lock).
local activeAction = nil
local lastPos = nil

local function cancelAction()
    if not activeAction then
        return
    end
    activeAction = nil
    lastPos = nil
    exports.ui:progressCancel()
    triggerServerEvent("holdActionCancelRequested", localPlayer)
end

addEventHandler("vehicleHoldStarted", root, function(actionType, durationMs)
    activeAction = actionType
    local x, y, z = getElementPosition(localPlayer)
    lastPos = { x = x, y = y, z = z }
    exports.ui:progressStart(actionType, durationMs)
end)

addEventHandler("vehicleHoldStopped", root, function()
    activeAction = nil
    lastPos = nil
    exports.ui:progressCancel()
end)

-- Cancel if the player moves or dies while performing a hold-action
addEventHandler("onClientRender", root, function()
    if not activeAction or not lastPos then
        return
    end
    if isPedDead(localPlayer) then
        return cancelAction()
    end
    local x, y, z = getElementPosition(localPlayer)
    local dist = getDistanceBetweenPoints3D(x, y, z, lastPos.x, lastPos.y, lastPos.z)
    if dist > 0.8 then
        cancelAction()
    end
end)

addCommandHandler("tow", function()
    triggerServerEvent("towRequested", localPlayer)
end)

addCommandHandler("lock", function()
    triggerServerEvent("lockToggleRequested", localPlayer)
end)
