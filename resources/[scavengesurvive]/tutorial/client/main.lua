-- The tutorial's client side: the offer to a new character, the boxes that point at the HUD (upstream's four
-- textdraws) and the tips for what the inventory dialog shows (items raises the rest on the server).
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=tutorial/" .. path))()
end
local logic = loadFile("shared/logic/tutorial.lua")

-- lang:begin
local GOAL = "To leave the tutorial, repair the Bobcat, fill its tank and drive it."
local COMPLETE = "Tutorial complete! Type /tutorial to leave it."
-- lang:end

-- upstream's textdraw boxes on its 640x448 screen: key, x, left edge y, right edge, centred
local LABELS = {
    { key = "TUTORKEYSPR", x = 390, y = 140, right = 480 },
    { key = "TUTORWATCHI", x = 8, y = 250, right = 158 },
    { key = "TUTORHPAPEN", x = 390, y = 20, right = 480 },
    { goal = true, x = 484, y = 280, right = 630 }, -- where upstream said "type /exit": what leaves the tutorial
}
local BOX = tocolor(0, 0, 0, 100)
local WHITE = tocolor(255, 255, 255, 255)

local active, done, invOpen, lastClose = false, false, false, -10000

local function language()
    return getElementData(localPlayer, "auth.lang") or "en"
end

local function say(key)
    exports.ui:tipShow(logic.clean(exports.data:t(language(), key)), false, logic.TIP_MS)
end

local function box(text, left, top, right, align)
    local sw, sh = guiGetScreenSize()
    local sx, sy = sw / 640, sh / 448
    local scale = sh / 700
    local l, t, r = left * sx, top * sy, right * sx
    local _, h = dxGetTextSize(text, r - l - 8, scale, "default-bold", true)
    dxDrawRectangle(l, t, r - l, h + 8, BOX)
    dxDrawText(text, l + 4, t + 4, r - 4, t + 4 + h, WHITE, scale, "default-bold", align or "left", "top", false, true)
end

addEventHandler("onClientRender", root, function()
    if active and not invOpen then
        for _, label in ipairs(LABELS) do
            local text
            if label.goal then
                text = lang.text(done and COMPLETE or GOAL)
            else
                text = logic.clean(exports.data:t(language(), label.key))
            end
            box(text, label.x, label.y, label.right)
        end
    end
end)

addEventHandler("tutorialStarted", root, function()
    active, done, invOpen = true, false, false
end)

addEventHandler("tutorialCompleted", root, function()
    done = true
end)

addEventHandler("tutorialEnded", root, function()
    active, done, invOpen = false, false, false
    exports.ui:listClose()
    exports.ui:tipHide()
end)

-- the overlay steps aside while a dialog is open (upstream hid it for the inventory and containers); a refresh the
-- server pushes after Equip or Use, right after the dialog closed, is not an opening
addEventHandler("inventoryOpened", localPlayer, function(p)
    if not active or invOpen or p.refresh or getTickCount() - lastClose < 2000 then
        return
    end
    invOpen = true
    if not p.trunk then
        say("TUTORINTINV")
    end
end)

addEventHandler("uiListClosed", root, function(listId)
    if listId == "inventory" then
        invOpen, lastClose = false, getTickCount()
    end
end)

addEventHandler("uiListActionSelected", root, function(listId, rowId, actionId)
    if active and listId == "inventory" and actionId == "select" and rowId == "nav:bag" then
        say("TUTORINTBAG")
    end
end)

addEventHandler("uiListActionsOpened", root, function(listId)
    if active and listId == "inventory" then
        say("TUTORITMOPT")
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("tutorialStateRequested", localPlayer)
end)
