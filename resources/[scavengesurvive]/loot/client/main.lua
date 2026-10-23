-- Supply drop visuals (a smoke trail on the falling crate and a smoke marker where it landed; upstream used the
-- SA-MP-only smoke object 18728, which is not in the model pack, so MTA's built-in effect replaces it) and the
-- landed crates: their label, and the interact key that opens them (upstream's SIF button next to the crate).
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=loot/" .. path))()
end
local drops = loadFile("shared/logic/drops.lua")

local function effectFor(ms, x, y, z)
    local fx = createEffect("smoke_flare", x, y, z)
    if not fx then
        return nil
    end
    setTimer(function(e)
        if isElement(e) then
            destroyElement(e)
        end
    end, ms, 1, fx)
    return fx
end

addEventHandler("supplyDropStarted", root, function(obj, x, y)
    if not isElement(obj) then
        return
    end
    local _, _, z = getElementPosition(obj)
    local fx = effectFor(10 * 60 * 1000, x, y, z + 1.5)
    if fx then
        attachElements(fx, obj, 0, 0, 1.5)
        addEventHandler("onClientElementDestroy", obj, function()
            if isElement(fx) then
                destroyElement(fx)
            end
        end)
    end
end)

addEventHandler("supplyCrateLanded", root, function(x, y, z)
    effectFor(3 * 60 * 1000, x, y, z + 0.5)
end)

-- Crates ------------------------------------------------------------------------------------------------------

-- The streamed-in crate objects carrying crate.id (set by the server on the first object of each crate).
local function streamedCrates()
    local out = {}
    for _, o in ipairs(getElementsByType("object", resourceRoot, true)) do
        local id = getElementData(o, "crate.id")
        if id then
            local x, y, z = getElementPosition(o)
            out[#out + 1] = { id = id, kind = getElementData(o, "crate.kind"), x = x, y = y, z = z }
        end
    end
    return out
end

local function crateNear()
    local px, py, pz = getElementPosition(localPlayer)
    return drops.crateAt(streamedCrates(), px, py, pz)
end

-- hud shows "Open supply crate" / "Open weapon cache" next to F: "supply" / "cache", or false
function nearbyCrate()
    local c = crateNear()
    return c and c.kind or false
end

-- hud's interact key: true when a crate took the press
function tryOpenCrate()
    local c = crateNear()
    if not c then
        return false
    end
    triggerServerEvent("supplyCrateOpenRequested", localPlayer, c.id)
    return true
end

addEventHandler("onClientRender", root, function()
    local px, py, pz = getElementPosition(localPlayer)
    local _, sh = guiGetScreenSize()
    for _, c in ipairs(streamedCrates()) do
        local dx, dy, dz = c.x - px, c.y - py, c.z - pz
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 < 20 * 20 then
            local sx, sy = getScreenFromWorldPosition(c.x, c.y, c.z + 1.2, 0, false)
            if sx then
                local scale = (sh / 1080) * (d2 < 9 and 1.1 or 0.9)
                local text = drops.TITLES[c.kind] or "Crate"
                local shadow, fill = tocolor(0, 0, 0, 200), tocolor(255, 255, 0, 230)
                dxDrawText(text, sx + 1, sy + 1, sx + 1, sy + 1, shadow, scale, "default-bold", "center", "center")
                dxDrawText(text, sx, sy, sx, sy, fill, scale, "default-bold", "center", "center")
            end
        end
    end
end)
