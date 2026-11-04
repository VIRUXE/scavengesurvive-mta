-- The driver's weapon heat bar (#151, upstream char/overheat.pwn): red, where upstream's player progress bar sat
-- (220, 380, 200 x 20 on SA-MP's 640 x 480 canvas), drawn as GTA's own bar with the ui resource's canvas, with
-- upstream's "Overheating!" over 80 % of the maximum.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local canvas = loadFile(":ui/shared/logic/canvas.lua", "=ui/canvas.lua")
local sw, sh = guiGetScreenSize()
local ctx = { canvas = canvas, c = canvas.new(sw, sh) }
local bar = loadFile(":ui/client/draw.lua", "=ui/draw.lua")(ctx)
local RED = tocolor(200, 0, 0, 255)
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local heat, max = nil, 40

local function draw()
    if not heat then
        return
    end
    bar.progressBar(220, 380, 200, 20, heat / max, 0xFF, 0, 0, 0xFF, "center")
    if heat > max * 0.8 then
        local top, bottom = canvas.y(ctx.c, 380 - 50), canvas.y(ctx.c, 380 - canvas.BAR_BORDER) - 4
        dxDrawText(lang.text("Overheating!"), 0, top, sw, bottom, RED, 2, "pricedown", "center", "bottom")
    end
end

addEventHandler("overheatChanged", localPlayer, function(value, maximum)
    if not heat then
        addEventHandler("onClientRender", root, draw)
    end
    heat, max = value, maximum
end)

addEventHandler("overheatEnded", localPlayer, function()
    if heat then
        removeEventHandler("onClientRender", root, draw)
    end
    heat = nil
end)
