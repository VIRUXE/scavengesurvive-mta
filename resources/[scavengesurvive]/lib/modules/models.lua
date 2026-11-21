-- Resolves custom model ids across the model resources (samp_models, hat_models, door_models, prop_models,
-- box_models).
-- Tries the owning resource by id range first, or the running model resources in turn.
-- Guards with getResourceState == "running" and pcall so a stopped resource makes resolve return false.
local models = {}

local ORDERED_RESOURCES = { "samp_models", "hat_models", "door_models", "prop_models", "box_models" }

local function resourceForId(id)
    if id >= 20001 and id <= 20100 then
        return "hat_models"
    elseif id >= 20101 and id <= 20199 then
        return "door_models"
    elseif id >= 20201 and id <= 20299 then
        return "prop_models"
    elseif id >= 20401 and id <= 20499 then
        return "box_models"
    elseif (id >= 11682 and id <= 11753) or (id >= 18631 and id <= 19999) then
        return "samp_models"
    end
    return nil
end

local function tryResolve(resName, id)
    local res = getResourceFromName(resName)
    if not res or getResourceState(res) ~= "running" then
        return false
    end
    local exp = exports[resName]
    if not exp or not exp.resolve then
        return false
    end
    local ok, resolved = pcall(exp.resolve, exp, id)
    return (ok and resolved) or false
end

function models.resolve(id)
    if not id then
        return false
    end
    local target = resourceForId(id)
    if target then
        local resolved = tryResolve(target, id)
        if resolved then
            return resolved
        end
    end
    for _, resName in ipairs(ORDERED_RESOURCES) do
        if resName ~= target then
            local resolved = tryResolve(resName, id)
            if resolved then
                return resolved
            end
        end
    end
    return false
end

-- An object's model-space box (getElementBoundingBox's six numbers), client-side. MTA reports a model's collision
-- box moved by its bounding sphere's centre, so any model whose box is not centred on its origin comes out shifted
-- (the Locker 1.03 m up, a door a hinge's width aside). The centre is the box's own middle in every model we load,
-- so the reported middle is twice the true one: half of it comes back off each corner.
function models.bounds(el)
    local x0, y0, z0, x1, y1, z1 = getElementBoundingBox(el)
    if not x0 then
        return false
    end
    local cx, cy, cz = (x0 + x1) / 4, (y0 + y1) / 4, (z0 + z1) / 4
    return x0 - cx, y0 - cy, z0 - cz, x1 - cx, y1 - cy, z1 - cz
end

function models.hatlessSkin(skin)
    local res = getResourceFromName("skin_models")
    if not res or getResourceState(res) ~= "running" then
        return false
    end
    local exp = exports.skin_models
    if not exp or not exp.hatlessSkin then
        return false
    end
    local ok, twin = pcall(exp.hatlessSkin, exp, skin)
    return (ok and twin) or false
end

function models.bareSkin(skin)
    local res = getResourceFromName("skin_models")
    if not res or getResourceState(res) ~= "running" then
        return false
    end
    local exp = exports.skin_models
    if not exp or not exp.bareSkin then
        return false
    end
    local ok, twin = pcall(exp.bareSkin, exp, skin)
    return (ok and twin) or false
end

return models
