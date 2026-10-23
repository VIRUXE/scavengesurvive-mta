-- Duty, teleports, spectate, name tags and the account-level commands (profile, players, adminlist, setadmin,
-- setmotd, acmds, restart). Upstream: admin/admin.pwn (duty, acmds, adminlist), level2.pwn (goto/get/gotopos,
-- setmotd), level3.pwn (spec/free), level4.pwn (setadmin, players), spectate.pwn, name-tags.pwn.
-- Deviation: upstream duty logs the character out of the world; here the character stays loaded and the duty
-- flag makes the staff member immune to player damage (weapons checks staff.duty) until character exposes a
-- suspend/resume export.
return function(ctx)
    local db, logic, state = ctx.db, ctx.logic, ctx.state
    local M = {}

    local function needsDuty(p, lvl)
        if state.duty[p] or lvl >= logic.MAX_LEVEL then
            return false
        end
        ctx.say(p, " >  You must be on duty (/duty) to do that.")
        return true
    end

    local function setNametags(p, flag)
        state.nametags[p] = flag or nil
        if isElement(p) then
            triggerClientEvent(p, "nametagsChanged", p, flag == true)
        end
    end

    local function dutyOn(p)
        local skin = getElementModel(p)
        state.duty[p] = { skin = skin }
        setElementData(p, "staff.duty", true, "broadcast", "deny")
        setElementModel(p, logic.dutySkin(skin))
        setNametags(p, true)
        ctx.say(p, " >  You are now on duty: immune to player damage, name tags on.")
        ctx.msgStaff(1, " >  %s went on duty", getPlayerName(p))
        ctx.log(p, "duty_on")
    end

    local function dutyOff(p, silent)
        local d = state.duty[p]
        state.duty[p] = nil
        if not d or not isElement(p) then
            return
        end
        setElementData(p, "staff.duty", false, "broadcast", "deny")
        if getElementModel(p) == logic.DUTY_SKIN_MALE or getElementModel(p) == logic.DUTY_SKIN_FEMALE then
            setElementModel(p, d.skin)
        end
        setNametags(p, false)
        if not silent then
            ctx.say(p, " >  You are off duty.")
            ctx.msgStaff(1, " >  %s went off duty", getPlayerName(p))
            ctx.log(p, "duty_off")
        end
    end

    ctx.command({
        name = "duty",
        level = 2,
        playerOnly = true,
        usage = "/duty",
        help = "Toggle staff duty (immune to players, name tags, duty skin)",
        needsDb = false,
        fn = function(p)
            if state.spectating[p] then
                return ctx.say(p, " >  You cannot do that while spectating.")
            end
            if state.duty[p] then
                dutyOff(p)
            else
                dutyOn(p)
            end
        end,
    })

    local function teleport(who, toX, toY, toZ, interior, dimension)
        local veh = getPedOccupiedVehicle(who)
        setElementInterior(who, interior or 0)
        setElementDimension(who, dimension or 0)
        if veh and getVehicleOccupant(veh) == who then
            setElementInterior(veh, interior or 0)
            setElementDimension(veh, dimension or 0)
            setElementPosition(veh, toX, toY, toZ)
        else
            setElementPosition(who, toX, toY, toZ)
        end
    end

    local function teleportToPlayer(who, target)
        local x, y, z = getElementPosition(target)
        local _, _, rz = getElementRotation(target)
        local rad = math.rad(rz)
        local tx, ty = x - math.sin(rad) * 1.5, y + math.cos(rad) * 1.5
        teleport(who, tx, ty, z + 0.5, getElementInterior(target), getElementDimension(target))
    end

    ctx.command({
        name = "goto",
        level = 2,
        playerOnly = true,
        usage = "/goto <player>",
        help = "Teleport to a player (on duty)",
        needsDb = false,
        fn = function(p, args, lvl)
            if needsDuty(p, lvl) then
                return
            end
            local target = args[1] and ctx.findPlayer(p, args[1])
            if not target then
                return args[1] == nil and ctx.say(p, " >  Usage: /goto <player>")
            end
            teleportToPlayer(p, target)
            ctx.say(p, " >  You have teleported to %s", getPlayerName(target))
            ctx.sayLang(target, "TELEPORTEDT", getPlayerName(p))
            ctx.log(p, "goto", getPlayerName(target), ctx.accountId(target))
        end,
    })

    ctx.command({
        name = "get",
        level = 2,
        playerOnly = true,
        usage = "/get <player>",
        help = "Teleport a player to you (on duty)",
        needsDb = false,
        fn = function(p, args, lvl)
            if needsDuty(p, lvl) then
                return
            end
            local target = args[1] and ctx.target(p, args[1], false)
            if not target then
                return args[1] == nil and ctx.say(p, " >  Usage: /get <player>")
            end
            teleportToPlayer(target, p)
            ctx.say(p, " >  You have teleported %s", getPlayerName(target))
            ctx.sayLang(target, "TELEPORTEDY", getPlayerName(p))
            ctx.log(p, "get", getPlayerName(target), ctx.accountId(target))
        end,
    })

    ctx.command({
        name = "gotopos",
        level = 2,
        playerOnly = true,
        usage = "/gotopos <x> <y> <z>",
        help = "Teleport to coordinates (with or without commas)",
        needsDb = false,
        fn = function(p, args, lvl)
            if needsDuty(p, lvl) then
                return
            end
            local nums = {}
            for _, w in ipairs(args) do
                for n in w:gmatch("[-+]?%d+%.?%d*") do
                    nums[#nums + 1] = tonumber(n)
                end
            end
            if #nums < 3 then
                return ctx.say(p, " >  Usage: /gotopos <x> <y> <z>")
            end
            teleport(p, nums[1], nums[2], nums[3], getElementInterior(p), getElementDimension(p))
            ctx.say(p, " >  Teleported to %.1f, %.1f, %.1f", nums[1], nums[2], nums[3])
            ctx.log(p, "gotopos", nil, nil, string.format("%.1f, %.1f, %.1f", nums[1], nums[2], nums[3]))
        end,
    })

    -- Spectate: camera on the target, the staff member parked frozen and invisible where they stood.
    local function spectate(p, target)
        local s = state.spectating[p]
        if not s then
            local x, y, z = getElementPosition(p)
            s = { x = x, y = y, z = z, interior = getElementInterior(p), dimension = getElementDimension(p) }
            state.spectating[p] = s
            setElementFrozen(p, true)
            setElementAlpha(p, 0)
            setElementCollisionsEnabled(p, false)
            setNametags(p, true)
        end
        s.target = target
        setElementDimension(p, getElementDimension(target))
        setElementInterior(p, getElementInterior(target))
        setCameraTarget(p, target)
        triggerClientEvent(p, "spectateChanged", p, target)
        ctx.util.log("staff", "info", "%s watches %s", getPlayerName(p), getPlayerName(target))
    end

    local function stopSpectating(p, silent)
        local s = state.spectating[p]
        state.spectating[p] = nil
        if not s or not isElement(p) then
            return
        end
        setCameraTarget(p, p)
        setElementInterior(p, s.interior)
        setElementDimension(p, s.dimension)
        setElementPosition(p, s.x, s.y, s.z)
        setElementFrozen(p, false)
        setElementAlpha(p, 255)
        setElementCollisionsEnabled(p, true)
        triggerClientEvent(p, "spectateChanged", p, false)
        if not state.duty[p] then
            setNametags(p, false)
        end
        if not silent then
            ctx.say(p, " >  Spectate ended.")
        end
    end
    M.stopSpectating = stopSpectating

    local function cycle(p, dir)
        local s = state.spectating[p]
        if not s then
            return
        end
        local list = {}
        for _, o in ipairs(getElementsByType("player")) do
            if o ~= p and not state.spectating[o] then
                list[#list + 1] = o
            end
        end
        if #list == 0 then
            return ctx.say(p, " >  Nobody else to watch.")
        end
        local idx = 1
        for i, o in ipairs(list) do
            if o == s.target then
                idx = i
            end
        end
        idx = ((idx - 1 + dir) % #list) + 1
        spectate(p, list[idx])
        ctx.say(p, " >  Now watching %s", getPlayerName(list[idx]))
    end

    ctx.command({
        name = "spec",
        level = 2,
        playerOnly = true,
        usage = "/spec <player|next|prev|off>",
        help = "Spectate a player (left/right arrows cycle, /free or /spec off to stop)",
        needsDb = false,
        fn = function(p, args, lvl)
            local word = (args[1] or ""):lower()
            if word == "off" then
                return stopSpectating(p)
            end
            if word == "next" or word == "prev" then
                return cycle(p, word == "next" and 1 or -1)
            end
            if needsDuty(p, lvl) then
                return
            end
            local target = args[1] and ctx.findPlayer(p, args[1])
            if not target then
                return args[1] == nil and ctx.say(p, " >  Usage: /spec <player|next|prev|off>")
            end
            if target == p then
                return ctx.say(p, " >  You cannot spectate yourself.")
            end
            spectate(p, target)
            ctx.say(p, " >  Spectating %s. Arrow keys switch player, /free returns you.", getPlayerName(target))
            ctx.log(p, "spec", getPlayerName(target), ctx.accountId(target))
        end,
    })

    ctx.command({
        name = "free",
        level = 2,
        playerOnly = true,
        usage = "/free",
        help = "Stop spectating",
        needsDb = false,
        fn = function(p)
            if not state.spectating[p] then
                return ctx.say(p, " >  You are not spectating.")
            end
            stopSpectating(p)
        end,
    })

    ctx.net.handler("spectateRequested", function(player, dir)
        if state.spectating[player] then
            cycle(player, dir == "prev" and -1 or 1)
        end
    end, { rate = 5 })

    -- when a watched player leaves, the watcher returns to where they stood
    addEventHandler("onPlayerQuit", root, function()
        for watcher, s in pairs(state.spectating) do
            if s.target == source then
                stopSpectating(watcher)
            end
        end
    end)

    ctx.command({
        name = "nametags",
        level = 2,
        playerOnly = true,
        usage = "/nametags",
        help = "Toggle name tags over every player",
        needsDb = false,
        fn = function(p)
            setNametags(p, not state.nametags[p])
            ctx.say(p, " >  Name tags %s", state.nametags[p] and "on" or "off")
        end,
    })

    ctx.command({
        name = "profile",
        level = 2,
        usage = "/profile <name>",
        help = "Account details: level, registered, last login, warnings, active",
        fn = function(p, args)
            if not args[1] then
                return ctx.say(p, " >  Usage: /profile <name>")
            end
            local sql = "SELECT a.id, a.name, a.admin_level, a.active, a.warnings, a.muted,"
                .. " DATE_FORMAT(a.registered_at, '%Y-%m-%d') AS reg,"
                .. " DATE_FORMAT(a.last_login_at, '%Y-%m-%d %H:%i') AS last,"
                .. " (SELECT COUNT(*) FROM characters c WHERE c.account_id = a.id) AS lives,"
                .. " (SELECT COUNT(*) FROM characters c WHERE c.account_id = a.id AND c.alive = 1) AS alive,"
                .. " (SELECT COUNT(*) FROM reports r WHERE r.name = a.name AND r.active = 1) AS reports"
                .. " FROM accounts a WHERE a.name = ?"
            db.one(sql, { args[1] }, function(r, actor)
                if not r then
                    return ctx.say(actor, " >  The account '%s' does not exist.", args[1])
                end
                local lvl = tonumber(r.admin_level) or 0
                local head =
                    string.format(" >  #33CCFF%s#FFFF00 #%d, %s (level %d)", r.name, r.id, logic.levelName(lvl), lvl)
                ctx.say(actor, "%s, registered %s, last login %s", head, tostring(r.reg), tostring(r.last or "never"))
                local active = tonumber(r.active) == 1 and "active" or "#FF8080inactive#FFFF00"
                local muted = tonumber(r.muted) == 1 and "#FF8080muted#FFFF00" or "not muted"
                local lives, alive, reports = tonumber(r.lives) or 0, tonumber(r.alive) or 0, tonumber(r.reports) or 0
                local fmt = " >  %s, warnings %d, %s, characters %d (%d alive), open reports %d"
                ctx.say(actor, fmt, active, tonumber(r.warnings) or 0, muted, lives, alive, reports)
            end, p)
        end,
    })

    ctx.command({
        name = "players",
        level = 4,
        usage = "/players",
        help = "Everyone online with level, character id, zone and ping",
        needsDb = false,
        fn = function(p)
            local rows = {}
            for _, o in ipairs(getElementsByType("player")) do
                local lvl = ctx.level(o)
                local charId = exports.character:getCharacterId(o)
                local zone = exports.maps:getPlayerZone(o)
                local prefix = (lvl > 0 and ("[" .. lvl .. "] ") or "") .. getPlayerName(o)
                local flags = (state.duty[o] and "  duty" or "") .. (state.spectating[o] and "  spec" or "")
                local where = tostring(charId or "-") .. "  " .. tostring(zone or "-")
                local label = string.format("%s  char %s  %d ms%s", prefix, where, getPlayerPing(o), flags)
                rows[#rows + 1] = { id = getPlayerName(o), label = label }
            end
            ctx.openList(p, "players", "Players (" .. #rows .. ")", rows, { "Close", "Close" }, function()
                ctx.closeList(p)
            end)
        end,
    })

    ctx.command({
        name = "adminlist",
        level = 3,
        usage = "/adminlist",
        help = "Staff accounts by level (online ones marked)",
        fn = function(p)
            local sql = "SELECT name, admin_level FROM accounts WHERE admin_level > 0 ORDER BY admin_level DESC, name"
            db.query(sql, {}, function(rows, actor)
                local out = {}
                for _, r in ipairs(rows or {}) do
                    local lvl = tonumber(r.admin_level) or 0
                    local online = getPlayerFromName(r.name) and " >  " or "    "
                    local label = string.format("%s%s (%d-%s)", online, r.name, lvl, logic.levelName(lvl))
                    out[#out + 1] = { id = r.name, label = label }
                end
                if #out == 0 then
                    out[1] = { id = "none", label = "No staff accounts", empty = true }
                end
                local title = "Staff (" .. #(rows or {}) .. ")"
                ctx.openList(actor, "adminlist", title, out, { "Close", "Close" }, function()
                    ctx.closeList(actor)
                end)
            end, p)
        end,
    })

    ctx.command({
        name = "setadmin",
        level = 4,
        usage = "/setadmin <player|name> <level 0-5>",
        help = "Set an account's staff level (below your own)",
        fn = function(p, args, lvl)
            local newLevel = tonumber(args[2])
            if not args[1] or not newLevel then
                return ctx.say(p, " >  Usage: /setadmin <player|name> <level 0-5>")
            end
            local entry = logic.findPlayer(args[1], ctx.onlinePlayers())
            local function apply(name, accountId, targetLevel, online)
                local ok, code =
                    logic.canSetLevel(lvl, newLevel, targetLevel, online == p or name:lower() == ctx.name(p):lower())
                if not ok then
                    local msg = ({
                        SELF = "You cannot set your own level",
                        BAD_LEVEL = "Level must be a whole number 0-5",
                        TOO_HIGH = "That level is not below your own",
                    })[code]
                    return ctx.say(p, " >  %s.", msg)
                end
                local sql = "UPDATE accounts SET admin_level = ? WHERE id = ?"
                db.exec(sql, { newLevel, accountId }, function(ok2, actor)
                    if not ok2 then
                        return ctx.say(actor, " >  An error occurred.")
                    end
                    local levelName = logic.levelName(newLevel)
                    if isElement(online) then
                        exports.auth:setSessionAdminLevel(online, newLevel)
                        ctx.say(online, " >  %s made you a level %d %s", ctx.name(actor), newLevel, levelName)
                        if newLevel < 2 and state.duty[online] then
                            dutyOff(online)
                        end
                    end
                    ctx.say(actor, " >  You set %s to level %d (%s).", name, newLevel, levelName)
                    ctx.log(actor, "setadmin", name, accountId, tostring(newLevel))
                end, p)
            end
            if entry and ctx.accountId(entry.player) then
                return apply(entry.name, ctx.accountId(entry.player), ctx.level(entry.player), entry.player)
            end
            ctx.lookupAccount(args[1], function(row)
                if not row then
                    return ctx.say(p, " >  The account '%s' does not exist.", args[1])
                end
                apply(row.name, row.id, tonumber(row.admin_level) or 0, nil)
            end)
        end,
    })

    ctx.command({
        name = "setmotd",
        level = 2,
        usage = "/setmotd <message|off>",
        help = "Set the message shown to players on login",
        fn = function(p, args)
            local text = logic.tail(args, 1)
            if not text then
                local current = state.settings["server.motd"] ~= "" and state.settings["server.motd"] or "none"
                return ctx.say(p, " >  Usage: /setmotd <message|off> (currently: %s)", current)
            end
            if text:lower() == "off" then
                text = ""
            end
            state.settings["server.motd"] = text
            local sql = "INSERT INTO settings (skey, svalue) VALUES ('server.motd', ?)"
                .. " ON DUPLICATE KEY UPDATE svalue = VALUES(svalue)"
            db.exec(sql, { text:sub(1, 255) })
            ctx.msgAll(text == "" and " >  MOTD cleared" or " >  MOTD updated: #33CCFF%s", text)
            ctx.log(p, "setmotd", nil, nil, text:sub(1, 255))
        end,
    })

    ctx.command({
        name = "acmds",
        level = 1,
        playerOnly = true,
        usage = "/acmds",
        help = "This list",
        needsDb = false,
        fn = function(p, _, lvl)
            local rows = {}
            for _, group in ipairs(logic.commandsFor(ctx.reg, lvl)) do
                rows[#rows + 1] = {
                    id = "lvl" .. group.level,
                    label = string.format("%s (level %d)", group.name, group.level),
                    empty = true,
                }
                for _, c in ipairs(group.commands) do
                    rows[#rows + 1] = { id = c.name, label = string.format("%s - %s", c.usage, c.help) }
                end
            end
            ctx.openList(p, "acmds", "Staff commands", rows, { "Close", "Close" }, function()
                ctx.closeList(p)
            end)
        end,
    })

    -- Supply crate / weapons cache on demand (upstream supply-crate.pwn ACMD:sc[4]); loot owns the mechanics.
    ctx.command({
        name = "sc",
        level = 4,
        playerOnly = true,
        usage = "/sc [type 1-5]",
        help = "Drop a supply crate of that type where you stand (no type lists them)",
        needsDb = false,
        fn = function(p, args)
            local types = exports.loot:supplyDropTypes()
            local idx = tonumber(args[1])
            if not idx or not types[idx] then
                ctx.say(p, " >  Usage: /sc [type] - types:")
                for i, t in ipairs(types) do
                    ctx.say(p, " >  %d: %s (%s, %d+ players)", i, t.name, t.table, t.required)
                end
                return
            end
            local x, y, z = getElementPosition(p)
            local done, why = exports.loot:dropSupply(idx, x, y, z - 0.8, "staff request")
            local fmt = done and " >  Supply crate %s on its way." or " >  Refused: %s"
            ctx.say(p, fmt, done and types[idx].name or tostring(why))
            if done then
                ctx.log(p, "supplydrop", nil, nil, types[idx].name)
            end
        end,
    })

    ctx.command({
        name = "wc",
        level = 4,
        playerOnly = true,
        usage = "/wc",
        help = "Place a weapons cache where you stand and start its signals",
        needsDb = false,
        fn = function(p)
            local x, y, z = getElementPosition(p)
            local done, why = exports.loot:dropWeaponCache(x, y, z - 0.8)
            ctx.say(p, done and " >  Weapons cache placed." or " >  Refused: %s", tostring(why))
            if done then
                ctx.log(p, "weaponcache", nil, nil, string.format("%.1f, %.1f, %.1f", x, y, z))
            end
        end,
    })

    ctx.command({
        name = "restart",
        level = 4,
        usage = "/restart <resource>",
        help = "Restart one gamemode resource",
        needsDb = false,
        fn = function(p, args)
            local res = args[1] and getResourceFromName(args[1])
            if not res then
                return ctx.say(p, " >  Usage: /restart <resource>")
            end
            ctx.msgStaff(1, " >  %s restarts resource %s", ctx.name(p), args[1])
            ctx.log(p, "restart", nil, nil, args[1])
            setTimer(function(r)
                restartResource(r)
            end, 200, 1, res)
        end,
    })

    function M.forget(p)
        if state.spectating[p] then
            stopSpectating(p, true)
        end
        if state.duty[p] then
            dutyOff(p, true)
        end
        if state.nametags[p] then
            setNametags(p, false)
        end
    end

    return M
end
