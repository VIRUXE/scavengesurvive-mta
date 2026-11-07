-- Dev tool: the sound browser /sfx opens. It walks GTA:SA's sound effects as playSFX numbers them (data/catalog.lua)
-- and plays each one it lands on: left/right the sound (on into the next bank), up/down the bank, page up/down the
-- container, K plays it again, J switches between plain and 3D (at the player, as a world sound would be), L marks
-- it: a chat line, a copy in the clipboard and an sfx.marked line in the server log. /sfx again closes it.
-- /sfx <playlist> (browser.LISTS, e.g. glass) walks only that list's sounds with left/right; up/down or page up/down
-- leave it for the whole catalog.
local function loadFile(path, name)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, name))()
end

local catalog = loadFile("data/catalog.lua", "=sfx/catalog.lua")
local browser = loadFile("shared/logic/browser.lua", "=sfx/browser.lua")

local open, pos, playing, threeD = false, nil, nil, false
local list, listName, listIndex = nil, nil, 1 -- a playlist being walked, or nil

local function stepSound(step)
    if list then
        listIndex = (listIndex - 1 + step) % #list + 1
        pos = browser.fromList(catalog, list, listIndex)
    else
        browser.stepSound(catalog, pos, step)
    end
end

local KEYS = {
    arrow_r = function()
        stepSound(1)
    end,
    arrow_l = function()
        stepSound(-1)
    end,
    arrow_u = function()
        list = nil
        browser.stepBank(catalog, pos, 1)
    end,
    arrow_d = function()
        list = nil
        browser.stepBank(catalog, pos, -1)
    end,
    pgup = function()
        list = nil
        browser.stepContainer(catalog, pos, 1)
    end,
    pgdn = function()
        list = nil
        browser.stepContainer(catalog, pos, -1)
    end,
    k = function() end, -- the same sound again
    j = function()
        threeD = not threeD
    end,
}

local function play()
    if isElement(playing) then
        stopSound(playing)
    end
    local name, bank, sound, _, loops = browser.describe(catalog, pos)
    if threeD then
        local x, y, z = getElementPosition(localPlayer)
        playing = playSFX3D(name, bank, sound, x, y, z, false)
    else
        playing = playSFX(name, bank, sound, false)
    end
    if playing and loops then -- a looped sound would go on for ever: a few seconds of it
        setTimer(function(s)
            if isElement(s) then
                stopSound(s)
            end
        end, 4000, 1, playing)
    end
end

local function onKey(key)
    KEYS[key]()
    play()
end

local function mark()
    local name, bank, sound = browser.describe(catalog, pos)
    local text = ('playSFX("%s", %d, %d)'):format(name, bank, sound)
    setClipboard(text)
    outputChatBox("[sfx] marked " .. text, 120, 220, 255)
    triggerServerEvent("sfxMarked", resourceRoot, name, bank, sound, list and ("%s #%d"):format(listName, listIndex))
end

local function draw()
    local name, bank, sound, len, loops, nSounds, nBanks = browser.describe(catalog, pos)
    local _, sh = guiGetScreenSize()
    local w, h = 430, 104
    local x, y = 24, math.floor(sh * 0.3) -- above the watch and the chat-free middle of the left edge
    dxDrawRectangle(x, y, w, h, tocolor(10, 12, 16, 210))
    dxDrawText(
        list and ("%s   %d of %d   (%s %d:%d)"):format(listName, listIndex, #list, name, bank, sound)
            or ("%s   bank %d/%d   sound %d/%d"):format(name, bank, nBanks - 1, sound, nSounds - 1),
        x + 12,
        y + 10,
        x + w,
        y + 34,
        tocolor(255, 255, 255),
        1.2,
        "default-bold"
    )
    dxDrawText(
        ('%.2f s%s   %s   playSFX("%s", %d, %d)'):format(
            len,
            loops and " loop" or "",
            threeD and "3D" or "2D",
            name,
            bank,
            sound
        ),
        x + 12,
        y + 38,
        x + w,
        y + 60,
        tocolor(170, 210, 255),
        1,
        "default"
    )
    dxDrawText(
        "<- -> sound   up/down bank   PgUp/PgDn container\nK again   J 2D/3D   L mark   /sfx closes",
        x + 12,
        y + 64,
        x + w,
        y + h,
        tocolor(160, 160, 160),
        1,
        "default"
    )
end

local function close()
    open = false
    for key in pairs(KEYS) do
        unbindKey(key, "down", onKey)
    end
    unbindKey("l", "down", mark)
    removeEventHandler("onClientRender", root, draw)
    if isElement(playing) then
        stopSound(playing)
    end
end

addEventHandler("sfxBrowserToggled", resourceRoot, function(container, bank, sound)
    if open and not container then
        return close()
    end
    if container and browser.LISTS[container] then -- a playlist, from its first sound (or the one numbered)
        list, listName, listIndex = browser.LISTS[container], container, tonumber(bank) or 1
        pos = browser.fromList(catalog, list, listIndex)
    else
        if container then
            list = nil
        end
        pos = browser.start(
            catalog,
            container or (pos and catalog.order[pos.c]) or "genrl",
            bank or (pos and pos.bank) or 0,
            sound or (pos and pos.sound) or 0
        )
    end
    if not open then
        open = true
        for key in pairs(KEYS) do
            bindKey(key, "down", onKey)
        end
        bindKey("l", "down", mark)
        addEventHandler("onClientRender", root, draw)
    end
    play()
end)
