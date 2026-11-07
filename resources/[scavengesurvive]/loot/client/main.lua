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

-- smoke_flare blows along the effect's local Y axis, so a -90 pitch points it up instead of sideways (#112)
local FLARE_RX = -90

local function effectFor(ms, x, y, z)
    local fx = createEffect("smoke_flare", x, y, z, FLARE_RX, 0, 0)
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
        attachElements(fx, obj, 0, 0, 1.5, FLARE_RX, 0, 0)
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

-- Duty loot overlay: the loot points the server pushes to developer-level staff on duty (server/overlay.lua). A beam per point in
-- 150 m coloured by state, and a two-line label within 40 m. /lootspots hides or shows it.
local spots, spotsShown, spotsHinted = {}, true, false
local SPOT_COLOURS = {
    ready = { 80, 255, 80 },
    cooldown = { 255, 170, 40 },
    blocked = { 80, 220, 255 },
    nobudget = { 160, 160, 160 },
    disabled = { 255, 70, 70 },
}

addEventHandler("lootSpotsChanged", root, function(list)
    spots = type(list) == "table" and list or {}
    if #spots > 0 and not spotsHinted then
        spotsHinted = true
        outputChatBox(" >  Loot points shown while on duty. /lootspots hides them.", 255, 255, 0)
    end
end)

addCommandHandler("lootspots", function()
    spotsShown = not spotsShown
    outputChatBox(" >  Loot points " .. (spotsShown and "shown" or "hidden"), 255, 255, 0)
end)

local function spotText(s)
    if s.state == "ready" then
        return "Ready to roll"
    elseif s.state == "cooldown" then
        local m = math.ceil(s.dueIn / 60)
        return string.format("Cooldown %dh%02dm", math.floor(m / 60), m % 60)
    elseif s.state == "blocked" then
        return string.format("%d item(s) out: %s", s.outTotal, s.lying or "carried")
    elseif s.state == "nobudget" then
        return "Zone budget spent"
    end
    return "Disabled"
end

local function outlined(text, x, y, c, scale)
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 210), scale, "default-bold", "center", "center")
    dxDrawText(text, x, y, x, y, tocolor(c[1], c[2], c[3], 255), scale, "default-bold", "center", "center")
end

addEventHandler("onClientRender", root, function()
    if #spots == 0 or not spotsShown then
        return
    end
    local px, py, pz = getElementPosition(localPlayer)
    for _, s in ipairs(spots) do
        local dx, dy, dz = s.x - px, s.y - py, s.z - pz
        local d2 = dx * dx + dy * dy + dz * dz
        if d2 < 150 * 150 then
            local c = SPOT_COLOURS[s.state] or SPOT_COLOURS.ready
            dxDrawLine3D(s.x, s.y, s.z, s.x, s.y, s.z + 1.5, tocolor(c[1], c[2], c[3], 220), 3)
            if d2 < 40 * 40 then
                local sx, sy = getScreenFromWorldPosition(s.x, s.y, s.z + 1.7, 0.06)
                if sx then
                    local head = string.format("#%d  %s  %d%%  x%s  zone %s (%d left)", s.id, s.tbl, s.chance,
                        s.size, s.zone, s.left)
                    outlined(head, sx, sy, { 255, 255, 255 }, 0.9)
                    outlined(spotText(s), sx, sy + 14, c, 0.9)
                end
            end
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    spots = {}
end)
