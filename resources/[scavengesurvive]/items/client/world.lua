local FALLBACK_MODEL = 1271
local objects = {} -- id -> { obj, uname, hp, x, y, z, name }
local typeCache = {}

local function itemType(uname)
    if typeCache[uname] == nil then
        typeCache[uname] = exports.data:itemType(uname) or false
    end
    return typeCache[uname] or nil
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

addEventHandler("onClientItemsSync", resourceRoot, function(delta)
    for _, id in ipairs(delta.remove or {}) do
        forget(id)
    end
    for _, r in ipairs(delta.add or {}) do
        if not objects[r.id] then
            local t = itemType(r.uname)
            local z = r.z + (t and t.modelz or 0)
            local rx, ry = t and t.rotx or 0, t and t.roty or 0
            local obj = createObject(t and t.mtaModel or FALLBACK_MODEL, r.x, r.y, z, rx, ry, r.rz or 0)
                or createObject(FALLBACK_MODEL, r.x, r.y, z, rx, ry, r.rz or 0)
            if obj then
                setElementCollisionsEnabled(obj, false)
                setElementInterior(obj, r.interior or 0)
                setElementDimension(obj, r.dimension or 0)
            end
            objects[r.id] =
                { obj = obj, uname = r.uname, hp = r.hp, x = r.x, y = r.y, z = r.z, name = t and t.name or r.uname }
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
                dxDrawText(e.name, sx, sy, sx, sy, tocolor(255, 255, 0, 230), scale, "default-bold", "center", "center")
            end
        end
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("onItemsRequestReady", localPlayer)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for id in pairs(objects) do
        forget(id)
    end
end)
