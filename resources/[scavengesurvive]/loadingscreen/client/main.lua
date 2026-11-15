-- The loading screen: key art, logo and a download bar in place of MTA's transfer box, from the moment this
-- resource's own files arrive (download_priority_group 110, ahead of everything else) until the character spawns.
-- The login, register and language dialogs open on top of it. It depends on no other resource, and its one word of
-- text stays English: lib, data and the player's language only exist after the download it covers.
-- images/keyart.jpg and images/logo.png are copies of docs/images/key-art-hero.png and logo-reborn.png (128 px).
local screen
do
    local f = fileOpen("shared/logic/screen.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    screen = assert(loadstring(src, "=loadingscreen/screen.lua"))()
end

local LANG_KEY = "auth.lang" -- set by auth once the player is logged in
local EMBER = { 255, 122, 0 } -- the logo's glow
local TITLE, DOWNLOADING = "SCAVENGE & SURVIVE", "DOWNLOADING"

local sw, sh = guiGetScreenSize()
local s = sh / 1080
local state -- nil while the screen is not up

local function close()
    if not state then
        return
    end
    local st = state
    state = nil
    removeEventHandler("onClientRender", root, st.draw)
    removeEventHandler("onClientTransferBoxProgressChange", root, st.onProgress)
    removeEventHandler("onClientPlayerSpawn", localPlayer, st.onSpawn)
    for _, texture in ipairs({ st.art, st.logo }) do
        if isElement(texture) then
            destroyElement(texture)
        end
    end
    setTransferBoxVisible(true)
end

local function text(str, x, y, x2, y2, alpha, scale, font, alignX, r, g, b)
    local o = math.max(1, math.floor(2 * s))
    dxDrawText(str, x + o, y + o, x2 + o, y2 + o, tocolor(0, 0, 0, alpha * 0.8), scale, font, alignX, "bottom")
    dxDrawText(str, x, y, x2, y2, tocolor(r or 255, g or 255, b or 255, alpha), scale, font, alignX, "bottom")
end

local function draw()
    local st = state
    local now = getTickCount()
    local dt = now - st.lastTick
    st.lastTick = now
    local opacity = screen.opacity(now, st.spawnedAt)
    if opacity <= 0 then
        return close()
    end
    local a = 255 * opacity

    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, a))
    if st.art then
        dxDrawImageSection(0, 0, sw, sh, st.u, st.v, st.uw, st.uh, st.art, 0, 0, 0, tocolor(255, 255, 255, a))
    end
    dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, a * 0.25)) -- the dialogs read better on a dimmed picture
    local shadeTop, steps = math.floor(sh * 0.55), 48
    for i = 0, steps - 1 do
        local y = shadeTop + math.floor((sh - shadeTop) * i / steps)
        local y2 = shadeTop + math.floor((sh - shadeTop) * (i + 1) / steps)
        local k = (i + 1) / steps
        dxDrawRectangle(0, y, sw, y2 - y, tocolor(0, 0, 0, a * 0.85 * k * k))
    end

    local margin, logoSize = 56 * s, 104 * s
    local barY = sh - margin
    local logoY = barY - 28 * s - logoSize
    if st.logo then
        dxDrawImage(margin, logoY, logoSize, logoSize, st.logo, 0, 0, 0, tocolor(255, 255, 255, a))
    end
    local titleX = margin + logoSize + 22 * s
    text(TITLE, titleX, logoY, sw, logoY + logoSize * 0.62, a, 2.1 * s, "bankgothic", "left")
    text("REBORN", titleX, logoY, sw, logoY + logoSize * 0.95, a, 1.25 * s, "bankgothic", "left", unpack(EMBER))

    -- the bar is only there while files are coming in; a client with everything cached never sees it
    local downloading = isTransferBoxActive()
    st.barAlpha = screen.approach(st.barAlpha, downloading and 1 or 0, dt, 6)
    st.shown = screen.approach(st.shown, screen.fraction(st.done, st.total), dt, 8)
    local ba = a * st.barAlpha
    if ba >= 1 then
        local barW, barH = sw - margin * 2, math.max(3, math.floor(5 * s))
        dxDrawRectangle(margin, barY, barW, barH, tocolor(255, 255, 255, ba * 0.22))
        dxDrawRectangle(margin, barY, barW * st.shown, barH, tocolor(EMBER[1], EMBER[2], EMBER[3], ba))
        local label = st.total > 0 and (DOWNLOADING .. "   " .. screen.label(st.done, st.total)) or DOWNLOADING
        text(label, margin, 0, sw - margin, barY - 8 * s, ba, 1.4 * s, "default-bold", "right")
    end
end

local function open()
    local st = { done = 0, total = 0, shown = 0, barAlpha = 0, lastTick = getTickCount(), draw = draw }
    st.art = dxCreateTexture("images/keyart.jpg", "argb", false, "clamp") or nil
    st.logo = dxCreateTexture("images/logo.png", "argb", true, "clamp") or nil
    if st.art then
        st.u, st.v, st.uw, st.uh = screen.cover(sw, sh, dxGetMaterialSize(st.art))
    end
    function st.onProgress(done, total)
        st.done, st.total = tonumber(done) or 0, tonumber(total) or 0
    end
    function st.onSpawn()
        if st.spawnedAt then
            return
        end
        st.spawnedAt = getTickCount()
        -- no dialog is left to stay above the picture: fade out over what the hud starts drawing at the spawn
        removeEventHandler("onClientRender", root, draw)
        addEventHandler("onClientRender", root, draw, true, "low")
    end
    state = st
    setTransferBoxVisible(false)
    -- "high": drawn before the other resources' frames, so their dialogs and windows land on top
    addEventHandler("onClientRender", root, draw, true, "high")
    addEventHandler("onClientTransferBoxProgressChange", root, st.onProgress)
    addEventHandler("onClientPlayerSpawn", localPlayer, st.onSpawn)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    -- a restart of this resource under a player who is already in: nothing to cover, and no spawn left to end it
    if getElementData(localPlayer, LANG_KEY) then
        return
    end
    open()
end)

addEventHandler("onClientResourceStop", resourceRoot, close)
