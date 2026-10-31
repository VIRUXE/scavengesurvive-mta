-- Loads the SA-MP custom object models listed in manifest.lua (written by tools/extract_samp_models.py together
-- with files/) into client-allocated model ids. Allocated ids differ per client, so nothing is
-- shared through the server: other resources ask exports.samp_models:resolve(sampModel) or use the lib models helper
-- on their own client and listen for sampModelsChanged (fired after loading and again before unloading)
-- to swap their objects' models.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- SA-MP model -> allocated MTA model
-- The house shells (lshouse1 ... sfhouse4) have translucent glass panes in their window openings, textured
-- house_window (tools/make_house_window.py). house_window.txd adds it to their vanilla dictionaries, once per
-- shared dictionary.
local HOUSE_SHELL = "^%a%ahouse%d$"
local windowTextureAdded = {} -- vanilla TXD id -> true
local shells = {} -- allocated model id -> true, for the house shell exteriors

addEvent("sampModelsChanged", false)

local ldr = loader.new({
    onTxdModel = function(id, e, txdId, loadTxd)
        if e.dff:match(HOUSE_SHELL) then
            shells[id] = true
            if not windowTextureAdded[txdId] then
                windowTextureAdded[txdId] = true
                local glass = loadTxd("house_window")
                -- without it the panes stay untextured; not worth dropping the house
                if not glass or not engineImportTXD(glass, id) then
                    outputDebugString("samp_models: house_window.txd not imported for " .. e.dff, 2)
                end
            end
        end
    end,
})

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    -- The hinged defence doors moved onto the middle of their footprint (defences.lua, tools/repivot_defences.py)
    -- are SA-MP models re-pivoted by the port, loaded like the manifest's.
    for _, name in ipairs({ "manifest", "defences" }) do
        local manifest = loader.loadLuaFile(name .. ".lua", "=samp_models/" .. name .. ".lua")
        for sampModel, e in pairs(manifest) do
            local id, err = ldr.loadModel(e)
            if id then
                ids[sampModel] = id
                count = count + 1
            else
                failed[#failed + 1] = sampModel .. " (" .. err .. ")"
            end
        end
    end
    local suffix = #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or ""
    local msg = ("samp_models: %d SA-MP models loaded%s"):format(count, suffix)
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
            local m = getElementMatrix(obj) -- rows: right, forward, up, position
            local right, fwd, up, pos = m[1], m[2], m[3], m[4]
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
    ids = {}
    triggerEvent("sampModelsChanged", root) -- users fall back to stand-ins before the ids go away
    ldr.freeAll()
end)

-- SA-MP model id -> this client's model id, or false while the model is not loaded
function resolve(sampModel)
    return ids[sampModel] or false
end
