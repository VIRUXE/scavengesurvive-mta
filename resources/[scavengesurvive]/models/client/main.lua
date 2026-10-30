-- Loads the SA-MP custom object models listed in manifest.lua (written by tools/extract_samp_models.py together
-- with files/) into client-allocated model ids. Allocated ids differ per client, so nothing is
-- shared through the server: other resources ask exports.models:resolve(sampModel) on their own client and listen
-- for sampModelsChanged (fired after loading and again before unloading) to swap their objects' models.
local ids = {} -- SA-MP model -> allocated MTA model
local allocated = {}
local keep = {} -- col/dff/txd elements stay alive while the models are in use
-- The house shells (lshouse1 ... sfhouse4) have translucent glass panes in their window openings, textured
-- house_window (tools/make_house_window.py). house_window.txd adds it to their vanilla dictionaries, once per
-- shared dictionary.
local HOUSE_SHELL = "^%a%ahouse%d$"
local windowTextureAdded = {} -- vanilla TXD id -> true
local shells = {} -- allocated model id -> true, for the house shell exteriors

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

-- e = { dff, txd | txdModel, dist, col }: own texture dictionary file, or the TXD of a vanilla model (or skin) that
-- already uses it; the collision file is the dff's own unless `col` names another one (the cut hats share the
-- beanie's). MTA requires COL -> TXD -> DFF order when replacing a model's assets.
local function loadModel(e, txds)
    local id = engineRequestModel("object")
    if not id then
        return nil, "no free model id"
    end
    allocated[#allocated + 1] = id
    local colName = e.col or e.dff
    local col = engineLoadCOL("files/" .. colName .. ".col")
    if not col or not engineReplaceCOL(col, id) then
        return nil, "col " .. colName
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
        if e.dff:match(HOUSE_SHELL) then
            shells[id] = true
        end
        if e.dff:match(HOUSE_SHELL) and not windowTextureAdded[txdId] then
            windowTextureAdded[txdId] = true
            local glass = loadTxd("house_window", txds)
            -- without it the panes stay untextured; not worth dropping the house
            if not glass or not engineImportTXD(glass, id) then
                outputDebugString("models: house_window.txd not imported for " .. e.dff, 2)
            end
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
-- skin's TXD and animations, plus its own `txd` when the head was rebuilt (the hair texture, #89);
-- items swaps a player onto it locally while a hat is worn (#75).
local hatless = {} -- base skin -> allocated ped model
local bare = {} -- base skin -> its twin, when the twin's head was rebuilt bare (its own hair TXD, #89)

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
    -- a rebuilt head's hair texture goes into that shared dictionary; the base skin never references it
    if e.txd then
        local txd = engineLoadTXD("files/" .. e.txd .. ".txd")
        if not txd or not engineImportTXD(txd, id) then
            return nil, "txd " .. e.txd
        end
        keep[#keep + 1] = txd
    end
    local dff = engineLoadDFF("files/" .. e.dff .. ".dff")
    if not dff or not engineReplaceModel(dff, id) then
        return nil, "dff " .. e.dff
    end
    keep[#keep + 1] = dff
    return id
end

-- Hats cut off the skins above (hats.lua, written by tools/extract_ped_models.py --hats): static objects under the
-- port's own model ids (tools/port_hats.py), resolved like the SA-MP ones, textured from the base skin's TXD (#77).
-- The props the port adds to the world (props.lua, tools/make_ls_hatch.py) bring their own TXD and collision.

addEventHandler("onClientResourceStart", resourceRoot, function()
    local txds, count, failed = {}, 0, {}
    for _, manifest in ipairs({ readManifest(), readLuaFile("hats.lua"), readLuaFile("props.lua") }) do
        for sampModel, e in pairs(manifest) do
            local id, err = loadModel(e, txds)
            if id then
                ids[sampModel] = id
                count = count + 1
            else
                failed[#failed + 1] = sampModel .. " (" .. err .. ")"
            end
        end
    end
    local peds = 0
    for base, e in pairs(readLuaFile("peds.lua")) do
        local id, err = loadPed(base, e)
        if id then
            hatless[base] = id
            bare[base] = e.txd and id or nil
            peds = peds + 1
        else
            failed[#failed + 1] = "skin " .. base .. " (" .. err .. ")"
        end
    end
    local suffix = #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or ""
    local msg = ("models: %d SA-MP and hat models and %d hatless skins loaded%s"):format(count, peds, suffix)
    outputDebugString(msg, #failed > 0 and 2 or 3)
    triggerEvent("sampModelsChanged", root)
end)

-- GTA only keeps rain out of a place through map cull zones or interior ids, neither of which a custom object can
-- carry, so rain would fall through the shells' roofs. While the camera is inside a streamed shell's bounding box
-- the rain level is forced to zero, and handed back to the weather when it leaves.
local RAIN_CHECK_MS = 250
local rainOff = false

local function insideShell(cx, cy, cz)
    for _, obj in ipairs(getElementsByType("object", root, true)) do
        if shells[getElementModel(obj)] then
            local right, fwd, up, pos = getElementMatrix(obj)
            local dx, dy, dz = cx - pos[1], cy - pos[2], cz - pos[3]
            local lx = dx * right[1] + dy * right[2] + dz * right[3]
            local ly = dx * fwd[1] + dy * fwd[2] + dz * fwd[3]
            local lz = dx * up[1] + dy * up[2] + dz * up[3]
            local x0, y0, z0, x1, y1, z1 = getElementBoundingBox(obj)
            if x0 and lx > x0 and lx < x1 and ly > y0 and ly < y1 and lz > z0 and lz < z1 then
                return true
            end
        end
    end
    return false
end

setTimer(function()
    local inside = next(shells) ~= nil and insideShell(getCameraMatrix())
    if inside and not rainOff then
        setRainLevel(0)
        rainOff = true
    elseif not inside and rainOff then
        resetRainLevel()
        rainOff = false
    end
end, RAIN_CHECK_MS, 0)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if rainOff then
        resetRainLevel()
        rainOff = false
    end
    shells = {}
    ids, hatless, bare = {}, {}, {}
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

-- base skin -> its twin when that twin has a rebuilt bare head, shown in place of the skin at all times; false for
-- the twins that are only fit to be seen under a hat
function bareSkin(skin)
    return bare[skin] or false
end
