-- Client-side crafting hold-action animator and key bindings.
local activeAction = nil
local lastPos = nil

local function cancelAction()
    if activeAction then
        activeAction = nil
        lastPos = nil
        exports.ui:progressCancel()
    end
end

addEventHandler("onClientCraftingHoldAction", root, function(actionType, durationMs)
    activeAction = actionType
    local x, y, z = getElementPosition(localPlayer)
    lastPos = { x = x, y = y, z = z }
    exports.ui:progressStart(actionType, durationMs)
end)

addEventHandler("onClientCraftingStopHoldAction", root, function()
    cancelAction()
end)

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
