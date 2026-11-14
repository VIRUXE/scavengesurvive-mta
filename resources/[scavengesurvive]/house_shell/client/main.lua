-- Replaces vanilla buildings for every client with enterable copies: the same exterior, with open doorways and
-- an interior behind them.
-- * des_westrn9_ (model 3250): an open front doorway and a plastered interior with floor and ceiling. Built from the
--   original gta3.img DFF in Blender with DragonFF; the COL (wall slabs, roof and ceiling surfaces) is rebuilt from
--   it and the TXD is the original cxref_oldwest cut down to the 12 textures the model uses (#131).
-- * the log cabin row (model 17067, cabins.lua, tools/cabin_shells): six one-room cabins with a swinging door, glazed
--   windows and furniture, behind the Flint County road.
-- * the trailers (models 3167-3175, trailers.lua, tools/trailer_shells): panelled rooms, glazed windows and the
--   vanilla door cut out as a leaf of its own that swings, hung in every trailer of the world (the upright vanilla
--   placements listed in trailers.lua, and the ones the maps resource builds, found once it has built them).
-- * the houses (houses.lua, tools/house_shells): the Fort Carson houses des_bighus01-03 (models 3305-3303), rooms
--   behind their front, porch and side doors (and 01's garage behind its side door), each door a leaf that swings;
--   the Verdant Meadows airstrip office des_byoffice (16326), its ground floor holding the game's own interior
--   (airfieldhus1/2, fitted inside it) and furnished with the same stock props, its vanilla locked door
--   (Gen_doorEXT03) removed and hung again as a leaf that swings.
local function readLua(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=house_shell/" .. path))()
end

local trailers = readLua("trailers.lua")
local cabins = readLua("cabins.lua")
local houses = readLua("houses.lua")
local DOOR_PHYSICS = 1491 -- Gen_doorINT01: its object.dat group makes a requested door model swing
local UPRIGHT = 0.999

local replaced = {} -- vanilla model -> true once its COL and DFF are replaced
local doorModels = {} -- vanilla trailer model -> requested model id of its door leaf
local requested = {} -- requested ids, freed on stop
local doors = {} -- door objects created
local props = {} -- furniture objects created
local removed = {} -- { model, radius, x, y, z } of vanilla objects removed, restored on stop
local hung = {} -- building or placement key -> true, so a trailer gets one door
local keep = {} -- loaded COL/TXD/DFF elements

local function replaceModel(model, col, txd, dff)
    -- Keep the RenderWare load order: collision, texture dictionary, then geometry.
    local c = engineLoadCOL("files/" .. col .. ".col")
    if not c or not engineReplaceCOL(c, model) then
        outputDebugString(("house_shell: failed to replace collision for model %d"):format(model), 1)
        return false
    end
    if not engineImportTXD(txd, model) then
        outputDebugString(("house_shell: failed to import TXD for model %d"):format(model), 1)
        engineRestoreCOL(model)
        return false
    end
    local d = engineLoadDFF("files/" .. dff .. ".dff", 0)
    if not d or not engineReplaceModel(d, model, false) then
        outputDebugString(("house_shell: failed to replace DFF for model %d"):format(model), 1)
        engineRestoreCOL(model)
        return false
    end
    keep[#keep + 1], keep[#keep + 2] = c, d
    replaced[model] = true
    return true
end

local function requestDoor(name, txd)
    local id = engineRequestModel("object")
    if not id then
        return nil
    end
    requested[#requested + 1] = id
    engineSetModelPhysicalPropertiesGroup(id, engineGetModelPhysicalPropertiesGroup(DOOR_PHYSICS))
    local c = engineLoadCOL("files/" .. name .. ".col")
    local loaded = c and engineReplaceCOL(c, id) and engineImportTXD(txd, id)
    local d = loaded and engineLoadDFF("files/" .. name .. ".dff")
    if not d or not engineReplaceModel(d, id) then
        outputDebugString("house_shell: failed to load door " .. name, 1)
        return nil
    end
    keep[#keep + 1], keep[#keep + 2] = c, d
    engineSetModelLODDistance(id, 100)
    return id
end

-- The cabins' doors: one leaf model, hung in each of the six cabins of every placement of the row (hinges are in the
-- model's frame).
local function hangCabinDoors(id, x, y, z, rz)
    local a = math.rad(rz)
    local c, s = math.cos(a), math.sin(a)
    for _, h in ipairs(cabins.hinges) do
        local obj =
            createObject(id, x + h[1] * c - h[2] * s, y + h[1] * s + h[2] * c, z + h[3], 0, 0, rz + cabins.door.rz)
        if obj then
            doors[#doors + 1] = obj
        end
    end
end

-- A house's doors: one leaf model, hung at each of its hinges (x, y, z, rz in the model's frame); then the vanilla
-- objects it removes and the stock props it is furnished with, if any (also in the model's frame).
local function hangHouseDoors(id, house, x, y, z, rz)
    local a = math.rad(rz)
    local c, s = math.cos(a), math.sin(a)
    local function at(p)
        return x + p[1] * c - p[2] * s, y + p[1] * s + p[2] * c, z + p[3]
    end
    for _, r in ipairs(house.remove or {}) do
        local wx, wy, wz = at({ r[2], r[3], r[4] })
        if removeWorldModel(r[1], r[5], wx, wy, wz) then
            removed[#removed + 1] = { r[1], r[5], wx, wy, wz }
        end
    end
    for _, h in ipairs(house.hinges) do
        local hx, hy, hz = at(h)
        local obj = createObject(id, hx, hy, hz, 0, 0, rz + h[4])
        if obj then
            doors[#doors + 1] = obj
        end
    end
    for _, p in ipairs(house.props or {}) do
        local px, py, pz = at({ p[2], p[3], p[4] })
        local obj = createObject(p[1], px, py, pz, 0, 0, rz + p[5])
        if obj then
            setElementFrozen(obj, true) -- client-side furniture: kept where it stands, the same for every player
            props[#props + 1] = obj
        end
    end
end

-- A door in the trailer at x, y, z turned rz degrees about Z: the leaf's hinge moved into the world.
local function hangDoor(model, x, y, z, rz)
    local id, door = doorModels[model], trailers.models[model].door
    local a = math.rad(rz)
    local c, s = math.cos(a), math.sin(a)
    local wx, wy = x + door.x * c - door.y * s, y + door.x * s + door.y * c
    local obj = createObject(id, wx, wy, z + door.z, 0, 0, rz + door.rz)
    if obj then
        doors[#doors + 1] = obj
    end
end

local function hangMapDoors()
    local count = 0
    for _, b in ipairs(getElementsByType("building")) do
        local model = getElementModel(b)
        if doorModels[model] and not hung[b] then
            local m = getElementMatrix(b) -- rows: right, forward, up, position
            if m[3][3] >= UPRIGHT then
                hung[b] = true
                local _, _, rz = getElementRotation(b)
                hangDoor(model, m[4][1], m[4][2], m[4][3], rz)
                count = count + 1
            end
        end
    end
    return count
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local westrn = engineLoadTXD("files/des_westrn9.txd", true)
    if westrn and replaceModel(3250, "des_westrn9", westrn, "des_westrn9") then
        outputDebugString("house_shell: open des_westrn9_ model 3250 loaded", 3)
    end
    local txd = engineLoadTXD("files/trailers.txd", true)
    if not txd then
        outputDebugString("house_shell: failed to load trailers.txd", 1)
        return
    end
    keep[#keep + 1] = txd
    local count = 0
    for model, m in pairs(trailers.models) do
        if replaceModel(model, m.dff, txd, m.dff) then
            -- the glass is drawn after the buildings around it, or it hides them
            engineSetModelFlag(model, "draw_last", true)
            doorModels[model] = requestDoor(m.door.dff, txd)
            count = count + 1
        end
    end
    -- GTA world buildings can keep their streamed copy until the world is restreamed.
    engineRestreamWorld()
    for i, p in ipairs(trailers.placements) do
        if doorModels[p[1]] then
            hung[i] = true
            hangDoor(p[1], p[2], p[3], p[4], p[5])
        end
    end
    local cabinTxd = engineLoadTXD("files/" .. cabins.dff .. ".txd", true)
    if cabinTxd and replaceModel(cabins.model, cabins.dff, cabinTxd, cabins.dff) then
        keep[#keep + 1] = cabinTxd
        engineSetModelFlag(cabins.model, "draw_last", true)
        local id = requestDoor(cabins.door.dff, cabinTxd)
        for _, p in ipairs(cabins.placements) do
            if id then
                hangCabinDoors(id, p[1], p[2], p[3], p[4])
            end
        end
    else
        outputDebugString("house_shell: failed to load the log cabins", 1)
    end
    for _, house in ipairs(houses) do
        local houseTxd = engineLoadTXD("files/" .. house.dff .. ".txd", true)
        if houseTxd and replaceModel(house.model, house.dff, houseTxd, house.dff) then
            keep[#keep + 1] = houseTxd
            engineSetModelFlag(house.model, "draw_last", true)
            local id = requestDoor(house.door, houseTxd)
            for _, p in ipairs(house.placements) do
                if id then
                    hangHouseDoors(id, house, p[1], p[2], p[3], p[4])
                end
            end
        else
            outputDebugString("house_shell: failed to load house " .. house.dff, 1)
        end
    end
    local fromMaps = hangMapDoors()
    local fmt = "house_shell: %d trailers enterable, %d doors hung (%d in map trailers)"
    local msg = fmt:format(count, #doors, fromMaps)
    outputDebugString(msg, 3)
end)

-- The maps resource builds its trailers after this resource may have started.
addEventHandler("mapsBuilt", root, function()
    hangMapDoors()
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, list in ipairs({ doors, props }) do
        for _, obj in ipairs(list) do
            if isElement(obj) then
                destroyElement(obj)
            end
        end
    end
    for _, r in ipairs(removed) do
        restoreWorldModel(r[1], r[2], r[3], r[4], r[5])
    end
    for model in pairs(replaced) do
        engineRestoreModel(model)
        engineRestoreCOL(model)
    end
    for _, id in ipairs(requested) do
        engineFreeModel(id)
    end
    engineRestreamWorld()
end)
