-- World items as client-side objects with a name label, from the server's per-player sync deltas.
-- ctx = { models, ammo, tent } from client/main.lua. A pitched TentPack is six objects (shared/logic/tent.lua)
-- placed with upstream's SA-MP rotations as they are: SA-MP's CreateObject and MTA's createObject both go
-- through GTA's own ZXY CMatrix::SetRotate (#55).
return function(ctx)
    local models = ctx.models
    local ammo = ctx.ammo
    local tent = ctx.tent
    local objects = {} -- id -> { obj | parts, pitched, row, uname, hp, x, y, z, name }
    local shaders = {} -- tent material key -> shader, or false when its texture could not be read
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
            for _, part in ipairs(e.parts or {}) do
                if isElement(part) then
                    destroyElement(part)
                end
            end
            objects[id] = nil
        end
    end

    -- Upstream retextures the tent parts with stock GTA textures (SetDynamicObjectMaterial); here a replace
    -- shader carries the same texture, read from the stock model that owns it.
    local function materialShader(key)
        if shaders[key] == nil then
            local m = tent.MATERIALS[key]
            local found = engineGetModelTextures(m.model, m.texture)
            local texture = found and found[m.texture]
            local shader = texture and dxCreateShader("client/replace.fx") or nil
            if shader then
                dxSetShaderValue(shader, "Tex", texture)
            end
            shaders[key] = shader or false
        end
        return shaders[key] or nil
    end

    local function place(obj, r)
        setElementCollisionsEnabled(obj, false)
        setElementInterior(obj, r.interior or 0)
        setElementDimension(obj, r.dimension or 0)
    end

    -- The pitched tent: six objects around the pack. None collide, so whoever pitched it from the middle walks out.
    local function createTentParts(r)
        local parts = {}
        for _, p in ipairs(tent.parts(r.x, r.y, r.z, r.rz or 0)) do
            local model = models.forSamp(p.model) or models.FALLBACK
            local obj = createObject(model, p.x, p.y, p.z, p.rx, p.ry, p.rz)
                or createObject(models.FALLBACK, p.x, p.y, p.z, p.rx, p.ry, p.rz)
            if obj then
                place(obj, r)
                local shader = materialShader(p.material)
                if shader then
                    engineApplyShaderToWorldTexture(shader, "*", obj)
                end
                parts[#parts + 1] = obj
            end
        end
        return parts
    end

    local function createItemObject(r, t)
        local z = r.z + (t and t.modelz or 0)
        local rx, ry = t and t.rotx or 0, t and t.roty or 0
        local obj = createObject(models.forType(t), r.x, r.y, z, rx, ry, r.rz or 0)
            or createObject(models.FALLBACK, r.x, r.y, z, rx, ry, r.rz or 0)
        if obj then
            place(obj, r)
        end
        return obj
    end

    addEventHandler("inventorySynced", resourceRoot, function(delta)
        for _, id in ipairs(delta.remove or {}) do
            forget(id)
        end
        for _, r in ipairs(delta.add or {}) do
            local t = itemType(r.uname)
            local isPitched = isPitchedTent(r)
            local e = objects[r.id]
            if e and e.pitched ~= isPitched then
                forget(r.id) -- pitched or packed in place: the row comes again and the objects are rebuilt
                e = nil
            end
            if e then
                e.name = formatName(t, r)
                if isElement(e.obj) then -- the row came again because it moved or turned (a door swung)
                    setElementPosition(e.obj, r.x, r.y, r.z + (t and t.modelz or 0))
                    setElementRotation(e.obj, t and t.rotx or 0, t and t.roty or 0, r.rz or 0)
                end
            else
                e = {
                    pitched = isPitched,
                    row = r,
                    uname = r.uname,
                    hp = r.hp,
                    x = r.x,
                    y = r.y,
                    z = r.z,
                    name = formatName(t, r),
                }
                if isPitched then
                    e.parts = createTentParts(r)
                else
                    e.obj = createItemObject(r, t)
                end
                objects[r.id] = e
            end
        end
    end)

    -- the SA-MP model pack came or went: world objects switch between real models and stand-ins in place
    models.onChanged(function()
        for _, e in pairs(objects) do
            if e.parts then
                for _, part in ipairs(e.parts) do
                    if isElement(part) then
                        destroyElement(part)
                    end
                end
                e.parts = createTentParts(e.row)
            elseif isElement(e.obj) then
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
