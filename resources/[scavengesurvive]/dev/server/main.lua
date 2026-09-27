local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local ready = false

local function say(p, fmt, ...)
    local msg = "[dev] " .. string.format(fmt, ...)
    if isElement(p) and getElementType(p) == "player" then
        outputChatBox(msg, p, 120, 200, 255)
    else
        outputServerLog(msg)
    end
end

local function allowed(p)
    if getElementType(p) == "console" then
        return true
    end
    if tostring(get("open")) == "true" then
        return true
    end
    local ok, level = pcall(function()
        return exports.auth:getAdminLevel(p)
    end)
    return ok and (tonumber(level) or 0) > 0
end

local function command(name, fn, consoleOk)
    addCommandHandler(name, function(p, _, ...)
        if getElementType(p) ~= "player" and not consoleOk then
            return say(p, "/%s is player-only", name)
        end
        if not allowed(p) then
            return say(p, "not allowed")
        end
        fn(p, ...)
    end)
end

local function setStat(key, hi)
    return function(p, value)
        local v = tonumber(value)
        if not v then
            return say(p, "usage: /set%s <0..%d>", key, hi)
        end
        local st = exports.character:getStats(p)
        if not st then
            return say(p, "no character loaded")
        end
        local now = exports.character:modifyStat(p, key, math.max(0, math.min(hi, v)) - st[key])
        say(p, "%s = %s", key, tostring(now))
    end
end

command("additem", function(p, uname)
    if not uname then
        return say(p, "usage: /additem <uname>")
    end
    if not ready then
        return say(p, "db not connected")
    end
    local x, y, z = getElementPosition(p)
    local params =
        { uname, nil, nil, x + 1, y, z - 0.9, 0, getElementInterior(p), getElementDimension(p), nil, nil, n = 11 }
    db.call("item_create", params, function(res, ctx)
        if not isElement(ctx.player) then
            return
        end
        if not res then
            return say(ctx.player, "item_create: db error (see logs/scripts.log)")
        end
        if not res.ok then
            return say(ctx.player, "item_create %s: code=%s", ctx.uname, res.code)
        end
        say(ctx.player, "created %s id=%s", ctx.uname, tostring(res.payload and res.payload.item_id))
        exports.items:refreshPlayer(ctx.player)
    end, { player = p, uname = uname })
end)

command("rollloot", function(p)
    local x, y = getElementPosition(p)
    exports.loot:rollNear(x, y, 400)
    say(p, "rollNear(%.0f, %.0f, 400) requested; due spawns appear within a few seconds", x, y)
end)

command("stats", function(p)
    local st = exports.character:getStats(p)
    if not st then
        return say(p, "no character loaded")
    end
    say(p, "hp=%.2f food=%.2f bleed=%.4f wounds=%d", st.hp, st.food, st.bleed, st.wounds or 0)
end)

command("sethp", setStat("hp", 100))
command("setfood", setStat("food", 100))
command("setbleed", setStat("bleed", 1))

command("dbtest", function(p)
    if not ready then
        return say(p, "db not connected")
    end
    local params = { "__dbtest__", nil, nil, 0, 0, 0, 0, 0, 0, nil, nil, n = 11 }
    db.call("item_create", params, function(res, ctx)
        if not isElement(ctx.player) then
            return
        end
        local ms = getTickCount() - ctx.t0
        if not res then
            return say(ctx.player, "dbtest: db error after %d ms", ms)
        end
        say(ctx.player, "dbtest: %d ms ok=%s code=%s", ms, tostring(res.ok), res.code)
    end, { player = p, t0 = getTickCount() })
end, true)

command("rr", function(p, name)
    local res = name and getResourceFromName(name)
    if not res then
        return say(p, "usage: /rr <resource>")
    end
    say(p, "restartResource(%s) -> %s", name, tostring(restartResource(res)))
end, true)

addEventHandler("onResourceStart", resourceRoot, function()
    ready = db.connect("dev")
end)
