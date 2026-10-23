-- Live gear tile previews, client side: the inventory renderer says which models sit in which tile areas and
-- this module draws them every frame with dxDrawModel3D, in world space just in front of the camera at the point
-- under each tile centre (the dx UI leaves the tile centre see-through, like upstream's 0xFFFFFF08 tile fill).
-- Each model is measured once through a throwaway object (bounding box + rotation matrix) and held in the
-- streamer while shown. ctx = { logic = shared/logic/preview.lua }.
return function(ctx)
    local logic = ctx.logic
    local M = { logic = logic }
    local shown = {} -- { { model = id, area = logic.area(...) }, ... } for the current dialog
    local held = {} -- model id -> true while this resource holds a streaming reference
    local frames = {} -- model id -> logic.frame(...) or false when the model cannot be measured
    local rx, ry, rz = logic.ROTATION.x, logic.ROTATION.y, logic.ROTATION.z

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
    end

    function M.hide()
        shown = {}
        for model in pairs(held) do
            engineStreamingReleaseModel(model, true)
        end
        held = {}
    end

    local function draw(e)
        acquire(e.model)
        local f = measure(e.model)
        if not f then
            return
        end
        local a = e.area
        local px, py, pz = getWorldFromScreenPosition(a.cx, a.cy, logic.DEPTH)
        local bx, by, bz = getWorldFromScreenPosition(a.cx, a.cy + logic.PROBE, logic.DEPTH)
        if not px or not bx then
            return
        end
        local sc = logic.scale(f.radius, a, logic.metresPerPixel(px, py, pz, bx, by, bz))
        local ox, oy, oz = logic.origin(px, py, pz, f, sc)
        dxDrawModel3D(e.model, ox, oy, oz, rx, ry, rz, sc, sc, sc, logic.LIGHTING)
    end

    addEventHandler("onClientPreRender", root, function()
        for _, e in ipairs(shown) do
            draw(e)
        end
    end)

    -- the models resource (re)started or stopped: SA-MP model ids are reassigned, so measurements and references
    -- taken under the old ids are dropped (the inventory renderer resolves and hands over fresh ids each frame)
    addEventHandler("sampModelsChanged", root, function()
        M.hide()
        frames = {}
    end)

    return M
end
