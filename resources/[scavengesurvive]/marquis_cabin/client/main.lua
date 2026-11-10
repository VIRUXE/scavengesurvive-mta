-- The Marquis (model 484) with a cabin a ped can walk into: the model, its textures and its ped collision are built
-- by tools/marquis_cabin/cabin.py (cabin.lua is its output: the door's hinge). The cabin's door (the interact key
-- opens it, vehicles' walk-in door code; its hinge is the model's cabin_door frame): each Marquis in view carries the
-- door leaf as an object in the doorway, solid while the door is shut. The game resets a
-- boat's frames every frame (a component rotation never lasts), so the model's own leaf stays hidden and this object,
-- attached at the hinge, is the door the player sees and swings.
local cabin
do
    local f = fileOpen("cabin.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    cabin = assert(loadstring(src, "=marquis_cabin/cabin.lua"))()
end

local loaded = false
local doorModel = nil -- requested object model: the door leaf and its collision
local angles = {} -- Marquis -> the leaf's angle now
local blockers = {} -- Marquis -> its door blocker object
local keep = {} -- loaded TXD/DFF/COL elements

local function block(vehicle)
    if not doorModel or blockers[vehicle] then
        return
    end
    local d = cabin.door
    local x, y, z = getElementPosition(vehicle)
    local obj = createObject(doorModel, x, y, z)
    if not obj then
        return
    end
    setElementDimension(obj, getElementDimension(vehicle))
    setElementInterior(obj, getElementInterior(vehicle))
    setElementCollidableWith(obj, vehicle, false)
    attachElements(obj, vehicle, d.x, d.y, d.z, 0, 0, d.rz)
    blockers[vehicle] = obj
    setVehicleComponentVisible(vehicle, cabin.component .. "_ok", false)
end

local function unblock(vehicle)
    if isElement(blockers[vehicle]) then
        destroyElement(blockers[vehicle])
    end
    blockers[vehicle] = nil
    angles[vehicle] = nil
end

local function dress(vehicle)
    if loaded and isElement(vehicle) and getElementModel(vehicle) == cabin.model then
        block(vehicle)
    end
end

-- the door leaf as a static object model: its collision box, its DFF to stand in for the shape (drawn unseen)
local function requestDoor(txd)
    local id = engineRequestModel("object")
    if not id then
        return nil
    end
    local path = "files/" .. cabin.door.dff
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
    local txd = engineLoadTXD("files/marquis.txd", true)
    local dff = txd and engineImportTXD(txd, cabin.model) and engineLoadDFF("files/marquis.dff")
    if not dff or not engineReplaceModel(dff, cabin.model) then
        return outputDebugString("marquis_cabin: failed to load the Marquis (model " .. cabin.model .. ")", 1)
    end
    keep[#keep + 1], keep[#keep + 2] = txd, dff
    loaded = true
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
        engineRestoreModel(cabin.model)
    end
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

-- the door's swing: the leaf object turns about the hinge (a boat's door ratio is not synced, so the state is element data
-- vehicles.cabinDoor, 0 shut, 1 open); it blocks the doorway until it has begun to open
local DATA = "vehicles.cabinDoor"
local OPEN_DEG, SPEED = 95, 200 -- degrees; degrees a second

addEventHandler("onClientPreRender", root, function(ms)
    for vehicle, obj in pairs(blockers) do
        if isElement(vehicle) and isElement(obj) then
            local target = getElementData(vehicle, DATA) == 1 and OPEN_DEG or 0
            local a = angles[vehicle] or target
            local step = SPEED * ms / 1000
            a = a + math.max(-step, math.min(step, target - a))
            angles[vehicle] = a
            local d = cabin.door
            setElementAttachedOffsets(obj, d.x, d.y, d.z, 0, 0, d.rz - a)
            setElementCollisionsEnabled(obj, target == 0 and a < 5)
        else
            unblock(vehicle)
        end
    end
end)
