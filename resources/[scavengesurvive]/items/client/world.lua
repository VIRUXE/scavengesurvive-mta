-- World items as client-side objects with a name label, from the server's per-player sync deltas.
-- ctx = { models } from client/main.lua (client/models.lua).
return function(ctx)
    local models = ctx.models
    local ammo = ctx.ammo
    local objects = {} -- id -> { obj, uname, hp, x, y, z, name }
    local typeCache = {}

    local function itemType(uname)
        if typeCache[uname] == nil then
            typeCache[uname] = exports.data:itemType(uname) or false
        end
        return typeCache[uname] or nil
    end

    local function calibreName(cal)
        return exports.data:calibreName(cal)
    end

    local function defaultAmmo(cal)
        local list = cal and exports.data:ammoTypesForCalibre(cal)
        return list and list[1] or nil
    end

    local function isPitchedTent(r)
        if r.uname ~= "TentPack" or not r.data then
            return false
        end
        if r.data.pitched == true then
            return true
        end
        if type(r.data) == "table" and r.data[1] and r.data[1].pitched == true then
            return true
        end
        return false
    end

    local function formatName(t, r)
        if isPitchedTent(r) then
            return "Pitched Tent"
        end
        if ammo and t then
            local defA = t.categoryData and defaultAmmo(t.categoryData.calibre) or nil
            return ammo.displayName(t, r.data, itemType, calibreName, defA)
        end
        return t and t.name or r.uname
    end

    local function forget(id)
        local e = objects[id]
        if e then
            if isElement(e.obj) then
                destroyElement(e.obj)
            end
            objects[id] = nil
        end
    end

    addEventHandler("inventorySynced", resourceRoot, function(delta)
        for _, id in ipairs(delta.remove or {}) do
            forget(id)
        end
        for _, r in ipairs(delta.add or {}) do
            local t = itemType(r.uname)
            local isPitched = isPitchedTent(r)
            if not objects[r.id] then
                local z = r.z + (t and t.modelz or 0)
                local rx, ry = t and t.rotx or 0, t and t.roty or 0
                local modelId = isPitched and 3243 or models.forType(t)
                local obj = createObject(modelId, r.x, r.y, z, rx, ry, r.rz or 0)
                    or createObject(models.FALLBACK, r.x, r.y, z, rx, ry, r.rz or 0)
                if obj then
                    setElementCollisionsEnabled(obj, isPitched or false)
                    setElementInterior(obj, r.interior or 0)
                    setElementDimension(obj, r.dimension or 0)
                end
                objects[r.id] = {
                    obj = obj,
                    uname = r.uname,
                    hp = r.hp,
                    x = r.x,
                    y = r.y,
                    z = r.z,
                    name = formatName(t, r),
                }
            else
                local e = objects[r.id]
                local targetModel = isPitched and 3243 or models.forType(t)
                if isElement(e.obj) and getElementModel(e.obj) ~= targetModel then
                    setElementModel(e.obj, targetModel)
                    setElementCollisionsEnabled(e.obj, isPitched or false)
                end
                e.name = formatName(t, r)
            end
        end
    end)

    -- the SA-MP model pack came or went: world objects switch between real models and stand-ins in place
    models.onChanged(function()
        for _, e in pairs(objects) do
            if isElement(e.obj) then
                setElementModel(e.obj, models.forType(itemType(e.uname)))
            end
        end
    end)

    addEventHandler("onClientRender", root, function()
        local px, py, pz = getElementPosition(localPlayer)
        local _, sh = guiGetScreenSize()
        for _, e in pairs(objects) do
            local dx, dy, dz = e.x - px, e.y - py, e.z - pz
            local d2 = dx * dx + dy * dy + dz * dz
            if d2 < 15 * 15 then
                local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 0.5, 0, false)
                if sx then
                    local scale = (sh / 1080) * (d2 < 9 and 1.1 or 0.9)
                    dxDrawText(
                        e.name,
                        sx + 1,
                        sy + 1,
                        sx + 1,
                        sy + 1,
                        tocolor(0, 0, 0, 200),
                        scale,
                        "default-bold",
                        "center",
                        "center"
                    )
                    dxDrawText(
                        e.name,
                        sx,
                        sy,
                        sx,
                        sy,
                        tocolor(255, 255, 0, 230),
                        scale,
                        "default-bold",
                        "center",
                        "center"
                    )
                end
            end
        end
    end)

    addEventHandler("onClientResourceStop", resourceRoot, function()
        for id in pairs(objects) do
            forget(id)
        end
    end)
end
