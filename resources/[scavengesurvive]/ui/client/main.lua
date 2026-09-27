UI = { scale = 1, font = "default-bold" }
local sw, sh = guiGetScreenSize()
UI.sw, UI.sh = sw, sh
UI.scale = math.max(0.75, sh / 1080)
UI.list = nil

addEventHandler("onClientRender", root, function()
    if UI.list then
        UI.drawList()
    end
    UI.drawProgress()
    UI.drawToasts()
end)
