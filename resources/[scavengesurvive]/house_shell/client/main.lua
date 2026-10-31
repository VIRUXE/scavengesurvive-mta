-- Replaces vanilla buildings for every client with enterable copies: the same exterior, with open doorways and
-- an interior behind them.
-- * des_westrn9_ (model 3250): an open front doorway and a plastered interior with floor and ceiling. Built from the
--   original gta3.img DFF in Blender with DragonFF; the COL (wall slabs, roof and ceiling surfaces) is rebuilt from
--   it and the TXD is the original cxref_oldwest cut down to the 12 textures the model uses (#131).
-- * the trailers (models 3167-3175, trailers.lua, tools/trailer_shells): panelled rooms, glazed windows and the
--   vanilla door cut out as a leaf of its own that swings, hung in every trailer of the world (the upright vanilla
--   placements listed in trailers.lua, and the ones the maps resource builds, found once it has built them).
local function readLua(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=house_shell/" .. path))()
end

local trailers = readLua("trailers.lua")
local DOOR_PHYSICS = 1491 -- Gen_doorINT01: its object.dat group makes a requested door model swing
local UPRIGHT = 0.999

local replaced = {} -- vanilla model -> true once its COL and DFF are replaced
local doorModels = {} -- vanilla trailer model -> requested model id of its door leaf
local requested = {} -- requested ids, freed on stop
local doors = {} -- door objects created
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
    for _, obj in ipairs(doors) do
        if isElement(obj) then
            destroyElement(obj)
        end
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
