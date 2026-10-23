-- Client half of staff: draws the server's list dialogs through ui, relays their actions back, shows the
-- spectate banner with arrow-key cycling, and draws name tags over players when the server turns them on.
local listKey = nil
local spectating = nil -- player element being watched
local nametags = false

addEventHandler("staffListOpened", root, function(key, title, rows, buttons)
    listKey = key
    exports.ui:listOpen("staff:" .. key, title, rows, buttons)
end)

addEventHandler("staffListDismissed", root, function()
    if listKey then
        exports.ui:listClose()
    end
    listKey = nil
end)

addEventHandler("uiListActionSelected", root, function(listId, rowId, actionId)
    local key = tostring(listId):match("^staff:(.+)$")
    if not key or key ~= listKey then
        return
    end
    triggerServerEvent("staffListActionSelected", localPlayer, key, rowId, actionId)
end)

addEventHandler("uiListClosed", root, function(listId)
    local key = tostring(listId):match("^staff:(.+)$")
    if key and key == listKey then
        listKey = nil
        triggerServerEvent("staffListClosed", localPlayer, key)
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
    if spectating then
        drawSpectate()
    end
end)

-- /kick, /ban, /mute, /unmute and /restart (logic.CHAT_BRIDGED) are MTA console commands too; typed in chat
-- they would reach the server's hardcoded handler and the Default ACL's denial instead of the staff resource,
-- so the client forwards them with their arguments and the server cancels the hardcoded path.
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=staff/" .. path))()
end
local logic = loadFile("shared/logic/staff.lua")
for name in pairs(logic.CHAT_BRIDGED) do
    addCommandHandler(name, function(_, ...)
        triggerServerEvent("staffCommandIssued", localPlayer, name, table.concat({ ... }, " "))
    end)
end
