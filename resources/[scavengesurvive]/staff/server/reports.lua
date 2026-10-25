-- Player reports: /report for everyone, /reports and /deletereports for staff.
-- Upstream: admin/report.pwn (storage) and report-cmds.pwn (the four filing modes and the staff list).
-- /report alone opens upstream's dialog chain; /report <name|near|killer> [reason] skips the menu (port addition).
return function(ctx)
    local db, logic, state = ctx.db, ctx.logic, ctx.state
    local M = {}

    -- target = { name, kind, x, y, z, interior, dimension }, captured when the player picks who to report
    local function file(reporter, target, reason)
        local sql = "INSERT INTO reports (name, reason, type, x, y, z, interior, dimension, by_name, by_account_id)"
            .. " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        local by, byId = ctx.name(reporter), ctx.accountId(reporter)
        local t = target
        local params = { t.name, reason:sub(1, 128), t.kind, t.x, t.y, t.z, t.interior, t.dimension, by, byId, n = 10 }
        db.exec(sql, params, function(ok, r)
            if not ok then
                return ctx.say(r, " >  Your report could not be saved; try again later.")
            end
            ctx.say(r, " >  Report filed. Thank you.")
            ctx.msgStaff(1, " >  %s reported %s, reason: %s", ctx.name(r), t.name, reason)
        end, reporter)
    end

    local function nearestPlayer(p, maxDist)
        local px, py, pz = getElementPosition(p)
        local best, bestDist = nil, maxDist
        for _, o in ipairs(getElementsByType("player")) do
            if o ~= p and not state.duty[o] and getElementDimension(o) == getElementDimension(p) then
                local ox, oy, oz = getElementPosition(o)
                local d = getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz)
                if d < bestDist then
                    best, bestDist = o, d
                end
            end
        end
        return best
    end

    -- An online or killer report carries the reporter's position, a near report the target's, a name report none.
    local function targetAt(name, kind, el)
        local x, y, z = getElementPosition(el)
        return {
            name = name,
            kind = kind,
            x = x,
            y = y,
            z = z,
            interior = getElementInterior(el),
            dimension = getElementDimension(el),
        }
    end

    local function nearTarget(p)
        local o = nearestPlayer(p, 100)
        if not o then
            return ctx.sayLang(p, "REPNOPF100M")
        end
        return targetAt(getPlayerName(o), logic.REPORT_TYPES.near, o)
    end

    local function killerTarget(p)
        local name = state.lastKiller[p]
        if not name then
            return ctx.sayLang(p, "REPNOPFOUND")
        end
        return targetAt(name, logic.REPORT_TYPES.killer, p)
    end

    local function nameTarget(name)
        return { name = name:sub(1, 24), kind = logic.REPORT_TYPES.name }
    end

    -- Upstream report-cmds.pwn: a mode list, then the online list or the offline name input, then the reason input;
    -- each "Back" returns to the mode list.
    local showMenu

    local BACK = { "Report", "Back" }

    local function askReason(p, target)
        local function answered(ok, text)
            if not ok then
                return showMenu(p)
            end
            local reason = logic.trim(text)
            if reason == "" then
                return askReason(p, target)
            end
            file(p, target, reason)
        end
        local body = "Enter the reason for your report below."
        ctx.openDialog(p, "report_reason", "input", "Enter report reason", body, BACK, answered)
    end

    local function askOfflineName(p)
        local function answered(ok, text)
            if not ok then
                return showMenu(p)
            end
            local name = logic.trim(text)
            if name == "" then
                return askOfflineName(p)
            end
            askReason(p, nameTarget(name))
        end
        ctx.openDialog(p, "report_name", "input", "Report Offline Player", "Enter name to report below", BACK, answered)
    end

    local function showOnline(p)
        local rows = {}
        for _, e in ipairs(ctx.onlinePlayers()) do
            if e.player ~= p then
                rows[#rows + 1] = { id = e.name, label = e.name }
            end
        end
        if #rows == 0 then
            ctx.say(p, " >  Nobody else is online.")
            return showMenu(p)
        end
        local function picked(name)
            local entry = logic.findPlayer(name, ctx.onlinePlayers())
            if not entry then
                return askReason(p, nameTarget(name))
            end
            askReason(p, targetAt(entry.name, logic.REPORT_TYPES.online, p))
        end
        ctx.openList(p, "report_online", "Report Online Player", rows, BACK, picked, function()
            showMenu(p)
        end)
    end

    local MENU = {
        { id = "online", label = "Specific player ID (who is online now)" },
        { id = "name", label = "Specific Player Name (Who isn't online now)" },
        { id = "killer", label = "Player that last killed me" },
        { id = "near", label = "Player closest to me" },
    }

    showMenu = function(p)
        ctx.openList(p, "report", "Report a player", MENU, { "Send", "Cancel" }, function(rowId)
            if rowId == "online" then
                return showOnline(p)
            elseif rowId == "name" then
                return askOfflineName(p)
            end
            local target = (rowId == "near" and nearTarget or killerTarget)(p)
            if target then
                askReason(p, target)
            else
                ctx.closeList(p)
            end
        end)
    end

    ctx.command({
        name = "report",
        level = 0,
        playerOnly = true,
        usage = "/report [name|near|killer] [reason]",
        help = "Report a player: the menu, or by name, the nearest player, or whoever last killed you",
        fn = function(p, args)
            local who, reason = args[1], logic.tail(args, 2)
            if not who then
                return showMenu(p)
            end
            local target
            if who:lower() == "near" then
                target = nearTarget(p)
            elseif who:lower() == "killer" then
                target = killerTarget(p)
            else
                local entry = logic.findPlayer(who, ctx.onlinePlayers())
                if entry and entry.player == p then
                    return ctx.say(p, " >  You cannot report yourself.")
                end
                -- an offline name is stored as typed (upstream "Specific Player Name (Who isn't online now)")
                target = entry and targetAt(entry.name, logic.REPORT_TYPES.online, p) or nameTarget(who)
            end
            if not target then
                return
            end
            if reason then
                return file(p, target, reason)
            end
            askReason(p, target)
        end,
    })

    local function showReports(p)
        local sql = "SELECT r.id, r.name, r.type, r.read_at, EXISTS(SELECT 1 FROM bans b WHERE b.name = r.name"
            .. " AND b.active = 1 AND (b.expires_at IS NULL OR b.expires_at > NOW())) AS banned"
            .. " FROM reports r WHERE r.active = 1 ORDER BY r.created_at DESC LIMIT 32"
        db.query(sql, {}, function(rows, actor)
            if not rows then
                return ctx.say(actor, " >  An error occurred.")
            end
            if #rows == 0 then
                return ctx.say(actor, " >  There are no reports to show.")
            end
            local bannedNames = {}
            for _, r in ipairs(rows) do
                if tonumber(r.banned) == 1 then
                    bannedNames[r.name] = true
                end
            end
            local rowsUi = logic.reportRows(rows, function(name)
                return bannedNames[name] == true
            end)
            local title = "Reports (" .. #rows .. ")"
            ctx.openList(actor, "reports", title, rowsUi, { "Options", "Close" }, function(rowId, actionId)
                M.action(actor, tonumber(rowId), actionId)
            end)
        end, p)
    end

    function M.action(actor, reportId, actionId)
        if not reportId then
            return
        end
        if actionId == "view" then
            local sql = "SELECT name, reason, type, x, y, z, by_name,"
                .. " DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS created FROM reports WHERE id = ?"
            db.one(sql, { reportId }, function(r, a)
                if not r then
                    return
                end
                db.exec("UPDATE reports SET read_at = COALESCE(read_at, NOW()) WHERE id = ?", { reportId })
                ctx.say(a, " >  #33CCFF%s#FFFF00 (%s) reported by %s on %s", r.name, r.type, r.by_name, r.created)
                ctx.say(a, " >  Reason: #33CCFF%s", r.reason)
                if r.x and r.x ~= false then
                    ctx.say(a, " >  Position: %.1f, %.1f, %.1f", r.x, r.y, r.z)
                end
                showReports(a)
            end, actor)
        elseif actionId == "goto" then
            if not state.duty[actor] and ctx.level(actor) < logic.MAX_LEVEL then
                ctx.say(actor, " >  Go on duty (/duty) to teleport to a report.")
                return showReports(actor)
            end
            db.one("SELECT x, y, z, interior, dimension FROM reports WHERE id = ?", { reportId }, function(r, a)
                if not r or not r.x or r.x == false then
                    ctx.say(a, " >  That report has no position.")
                    return showReports(a)
                end
                ctx.closeList(a)
                setElementInterior(a, tonumber(r.interior) or 0)
                setElementDimension(a, tonumber(r.dimension) or 0)
                setElementPosition(a, r.x, r.y, r.z + 1)
                ctx.log(a, "report_goto", nil, nil, "report " .. reportId)
            end, actor)
        elseif actionId == "delete" then
            local sql = "UPDATE reports SET active = 0, read_at = COALESCE(read_at, NOW()) WHERE id = ?"
            db.exec(sql, { reportId }, function(_, a)
                ctx.log(a, "report_delete", nil, nil, "report " .. reportId)
                showReports(a)
            end, actor)
        elseif actionId == "deleteall" then
            local sql = "UPDATE reports SET active = 0, read_at = COALESCE(read_at, NOW())"
                .. " WHERE name = (SELECT name FROM (SELECT name FROM reports WHERE id = ?) AS t)"
            db.exec(sql, { reportId }, function(_, a)
                ctx.log(a, "report_delete_all", nil, nil, "report " .. reportId)
                showReports(a)
            end, actor)
        elseif actionId == "unread" then
            db.exec("UPDATE reports SET read_at = NULL WHERE id = ?", { reportId }, function(_, a)
                showReports(a)
            end, actor)
        end
    end

    ctx.command({
        name = "reports",
        level = 1,
        usage = "/reports",
        help = "Open the report list",
        playerOnly = true,
        fn = showReports,
    })

    ctx.command({
        name = "deletereports",
        level = 2,
        usage = "/deletereports",
        help = "Delete every report that has been read",
        fn = function(p)
            local sql = "UPDATE reports SET active = 0 WHERE active = 1 AND read_at IS NOT NULL"
            db.exec(sql, {}, function(ok, actor, affected)
                if not ok then
                    return ctx.say(actor, " >  An error occurred.")
                end
                ctx.say(actor, " >  All read reports deleted (%d).", affected or 0)
                ctx.log(actor, "report_delete_read", nil, nil, tostring(affected or 0))
            end, p)
        end,
    })

    return M
end
