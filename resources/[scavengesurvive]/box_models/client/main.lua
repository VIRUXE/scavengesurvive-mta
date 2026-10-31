-- GTA's boxes, crates and bags cut out of the map (boxes.lua, tools/extract_world_boxes.py): port model ids 20401+,
-- the world box items and what is left of the models they came from, each with its own TXD and collision.
local loader = loadstring(exports.lib:getModule("model_loader"), "=lib/model_loader.lua")()

local ids = {} -- port model id -> allocated MTA model
local ldr = loader.new()

addEvent("sampModelsChanged", false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    local count, failed = 0, {}
    for boxModel, e in pairs(loader.loadLuaFile("boxes.lua", "=box_models/boxes.lua")) do
        local id, err = ldr.loadModel(e)
        if id then
            ids[boxModel] = id
            count = count + 1
        else
            failed[#failed + 1] = boxModel .. " (" .. err .. ")"
        end
    end
    if #failed > 0 then
        outputDebugString(("box_models: %d loaded, failed: %s"):format(count, table.concat(failed, ", ")), 2)
    end
    triggerEvent("sampModelsChanged", root)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    ids = {}
    triggerEvent("sampModelsChanged", root)
    ldr.freeAll()
end)

-- Port box model id -> this client's model id, or false while the model is not loaded
function resolve(boxModel)
    return ids[boxModel] or false
end
