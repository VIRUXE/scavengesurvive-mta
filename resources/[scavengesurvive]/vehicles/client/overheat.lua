-- The driver's weapon heat bar (#151, upstream char/overheat.pwn): red, where upstream's player progress bar sat
-- (220, 380, 200 x 20 on SA-MP's 640 x 480 canvas), with upstream's "Overheating!" over 80 % of the maximum.
local heat, max = nil, 40

local function draw()
    if not heat then
        return
    end
    local sw, sh = guiGetScreenSize()
    local x, y, w, h = 220 / 640 * sw, 380 / 480 * sh, 200 / 640 * sw, 20 / 480 * sh
    local fill = math.max(0, math.min(1, heat / max))
    dxDrawRectangle(x - 2, y - 2, w + 4, h + 4, tocolor(0, 0, 0, 200))
    dxDrawRectangle(x, y, w, h, tocolor(90, 0, 0, 200))
    dxDrawRectangle(x, y, w * fill, h, tocolor(255, 0, 0, 230))
    if heat > max * 0.8 then
        local red = tocolor(200, 0, 0, 255)
        dxDrawText("Overheating!", 0, y - h * 2.5, sw, y - 4, red, 2, "pricedown", "center", "bottom")
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
