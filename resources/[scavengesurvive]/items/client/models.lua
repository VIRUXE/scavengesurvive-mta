-- Which MTA model an item type's object uses on this client: the SA-MP model loaded by the `models` resource
-- while it is running, otherwise the vanilla stand-in chosen by data/model_map.lua (type.mtaModel).
-- Returns { FALLBACK, forType, onChanged }; onChanged(fn) runs fn whenever the model pack (re)loads or stops.
return function()
    local M = { FALLBACK = 1271 }
    local cache = {}
    local refreshers = {}

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

    function M.forType(t)
        if not t then
            return M.FALLBACK
        end
        if not t.sampOnly then
            return t.model
        end
        local id = cache[t.model]
        if id == nil then
            id = sampModel(t.model)
            cache[t.model] = id
        end
        return id or t.mtaModel or M.FALLBACK
    end

    function M.onChanged(refresh)
        refreshers[#refreshers + 1] = refresh
    end

    -- the models resource (re)started or is stopping: every live object picks its model again
    addEventHandler("onClientSampModelsChanged", root, function()
        cache = {}
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end)

    return M
end
