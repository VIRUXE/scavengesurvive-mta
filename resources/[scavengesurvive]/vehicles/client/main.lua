-- Client-side vehicles: hold-action progress bars, cancel checks, the trailer hitch, walk-in doors and the /lock
-- command.
local vlogic
do
    local f = fileOpen("shared/logic/vehicle.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    vlogic = assert(loadstring(src, "=vehicles/vehicle.lua"))()
end
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

-- Walk-in doors (vehicle types with door = true, the towable Airstream): the one within reach of its hinge, on foot.
local doorTypes = {} -- vehicle type uname -> whether it has a walk-in door (the data resource, asked once)

local function hasWalkInDoor(vehicle)
    local uname = getElementData(vehicle, "vehicles.type")
    if not uname then
        return false
    end
    if doorTypes[uname] == nil then
        local vt = exports.data:vehicleType(uname)
        doorTypes[uname] = vt and vt.door == true or false
    end
    return doorTypes[uname]
end

-- export: the walk-in door in reach and whether it is open (vehicle, open) or false; the HUD's F line. A world item
-- lying nearer than the door wins, as with the world's buttons: the key picks it up instead.
function nearbyTrailerDoor()
    if getPedOccupiedVehicle(localPlayer) then
        return false
    end
    local px, py, pz = getElementPosition(localPlayer)
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if hasWalkInDoor(v) then
            local hx, hy, hz = getVehicleComponentPosition(v, "door_lf_dummy", "world")
            local d = hx and getDistanceBetweenPoints3D(px, py, pz, hx, hy, hz)
            if d and d < vlogic.DOOR_REACH then
                local itemD = exports.items:nearestItemDistance()
                if itemD ~= false and itemD < d then
                    return false
                end
                return v, getVehicleDoorOpenRatio(v, vlogic.WALK_IN_DOOR) > 0.5
            end
        end
    end
    return false
end

-- export: the interact key at a walk-in door opens or shuts it; true when it did (hud keys.lua stops there)
function tryTrailerDoor()
    local v = nearbyTrailerDoor()
    if not v then
        return false
    end
    triggerServerEvent("trailerDoorToggleRequested", localPlayer, v)
    return true
end

addCommandHandler("lock", function()
    triggerServerEvent("lockToggleRequested", localPlayer)
end)
