-- Level 1-2 moderation: mute, warn, kick, msg, clearchat, aliases, serial, history, staff chat, freeze.
-- Upstream: admin/level1.pwn, level2.pwn (freeze), mute.pwn, freeze.pwn.
return function(ctx)
    local db, logic, state = ctx.db, ctx.logic, ctx.state
    local M = {}

    ctx.command({
        name = "a",
        level = 1,
        usage = "/a <message>",
        help = "Staff chat channel",
        needsDb = false,
        fn = function(p, args)
            local text = logic.tail(args, 1)
            if not text then
                return ctx.say(p, " >  Usage: /a <message>")
            end
            local lvl = ctx.level(p)
            local c = logic.levelColour(lvl)
            local tag = string.format("#%02X%02X%02X[%s] %s:", c[1], c[2], c[3], logic.levelName(lvl), ctx.name(p))
            ctx.msgStaff(1, "%s #FFFFFF%s", tag, text)
        end,
    })

    ctx.command({
        name = "mute",
        level = 1,
        usage = "/mute <player> <seconds|forever> [reason]",
        help = "Mute a player from global chat",
        fn = function(p, args)
            local target = args[1] and ctx.target(p, args[1], false)
            local seconds = logic.parseDuration(args[2] or "")
            if not target or not seconds then
                if not args[1] or not args[2] then
                    ctx.say(p, " >  Usage: /mute <player> <seconds|forever> [reason]")
                elseif target then
                    ctx.say(p, " >  '%s' is not a duration (10m, 2h, 1d or forever).", tostring(args[2]))
                end
                return
            end
            if state.muted[target] then
                return ctx.say(p, " >  Player already muted.")
            end
            local reason = logic.tail(args, 3) or "no reason given"
            ctx.setMuted(target, true, seconds)
            if seconds > 0 then
                ctx.say(p, " >  Muted %s #FFFFFFfor %s.", getPlayerName(target), logic.formatDuration(seconds))
                ctx.sayLang(target, "MUTEDANTIME", seconds, reason)
            else
                ctx.say(p, " >  Muted %s permanently.", getPlayerName(target))
                ctx.sayLang(target, "MUTEDREASON", reason)
            end
            local details = logic.formatDuration(seconds) .. ": " .. reason
            ctx.log(p, "mute", getPlayerName(target), ctx.accountId(target), details)
        end,
    })

    ctx.command({
        name = "unmute",
        level = 1,
        usage = "/unmute <player>",
        help = "Lift a mute",
        fn = function(p, args)
            local target = args[1] and ctx.target(p, args[1], true)
            if not target then
                return args[1] == nil and ctx.say(p, " >  Usage: /unmute <player>")
            end
            if not state.muted[target] then
                return ctx.say(p, " >  %s is not muted.", getPlayerName(target))
            end
            ctx.setMuted(target, false)
            ctx.say(p, " >  Un-muted %s", getPlayerName(target))
            ctx.sayLang(target, "MUTEDUNMUTE")
            ctx.log(p, "unmute", getPlayerName(target), ctx.accountId(target))
        end,
    })

    ctx.command({
        name = "warn",
        level = 1,
        usage = "/warn <player> <reason>",
        help = "Warn a player; staff.max_warnings warnings = a staff.warn_ban_hours ban",
        fn = function(p, args)
            local target = args[1] and ctx.target(p, args[1], true)
            local reason = logic.tail(args, 2)
            if not target or not reason then
                return (not args[1] or not reason) and ctx.say(p, " >  Usage: /warn <player> <reason>")
            end
            local accountId = ctx.accountId(target)
            if not accountId then
                return ctx.say(p, " >  %s is not logged in yet.", getPlayerName(target))
            end
            local maxWarnings = tonumber(state.settings["staff.max_warnings"]) or 5
            local banSeconds = (tonumber(state.settings["staff.warn_ban_hours"]) or 24) * 3600
            db.call("staff_warn", {
                accountId,
                getPlayerName(target),
                getPlayerIP(target),
                getPlayerSerial(target),
                ctx.accountId(p),
                ctx.name(p),
                reason:sub(1, 128),
                maxWarnings,
                banSeconds,
                n = 9,
            }, function(res, c)
                if not isElement(c.actor) then
                    return
                end
                if not res or not res.ok then
                    return ctx.say(c.actor, " >  Warning failed: %s", res and res.code or "db error")
                end
                local warnings = res.payload.warnings
                local fmt = " >  #FFAA00%s#FFFF00 has been warned (%d/%d) for: %s"
                ctx.say(c.actor, fmt, c.name, warnings, maxWarnings, c.reason)
                if isElement(c.target) then
                    ctx.sayLang(c.target, "WARNEDMESSG", warnings, c.reason)
                    if tonumber(res.payload.banned) == 1 then
                        ctx.sayLang(c.target, "BANNEDMESSG", "Getting " .. maxWarnings .. " warnings")
                        ctx.kick(c.target, c.actor, "Banned: " .. maxWarnings .. " warnings")
                    end
                end
                if tonumber(res.payload.banned) == 1 then
                    local line = " >  %s reached %d warnings and was banned for %dh"
                    ctx.msgStaff(1, line, c.name, maxWarnings, banSeconds / 3600)
                end
            end, { actor = p, target = target, name = getPlayerName(target), reason = reason })
        end,
    })

    ctx.command({
        name = "kick",
        level = 1,
        usage = "/kick <player> <reason>",
        help = "Kick a player (becomes a request when higher staff are online)",
        needsDb = false,
        fn = function(p, args, lvl)
            local target = args[1] and ctx.target(p, args[1], true)
            local reason = logic.tail(args, 2)
            if not target or not reason then
                return (not args[1] or not reason) and ctx.say(p, " >  Usage: /kick <player> <reason>")
            end
            local highest = ctx.highestLevelOnline()
            if logic.kickNeedsApproval(lvl, highest) then
                local who = getPlayerName(target)
                local fmt = " >  %s kick request: %s reason: %s (run /kick %s %s to approve)"
                ctx.msgStaff(highest, fmt, ctx.name(p), who, reason, who, reason)
                return ctx.say(p, " >  Higher staff are online; your kick was sent to them as a request.")
            end
            if target == p then
                ctx.msgAll(" >  #FF80FF%s failed and kicked themselves", getPlayerName(target))
            end
            ctx.sayLang(target, "KICKMESSAGE", reason)
            ctx.msgStaff(1, " >  %s kicked, reason: #33CCFF%s", getPlayerName(target), reason)
            ctx.log(p, "kick", getPlayerName(target), ctx.accountId(target), reason)
            ctx.kick(target, p, reason)
        end,
    })

    ctx.command({
        name = "msg",
        level = 1,
        usage = "/msg <message>",
        help = "Server message to everyone",
        needsDb = false,
        fn = function(p, args)
            local text = logic.tail(args, 1)
            if not text then
                return ctx.say(p, " >  Usage: /msg <message>")
            end
            ctx.msgAll(" >  #33CCFF%s", text)
            ctx.log(p, "msg", nil, nil, text:sub(1, 255))
        end,
    })

    ctx.command({
        name = "clearchat",
        level = 1,
        usage = "/clearchat",
        help = "Clear everyone's chat box",
        needsDb = false,
        fn = function(p)
            clearChatBox(root)
            ctx.log(p, "clearchat")
        end,
    })

    -- Other accounts seen from the same IP and/or serial (upstream /aliases i/h/a; the serial replaces gpci).
    local ALIAS_MATCH = {
        both = "((serial IS NOT NULL AND serial = ?) OR (ip IS NOT NULL AND ip = ?))",
        ip = "(ip IS NOT NULL AND ip = ?)",
        serial = "(serial IS NOT NULL AND serial = ?)",
    }
    ctx.command({
        name = "aliases",
        level = 1,
        usage = "/aliases <name> [i|s]",
        help = "Accounts that share this account's IP or serial (i = IP only, s = serial only)",
        fn = function(p, args)
            local mode = logic.aliasMode(args[2])
            if not args[1] or not mode then
                return ctx.say(p, " >  Usage: /aliases <name> [i|s]")
            end
            ctx.lookupAccount(args[1], function(row, actor)
                if not row then
                    return ctx.say(actor, " >  The account '%s' does not exist.", args[1])
                end
                if (tonumber(row.admin_level) or 0) > ctx.level(actor) and row.name ~= ctx.name(actor) then
                    return ctx.say(actor, " >  No aliases found for %s", row.name)
                end
                local params = { row.name, row.last_serial, row.last_ip, n = 3 }
                if mode == "ip" then
                    params = { row.name, row.last_ip, n = 2 }
                elseif mode == "serial" then
                    params = { row.name, row.last_serial, n = 2 }
                end
                local sql = "SELECT DISTINCT name FROM connection_log WHERE name <> ? AND "
                    .. ALIAS_MATCH[mode]
                    .. " ORDER BY name LIMIT 32"
                db.query(sql, params, function(rows, a)
                    if not rows then
                        return ctx.say(a, " >  An error occurred.")
                    end
                    if #rows == 0 then
                        return ctx.say(a, " >  No aliases found for %s", row.name)
                    end
                    local names = {}
                    for _, r in ipairs(rows) do
                        names[#names + 1] = r.name
                    end
                    ctx.say(a, " >  %s (%d): #33CCFF%s", row.name, #names, table.concat(names, ", "))
                    ctx.log(a, "aliases", row.name, row.id, mode)
                end, actor)
            end, p)
        end,
    })

    -- Names seen with a raw serial (upstream's player-list "accounts by gpci hash" view). Accounts that
    -- outrank the caller stay hidden, as /aliases hides them.
    ctx.command({
        name = "serial",
        level = 1,
        usage = "/serial <serial>",
        help = "Names seen with a serial (32 hex digits, see /ip or /history)",
        fn = function(p, args)
            local serial = logic.normaliseSerial(args[1])
            if not serial then
                return ctx.say(p, " >  Usage: /serial <serial> (32 hex digits)")
            end
            local sql = "SELECT c.name, MAX(COALESCE(a.admin_level, 0)) AS lvl FROM connection_log c"
                .. " LEFT JOIN accounts a ON a.id = c.account_id WHERE c.serial = ? GROUP BY c.name ORDER BY c.name"
                .. " LIMIT 32"
            db.query(sql, { serial }, function(rows, a)
                if not rows then
                    return ctx.say(a, " >  An error occurred.")
                end
                local names, level, own = {}, ctx.level(a), ctx.name(a)
                for _, r in ipairs(rows) do
                    if (tonumber(r.lvl) or 0) <= level or r.name == own then
                        names[#names + 1] = r.name
                    end
                end
                if #names == 0 then
                    return ctx.say(a, " >  No names found for serial %s", serial)
                end
                ctx.say(a, " >  %s (%d): #33CCFF%s", serial, #names, table.concat(names, ", "))
                ctx.log(a, "serial", nil, nil, serial)
            end, p)
        end,
    })

    ctx.command({
        name = "history",
        level = 1,
        usage = "/history <name> [n]",
        help = "Last n (default 10) connections of an account: date, IP, serial",
        fn = function(p, args)
            if not args[1] then
                return ctx.say(p, " >  Usage: /history <name> [n]")
            end
            local n = math.min(50, math.max(1, tonumber(args[2]) or 10))
            ctx.lookupAccount(args[1], function(row, actor)
                if not row then
                    return ctx.say(actor, " >  The account '%s' does not exist.", args[1])
                end
                if (tonumber(row.admin_level) or 0) > ctx.level(actor) and row.name ~= ctx.name(actor) then
                    return ctx.say(actor, " >  No history found for %s", row.name)
                end
                local sql = "SELECT DATE_FORMAT(joined_at, '%Y-%m-%d %H:%i') AS at_, ip, serial FROM connection_log"
                    .. " WHERE account_id = ? ORDER BY joined_at DESC LIMIT "
                    .. n
                db.query(sql, { row.id }, function(rows, a)
                    if not rows or #rows == 0 then
                        return ctx.say(a, " >  No history found for %s", row.name)
                    end
                    local lines = {}
                    for _, r in ipairs(rows) do
                        local label =
                            string.format("%s  %s  %s", r.at_, tostring(r.ip or "-"), tostring(r.serial or "-"))
                        lines[#lines + 1] = { id = r.at_, label = label }
                    end
                    ctx.openList(a, "history", "History of " .. row.name, lines, { "Close", "Close" }, function()
                        ctx.closeList(a)
                    end)
                    ctx.log(a, "history", row.name, row.id)
                end, actor)
            end, p)
        end,
    })

    -- Freeze (upstream FreezePlayer): no movement and no controls, optionally for n seconds.
    local function unfreeze(target, silent)
        local t = state.frozen[target]
        if isTimer(t) then
            killTimer(t)
        end
        state.frozen[target] = nil
        if not isElement(target) then
            return
        end
        setElementFrozen(target, false)
        local ko = exports.character:isKnockedOut(target) or exports.character:isPlayerCuffed(target)
        if not ko then
            toggleAllControls(target, true, true, false)
        end
        if not silent then
            ctx.sayLang(target, "FREEZEUNFRE")
        end
    end
    M.unfreeze = unfreeze

    ctx.command({
        name = "freeze",
        level = 2,
        usage = "/freeze <player> [seconds]",
        help = "Freeze a player in place",
        needsDb = false,
        fn = function(p, args)
            local target = args[1] and ctx.target(p, args[1], true)
            if not target then
                return args[1] == nil and ctx.say(p, " >  Usage: /freeze <player> [seconds]")
            end
            local seconds = tonumber(args[2]) or 0
            if isTimer(state.frozen[target]) then
                killTimer(state.frozen[target])
            end
            setElementFrozen(target, true)
            toggleAllControls(target, false, true, false)
            state.frozen[target] = true
            if seconds > 0 then
                state.frozen[target] = setTimer(unfreeze, seconds * 1000, 1, target)
                ctx.say(p, " >  Frozen %s for %d seconds", getPlayerName(target), seconds)
                ctx.sayLang(target, "FREEZETIMER", seconds)
            else
                ctx.say(p, " >  Frozen %s", getPlayerName(target))
                ctx.sayLang(target, "FREEZEFROZE")
            end
            ctx.log(p, "freeze", getPlayerName(target), ctx.accountId(target), seconds > 0 and (seconds .. "s") or nil)
        end,
    })

    ctx.command({
        name = "unfreeze",
        level = 2,
        usage = "/unfreeze <player>",
        help = "Unfreeze a player",
        needsDb = false,
        fn = function(p, args)
            local target = args[1] and ctx.findPlayer(p, args[1])
            if not target then
                return args[1] == nil and ctx.say(p, " >  Usage: /unfreeze <player>")
            end
            if not state.frozen[target] then
                return ctx.say(p, " >  %s is not frozen.", getPlayerName(target))
            end
            unfreeze(target)
            ctx.say(p, " >  Unfrozen %s", getPlayerName(target))
            ctx.log(p, "unfreeze", getPlayerName(target), ctx.accountId(target))
        end,
    })

    -- After every login (upstream CheckForExtraAccounts): other names from this IP or serial, their highest staff
    -- level and whether any is banned. Catches a name banned while offline, whose bans row has no IP or serial yet.
    local ALIAS_LOGIN_SQL = "SELECT c.name, MAX(COALESCE(a.admin_level, 0)) AS lvl, MAX(EXISTS(SELECT 1 FROM bans b"
        .. " WHERE b.name = c.name AND b.active = 1 AND (b.expires_at IS NULL OR b.expires_at > NOW()))) AS banned"
        .. " FROM connection_log c LEFT JOIN accounts a ON a.id = c.account_id"
        .. " WHERE c.name <> ? AND (c.serial = ? OR c.ip = ?) GROUP BY c.name ORDER BY c.name LIMIT 32"
    function M.checkAliases(p)
        local params = { getPlayerName(p), getPlayerSerial(p), getPlayerIP(p) }
        db.query(ALIAS_LOGIN_SQL, params, function(rows, pl)
            if not rows or not isElement(pl) then
                return
            end
            local staffOnline = 0
            for _, other in ipairs(getElementsByType("player")) do
                if ctx.level(other) >= 1 then
                    staffOnline = staffOnline + 1
                end
            end
            local report = logic.aliasReport(rows, staffOnline)
            if not report then
                return
            end
            if report.banned then
                ctx.msgStaff(1, "#FF5050 >  Warning: One or more of those aliases is banned!")
            end
            if report.kick then
                ctx.util.log("staff", "info", "%s kicked: banned alias among %s", getPlayerName(pl), report.list)
                return ctx.kick(pl, nil, logic.ALIAS_BANNED_KICK)
            end
            ctx.msgStaff(report.level, " >  Aliases: #33CCFF(%d)#FFAA00 %s", report.count, report.list)
        end, p)
    end

    function M.forget(p)
        if state.frozen[p] then
            unfreeze(p, true)
        end
    end

    return M
end
