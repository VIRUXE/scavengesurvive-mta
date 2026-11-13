-- The tutorial's client side: the offer to a new character, the boxes that point at the HUD (upstream's four
-- textdraws) and the tips for what the inventory dialog shows (items raises the rest on the server).
-- luacheck: read_globals getPlayerHudComponentProperty getVehicleWheelStates getVehicleComponentPosition
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=tutorial/" .. path))()
end
local logic = loadFile("shared/logic/tutorial.lua")

-- luacheck: push ignore 631
-- lang:begin
local COMPLETE = "Tutorial complete! Type /tutorial to leave it."
local BAG_ON_GROUND = "A tap on [F] opens a bag lying on the ground; hold [F] to pick it up."
local CHECKLIST = "Checklist"
local GOOD = "Good!"
-- the checklist: one line per step of logic.STEPS
local STEP_LABELS = {
    "Open the bonnet",
    "Repair the engine",
    "Change the flat tyres",
    "Fill the tank",
    "Start the engine",
    "Drive",
}
-- what to do now, by the hint key the server sends (%s is the item's name)
local HINTS = {
    BONNET_OPEN = "Stand in front of the truck, hands empty, and press [F] to open the bonnet.",
    BONNET_EMPTY = "Put down what you hold with [N]. Then stand in front of the truck and press [F] to open the bonnet.",
    PICK_UP = "Pick up the %s from the ground: stand over it and press [F].",
    PUT_DOWN = "Put down what you hold with [N]. Then pick up the %s.",
    ENGINE_FIX = "With the %s in hand, stand at the open bonnet and press [F]. Wait until it is repaired.",
    TYRES_ENGINE_OFF = "The engine is on. Sit in the truck and press [Y] to turn it off.",
    TYRES_REMOVE = "Stand beside a flat wheel and press [F]. Click a nut and hold the mouse button until it is off. Do all 6.",
    TYRES_HUB = "The wheel is off. Pick up a spare Wheel and put it down beside the hub with [N]. Then hold the %s and press [F].",
    TYRES_PLACE = "Stand beside the empty hub and press [N] to put the wheel on the ground.",
    TYRES_FIT = "Press [F] beside the empty hub. Click a nut and hold the mouse button until it is on. Do all 6.",
    FUEL_POUR = "Stand at the front or side of the truck and press [F]. Stay still while it fills.",
    START_ENTER = "Get in the truck: stand by the driver's door and press [F].",
    START_EMPTY = "Put down what you hold with [N]. Then get in the truck: stand by the driver's door and press [F].",
    START_KEY = "Tap [Y] to turn the key. Then hold [Y] until the engine starts.",
    DRIVE = "Hold [W] to drive forward.",
}
-- a tip for the toast the game just showed, when a newcomer is likely to need more than the toast says
local TOAST_TIPS = {
    BONNET_SHUT = "Empty your hands first with [N]. Then press [F] in front of the truck to open the bonnet.",
    NEEDANOTOOL = "That tool has done its part. The checklist shows which one you need now.",
    WHEEL_LAY = "Press [N] to put the wheel on the ground beside the truck. Then hold the Tyre Wrench and press [F].",
    NO_FUEL = "The tank is empty. Fill it with the Petrol Can first.",
}
local NUTS = "Click a nut and hold the mouse button to turn it. Do all %d nuts."
-- lang:end
-- luacheck: pop

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
-- the server's guide: the step, what to do and the item it names
local stage, hint, tool, goodUntil = 0, nil, nil, 0
local tipAt = {} -- toast code -> when its tip was last shown
-- the marker over what to touch next, where it points and when that was last worked out
local arrowMarker, arrowTarget, arrowChecked

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

-- Wrapped on spaces only: dxDrawText's own word break also breaks after "/", splitting "/tutorial".
local function wrap(text, width, scale, font)
    local lines = {}
    for paragraph in (text .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in paragraph:gmatch("%S+") do
            local candidate = line == "" and word or (line .. " " .. word)
            if line ~= "" and dxGetTextWidth(candidate, scale, font) > width then
                lines[#lines + 1] = line
                line = word
            else
                line = candidate
            end
        end
        lines[#lines + 1] = line
    end
    return table.concat(lines, "\n"), #lines
end

local function textBox(c, text)
    local scale = canvas.textScale(c, 1.2, 1)
    local w = canvas.len(c, BOX_W)
    local pad = canvas.len(c, PAD)
    local n
    text, n = wrap(text, w - 2 * pad, scale, "default-bold")
    local h = n * dxGetFontHeight(scale, "default-bold") + 2 * pad
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
                false -- already wrapped
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

local GREEN, GREY, YELLOW = tocolor(120, 220, 120, 255), tocolor(170, 170, 170, 255), tocolor(0xE8, 0xE8, 0x90, 255)

local function hintText()
    local fmt = HINTS[hint]
    if not fmt then
        return ""
    end
    return tool and lang.format(fmt, lang.itemName(tool)) or lang.text(fmt)
end

-- One line per step with a tick box, the current one lit, and under them what to do now.
local function drawChecklist(c)
    if stage < 1 then
        return
    end
    local scale = canvas.textScale(c, 1.2, 1)
    local w = canvas.len(c, 170)
    local pad = canvas.len(c, PAD)
    local lineH = dxGetFontHeight(scale, "default-bold") + pad
    local x = canvas.x(c, 632, "right") - w
    local text, n = wrap(hintText(), w - 2 * pad, scale * 1.1, "default-bold")
    local hintH = n * dxGetFontHeight(scale * 1.1, "default-bold") + 2 * pad
    local h = pad + lineH * (#STEP_LABELS + 1) + hintH
    local y = math.min(canvas.y(c, 260), canvas.y(c, 470) - h) -- below the key list, within the screen
    dxDrawRectangle(x, y, w, h, BOX)
    local ty = y + pad
    dxDrawText(lang.text(CHECKLIST), x + pad, ty, x + w - pad, ty + lineH, WHITE, scale, "default-bold")
    local boxSize = lineH * 0.6
    for i, label in ipairs(STEP_LABELS) do
        ty = ty + lineH
        local colour = i < stage and GREEN or (i == stage and YELLOW or GREY)
        local bx, by = x + pad, ty + (lineH - boxSize) / 2
        dxDrawRectangle(bx, by, boxSize, boxSize, colour)
        if i < stage then
            dxDrawLine(bx + boxSize * 0.2, by + boxSize * 0.55, bx + boxSize * 0.45, by + boxSize * 0.8, BOX, 2)
            dxDrawLine(bx + boxSize * 0.45, by + boxSize * 0.8, bx + boxSize * 0.85, by + boxSize * 0.2, BOX, 2)
        else
            dxDrawRectangle(bx + 2, by + 2, boxSize - 4, boxSize - 4, BOX)
        end
        dxDrawText(
            lang.text(label),
            bx + boxSize + pad,
            ty,
            x + w - pad,
            ty + lineH,
            colour,
            scale,
            "default-bold",
            "left",
            "center"
        )
    end
    local hy = y + h - hintH
    dxDrawRectangle(x, hy, w, hintH, tocolor(0x30, 0x30, 0x10, 220))
    dxDrawText(text, x + pad, hy + pad, x + w - pad, hy + hintH - pad, WHITE, scale * 1.1, "default-bold")
    if getTickCount() < goodUntil then
        dxDrawText(
            lang.text(GOOD),
            x,
            y - lineH * 1.6,
            x + w,
            y,
            GREEN,
            scale * 1.6,
            "default-bold",
            "center",
            "bottom"
        )
    end
end

-- The Bobcat: the nearest vehicle in the tutorial's dimension.
local function bobcat()
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestD
    for _, v in ipairs(getElementsByType("vehicle", root, true)) do
        if getElementDimension(v) == getElementDimension(localPlayer) then
            local d = getDistanceBetweenPoints3D(px, py, pz, getElementPosition(v))
            if not bestD or d < bestD then
                best, bestD = v, d
            end
        end
    end
    return best
end

-- vehicle's own getVehicleWheelStates order (front-left, rear-left, front-right, rear-right)
local WHEELS = { "wheel_lf_dummy", "wheel_lb_dummy", "wheel_rf_dummy", "wheel_rb_dummy" }

local function nearestWheel(v, wanted)
    local px, py, pz = getElementPosition(localPlayer)
    local states = { getVehicleWheelStates(v) }
    local bx, by, bz, bestD
    for i, name in ipairs(WHEELS) do
        if wanted(states[i]) then
            local x, y, z = getVehicleComponentPosition(v, name, "world")
            if x then
                local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                if not bestD or d < bestD then
                    bx, by, bz, bestD = x, y, z, d
                end
            end
        end
    end
    return bx, by, bz
end

local function atComponent(v, name, fx, fy, fz)
    local x, y, z = getVehicleComponentPosition(v, name, "world")
    if x then
        return x, y, z
    end
    local m = getElementMatrix(v)
    return fx * m[1][1] + fy * m[2][1] + fz * m[3][1] + m[4][1],
        fx * m[1][2] + fy * m[2][2] + fz * m[3][2] + m[4][2],
        fx * m[1][3] + fy * m[2][3] + fz * m[3][3] + m[4][3]
end

-- Where the arrow goes for what the server asks of the player now, or nothing.
local function targetFor()
    if hint == "PICK_UP" and tool then
        local px, py, pz = getElementPosition(localPlayer)
        local bx, by, bz, bestD
        for _, obj in pairs(exports.items:worldObjectsOfType(tool) or {}) do
            if isElement(obj) and getElementDimension(obj) == getElementDimension(localPlayer) then
                local x, y, z = getElementPosition(obj)
                local d = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
                if not bestD or d < bestD then
                    bx, by, bz, bestD = x, y, z, d
                end
            end
        end
        return bx, by, bz
    end
    local v = bobcat()
    if not v then
        return
    end
    if stage <= 2 or stage == 4 then
        local x, y, z = atComponent(v, "bonnet_dummy", 0, 2.4, 0.6)
        return x, y, z
    elseif stage == 3 and hint ~= "TYRES_ENGINE_OFF" then
        return nearestWheel(v, function(state)
            return state ~= 0
        end)
    elseif stage == 5 and hint ~= "START_KEY" then
        return atComponent(v, "door_lf_dummy", -1.2, 0.4, 0.4)
    end
end

local function hideArrow()
    if isElement(arrowMarker) then
        destroyElement(arrowMarker)
    end
    arrowMarker = nil
end

addEventHandler("onClientRender", root, function()
    if not active or done or stage < 1 then
        return hideArrow()
    end
    local now = getTickCount()
    if not arrowChecked or now - arrowChecked > 250 then
        arrowChecked = now
        arrowTarget = { targetFor() }
    end
    local x, y, z = unpack(arrowTarget)
    if not x then
        return hideArrow()
    end
    if not isElement(arrowMarker) then
        arrowMarker = createMarker(x, y, z, "arrow", 0.9, 255, 230, 60, 220)
    end
    setElementDimension(arrowMarker, getElementDimension(localPlayer))
    setElementPosition(arrowMarker, x, y, z + 1.2 + 0.15 * math.sin(now / 250))
end)

addEventHandler("onClientRender", root, function()
    if not active or invOpen then
        return
    end
    local sw, sh = guiGetScreenSize()
    local c = canvas.new(sw, sh)
    local intro = math.floor((getTickCount() - startedAt) / STEP_MS) + 1
    if intro <= #STEPS then
        drawStep(intro, c, sw)
    end
    -- the checklist (where upstream said "type /exit"), right-hand side
    if done then
        local box = textBox(c, lang.text(COMPLETE))
        return box.draw(canvas.x(c, 632, "right") - box.w, canvas.y(c, 300))
    end
    drawChecklist(c)
end)

addEventHandler("tutorialStarted", root, function()
    active, done, invOpen, startedAt = true, false, false, getTickCount()
    stage, hint, tool = 0, nil, nil
end)

-- the server's guide: a step finished is cheered
addEventHandler("tutorialStepChanged", root, function(newStep, newHint, newTool)
    if stage > 0 and newStep > stage then
        goodUntil = getTickCount() + 1800
    end
    stage, hint, tool = newStep, newHint, newTool
    arrowChecked = nil
end)

-- a refusal or a result the newcomer may not understand: say what to do about it
addEventHandler("toastShown", localPlayer, function(code)
    local text = active and not done and TOAST_TIPS[code]
    local now = getTickCount()
    if text and now - (tipAt[code] or -10000) > 8000 then
        tipAt[code] = now
        exports.ui:tipShow(lang.text(text), false, logic.TIP_MS)
    end
end)

-- the lug nut view opens: how it is worked
addEventHandler("lugnutsStarted", root, function(count)
    if active and not done then
        exports.ui:tipShow(lang.format(NUTS, tonumber(count) or 6), false, logic.TIP_MS)
    end
end)

addEventHandler("tutorialCompleted", root, function()
    done = true
end)

addEventHandler("tutorialEnded", root, function()
    active, done, invOpen = false, false, false
    stage, hint, tool = 0, nil, nil
    hideArrow()
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
    elseif p.carryable then
        exports.ui:tipShow(lang.text(BAG_ON_GROUND), false, logic.TIP_MS)
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
