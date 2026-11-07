-- Props the port adds to the world (props.lua, tools/make_props.py): port model ids 20201+ with their
-- own TXD and collision.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- port model id -> allocated MTA model
local ldr = loader.new()

addEvent("sampModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    local manifest = loader.loadLuaFile("props.lua", "=prop_models/props.lua")
    for propModel, e in pairs(manifest) do
        local id, err = ldr.loadModel(e)
        if id and e.ideFlags then -- drawn as its IDE flags say (the snack machine's glass: alpha, glass)
            engineSetModelFlags(id, e.ideFlags, true)
        end
        if id then
            ids[propModel] = id
            count = count + 1
        else
            failed[#failed + 1] = propModel .. " (" .. err .. ")"
        end
    end
    if #failed > 0 then
        outputDebugString(("prop_models: %d loaded, failed: %s"):format(count, table.concat(failed, ", ")), 2)
    end
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
