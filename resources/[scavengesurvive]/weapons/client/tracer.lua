-- Client bullet tracer renderer (onClientPlayerWeaponFire + dxDrawLine3D).
local tracer
do
    local f = fileOpen("shared/logic/tracer.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    tracer = assert(loadstring(src, "=weapons/shared/logic/tracer.lua"))()
end

local active = {}
local COLOUR = tocolor(255, 230, 120, 220)

addEventHandler("onClientPlayerWeaponFire", root, function(_, _, _, hitX, hitY, hitZ, _, startX, startY, startZ)
    local ammoUname = getElementData(source, "items.ammo")
    if not tracer.isTracerAmmo(ammoUname) then
        return
    end
    if not startX or not hitX then
        return
    end
    local tr = tracer.spawn(startX, startY, startZ, hitX, hitY, hitZ, getTickCount())
    if tr then
        active[#active + 1] = tr
    end
end)

addEventHandler("onClientRender", root, function()
    if #active == 0 then
        return
    end
    local now = getTickCount()
    for i = #active, 1, -1 do
        local x1, y1, z1, x2, y2, z2 = tracer.segment(active[i], now)
        if not x1 then
            table.remove(active, i)
        else
            dxDrawLine3D(x1, y1, z1, x2, y2, z2, COLOUR, 2.0)
        end
    end
end)
