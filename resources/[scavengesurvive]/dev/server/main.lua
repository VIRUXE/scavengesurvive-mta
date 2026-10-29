local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local ready = false

local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local itemSpawnLogic = loadFile("shared/logic/item_spawn.lua", "=dev/item_spawn_logic.lua")

-- Chat lines as each client saw them (client/main.lua forwards onClientChatMessage), oldest first, 100 kept.
local CHAT_KEEP = 100
local chatSeen = {} -- player -> { { at = "HH:MM:SS", text = s }, ... }
net.handler("devChatLineReceived", function(player, text)
    local lines = chatSeen[player] or {}
    chatSeen[player] = lines
    local t = getRealTime()
    local at = string.format("%02d:%02d:%02d", t.hour, t.minute, t.second)
    lines[#lines + 1] = { at = at, text = (tostring(text):gsub("#%x%x%x%x%x%x", "")) }
    if #lines > CHAT_KEEP then
        table.remove(lines, 1)
    end
end, { rate = 60 })
addEventHandler("onPlayerQuit", root, function()
    chatSeen[source] = nil
end)

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

function isItemSpawnAllowed(p)
    if not isElement(p) then
        return getElementType(p) == "console"
    end
    if getElementType(p) == "console" then
        return true
    end
    local isOpen = tostring(get("open")) == "true"
    local okLevel, level = pcall(function()
        return exports.auth:getAdminLevel(p)
    end)
    local adminLevel = okLevel and tonumber(level) or 0
    local pName = getPlayerName(p)
    local okAccName, accName = pcall(function()
        return exports.auth:getAccountName(p)
    end)
    local okAccId, accId = pcall(function()
        return exports.auth:getAccountId(p)
    end)
    local allowedList = get("item_spawners")
    return itemSpawnLogic.isAllowed({
        isConsole = false,
        isOpen = isOpen,
        adminLevel = adminLevel,
        playerName = pName,
        accountName = okAccName and accName or nil,
        accountId = okAccId and accId or nil,
        allowedList = allowedList,
    })
end

local function logItemSpawn(p, uname, itemId, x, y, z)
    local okLevel, lvl = pcall(function()
        return exports.auth:getAdminLevel(p)
    end)
    local actorLevel = okLevel and tonumber(lvl) or 0
    if not itemSpawnLogic.shouldLogItemSpawn(actorLevel) then
        return
    end

    local actorName = isElement(p) and getElementType(p) == "player" and getPlayerName(p) or "Console"
    local zone = isElement(p) and getElementType(p) == "player" and exports.maps:getPlayerZone(p) or nil

    -- 1. Log to Discord staff channel
    local logged = false
    local dc = getResourceFromName("discordchat")
    if dc and getResourceState(dc) == "running" then
        local ok, res = pcall(function()
            return exports.discordchat:logItemSpawn(actorName, uname, itemId, zone)
        end)
        if ok and res then
            logged = true
        end
    end
    if not logged then
        local d = getResourceFromName("discord")
        if d and getResourceState(d) == "running" then
            local payload = {
                player = actorName,
                item = tostring(uname),
                id = itemId and tostring(itemId) or nil,
                zone = zone,
                channel = "1563498523507425421",
                text = itemSpawnLogic.formatLog(actorName, uname, itemId, zone),
            }
            pcall(function()
                call(d, "send", "staff.log", payload)
            end)
        end
    end

    -- 2. Log to staff_actions table if staff resource is running
    local st = getResourceFromName("staff")
    if st and getResourceState(st) == "running" then
        local zoneStr = zone and (" " .. tostring(zone)) or ""
        pcall(function()
            exports.staff:logAction(
                actorName,
                "item_spawn",
                tostring(uname),
                string.format("id=%s pos=%.1f,%.1f,%.1f%s", tostring(itemId or "none"), x or 0, y or 0, z or 0, zoneStr)
            )
        end)
    end
end

local function itemCommand(name, fn)
    addCommandHandler(name, function(p, _, ...)
        if getElementType(p) ~= "player" then
            return say(p, "/%s is player-only", name)
        end
        if not isItemSpawnAllowed(p) then
            return say(p, "not allowed")
        end
        fn(p, ...)
    end)
end

local function handleAddItem(p, ...)
    local args = { ... }
    if #args == 0 or not args[1] or args[1] == "" then
        say(p, "Usage: /additem [itemid/itemname] [extradata format specifiers] [extradata array, comma separated]")
        return say(
            p,
            "Example: `/additem gascan df 1, 4.5` create a petrol can with an integer and a float in extradata."
        )
    end
    if not ready then
        return say(p, "db not connected")
    end

    local query = args[1]
    local specifiers = args[2]
    local dataStr = #args >= 3 and table.concat(args, " ", 3) or nil

    local itemsData = {
        order = exports.data:itemTypes(),
        itemType = function(u)
            return exports.data:itemType(u)
        end,
    }

    local uname, typeErr = itemSpawnLogic.resolveItemType(query, itemsData)
    if not uname then
        return say(p, "%s", typeErr)
    end

    local pData = nil
    if specifiers and specifiers ~= "" then
        local dataArr, dataErr = itemSpawnLogic.parseExtraData(specifiers, dataStr)
        if not dataArr then
            return say(p, "%s", dataErr)
        end
        pData = itemSpawnLogic.encodeJsonArray(dataArr)
    end

    local x, y, z = getElementPosition(p)
    local _, _, rz = getElementRotation(p)
    local sx, sy, sz, srz = itemSpawnLogic.calculateSpawnPosition(x, y, z, rz)
    local interior = getElementInterior(p)
    local dimension = getElementDimension(p)

    -- Upstream ACMD:additem shows a justification dialog for staff below lead level;
    -- the port logs all spawns via logItemSpawn to Discord and staff_actions instead.
    local params = { uname, nil, pData, sx, sy, sz, srz, interior, dimension, nil, nil, n = 11 }
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
        local itemId = res.payload and res.payload.item_id
        say(ctx.player, "created %s id=%s", ctx.uname, tostring(itemId))
        exports.items:refreshPlayer(ctx.player)
        logItemSpawn(ctx.player, ctx.uname, itemId, ctx.x, ctx.y, ctx.z)
    end, { player = p, uname = uname, x = sx, y = sy, z = sz })
