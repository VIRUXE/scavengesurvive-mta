-- Props the port adds to the world (props.lua, tools/make_ls_hatch.py): port model ids 20201+ with their
-- own TXD and collision.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- port model id -> allocated MTA model
local ldr = loader.new()

addEvent("sampModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    local manifests = {
        loader.loadLuaFile("props.lua", "=prop_models/props.lua"),
        loader.loadLuaFile("fort.lua", "=prop_models/fort.lua"),
    }
    for _, manifest in ipairs(manifests) do
        for propModel, e in pairs(manifest) do
            local id, err = ldr.loadModel(e)
            if id then
                ids[propModel] = id
                count = count + 1
            else
                failed[#failed + 1] = propModel .. " (" .. err .. ")"
            end
        end
    end
    local suffix = #failed > 0 and (", failed: " .. table.concat(failed, ", ")) or ""
    local msg = ("prop_models: %d port props loaded%s"):format(count, suffix)
    outputDebugString(msg, #failed > 0 and 2 or 3)
    triggerEvent("sampModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids = {}
    triggerEvent("sampModelsChanged", root)
    ldr.freeAll()
end)

-- Port prop model id -> this client's model id, or false while the model is not loaded
function resolve(propModel)
    return ids[propModel] or false
end
