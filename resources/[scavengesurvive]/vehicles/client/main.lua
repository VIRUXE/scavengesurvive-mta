-- Client-side vehicles: hold-action progress bars, cancel checks, the trailer hitch, and the /lock command.
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

-- The hitch key's outcome, carried out by the driver's own client (trailer false: drop the one towed), so the driver's
-- sync reports the change instead of overwriting one made on the server.
addEventHandler("trailerHitchOrdered", localPlayer, function(truck, trailer)
    if not isElement(truck) or getVehicleController(truck) ~= localPlayer then
        return
    end
    if trailer == false then
        detachTrailerFromVehicle(truck)
    elseif isElement(trailer) then
        attachTrailerToVehicle(truck, trailer)
    end
end)

addCommandHandler("lock", function()
    triggerServerEvent("lockToggleRequested", localPlayer)
end)
