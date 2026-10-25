-- Live gear tile previews, client side: the inventory renderer says which models sit in which tile areas and
-- this module draws them every frame with dxDrawModel3D, in world space just in front of the camera at the point
-- under each tile centre (the dx UI leaves the tile centre see-through, like upstream's 0xFFFFFF08 tile fill).
-- Item types with a DefineItemType colour (#96) use a client-side object with the unlit tint shader, since
-- dxDrawModel3D has no element to attach a shader to.
-- Each model is measured once through a throwaway object (bounding box + rotation matrix) and held in the
-- streamer while shown. ctx = { logic = shared/logic/preview.lua, models = client/models.lua }.
return function(ctx)
    local logic = ctx.logic
    local models = ctx.models
    local M = { logic = logic }
    local shown = {} -- { { model = id, area = logic.area(...), itemType = t }, ... } for the current dialog
    local held = {} -- model id -> true while this resource holds a streaming reference
    local frames = {} -- model id -> logic.frame(...) or false when the model cannot be measured
    local slots = {} -- index -> { obj, model, colour } for tinted preview slots
    local rx, ry, rz = logic.ROTATION.x, logic.ROTATION.y, logic.ROTATION.z

    local function clearSlot(i)
        local s = slots[i]
        if s then
            if isElement(s.obj) then
                destroyElement(s.obj)
            end
            slots[i] = nil
        end
    end

    local function measure(model)
        local f = frames[model]
        if f ~= nil then
            return f or nil
        end
        local obj = createObject(model, 0, 0, -1000)
        if not obj then
            frames[model] = false
            return nil
        end
        setElementRotation(obj, rx, ry, rz)
        local minX, minY, minZ, maxX, maxY, maxZ = getElementBoundingBox(obj)
        local m = getElementMatrix(obj)
        destroyElement(obj)
        if not minX or not m then
            frames[model] = false
            return nil
        end
        f = logic.frame(minX, minY, minZ, maxX, maxY, maxZ, m)
        frames[model] = f
        return f
    end

    local function acquire(model)
        if not held[model] then
            engineStreamingRequestModel(model, true, true)
            held[model] = true
        end
    end

    function M.show(entries)
        shown = entries or {}
        for i in pairs(slots) do
            if i > #shown then
                clearSlot(i)
            end
        end
    end

    function M.hide()
        shown = {}
        for i in pairs(slots) do
            clearSlot(i)
        end
        for model in pairs(held) do
            engineStreamingReleaseModel(model, true)
        end
        held = {}
    end

    local function drawTinted(i, e, ox, oy, oz, sc)
        local s = slots[i]
        if s and (s.model ~= e.model or s.colour ~= e.itemType.colour or not isElement(s.obj)) then
            clearSlot(i)
            s = nil
        end
        if not s then
            local obj = createObject(e.model, ox, oy, oz, rx, ry, rz)
            if not obj then
                return
            end
            setElementCollisionsEnabled(obj, false)
            models.applyTint(obj, e.itemType, true)
            s = { obj = obj, model = e.model, colour = e.itemType.colour }
            slots[i] = s
        end
        setElementPosition(s.obj, ox, oy, oz)
        setElementRotation(s.obj, rx, ry, rz)
        setObjectScale(s.obj, sc, sc, sc)
        setElementInterior(s.obj, getElementInterior(localPlayer))
        setElementDimension(s.obj, getElementDimension(localPlayer))
    end

    local function draw(i, e)
        acquire(e.model)
        local f = measure(e.model)
        if not f then
            clearSlot(i)
            return
        end
        local a = e.area
        local px, py, pz = getWorldFromScreenPosition(a.cx, a.cy, logic.DEPTH)
        local bx, by, bz = getWorldFromScreenPosition(a.cx, a.cy + logic.PROBE, logic.DEPTH)
        if not px or not bx then
            clearSlot(i)
            return
        end
        local sc = logic.scale(f.radius, a, logic.metresPerPixel(px, py, pz, bx, by, bz))
        local ox, oy, oz = logic.origin(px, py, pz, f, sc)
        if models and models.hasTint(e.itemType) then
            drawTinted(i, e, ox, oy, oz, sc)
        else
            clearSlot(i)
            dxDrawModel3D(e.model, ox, oy, oz, rx, ry, rz, sc, sc, sc, logic.LIGHTING)
        end
    end

    addEventHandler("onClientPreRender", root, function()
        for i, e in ipairs(shown) do
            draw(i, e)
        end
    end)

    -- the models resource (re)started or stopped: SA-MP model ids are reassigned, so measurements and references
    -- taken under the old ids are dropped (the inventory renderer resolves and hands over fresh ids each frame)
    addEventHandler("sampModelsChanged", root, function()
        M.hide()
        frames = {}
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        M.hide()
    end)

    return M
end
