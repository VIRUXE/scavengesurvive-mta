local showing, cause = false, nil
local sw, sh = guiGetScreenSize()

local function draw()
    local s = sh / 1080
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, 170))
    dxDrawText(
        "YOU ARE DEAD",
        0,
        sh * 0.35,
        sw,
        sh * 0.45,
        tocolor(200, 30, 30),
        3 * s,
        "default-bold",
        "center",
        "center"
    )
    local line = cause and ("Cause: " .. cause) or ""
    dxDrawText(line, 0, sh * 0.46, sw, sh * 0.5, tocolor(220, 220, 220), s, "default-bold", "center", "center")
    dxDrawText(
        "> Play Again <",
        0,
        sh * 0.55,
        sw,
        sh * 0.6,
        tocolor(255, 255, 255),
        1.5 * s,
        "default-bold",
        "center",
        "center"
    )
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

addEventHandler("onClientClick", root, function(button, state, _, ay)
    if not showing or button ~= "left" or state ~= "down" then
        return
    end
    if ay > sh * 0.55 and ay < sh * 0.6 then
        triggerServerEvent("onCharacterRequestRespawn", localPlayer)
    end
end)
