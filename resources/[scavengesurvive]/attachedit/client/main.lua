-- Attachment editor, client side. /attachedit <slot> opens it on the local player's attachment in that slot,
-- starting from the live values (items' getAttachConfig); every nudge goes to items' setAttachPreview, which
-- replaces the configured values on this client only. Keys are taken through onClientKey only while the editor is
-- open, and cancelled there, so no GTA control or MTA bind on them fires meanwhile (rcon "key" presses arrive the
-- same way). Enter sends the row to the server, which logs it and appends it to attachedit-out.lua; Escape clears
-- the preview and closes.
local logic
do
    local f = fileOpen("shared/logic/attachedit.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    logic = assert(loadstring(src, "=attachedit/logic.lua"))()
end

local state -- the open editor (logic.new), or nil
local previewed = {} -- slots this resource set a preview on, cleared when it stops
local FONT = "default-bold"
local LINE_H = 16

local function itemsRunning()
    local res = getResourceFromName("items")
    return res and getResourceState(res) == "running"
end

local function getConfig(slot)
    if not itemsRunning() then
        return nil
    end
    return exports.items:getAttachConfig(slot)
end

local function report(slot, cfg)
    triggerServerEvent("attachEditConfigReported", localPlayer, slot, cfg or false)
end

-- offsets nil clears the preview; returns the attachment's config afterwards (nil when the slot shows nothing)
local function setPreview(slot, offsets, scale)
    if not itemsRunning() then
        return nil
    end
    local cfg = exports.items:setAttachPreview(slot, offsets, scale)
    previewed[slot] = offsets and true or nil
    report(slot, cfg)
    return cfg
end

local function render()
    if not state then
        return
    end
    local lines = logic.describe(state)
    local x, y = 24, 220
    dxDrawRectangle(x - 8, y - 6, 560, #lines * LINE_H + 12, tocolor(0, 0, 0, 170), true)
    for i, line in ipairs(lines) do
        local selected = line:sub(1, 1) == ">"
        local colour = (i == 1 and tocolor(120, 200, 255))
            or (selected and tocolor(255, 220, 90))
            or tocolor(230, 230, 230)
        -- postGUI = true: takePlayerScreenShot leaves post-GUI draws out, so rcon screenshots stay clean
        dxDrawText(line, x, y + (i - 1) * LINE_H, x + 544, 0, colour, 1, FONT, "left", "top", false, false, true)
    end
end

local onKey

local function close(clear)
    if not state then
        return
    end
    local slot = state.slot
    state = nil
    removeEventHandler("onClientKey", root, onKey)
    removeEventHandler("onClientRender", root, render)
    if clear then
        setPreview(slot, nil)
    end
end

local function save()
    local cfg = getConfig(state.slot)
    if cfg then
        state.uname, state.skin, state.bone = cfg.uname, cfg.skin, cfg.bone
    end
    local entry = logic.formatEntry(state.uname, state.skin, state.slot, state.values)
    outputChatBox("[attachedit] " .. entry, 120, 200, 255)
    triggerServerEvent("attachEditSaveRequested", localPlayer, state.slot, state.uname, state.skin, state.values)
end

onKey = function(key, down)
    if not state or not down or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then
        return
    end
    local result = logic.handleKey(state, key)
    if not result then
        return
    end
    cancelEvent()
    if result == "changed" then
        local offsets, scale = logic.split(state.values)
        local cfg = setPreview(state.slot, offsets, scale)
        if cfg then
            state.uname, state.skin, state.bone = cfg.uname, cfg.skin, cfg.bone
        end
    elseif result == "save" then
        save()
    elseif result == "cancel" then
        close(true)
        outputChatBox("[attachedit] cancelled; preview cleared", 120, 200, 255)
    end
end

local function open(slot)
    local cfg = getConfig(slot)
    if not cfg then
        return outputChatBox(
            "[attachedit] nothing attached in " .. slot .. " (empty, or a weapon GTA draws itself)",
            255,
            160,
            80
        )
    end
    state = logic.new(cfg)
    addEventHandler("onClientKey", root, onKey, true, "high")
    addEventHandler("onClientRender", root, render)
end

-- /attachedit <slot> (checked on the server): same slot closes, keeping the preview; another slot switches
addEventHandler("attachEditToggled", root, function(slot)
    if state and state.slot == slot then
        close(false)
        return outputChatBox("[attachedit] closed; the preview stays (Escape in the editor clears it)", 120, 200, 255)
    end
    close(false)
    open(slot)
end)

-- rcon "attach <player> <slot> x y z rx ry rz [sx sy sz]" or "off" (offsets false)
addEventHandler("attachEditPreviewChanged", root, function(slot, offsets, scale)
    local cfg = setPreview(slot, offsets or nil, offsets and scale or nil)
    if state and state.slot == slot then
        if offsets then
            state.values = logic.join(offsets, scale)
        elseif cfg then
            state = logic.new(cfg)
        end
    end
end)

addEventHandler("attachEditConfigRequested", root, function(slot)
    report(slot, getConfig(slot))
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    close(false)
    for slot in pairs(previewed) do
        setPreview(slot, nil)
    end
end)
