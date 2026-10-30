-- Client side of item tweaking (upstream core/world/item-tweak.pwn's player textdraws): the pad of eight buttons
-- on the right of the screen while the server has the player tweaking an item, the mouse shown with the walk key
-- (LALT) or hidden with the Move button so the player can step away from the item, Enter or Done to finish, and
-- a yellow arrow on a built defence showing the side it faces. Every click is a request; the server moves the item.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local canvas = loadFile(":ui/shared/logic/canvas.lua", "=ui/canvas.lua")
local tweak = loadFile("shared/logic/tweak.lua", "=building/tweak.lua")
local sw, sh = guiGetScreenSize()
local ctx = { canvas = canvas, c = canvas.new(sw, sh) }
local draw = loadFile(":ui/client/draw.lua", "=ui/draw.lua")(ctx)
local rects = tweak.layout(canvas, ctx.c)
local ARROW = tocolor(255, 220, 0, 230)
local REPEAT_MS = 150 -- a held move button keeps stepping
local state = nil -- { id, x, y, z, heading, arrow, labels, cursor }
local repeatTimer = nil

local function send(action)
    triggerServerEvent("itemTweakRequested", localPlayer, action)
end

local function stopRepeat()
    if isTimer(repeatTimer) then
        killTimer(repeatTimer)
    end
    repeatTimer = nil
end

local function setCursor(on)
    if not state or state.cursor == on then
        return
    end
    state.cursor = on
    showCursor(on)
end

local function close()
    if not state then
        return
    end
    stopRepeat()
    if state.cursor then
        showCursor(false)
    end
    state = nil
end

addEventHandler("itemTweakStarted", localPlayer, function(id, x, y, z, heading, arrow, labels)
    close()
    state = {
        id = id,
        x = x,
        y = y,
        z = z,
        heading = heading or 0,
        arrow = arrow == true,
        labels = labels or {},
        cursor = false,
    }
end)

addEventHandler("itemTweakUpdated", localPlayer, function(id, x, y, z, heading)
    if state and state.id == id then
        state.x, state.y, state.z, state.heading = x, y, z, heading or state.heading
    end
end)

addEventHandler("itemTweakFinished", localPlayer, function()
    close()
end)

addEventHandler("onClientRender", root, function()
    if not state then
        return
    end
    for i, b in ipairs(tweak.BUTTONS) do
        local label = b.label
        if b.id == "toggle" then
            label = state.cursor and (state.labels.move or "Move") or (state.labels.edit or "Edit: LALT")
        end
        draw.pxButton(rects[i], label)
    end
    if state.arrow then
        for _, l in ipairs(tweak.arrow(state.x, state.y, state.z, state.heading)) do
            dxDrawLine3D(l[1], l[2], l[3], l[4], l[5], l[6], ARROW, 4)
        end
    end
end)

addEventHandler("onClientClick", root, function(btn, pressState, ax, ay)
    if not state or not state.cursor or btn ~= "left" then
        return
    end
    if pressState == "up" then
        return stopRepeat()
    end
    local id = tweak.hit(rects, ax, ay)
    if id == "toggle" then
        setCursor(false)
    elseif id == "done" then
        send("done")
        close()
    elseif id and tweak.ACTIONS[id] then
        send(id)
        stopRepeat()
        repeatTimer = setTimer(send, REPEAT_MS, 0, id)
    end
end)

-- the walk key shows the mouse (and hides it again); Enter with the mouse up finishes, as upstream's key 16 did
local function toggleCursor()
    if state and not isChatBoxInputActive() and not isConsoleActive() then
        setCursor(not state.cursor)
    end
end

addEventHandler("onClientKey", root, function(key, press)
    if not state or not state.cursor or not press then
        return
    end
    if key == "enter" or key == "num_enter" then
        send("done")
        close()
        cancelEvent()
    end
end)

function tweakIsOpen()
    return state ~= nil
end

function tweakFinish()
    if state then
        send("done")
        close()
    end
    return true
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    bindKey("walk", "down", toggleCursor)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    unbindKey("walk", "down", toggleCursor)
    close()
end)
