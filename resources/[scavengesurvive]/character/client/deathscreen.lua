-- The death screen (core/player/death.pwn): the camera slowly rises over the body while BrightnessUI (alpha 200)
-- darkens the screen over two global boxed textdraws, "YOU ARE DEAD!" at 320,300 (font 1, 0.50/2.00) and the
-- clickable ">Play Again<" at 320,323 (0.37/1.60), box colour 0x00000055. Measured on p52g-vd0syA @ 11:52.
local showing, startTick = false, 0
local deathPos = { x = 0, y = 0, z = 0, rz = 0 }
local sw, sh = guiGetScreenSize()
local s = sh / 480
local BLACK = tocolor(0, 0, 0, 255)
local OVERLAY = tocolor(0, 0, 0, 185)
local BOX = tocolor(0, 0, 0, 0x55)
local WHITE = tocolor(255, 255, 255, 255)
local HOVER = tocolor(255, 255, 255, 220)
local LINE_UNITS = 9.8
local X_STRETCH = 1.25
local FONT = "default-bold"
local box = { x = 213.3, y = 320, w = 213.3, h = 48 }
local button = { x = 213.3, y = 345, w = 213.3, h = 20 }

local function isHovered()
    if not isCursorShowing() then
        return false
    end
    local cx, cy = getCursorPosition()
    if not cx then
        return false
    end
    local ax, ay = cx * sw, cy * sh
    local bx = sw / 2 + (button.x - 320) * s
    return ax >= bx and ax <= bx + button.w * s and ay >= button.y * s and ay <= (button.y + button.h) * s
end

local function text(str, yUnits, letterY, colour)
    local scaleY = letterY * LINE_UNITS * s / 15
    local scaleX = scaleY * X_STRETCH
    local x1, x2 = sw / 2 - 300 * s, sw / 2 + 300 * s
    local y = yUnits * s
    local d = math.max(1, math.floor(s + 0.5))
    dxDrawText(str, x1 + d, y + d, x2 + d, y + d, BLACK, scaleX, scaleY, FONT, "center", "top")
    dxDrawText(str, x1, y, x2, y, colour, scaleX, scaleY, FONT, "center", "top")
end

local function updateCamera()
    local t = math.min(1, (getTickCount() - startTick) / 30000)
    local rad = math.rad(-deathPos.rz)
    local cx = deathPos.x - math.sin(rad)
    local cy = deathPos.y - math.cos(rad)
    local cz = deathPos.z + 1 + 19 * t
    setCameraMatrix(cx, cy, cz, deathPos.x, deathPos.y, deathPos.z + t)
end

local function draw()
    updateCamera()
    dxDrawRectangle(sw / 2 + (box.x - 320) * s, box.y * s, box.w * s, box.h * s, BOX)
    text("YOU ARE DEAD!", 325, 2.0, WHITE)
    local hover = isHovered()
    if not hover then
        text(">Play Again<", 349, 1.6, WHITE)
    end
    dxDrawRectangle(0, 0, sw, sh, OVERLAY)
    if hover then
        text(">Play Again<", 349, 1.6, HOVER)
    end
end

addEventHandler("onClientCharacterDeathScreen", root, function(show)
    if show == showing then
        return
    end
    showing = show
    if show then
        startTick = getTickCount()
        local x, y, z = getElementPosition(localPlayer)
        local _, _, rz = getElementRotation(localPlayer)
        deathPos = { x = x, y = y, z = z, rz = rz or 0 }
        addEventHandler("onClientRender", root, draw)
        showCursor(true)
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
