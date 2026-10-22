-- The death screen (core/player/death.pwn): a black screen with two small boxed lines, "YOU ARE DEAD!" at
-- 320,300 (font 1, 0.50/2.00) and the clickable ">Play Again<" at 320,323 (0.37/1.60), box colour 0x00000055.
-- Measured on the footage the two boxes merge into one 204 x 46 unit box.
local showing, cause = false, nil
local sw, sh = guiGetScreenSize()
local s = sh / 480
local BLACK = tocolor(0, 0, 0, 255)
local BOX = tocolor(0, 0, 0, 0x55)
local GREY = tocolor(255, 255, 255, 180)
local WHITE = tocolor(255, 255, 255, 255)
local LINE_UNITS = 9.8
local FONT = "default-bold"
local box = { x = 218, y = 321, w = 204, h = 46 }
local button = { x = 218, y = 345, w = 204, h = 16 }

local function text(str, yUnits, letterY, colour)
    local scale = letterY * LINE_UNITS * s / 15
    local x1, x2 = sw / 2 - 300 * s, sw / 2 + 300 * s
    local y = yUnits * s
    dxDrawText(str, x1 + 1, y + 1, x2 + 1, y + 1, BLACK, scale, FONT, "center", "top")
    dxDrawText(str, x1, y, x2, y, colour, scale, FONT, "center", "top")
end

local function draw()
    dxDrawRectangle(0, 0, sw, sh, BLACK)
    dxDrawRectangle(sw / 2 + (box.x - 320) * s, box.y * s, box.w * s, box.h * s, BOX)
    text("YOU ARE DEAD!", 327, 2.0, GREY)
    text(">Play Again<", 349, 1.6, WHITE)
    if cause then
        text(cause, 372, 1.2, GREY)
    end
end

addEventHandler("onClientCharacterDeathScreen", root, function(show, c)
    cause = c
    if show == showing then
        return
    end
    showing = show
    if show then
        addEventHandler("onClientRender", root, draw)
        showCursor(true)
        local x, y, z = getElementPosition(localPlayer)
        setCameraMatrix(x + 3, y + 3, z + 4, x, y, z)
    else
        removeEventHandler("onClientRender", root, draw)
        showCursor(false)
        setCameraTarget(localPlayer)
    end
end)

addEventHandler("onClientClick", root, function(btn, state, ax, ay)
    if not showing or btn ~= "left" or state ~= "down" then
        return
    end
    local bx = sw / 2 + (button.x - 320) * s
    if ax >= bx and ax <= bx + button.w * s and ay >= button.y * s and ay <= (button.y + button.h) * s then
        triggerServerEvent("onCharacterRequestRespawn", localPlayer)
    end
end)
