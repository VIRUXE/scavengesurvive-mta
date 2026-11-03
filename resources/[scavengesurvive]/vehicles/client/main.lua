-- Client-side vehicles: hold-action progress bars, cancel checks, the trailer hitch, walk-in doors and the /lock
-- command.
local vlogic
do
    local f = fileOpen("shared/logic/vehicle.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    vlogic = assert(loadstring(src, "=vehicles/vehicle.lua"))()
end
local bodyparts
do
    local f = fileOpen("shared/logic/bodyparts.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    bodyparts = assert(loadstring(src, "=vehicles/bodyparts.lua"))()
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
                local locked = (tonumber(getElementData(v, "vehicles.locked")) or 0) > 0
                if locked then
                    local m = getElementMatrix(v)
                    local dx, dy, dz = px - m[4][1], py - m[4][2], pz - m[4][3]
                    local lx = dx * m[1][1] + dy * m[1][2] + dz * m[1][3]
                    local ly = dx * m[2][1] + dy * m[2][2] + dz * m[2][3]
                    local lz = dx * m[3][1] + dy * m[3][2] + dz * m[3][3]
                    locked = not vlogic.inCargoBox(lx, ly, lz)
                end
                return v, getVehicleDoorOpenRatio(v, vlogic.WALK_IN_DOOR) > 0.5, locked
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

-- export: the interact key at a trailer's A-frame mounts (vehicles/server/gasbottles.lua): with a Gas Bottle in hand
-- (heldUname "GasBottle") it asks to mount it on a free mount, with empty hands (heldUname false) to take the bottle
-- off a filled one; true when it asked (hud keys.lua stops there). A world item lying nearer takes the key instead.
function tryGasMount(heldUname)
    if getPedOccupiedVehicle(localPlayer) or (heldUname and heldUname ~= "GasBottle") then
        return false
    end
    local px, py, pz = getElementPosition(localPlayer)
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        local filled = getElementData(v, "vehicles.gasBottles")
        if type(filled) == "string" then
            local m = getElementMatrix(v)
            local dx, dy, dz = px - m[4][1], py - m[4][2], pz - m[4][3]
            local lx = dx * m[1][1] + dy * m[1][2] + dz * m[1][3]
            local ly = dx * m[2][1] + dy * m[2][2] + dz * m[2][3]
            local slot = vlogic.nearGasMount(lx, ly)
            local wanted = heldUname == false
            if slot and (filled:find(slot, 1, true) ~= nil) == wanted then
                local mount = vlogic.GAS_MOUNTS[slot]
                local d = math.sqrt((lx - mount.x) ^ 2 + (ly - mount.y) ^ 2)
                local itemD = exports.items:nearestItemDistance()
                if itemD == false or itemD >= d then
                    triggerServerEvent("vehicleInteractRequested", localPlayer, v)
                    return true
                end
            end
        end
    end
    return false
end

-- export: the vehicle has an engine under a bonnet (a battery to take or fit); the server publishes it
function hasBatteryBay(vehicle)
    return isElement(vehicle) and getElementData(vehicle, "vehicles.bay") == true
end

-- export: the part item `uname` is a removable vehicle body part (fits a slot of some model)
function isBodyPart(uname)
    return bodyparts.partOf(uname) ~= nil
end

-- export: the body-part slot of `vehicle` nearest the local player within reach, its condition
-- ("good" | "bad" | "missing") and whether it is only fitted loose; nil when the model has no slots or none is in reach
function bodyPartSlot(vehicle)
    if not isElement(vehicle) or not bodyparts.MODELS[getElementModel(vehicle)] then
        return nil
    end
    local px, py, pz = getElementPosition(localPlayer)
    local m = getElementMatrix(vehicle)
    local dx, dy, dz = px - m[4][1], py - m[4][2], pz - m[4][3]
    local lx = dx * m[1][1] + dy * m[1][2] + dz * m[1][3]
    local ly = dx * m[2][1] + dy * m[2][2] + dz * m[2][3]
    local slot = bodyparts.nearestSlot(getElementModel(vehicle), lx, ly)
    if not slot then
        return nil
    end
    local value = slot.door and getVehicleDoorState(vehicle, slot.door) or getVehiclePanelState(vehicle, slot.panel)
    local loose = getElementData(vehicle, "vehicles.loose")
    local isLoose = type(loose) == "string" and ("," .. loose .. ","):find("," .. slot.name .. ",", 1, true) ~= nil
    return slot.name, bodyparts.condition(slot, value), isLoose
end

-- upstream's KEY_SUBMISSION ("2" / Num+) toggles the lock from inside a vehicle; /lock does the same
local function requestLockToggle()
    if getPedOccupiedVehicle(localPlayer) then
        triggerServerEvent("lockToggleRequested", localPlayer)
    end
end

addCommandHandler("lock", requestLockToggle)
bindKey("sub_mission", "down", requestLockToggle)
