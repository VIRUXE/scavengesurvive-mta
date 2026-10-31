-- The towable Airstream (towable.lua, tools/trailer_shells/towable.py): the medium Airstream's shell as a trailer
-- vehicle in place of the farm trailer (model 610). Its step shows only while it stands unhitched, the rear wheel
-- pair (0.10 m behind the front pair, so the wheelbase is not zero) never shows, and as a vehicle's door has no
-- collision each one in view carries its door leaf as an unseen object in the doorway, solid while the door is shut.
local towable
do
    local f = fileOpen("towable.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    towable = assert(loadstring(src, "=vehicles/towable.lua"))()
end

local DOOR = 2 -- the vehicle's front-left door
local BLOCKER_MS = 200
local loaded = false
local doorModel = nil -- requested object model: the door leaf and its collision
local blockers = {} -- towable vehicle -> its door blocker object
local keep = {} -- loaded TXD/DFF/COL elements

local function block(vehicle)
    if not doorModel or blockers[vehicle] then
        return
    end
    local d = towable.door
    local x, y, z = getElementPosition(vehicle)
    local obj = createObject(doorModel, x, y, z)
    if not obj then
        return
    end
    setElementAlpha(obj, 0)
    setElementDimension(obj, getElementDimension(vehicle))
    setElementInterior(obj, getElementInterior(vehicle))
    setElementCollidableWith(obj, vehicle, false)
    attachElements(obj, vehicle, d.x, d.y, d.z, 0, 0, d.rz)
    blockers[vehicle] = obj
end

local function unblock(vehicle)
    if isElement(blockers[vehicle]) then
        destroyElement(blockers[vehicle])
    end
    blockers[vehicle] = nil
end

local function dress(vehicle)
    if loaded and isElement(vehicle) and getElementModel(vehicle) == towable.model then
        setVehicleComponentVisible(vehicle, "step", not getVehicleTowingVehicle(vehicle))
        setVehicleComponentVisible(vehicle, "wheel_rb_dummy", false)
        setVehicleComponentVisible(vehicle, "wheel_lb_dummy", false)
        block(vehicle)
    end
end

-- the door leaf as a static object model: its collision box, its DFF to stand in for the shape (drawn unseen)
local function requestDoor(txd)
    local id = engineRequestModel("object")
    if not id then
        return nil
    end
    local path = "files/" .. towable.door.dff
    local c = engineLoadCOL(path .. ".col")
    local d = c and engineReplaceCOL(c, id) and engineImportTXD(txd, id) and engineLoadDFF(path .. ".dff")
    if not d or not engineReplaceModel(d, id) then
        engineFreeModel(id)
        return nil
    end
    keep[#keep + 1], keep[#keep + 2] = c, d
    return id
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local txd = engineLoadTXD("files/" .. towable.dff .. ".txd", true)
    local d = txd and engineImportTXD(txd, towable.model) and engineLoadDFF("files/" .. towable.dff .. ".dff")
    if not d or not engineReplaceModel(d, towable.model) then
        return outputDebugString("vehicles: failed to load the towable Airstream (model " .. towable.model .. ")", 1)
    end
    keep[#keep + 1], keep[#keep + 2] = txd, d
    loaded = true
    setVehicleModelWheelSize(towable.model, "all_wheels", towable.wheelSize)
    doorModel = requestDoor(txd)
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        dress(v)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for vehicle in pairs(blockers) do
        unblock(vehicle)
    end
    if doorModel then
        engineFreeModel(doorModel)
    end
    if loaded then
        engineRestoreModel(towable.model)
    end
end)

addEventHandler("onClientTrailerAttach", root, function()
    dress(source)
end)

addEventHandler("onClientTrailerDetach", root, function()
    dress(source)
end)

addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) == "vehicle" then
        dress(source)
    end
end)

addEventHandler("onClientElementStreamOut", root, function()
    if blockers[source] then
        unblock(source)
    end
end)

addEventHandler("onClientElementDestroy", root, function()
    if blockers[source] then
        unblock(source)
    end
end)

setTimer(function()
    for vehicle, obj in pairs(blockers) do
        if isElement(vehicle) and isElement(obj) then
            setElementCollisionsEnabled(obj, getVehicleDoorOpenRatio(vehicle, DOOR) < 0.05)
        else
            unblock(vehicle)
        end
    end
end, BLOCKER_MS, 0)
