-- Loads the SA-MP custom object models listed in manifest.lua (written by tools/extract_samp_models.py together
-- with files/) into client-allocated model ids. Allocated ids differ per client, so nothing is
-- shared through the server: other resources ask exports.models:resolve(sampModel) on their own client and listen
-- for sampModelsChanged (fired after loading and again before unloading) to swap their objects' models.
local ids = {} -- SA-MP model -> allocated MTA model
local allocated = {}
local keep = {} -- col/dff/txd elements stay alive while the models are in use

addEvent("sampModelsChanged", false)

local function readManifest()
    local f = fileOpen("manifest.lua", true)
    if not f then
        return {}
    end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    local chunk = loadstring(src, "=models/manifest.lua")
    return chunk and chunk() or {}
end

local function loadTxd(name, cache)
    if cache[name] == nil then
        cache[name] = engineLoadTXD("files/" .. name .. ".txd") or false
        if cache[name] then
            keep[#keep + 1] = cache[name]
        end
    end
    return cache[name]
end

-- e = { dff, txd | txdModel, dist }: own texture dictionary file, or the TXD of a vanilla model that already uses it.
-- MTA requires COL -> TXD -> DFF order when replacing a model's assets.
local function loadModel(e, txds)
    local id = engineRequestModel("object")
    if not id then
        return nil, "no free model id"
    end
    allocated[#allocated + 1] = id
    local col = engineLoadCOL("files/" .. e.dff .. ".col")
    if not col or not engineReplaceCOL(col, id) then
        return nil, "col " .. e.dff
    end
    keep[#keep + 1] = col
    if e.txd then
        local txd = loadTxd(e.txd, txds)
        if not txd or not engineImportTXD(txd, id) then
            return nil, "txd " .. e.txd
        end
    elseif e.txdModel then
        local txdId = engineGetModelTXDID(e.txdModel)
        if not txdId or not engineSetModelTXDID(id, txdId) then
            return nil, "txd of model " .. e.txdModel
        end
    end
    local dff = engineLoadDFF("files/" .. e.dff .. ".dff")
    if not dff or not engineReplaceModel(dff, id) then
        return nil, "dff " .. e.dff
    end
    keep[#keep + 1] = dff
    if e.dist then
        engineSetModelLODDistance(id, math.min(e.dist, 300))
    end
    return id
end

-- Hatless ped variants (peds.lua, written by tools/extract_ped_models.py): a copy of a skin whose mesh carries
-- its own hat, cap or helmet, with that headgear cut away so a worn hat sits clean. The variant shares the base
-- skin's TXD and animations; items swaps a player onto it locally while a hat is worn (#75).
local hatless = {} -- base skin -> allocated ped model

local function readLuaFile(name)
    local f = fileOpen(name, true)
    if not f then
        return {}
    end
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    local chunk = loadstring(src, "=models/" .. name)
    return chunk and chunk() or {}
end

local function loadPed(base, e)
    local id = engineRequestModel("ped", base)
    if not id then
        return nil, "no free ped model id"
    end
    allocated[#allocated + 1] = id
    local txdId = engineGetModelTXDID(base)
    if not txdId or not engineSetModelTXDID(id, txdId) then
        return nil, "txd of skin " .. base
    end
    local dff = engineLoadDFF("files/" .. e.dff .. ".dff")
    if not dff or not engineReplaceModel(dff, id) then
        return nil, "dff " .. e.dff
    end
    keep[#keep + 1] = dff
    return id
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local txds, count, failed = {}, 0, {}
    for sampModel, e in pairs(readManifest()) do
        local id, err = loadModel(e, txds)
        if id then
            ids[sampModel] = id
            count = count + 1
        else
            failed[#failed + 1] = sampModel .. " (" .. err .. ")"
        end
    end
    local peds = 0
    for base, e in pairs(readLuaFile("peds.lua")) do
        local id, err = loadPed(base, e)
        if id then
            hatless[base] = id
            peds = peds + 1
        else
            failed[#failed + 1] = "skin " .. base .. " (" .. err .. ")"
        end
    end
    local suffix = #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or ""
    local msg = ("models: %d SA-MP models and %d hatless skins loaded%s"):format(count, peds, suffix)
    outputDebugString(msg, #failed > 0 and 2 or 3)
    triggerEvent("sampModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids, hatless = {}, {}
    triggerEvent("sampModelsChanged", root) -- users fall back to stand-ins before the ids go away
    for _, id in ipairs(allocated) do
        engineFreeModel(id)
    end
    allocated, keep = {}, {}
end)

-- SA-MP model id -> this client's model id, or false while the model is not loaded
function resolve(sampModel)
    return ids[sampModel] or false
end

-- base skin -> this client's hatless variant of it, or false when the skin has none (or the pack is not loaded)
function hatlessSkin(skin)
    return hatless[skin] or false
end