end

itemCommand("additem", handleAddItem)
itemCommand("spawnitem", handleAddItem)

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

command("zone", function(p, xArg, yArg)
    if xArg and yArg then
        local x, y = tonumber(xArg), tonumber(yArg)
        if not x or not y then
            return say(p, "usage: /zone [x y]")
        end
        return say(p, "zone(%.1f, %.1f) = %s", x, y, tostring(exports.maps:getZoneAt(x, y) or "none"))
    end
    if getElementType(p) ~= "player" then
        return say(p, "usage: /zone <x> <y>")
    end
    local x, y = getElementPosition(p)
    say(p, "zone = %s (%.1f, %.1f)", tostring(exports.maps:getPlayerZone(p) or "none"), x, y)
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

local useFly = {}

command("move", function(p, dir, distArg)
    local d = type(dir) == "string" and dir:sub(1, 1):lower() or nil
    if d ~= "f" and d ~= "b" and d ~= "u" and d ~= "d" then
        return say(p, "usage: /move [f/b/u/d] [optional:distance]")
    end
    local amount = tonumber(distArg) or 2.0
    local elem = getPedOccupiedVehicle(p) or p
    local x, y, z = getElementPosition(elem)
    local _, _, rz = getElementRotation(elem)
    local rad = math.rad(-rz)
    if d == "f" then
        x = x + amount * math.sin(rad)
        y = y + amount * math.cos(rad)
    elseif d == "b" then
        x = x - amount * math.sin(rad)
        y = y - amount * math.cos(rad)
    elseif d == "u" then
        z = z + amount
    elseif d == "d" then
        z = z - amount
    end
    setElementPosition(elem, x, y, z)
end)

command("fly", function(p, arg)
    if arg == "now" then
        useFly[p] = true
        triggerClientEvent(p, "devFlyStateChanged", p, true, true)
        return say(p, "fly activated")
    end
    useFly[p] = not useFly[p]
    triggerClientEvent(p, "devFlyStateChanged", p, useFly[p], false)
    if useFly[p] then
        say(p, "fly mode enabled: press Jump and Enter/Exit together to fly")
    else
        say(p, "fly mode disabled")
        setPedAnimation(p)
    end
end)

addEventHandler("onPlayerQuit", root, function()
    useFly[source] = nil
end)

addEventHandler("devFlyActiveChanged", root, function(isFlying)
    if not isElement(client) or client ~= source then
        return
    end
    if isFlying then
        setPedAnimation(client, "PARACHUTE", "FALL_SKYDIVE", -1, true, false, false, false)
    else
        setPedAnimation(client)
    end
end)

local studio = loadFile("server/studio.lua", "=dev/studio.lua")({
    logic = loadFile("shared/logic/studio.lua", "=dev/studio_logic.lua"),
    say = say,
    command = command,
})

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
    "hold <player> <command> <ms>  hold a bound command or key for <ms> (0 releases early) so hold polls see it",
    "clua <player> <code>          run a Lua chunk on that client; its return values land in its chat (rcon chat)",
    "chat <player> [n|clear]       last n (20) chat lines that client received (screenshots omit the chat box)",
    "studio <player> [cam|off]     green-screen studio; cam = preset (front back left right threequarter top face",
    "                              hands) or yaw dist height [lookZ]; then screenshot <player>",
    "attach <player> <slot> x y z rx ry rz [sx sy sz] | off | get",
    "                              preview attachment offsets (attachedit resource); get = last client report",
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
                "%s char=%s zone=%s pos=%.1f,%.1f,%.1f",
                getPlayerName(p),
                tostring(exports.character:getCharacterId(p)),
                tostring(exports.maps:getPlayerZone(p) or "none"),
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
            if not ok then
                -- the Default ACL denies command.kick/ban/mute/unmute/restart to players; staff bridges them
                local staff = getResourceFromName("staff")
                if staff and getResourceState(staff) == "running" then
                    ok = exports.staff:runCommand(p, cmd, args) == true
                end
            end
            put("%s ran /%s %s -> %s (reply in that player's chat: rcon chat %s)", who, cmd, args, tostring(ok), who)
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
    elseif verb == "chat" then
        local who, what = rest:match("^(%S+)%s*(%S*)$")
        local p = who and getPlayerFromName(who)
        if not p then
            ok = false
            put("no player '%s' (usage: chat <player> [n|clear])", tostring(who))
        elseif what == "clear" then
            chatSeen[p] = nil
            put("cleared")
        else
            local lines = chatSeen[p] or {}
            local n = math.min(#lines, tonumber(what) or 20)
            for i = #lines - n + 1, #lines do
                put("%s %s", lines[i].at, lines[i].text)
            end
            if n == 0 then
                put("no chat lines seen by %s yet", who)
            end
        end
    elseif verb == "key" then
        local who, bound = rest:match("^(%S+)%s+(%S+)$")
        local p = who and getPlayerFromName(who)
        if not p then
            ok = false
            put("usage: key <player> <command>")
        else
            triggerClientEvent(p, "devKeyPressed", p, bound)
            put("%s pressed %s", who, bound)
        end
    elseif verb == "hold" then
        local who, bound, msArg = rest:match("^(%S+)%s+(%S+)%s+(%S+)$")
        local p = who and getPlayerFromName(who)
        local ms = tonumber(msArg)
        if not p or not ms or ms < 0 then
            ok = false
            put("usage: hold <player> <command> <ms>")
        else
            ms = math.floor(ms)
            triggerClientEvent(p, "devKeyPressed", p, bound, ms)
            put(ms > 0 and string.format("%s holding %s for %d ms", who, bound, ms) or (who .. " released " .. bound))
        end
    elseif verb == "clua" then
        local who, code = rest:match("^(%S+)%s+(.+)$")
        local p = who and getPlayerFromName(who)
        if not p then
            ok = false
            put("usage: clua <player> <code>")
        else
            triggerClientEvent(p, "devClientLuaRequested", p, code)
            put("sent to %s; read the result with: chat %s", who, who)
        end
    elseif verb == "studio" then
        local who, args = rest:match("^(%S+)%s*(.-)$")
        local p = who and getPlayerFromName(who)
        local words = {}
        for w in (args or ""):gmatch("%S+") do
            words[#words + 1] = w
        end
        if not p then
            ok = false
            put("no player '%s' (usage: studio <player> [preset|yaw dist height [lookZ]|off])", tostring(who))
        elseif words[1] == "off" then
            ok = studio.leave(p)
            put(ok and "%s left the studio" or "%s was not in the studio", who)
        else
            studio.enter(p)
            local cam, err = studio.setCam(p, words)
            ok = cam ~= nil
            put("%s", cam and (who .. " in the studio: " .. studio.describeCam(cam)) or err)
        end
    elseif verb == "attach" then
        local who, args = rest:match("^(%S+)%s*(.-)$")
        local p = who and getPlayerFromName(who)
        local res = getResourceFromName("attachedit")
        local words = {}
        for w in (args or ""):gmatch("%S+") do
            words[#words + 1] = w
        end
        if not p then
            ok = false
            put("no player '%s' (usage: attach <player> <slot> x y z rx ry rz [sx sy sz] | off | get)", tostring(who))
        elseif not res or getResourceState(res) ~= "running" then
            ok = false
            put("the attachedit resource is not running")
        else
            local lines
            ok, lines = exports.attachedit:rcon(p, words)
            ok = ok == true
            for _, l in ipairs(type(lines) == "table" and lines or {}) do
                put("%s", tostring(l))
            end
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
