-- Server objects whose model exists only on clients: the SA-MP models (samp_models) and the port's own (hat_models,
-- door_models, prop_models, box_models), whose ids each client allocates for itself (lib models.lua). The server
-- creates them with a stand-in (CJ_CIGGY, invisible), marks each with the model it stands for (element data "samp"),
-- and tells the collision companion to collide it as that model (lib sageom.lua); each client swaps in its own
-- allocated model and shows it, and puts the stand-in back while the model is not loaded.
--   local standins = loadstring(exports.lib:getModule("standins"), "=lib/standins.lua")()
--   server: standins.create(model, x, y, z, rx, ry, rz)   client: standins.track(resourceRoot, onSwap)
local KEY = "samp"
local STANDIN = 1485 -- CJ_CIGGY: valid on the server, tiny, drawn nowhere (alpha 0) until the client swaps

-- SA-MP object models and the port's 20001+ ids (lib models.lua resolves both)
local function isCustom(model)
    return model >= 18631 or (model >= 11682 and model <= 11753)
end

local placed = {} -- server: stand-in -> the model it stands for, for the collision companion
local sageom

-- server: a frozen stand-in for model at that position (dimension and interior left to the caller), or false
local function create(model, x, y, z, rx, ry, rz)
    local e = createObject(STANDIN, x, y, z, rx or 0, ry or 0, rz or 0)
    if not e then
        return false
    end
    setElementAlpha(e, 0)
    setElementFrozen(e, true)
    setElementData(e, KEY, model, "broadcast", "deny")
    if not sageom then
        sageom = loadstring(exports.lib:getModule("sageom"), "=lib/sageom.lua")()
        -- a companion (re)started after these were created takes them all again
        sageom.onReady(function()
            for s, m in pairs(placed) do
                if isElement(s) then
                    sageom.call("setElementCollisionModel", s, m)
                else
                    placed[s] = nil
                end
            end
        end)
    end
    placed[e] = model
    sageom.call("setElementCollisionModel", e, model)
    return e
end

-- client: swaps the models of the stand-ins under parent now and whenever a model pack (re)loads; onSwap(e, model,
-- loaded) runs after each (loaded: this client's id, or false while the stand-in is back). Returns the count.
local function track(parent, onSwap)
    local models = loadstring(exports.lib:getModule("models"), "=lib/models.lua")()
    local marked = {}
    for _, e in ipairs(getElementsByType("object", parent)) do
        local model = getElementData(e, KEY)
        if model then
            marked[e] = model
        end
    end
    local function swapAll()
        for e, model in pairs(marked) do
            if isElement(e) then
                local id = models.resolve(model)
                if getElementModel(e) ~= (id or STANDIN) then
                    setElementModel(e, id or STANDIN)
                end
                setElementAlpha(e, id and 255 or 0)
                if onSwap then
                    onSwap(e, model, id)
                end
            else
                marked[e] = nil
            end
        end
    end
    swapAll()
    addEvent("customModelsChanged", false)
    addEventHandler("customModelsChanged", root, swapAll)
    local count = 0
    for _ in pairs(marked) do
        count = count + 1
    end
    return count
end

return {
    KEY = KEY,
    STANDIN = STANDIN,
    isCustom = isCustom,
    create = create,
    track = track,
}
