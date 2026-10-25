-- The whitelist countdown (upstream whitelist.pwn wl_CountdownUI: centred at 430, 40, font 1, 0.20 x 1.0, white,
-- outlined). The server sends the seconds left once (whitelistCountdownChanged) and false to hide it; the kick
-- itself is the server's timer.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local canvas = loadFile(":ui/shared/logic/canvas.lua", "=ui/canvas.lua")
local access = loadFile("shared/logic/access.lua", "=auth/access.lua")
local sw, sh = guiGetScreenSize()
local ctx = { canvas = canvas, c = canvas.new(sw, sh) }
local draw = loadFile(":ui/client/draw.lua", "=ui/draw.lua")(ctx)

local WHITE = tocolor(255, 255, 255, 255)
local ends = nil -- getTickCount() at which the countdown reaches zero

local function render()
    local left = math.ceil((ends - getTickCount()) / 1000)
    local text = access.countdownText(left)
    draw.text({
        text = text,
        x = 430,
        y = 40,
        font = 1,
        lx = 0.2,
        ly = 1.0,
        colour = WHITE,
        align = "center",
        outline = 1,
    })
end

addEventHandler("whitelistCountdownChanged", root, function(seconds)
    seconds = tonumber(seconds)
    if ends then
        removeEventHandler("onClientRender", root, render)
    end
    ends = seconds and getTickCount() + seconds * 1000 or nil
    if ends then
        addEventHandler("onClientRender", root, render)
    end
end)
