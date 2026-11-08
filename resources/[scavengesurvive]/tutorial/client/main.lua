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

-- The HUD's own canvas (ui): 640x480 units scaled by screenH/480, right-hand elements anchored to the right edge.
local function loadUi(path, name)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, name))()
end
local canvas = loadUi(":ui/shared/logic/canvas.lua", "=ui/canvas.lua")

-- A guided intro (upstream showed its four boxes all at once): one callout at a time, with the HUD element it
-- explains outlined and pulsing and an arrow to it, then only the goal box stays.
local STEP_MS = 6000
local STEPS = { "TUTORHPAPEN", "TUTORKEYSPR", "TUTORWATCHI" }
local BOX = tocolor(0, 0, 0, 170)
local WHITE = tocolor(255, 255, 255, 255)
local BOX_W, PAD, GAP = 150, 4, 14 -- canvas units

local active, done, invOpen, lastClose, startedAt = false, false, false, -10000, 0

local function language()
    return getElementData(localPlayer, "auth.lang") or "en"
end

local function say(key)
    exports.ui:tipShow(logic.clean(exports.data:t(language(), key)), false, logic.TIP_MS)
end

-- Pixel rectangle {x, y, w, h} of what a step points at.
local function stockRect(c, sw)
    -- GTA's health, armour and weapon icon: MTA reports where it draws them; otherwise their place at 4:3 scaling
    local ok, l, t, r, b = pcall(function()
        local x1, y1, x2, y2 = math.huge, math.huge, 0, 0
        for _, comp in ipairs({ "weapon", "health", "armour" }) do
            local pos = getPlayerHudComponentProperty(comp, "position")
            local size = getPlayerHudComponentProperty(comp, "size")
            if type(pos) ~= "table" or type(size) ~= "table" then
                error("no hud properties")
            end
            x1, y1 = math.min(x1, pos[1]), math.min(y1, pos[2])
            x2, y2 = math.max(x2, pos[1] + size[1]), math.max(y2, pos[2] + size[2])
        end
        return x1, y1, x2, y2
    end)
    if ok then
        return { x = l, y = t, w = r - l, h = b - t }
    end
    local x1 = canvas.x(c, 452, "right")
    return { x = x1, y = canvas.y(c, 35), w = sw - canvas.len(c, 40) - x1, h = canvas.len(c, 73) }
end

local function targetOf(step, c, sw)
    if step == "TUTORHPAPEN" then
        return stockRect(c, sw)
    elseif step == "TUTORKEYSPR" then
        -- the key list, right-aligned at x 618 from y 120 (hud drawKeyActions); a couple of lines' worth
        local x1 = canvas.x(c, 470, "right")
        return { x = x1, y = canvas.y(c, 117), w = canvas.x(c, 622, "right") - x1, h = canvas.len(c, 34) }
    end
    -- the watch: an ellipse centred at 87, 382.5, 108 x 89 units (hud/shared/logic/watch.lua)
    return { x = canvas.x(c, 33), y = canvas.y(c, 338), w = canvas.len(c, 108), h = canvas.len(c, 89) }
end

local function textBox(c, text)
    local scale = canvas.textScale(c, 1.2, 1)
    local w = canvas.len(c, BOX_W)
    local pad = canvas.len(c, PAD)
    local _, h = dxGetTextSize(text, w - 2 * pad, scale, "default-bold", true)
    h = (h or 0) + 2 * pad
    return {
        w = w,
        h = h,
        draw = function(bx, by)
            dxDrawRectangle(bx, by, w, h, BOX)
            dxDrawText(
                text,
                bx + pad,
                by + pad,
                bx + w - pad,
                by + h - pad,
                WHITE,
                scale,
                "default-bold",
                "left",
                "top",
                false,
                true
            )
        end,
    }
end

local function outline(r, colour, thick)
    local x2, y2 = r.x + r.w, r.y + r.h
    dxDrawLine(r.x, r.y, x2, r.y, colour, thick)
    dxDrawLine(x2, r.y, x2, y2, colour, thick)
    dxDrawLine(x2, y2, r.x, y2, colour, thick)
    dxDrawLine(r.x, y2, r.x, r.y, colour, thick)
end

local function arrow(x1, y1, x2, y2, colour, thick)
    dxDrawLine(x1, y1, x2, y2, colour, thick)
    local a = math.atan2(y2 - y1, x2 - x1)
    local len = thick * 6
    for _, d in ipairs({ 2.6, -2.6 }) do
        dxDrawLine(x2, y2, x2 + math.cos(a + d) * len, y2 + math.sin(a + d) * len, colour, thick)
    end
end

local function drawStep(index, c, sw)
    local key = STEPS[index]
    local target = targetOf(key, c, sw)
    -- the box wraps by itself: upstream's line breaks and its ">>" pointer (the arrow is drawn) go
    local text = logic.clean(exports.data:t(language(), key)):gsub("%s*>>%s*", " "):gsub("%s*\n%s*", " ")
    local box = textBox(c, text .. "\n" .. index .. "/" .. #STEPS)
    local gap = canvas.len(c, GAP)
    local bx, by, ax, ay, tx, ty
    if key == "TUTORWATCHI" then
        -- above the watch (the help tip sits to its right)
        bx, by = target.x, target.y - gap - box.h
        ax, ay, tx, ty = bx + box.w / 2, by + box.h, target.x + target.w / 2, target.y
    else
        -- to the left of the element, level with it
        bx, by = target.x - gap - box.w, target.y + target.h / 2 - box.h / 2
        ax, ay, tx, ty = bx + box.w, by + box.h / 2, target.x, target.y + target.h / 2
    end
    box.draw(bx, by)
    local pulse = 155 + 100 * math.abs(math.sin(getTickCount() / 300))
    local yellow = tocolor(0xE8, 0xE8, 0x90, pulse)
    local thick = math.max(3, canvas.len(c, 2))
    local pad = canvas.len(c, 3)
    outline({ x = target.x - pad, y = target.y - pad, w = target.w + 2 * pad, h = target.h + 2 * pad }, yellow, thick)
    arrow(ax, ay, tx, ty, yellow, thick)
end

addEventHandler("onClientRender", root, function()
    if not active or invOpen then
        return
    end
    local sw, sh = guiGetScreenSize()
    local c = canvas.new(sw, sh)
    local step = math.floor((getTickCount() - startedAt) / STEP_MS) + 1
    if step <= #STEPS then
        return drawStep(step, c, sw)
    end
    -- the goal (where upstream said "type /exit"), right-hand side
    local goal = textBox(c, lang.text(done and COMPLETE or GOAL))
    goal.draw(canvas.x(c, 632, "right") - goal.w, canvas.y(c, 300))
end)

addEventHandler("tutorialStarted", root, function()
    active, done, invOpen, startedAt = true, false, false, getTickCount()
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
