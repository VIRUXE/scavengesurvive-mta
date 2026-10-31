-- The house shells' fitted doors (doors.lua, tools/fit_house_doors.py): port model ids 20101+, each given its vanilla
-- door's physical properties group so it swings properly.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- port model id -> allocated MTA model
local ldr = loader.new()

addEvent("sampModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    local manifest = loader.loadLuaFile("doors.lua", "=door_models/doors.lua")
    for doorModel, e in pairs(manifest) do
        local id, err = ldr.loadModel(e)
        if id then
            ids[doorModel] = id
            count = count + 1
        else
            failed[#failed + 1] = doorModel .. " (" .. err .. ")"
        end
    end
    if #failed > 0 then
        outputDebugString(("door_models: %d loaded, failed: %s"):format(count, table.concat(failed, ", ")), 2)
    end
    triggerEvent("sampModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids = {}
    triggerEvent("sampModelsChanged", root)
    ldr.freeAll()
end)

-- Port door model id -> this client's model id, or false while the model is not loaded
function resolve(doorModel)
    return ids[doorModel] or false
end
