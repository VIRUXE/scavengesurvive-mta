-- Which MTA model an item type's object uses on this client: the SA-MP model loaded by the `samp_models` resource
-- while it is running, otherwise the vanilla stand-in chosen by data/model_map.lua (type.mtaModel). Also owns the
-- per-colour tint shaders for item types whose DefineItemType colour is not -1 (#96).
-- Returns { FALLBACK, forType, forSamp, colourRgba, hasTint, applyTint, onChanged }.
return function()
    local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
    local M = { FALLBACK = 1271 }
    local cache = {}
    local tintShaders = {} -- colour key -> shader, or false when the shader could not be created
    local refreshers = {}

    -- SA-MP's DefineItemType colour is 0xAARRGGBB ("0xFF000000" for BurntLog, -1 when unset).
    function M.colourRgba(colour)
        if not colour or colour == -1 then
            return nil
        end
        local n = tonumber(colour)
        if not n or n < 0 then
            return nil
        end
        local a = math.floor(n / 0x1000000) % 0x100
        local r = math.floor(n / 0x10000) % 0x100
        local g = math.floor(n / 0x100) % 0x100
        local b = n % 0x100
        return r / 255, g / 255, b / 255, a / 255
    end

    function M.hasTint(t)
        return (t and M.colourRgba(t.colour)) ~= nil
    end

    local function tintShader(colour, unlit)
        local key = tostring(colour) .. (unlit and ":unlit" or "")
        if tintShaders[key] == nil then
            local r, g, b, a = M.colourRgba(colour)
            local shader = r and dxCreateShader("client/tint.fx") or nil
            if shader then
                dxSetShaderValue(shader, "Colour", r, g, b, a)
                if unlit then
                    dxSetShaderValue(shader, "Unlit", true)
                end
            end
            tintShaders[key] = shader or false
        end
        return tintShaders[key] or nil
    end

    function M.applyTint(obj, t, unlit)
        local shader = M.hasTint(t) and tintShader(t.colour, unlit) or nil
        if shader and isElement(obj) then
            engineApplyShaderToWorldTexture(shader, "*", obj)
        end
    end

    local function sampModel(model)
        return models.resolve(model)
    end

    -- A SA-MP-only model id as this client can create it (the pitched tent's parts, shared/logic/tent.lua), or
    -- false while the pack is not running.
    function M.forSamp(model)
        local id = cache[model]
        if id == nil then
            id = sampModel(model)
            cache[model] = id
        end
        return id or false
    end

    function M.forType(t)
        if not t then
            return M.FALLBACK
        end
        if not t.sampOnly then
            return t.model
        end
        return M.forSamp(t.model) or t.mtaModel or M.FALLBACK
    end

    function M.onChanged(refresh)
        refreshers[#refreshers + 1] = refresh
    end

    -- a model resource (re)started or is stopping: every live object picks its model again
    addEventHandler("sampModelsChanged", root, function()
        cache = {}
        for _, refresh in ipairs(refreshers) do
            refresh()
        end
    end)

    return M
end
