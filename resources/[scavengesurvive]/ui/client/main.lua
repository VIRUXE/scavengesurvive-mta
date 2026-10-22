-- dx UI kit entry: the shared canvas, the render loop and the exports (global wrappers).
-- The widgets are modules read from the downloaded files; docs/ui-reference-samp.md has the numbers.
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=ui/" .. path))()
end
local canvas = loadModule("shared/logic/canvas.lua")
local dialog = loadModule("shared/logic/dialog.lua")
local sw, sh = guiGetScreenSize()
local ctx = { canvas = canvas, dialog = dialog, c = canvas.new(sw, sh) }
ctx.draw = loadModule("client/draw.lua")(ctx)
local actionText = loadModule("client/actiontext.lua")(ctx)
local progress = loadModule("client/progress.lua")(ctx)
local list = loadModule("client/list.lua")(ctx)

addEventHandler("onClientRender", root, function()
    if list.isOpen() then
        list.draw()
    end
    progress.draw()
    actionText.draw()
end)

-- Exports (MTA needs global functions): other resources call exports.ui:actionText(...) etc.
function actionTextShow(text, ms)
    return actionText.show(text, ms)
end

function actionTextHide()
    return actionText.hide()
end

-- Older name kept for callers: a 3 s action text (the colour arguments are ignored, upstream is always white).
function toast(text)
    return actionText.show(text, 3000)
end

function progressStart(label, durationMs)
    return progress.start(label, durationMs)
end

function progressCancel()
    return progress.cancel()
end

function listOpen(listId, title, rows, buttons)
    return list.open(listId, title, rows, buttons)
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
