-- Loads the SA-MP custom object models listed in manifest.lua (written by tools/extract_samp_models.py together
-- with files/) into client-allocated model ids. Allocated ids differ per client, so nothing is
-- shared through the server: other resources ask exports.samp_models:resolve(sampModel) or use the lib models helper
-- on their own client and listen for customModelsChanged (fired after loading and again before unloading)
-- to swap their objects' models.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- SA-MP model -> allocated MTA model
-- The house shells (lshouse1 ... sfhouse4) have translucent glass panes in their window openings, textured
-- house_window (tools/make_house_window.py). house_window.txd adds it to their vanilla dictionaries, once per
-- shared dictionary.
local HOUSE_SHELL = "^%a%ahouse%dw?$" -- w: stretched to a deeper plot (stretched.lua, tools/stretch_house_shells.py)
local windowTextureAdded = {} -- vanilla TXD id -> true

addEvent("customModelsChanged", false)

local ldr = loader.new({
    onTxdModel = function(id, e, txdId, loadTxd)
        if e.dff:match(HOUSE_SHELL) then
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
    -- and the house shells stretched to deeper plots (stretched.lua, tools/stretch_house_shells.py) are SA-MP models
    -- reworked by the port, loaded like the manifest's.
    for _, name in ipairs({ "manifest", "defences", "stretched" }) do
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
    if #failed > 0 then
        outputDebugString(("samp_models: %d loaded, failed: %s"):format(count, table.concat(failed, ", ")), 2)
    end
    triggerEvent("customModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids = {}
    triggerEvent("customModelsChanged", root) -- users fall back to stand-ins before the ids go away
    ldr.freeAll()
end)

-- SA-MP model id -> this client's model id, or false while the model is not loaded
function resolve(sampModel)
    return ids[sampModel] or false
end
