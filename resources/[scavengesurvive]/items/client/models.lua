-- Which MTA model an item type's object uses on this client: the SA-MP model loaded by the `models` resource
-- while it is running, otherwise the vanilla stand-in chosen by data/model_map.lua (type.mtaModel).
ItemModels = { FALLBACK = 1271, refreshers = {} }
local cache = {}

local function sampModel(model)
    local res = getResourceFromName("models")
    if not res or getResourceState(res) ~= "running" then
        return false
    end
    local ok, id = pcall(function()
        return exports.models:resolve(model)
    end)
    return ok and id or false
end

function ItemModels.forType(t)
    if not t then
        return ItemModels.FALLBACK
    end
    if not t.sampOnly then
        return t.model
    end
    local id = cache[t.model]
    if id == nil then
        id = sampModel(t.model)
        cache[t.model] = id
    end
    return id or t.mtaModel or ItemModels.FALLBACK
end

-- the models resource (re)started or is stopping: every live object picks its model again
addEventHandler("onClientSampModelsChanged", root, function()
    cache = {}
    for _, refresh in ipairs(ItemModels.refreshers) do
        refresh()
    end
end)
