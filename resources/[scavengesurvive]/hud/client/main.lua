local bars
do
    local f = fileOpen("shared/logic/bars.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    bars = assert(loadstring(src, "=hud/bars.lua"))()
end
local sw, sh = guiGetScreenSize()
local scale = math.max(0.75, sh / 1080)
local stats = { hp = 100, food = 80, bleed = 0 }
local held = false
local typeCache = {}

addEventHandler("onClientCharacterStats", root, function(s)
    stats = s
end)
addEventHandler("onClientItemsHeld", root, function(item)
    held = item
end)

local function heldName()
    if not held then
        return "Empty hands"
    end
    if typeCache[held.uname] == nil then
        typeCache[held.uname] = exports.data:itemType(held.uname) or false
    end
    local t = typeCache[held.uname]
    return t and t.name or held.uname
end

local function keyHint(cmd, default)
    local key = getKeyBoundToCommand(cmd)
    return string.upper(key or default)
end

local function bar(l, index, kind, value)
    local y = l.y + index * (l.h + l.gap)
    local frac = bars.fill(value, kind == "bleed" and 1 or 100)
    local r, g, b = bars.colour(kind, frac)
    dxDrawRectangle(l.x - 2, y - 2, l.w + 4, l.h + 4, tocolor(0, 0, 0, 160))
    dxDrawRectangle(l.x, y, l.w * frac, l.h, tocolor(r, g, b, 220))
end

addEventHandler("onClientRender", root, function()
    local l = bars.layout(sw, sh, scale)
    bar(l, 0, "hp", stats.hp)
    bar(l, 1, "food", stats.food)
    if stats.bleed > 0 then
        bar(l, 2, "bleed", stats.bleed)
    end
    dxDrawText(
        heldName(),
        l.x,
        l.y - 24 * scale,
        l.x + l.w,
        l.y,
        tocolor(255, 255, 255, 230),
        scale,
        "default-bold",
        "left",
        "center"
    )
    local hints = string.format(
        "[%s] Interact  [%s] Drop  [%s] Put away  [%s] Inventory",
        keyHint("interact", "f"),
        keyHint("dropitem", "n"),
        keyHint("putaway", "y"),
        keyHint("inventory", "h")
    )
    dxDrawText(
        hints,
        l.x,
        sh - 24 * scale,
        sw,
        sh,
        tocolor(200, 200, 200, 200),
        scale * 0.85,
        "default",
        "left",
        "center"
    )
end)
