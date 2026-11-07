-- Client half of staff: the CEGUI dialogs the server opens (client/dialogs.lua) and the staff panel
-- (client/panel.lua), the spectate banner with arrow-key cycling, and name tags over players when the server
-- turns them on. This resource shows the cursor itself while one of its windows is open.
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=staff/" .. path))()
end
local logic = loadFile("shared/logic/staff.lua")
local spectating = nil -- player element being watched
local nametags = false

addEventHandler("dutyWeatherChanged", root, function(weather)
    if type(weather) == "number" then
        setWeather(weather)
    end
end)

-- Windows open at once; the cursor and the no-binds-when-editing input mode follow the count.
local ctx = { logic = logic }
local openWindows, savedInputMode = 0, nil
function ctx.cursor(delta)
    openWindows = math.max(0, openWindows + delta)
    if openWindows == 1 and delta > 0 then
        savedInputMode = guiGetInputMode()
        guiSetInputMode("no_binds_when_editing")
        showCursor(true)
    elseif openWindows == 0 and delta < 0 then
        guiSetInputMode(savedInputMode or "allow_binds")
        showCursor(false)
    end
end
local dialogs = loadFile("client/dialogs.lua")(ctx)
local panel = loadFile("client/panel.lua")(ctx)

addEventHandler("staffListOpened", root, function(key, title, rows, buttons)
    dialogs.listOpen(key, title, rows, buttons)
end)

addEventHandler("staffListDismissed", root, function()
    dialogs.listDismiss()
end)

addEventHandler("staffDialogOpened", root, function(key, style, title, body, left, right)
    dialogs.dialogOpen(key, style, title, body, left, right)
end)

-- Escape answers the open dialog or closes the list, then the panel; swallowed so the main menu stays shut.
addEventHandler("onClientKey", root, function(button, press)
    if press and button == "escape" and (dialogs.escape() or panel.escape()) then
        cancelEvent()
    end
end)

-- Spectate banner and arrow keys (upstream spectate.pwn: left/right switch target).
local function cycleSpectate(dir)
    return function()
        if spectating and not isChatBoxInputActive() then
            triggerServerEvent("spectateRequested", localPlayer, dir)
        end
    end
end
local cyclePrev, cycleNext = cycleSpectate("prev"), cycleSpectate("next")

addEventHandler("spectateChanged", root, function(target)
    local was = spectating ~= nil
    spectating = isElement(target) and target or nil
    if spectating and not was then
        bindKey("arrow_l", "down", cyclePrev)
        bindKey("arrow_r", "down", cycleNext)
    elseif not spectating and was then
        unbindKey("arrow_l", "down", cyclePrev)
        unbindKey("arrow_r", "down", cycleNext)
    end
end)

addEventHandler("nametagsChanged", root, function(flag)
    nametags = flag == true
end)

local TAG_DISTANCE = 300
-- text with a one-pixel black shadow, centred on (x, y)
local function shadowText(text, x, y, colour, scale, font, alignY)
    dxDrawText(text, x + 1, y + 1, x + 1, y + 1, tocolor(0, 0, 0, 210), scale, font, "center", alignY or "center")
    dxDrawText(text, x, y, x, y, colour, scale, font, "center", alignY or "center")
end

local function drawNametags()
    local cx, cy, cz = getCameraMatrix()
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if p ~= localPlayer and not isPedDead(p) then
            local x, y, z = getPedBonePosition(p, 8)
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
            if dist < TAG_DISTANCE then
                local sx, sy = getScreenFromWorldPosition(x, y, z + 0.35, 0.06)
                if sx then
                    local scale = math.max(0.8, 1.6 - dist / 120)
                    local hp = math.floor(getElementHealth(p))
                    local text = string.format("%s  %d%%  %dm", getPlayerName(p), hp, dist)
                    shadowText(text, sx, sy, tocolor(255, 255, 0, 255), scale, "default-bold")
                end
            end
        end
    end
end

-- Duty ghosts: quit spots the server pushes to staff on duty (server/ghosts.lua). Each is a translucent frozen ped
-- plus a label; ages arrive relative to the moment the list was received so client clock skew does not matter.
local GHOST_DISTANCE = 150
local ghosts = {} -- { data..., ped, receivedAt }

local function clearGhosts()
    for _, g in ipairs(ghosts) do
        if isElement(g.ped) then
            destroyElement(g.ped)
        end
    end
    ghosts = {}
end

addEventHandler("staffGhostsChanged", root, function(list)
    clearGhosts()
    if type(list) ~= "table" then
        return
    end
    local now = getTickCount()
    for _, d in ipairs(list) do
        local ped = createPed(d.skin or 0, d.x, d.y, d.z, d.rz or 0)
        if ped then
            setElementInterior(ped, d.int or 0)
            setElementDimension(ped, d.dim or 0)
            setElementAlpha(ped, 120)
            setElementFrozen(ped, true)
            setElementCollisionsEnabled(ped, false)
            d.ped, d.receivedAt = ped, now
            ghosts[#ghosts + 1] = d
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, clearGhosts)

local function formatAge(seconds)
    if seconds < 60 then
        return seconds .. "s"
    end
    return math.floor(seconds / 60) .. "m"
end

local function drawGhosts()
    if #ghosts == 0 then
        return
    end
    local cx, cy, cz = getCameraMatrix()
    local interior, dimension = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local now = getTickCount()
    for _, g in ipairs(ghosts) do
        if (g.int or 0) == interior and (g.dim or 0) == dimension then
            local dist = getDistanceBetweenPoints3D(cx, cy, cz, g.x, g.y, g.z)
            if dist < GHOST_DISTANCE then
                local sx, sy = getScreenFromWorldPosition(g.x, g.y, g.z + 1.1, 0.06)
                if sx then
                    local age = (g.age or 0) + math.floor((now - g.receivedAt) / 1000)
                    local scale = math.max(0.8, 1.5 - dist / 100)
                    local text = string.format("%s  %s ago  %s  %dm", g.name, formatAge(age), g.reason or "Quit", dist)
                    shadowText(text, sx, sy, tocolor(140, 230, 255, 255), scale, "default-bold")
                end
            end
        end
    end
end

local function drawSpectate()
    if not isElement(spectating) then
        return
    end
    local sw, sh = guiGetScreenSize()
    local hp = math.floor(getElementHealth(spectating))
    local how = getPedOccupiedVehicle(spectating) and "in vehicle" or "on foot"
    local text = string.format("Spectating %s   hp %d   %s", getPlayerName(spectating), hp, how)
    shadowText(text, sw / 2, sh * 0.08, tocolor(255, 255, 0, 255), 1.6, "default-bold", "top")
    local hint = "<- / -> switch player     /free to stop"
    shadowText(hint, sw / 2, sh * 0.08 + 30, tocolor(220, 220, 220, 255), 1.1, "default", "top")
end

addEventHandler("onClientRender", root, function()
    if nametags then
        drawNametags()
    end
    drawGhosts()
    if spectating then
        drawSpectate()
    end
end)

-- /kick, /ban, /mute, /unmute and /restart (logic.CHAT_BRIDGED) are MTA console commands too; typed in chat
-- they would reach the server's hardcoded handler and the Default ACL's denial instead of the staff resource,
-- so the client forwards them with their arguments and the server cancels the hardcoded path.
for name in pairs(logic.CHAT_BRIDGED) do
    addCommandHandler(name, function(_, ...)
        triggerServerEvent("staffCommandIssued", localPlayer, name, table.concat({ ... }, " "))
    end)
end
