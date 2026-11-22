-- Vehicle salvage parts (parts.lua, tools/car_parts.py): port model ids 21001+, Rockstar's own ok/dam panels cut
-- out of each car, all on one shared TXD, each with a box collision.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- port model id -> allocated MTA model
local ldr = loader.new()

addEvent("customModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    local manifest = loader.loadLuaFile("parts.lua", "=car_part_models/parts.lua")
    for partModel, e in pairs(manifest) do
        local id, err = ldr.loadModel(e)
        if id then
            ids[partModel] = id
            count = count + 1
        else
            failed[#failed + 1] = partModel .. " (" .. err .. ")"
        end
    end
    if #failed > 0 then
        outputDebugString(("car_part_models: %d loaded, failed: %s"):format(count, table.concat(failed, ", ")), 2)
    end
    triggerEvent("customModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids = {}
    triggerEvent("customModelsChanged", root)
    ldr.freeAll()
end)

-- Port part model id -> this client's model id, or false while the model is not loaded
function resolve(partModel)
    return ids[partModel] or false
end
