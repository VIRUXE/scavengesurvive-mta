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

command("vehcount", function(p)
    say(p, "%d loot vehicles", exports.vehicles:countVehicles())
end, true)

command("vehrespawn", function(p)
    local ok = exports.vehicles:respawnAll()
    say(
        p,
        ok and "all loot vehicles dropped; rolling the spawn points again (count in the server log)"
            or "a roll is already running"
    )
end, true)

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

command("weather", function(p, idOrName)
    if not idOrName then
        return say(p, "weather = %s; usage: /weather <0..19|NAME>", tostring(exports.world:getWeather()))
    end
    local id = exports.world:setGlobalWeather(idOrName)
    if not id then
        return say(p, "unknown weather %s", idOrName)
    end
    say(p, "weather = %d", id)
end, true)

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

-- HTTP "rcon" (MTA has no RCON): POST http://127.0.0.1:22005/dev/call/rcon with a JSON array holding one command
-- line, HTTP Basic auth as the account named by *dev.http_user (created below from *dev.http_pass; run-local.ps1
-- puts it in an ACL group that only grants general.http). Returns { ok, output = { lines } }.
-- Client: pwsh server-config/rcon.ps1 <command>. Built for scripts and LLM agents driving a local test server.
local RCON_HELP = {
    "help                          this list",
    "players                       connected players: name, character id, position",
    "start|stop|restart|rr <res>   resource control (rr = restart)",
    "cmd <player> <command> [args] run a chat command as that player, e.g. cmd Bob additem M9Pistol",
    "say <text>                    chat message to everyone",
    "lua <code>                    run server-side Lua and print its return values, e.g. lua return getPlayerCount()",
    "screenshot <player> [w h]     ask that client for a screenshot; saved as dev/screenshots/<player>-<time>.jpg",
    "key <player> <command|key>    run a bound command (interact, inventory) or client key (arrow_d, enter, escape)",
    "shutdown                      stop the server",
}
local RESOURCE_VERBS = { start = startResource, stop = stopResource, restart = restartResource, rr = restartResource }

local function describe(v)
    if type(v) == "table" then
        return toJSON(v)
    end
    if isElement(v) then
        return getElementType(v) .. ":" .. (getElementType(v) == "player" and getPlayerName(v) or getElementID(v))
    end
    return tostring(v)
end

function rcon(line)
    local verb, rest = tostring(line or ""):match("^%s*(%S+)%s*(.-)%s*$")
    local out, ok = {}, true
    local function put(fmt, ...)
        out[#out + 1] = string.format(fmt, ...)
    end
    if not verb or verb == "help" then
        for _, l in ipairs(RCON_HELP) do
            put("%s", l)
        end
    elseif verb == "players" then
        for _, p in ipairs(getElementsByType("player")) do
            local x, y, z = getElementPosition(p)
            put(
                "%s char=%s pos=%.1f,%.1f,%.1f",
                getPlayerName(p),
                tostring(exports.character:getCharacterId(p)),
                x,
                y,
                z
            )
        end
        if #out == 0 then
            put("no players")
        end
    elseif RESOURCE_VERBS[verb] then
        local res = rest ~= "" and getResourceFromName(rest)
        if not res then
            ok = false
            put("unknown resource '%s'", rest)
        else
            local r = RESOURCE_VERBS[verb](res)
            ok = r == true
            put("%s %s -> %s", verb, rest, tostring(r))
        end
    elseif verb == "cmd" then
        local who, cmd, args = rest:match("^(%S+)%s+(%S+)%s*(.-)$")
        local p = who and getPlayerFromName(who)
        if not p then
            ok = false
            put("no player '%s' (usage: cmd <player> <command> [args])", tostring(who))
        else
            ok = executeCommandHandler(cmd, p, args ~= "" and args or nil) == true
            put("%s ran /%s %s -> %s (the reply went to that player's chat)", who, cmd, args, tostring(ok))
        end
    elseif verb == "say" then
        outputChatBox("[rcon] " .. rest, root, 255, 200, 80)
        put("sent")
    elseif verb == "lua" then
        local chunk, err = loadstring(rest, "=rcon")
        if not chunk then
            ok = false
            put("compile error: %s", tostring(err))
        else
            local r = { pcall(chunk) }
            ok = table.remove(r, 1) == true
            if not ok then
                put("runtime error: %s", tostring(r[1]))
            elseif #r == 0 then
                put("ok (no return values)")
            else
                for i = 1, #r do
                    put("[%d] %s", i, describe(r[i]))
                end
            end
        end
    elseif verb == "screenshot" then
        local who, w, h = rest:match("^(%S+)%s*(%d*)%s*(%d*)$")
        local p = who and getPlayerFromName(who)
        if not p then
            ok = false
            put("no player '%s' (usage: screenshot <player> [width height])", tostring(who))
        else
            local tag = string.format("%s-%s", who, getRealTime().timestamp)
            -- local server: lift the default 5 kB/s upload cap so a 1080p frame arrives in a second, not a minute
            ok = takePlayerScreenShot(p, tonumber(w) or 1280, tonumber(h) or 720, tag, 90, 5000000, 50000) == true
            put("requested %s -> %s; the client uploads it within a few seconds", tag, tostring(ok))
        end
    elseif verb == "key" then
        local who, bound = rest:match("^(%S+)%s+(%S+)$")
        local p = who and getPlayerFromName(who)
        if not p then
            ok = false
            put("usage: key <player> <command>")
        else
            triggerClientEvent(p, "onClientDevKey", p, bound)
            put("%s pressed %s", who, bound)
        end
    elseif verb == "shutdown" then
        put("shutting down")
        setTimer(function()
            shutdown("rcon")
        end, 500, 1)
    else
        ok = false
        put("unknown command '%s'; try help", verb)
    end
    return { ok = ok, output = out }
end

-- the client renders the frame and uploads it (works in exclusive fullscreen, unlike a desktop capture);
-- the resource directory is junctioned to the repo, so screenshots/ is git-ignored
addEventHandler("onPlayerScreenShot", root, function(res, status, data, _, tag)
    if res ~= getThisResource() then
        return
    end
    if status ~= "ok" then
        return outputServerLog(string.format("[dev] screenshot %s from %s: %s", tag, getPlayerName(source), status))
    end
    local path = "screenshots/" .. tag .. ".jpg"
    local f = fileCreate(path)
    if not f then
        return outputServerLog("[dev] screenshot: cannot create " .. path)
    end
    fileWrite(f, data)
    fileClose(f)
    outputServerLog(string.format("[dev] screenshot saved: dev/%s (%d bytes)", path, #data))
end)

local function ensureRconAccount()
    local user, pass = get("http_user"), get("http_pass")
    if not user or user == "" or not pass or pass == "" then
        return outputServerLog("[dev] rcon disabled: set *dev.http_user and *dev.http_pass in settings.xml")
    end
    local acc = getAccount(user) or addAccount(user, pass)
    if not acc then
        return outputServerLog("[dev] rcon: could not create account '" .. user .. "'")
    end
    setAccountPassword(acc, pass) -- keep internal.db in step with settings.xml
    outputServerLog("[dev] rcon ready: POST /dev/call/rcon on the HTTP port as account '" .. user .. "'")
end

addEventHandler("onResourceStart", resourceRoot, function()
    ready = db.connect("dev")
    ensureRconAccount()
end)
