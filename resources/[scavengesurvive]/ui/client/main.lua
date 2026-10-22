-- dx UI kit entry: the screen metrics every widget shares, the render loop, and the exports (global wrappers).
-- The widgets are modules read from the downloaded files (client/toast.lua, client/progress.lua, client/list.lua).
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=ui/" .. path))()
end
local sw, sh = guiGetScreenSize()
local ui = { sw = sw, sh = sh, scale = math.max(0.75, sh / 1080), font = "default-bold" }
ui.layout = loadModule("shared/logic/listlayout.lua")
local toasts = loadModule("client/toast.lua")(ui)
local progress = loadModule("client/progress.lua")(ui)
local list = loadModule("client/list.lua")(ui)

addEventHandler("onClientRender", root, function()
    if list.isOpen() then
        list.draw()
    end
    progress.draw()
    toasts.draw()
end)

-- Exports (MTA needs global functions): other resources call exports.ui:toast(...) etc.
function toast(text, r, g, b)
    return toasts.show(text, r, g, b)
end

function progressStart(label, durationMs)
    return progress.start(label, durationMs)
end

function progressCancel()
    return progress.cancel()
end

function listOpen(listId, title, rows)
    return list.open(listId, title, rows)
end

function listUpdate(listId, rows)
    return list.update(listId, rows)
end

function listClose()
    return list.close()
end

function listIsOpen()
    return list.isOpen()
end
