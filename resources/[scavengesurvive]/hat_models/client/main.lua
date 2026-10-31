-- Hats cut off skins (hats.lua, written by tools/extract_ped_models.py --hats): static objects under the
-- port's own model ids (tools/port_hats.py, 20001+), textured from the base skin's TXD (#77) and using beanie1.col
-- (copied into hat_models/files/ so no resource reads another's files).
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- port model id -> allocated MTA model
local ldr = loader.new()

addEvent("sampModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    local manifest = loader.loadLuaFile("hats.lua", "=hat_models/hats.lua")
    for hatModel, e in pairs(manifest) do
        local id, err = ldr.loadModel(e)
        if id then
            ids[hatModel] = id
            count = count + 1
        else
            failed[#failed + 1] = hatModel .. " (" .. err .. ")"
        end
    end
    local suffix = #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or ""
    local msg = ("hat_models: %d port hat models loaded%s"):format(count, suffix)
    outputDebugString(msg, #failed > 0 and 2 or 3)
    triggerEvent("sampModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids = {}
    triggerEvent("sampModelsChanged", root)
    ldr.freeAll()
end)

-- Port hat model id -> this client's model id, or false while the model is not loaded
function resolve(hatModel)
    return ids[hatModel] or false
end
