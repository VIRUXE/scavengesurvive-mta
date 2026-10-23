-- Client half of staff: draws the server's list dialogs through ui, relays their actions back, shows the
-- spectate banner with arrow-key cycling, and draws name tags over players when the server turns them on.
local listKey = nil
local spectating = nil -- player element being watched
local nametags = false

local function uiRunning()
    local ui = getResourceFromName("ui")
    return ui and getResourceState(ui) == "running"
end

addEventHandler("staffListOpened", root, function(key, title, rows, buttons)
    if not uiRunning() then
        return outputChatBox("[staff] ui resource is not running", 255, 100, 100)
    end
    listKey = key
    exports.ui:listOpen("staff:" .. key, title, rows, buttons)
end)

addEventHandler("staffListDismissed", root, function()
    if listKey and uiRunning() then
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
                    dxDrawText(
                        text,
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
                        text,
                        sx,
                        sy,
                        sx,
                        sy,
                        tocolor(255, 255, 0, 255),
                        scale,
                        "default-bold",
                        "center",
                        "center"
                    )
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
    local text = string.format(
        "Spectating %s   hp %d   %s",
        getPlayerName(spectating),
        math.floor(getElementHealth(spectating)),
        getPedOccupiedVehicle(spectating) and "in vehicle" or "on foot"
    )
    dxDrawText(
        text,
        1,
        sh * 0.08 + 1,
        sw + 1,
        sh * 0.08 + 1,
        tocolor(0, 0, 0, 220),
        1.6,
        "default-bold",
        "center",
        "top"
    )
    dxDrawText(text, 0, sh * 0.08, sw, sh * 0.08, tocolor(255, 255, 0, 255), 1.6, "default-bold", "center", "top")
    local hint = "<- / -> switch player     /free to stop"
    dxDrawText(
        hint,
        0,
        sh * 0.08 + 30,
        sw,
        sh * 0.08 + 30,
        tocolor(220, 220, 220, 255),
        1.1,
        "default",
        "center",
        "top"
    )
end

addEventHandler("onClientRender", root, function()
    if nametags then
        drawNametags()
    end
    if spectating then
        drawSpectate()
    end
end)
