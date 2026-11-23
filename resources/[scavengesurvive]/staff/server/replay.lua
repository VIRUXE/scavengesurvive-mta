-- /replay: rebuild what one player did in a time range, for the viewer only (the replay resource does the work, see
-- docs/superpowers/specs/2026-11-23-replay-design.md). Moderator level, on duty.
return function(ctx)
    local db = ctx.db
    local M = {}

    local USAGE = "/replay <player|#charId> <from> [<to>|<length>] | /replay stop | /replay list <player>"
    local HELP = "Replay a player's movements and what they touched; times: 2026-11-18 19:15, 19:15, -2h, 30m"

    local function running()
        local res = getResourceFromName("replay")
        return res and getResourceState(res) == "running"
    end

    local function fmt(ts)
        return os.date("%Y-%m-%d %H:%M:%S", tonumber(ts))
    end

    local function list(p, name)
        if not name then
            return ctx.say(p, " >  Usage: %s", USAGE)
        end
        local sql = "SELECT a.id, a.name, c.id AS char_id,"
            .. " (SELECT UNIX_TIMESTAMP(MIN(t0)) FROM replay_chunk r WHERE r.char_id = c.id) AS rec_from,"
            .. " (SELECT UNIX_TIMESTAMP(MAX(t0)) FROM replay_chunk r WHERE r.char_id = c.id) AS rec_to,"
            .. " (SELECT UNIX_TIMESTAMP(MIN(at)) FROM character_track t WHERE t.char_id = c.id) AS trk_from,"
            .. " (SELECT UNIX_TIMESTAMP(MAX(at)) FROM character_track t WHERE t.char_id = c.id) AS trk_to"
            .. " FROM accounts a JOIN characters c ON c.account_id = a.id WHERE a.name = ?"
            -- a staff account above the viewer's level is not theirs to replay, so its ranges are not shown either
            .. " AND (a.admin_level <= ? OR a.id = ?) ORDER BY c.id DESC LIMIT 5"
        local viewerLevel = tonumber(exports.auth:getAdminLevel(p)) or 0
        local viewerAccount = tonumber(exports.auth:getAccountId(p)) or 0
        db.query(sql, { name, viewerLevel, viewerAccount }, function(rows)
            if not rows or #rows == 0 then
                return ctx.say(p, " >  No such account: %s", name)
            end
            for _, r in ipairs(rows) do
                ctx.say(
                    p,
                    " >  %s character %d: recorder %s, trail %s",
                    r.name,
                    r.char_id,
                    r.rec_from and (fmt(r.rec_from) .. " .. " .. fmt(r.rec_to)) or "nothing",
                    r.trk_from and (fmt(r.trk_from) .. " .. " .. fmt(r.trk_to)) or "nothing"
                )
            end
        end)
    end

    ctx.command({
        name = "replay",
        level = 2,
        playerOnly = true,
        usage = USAGE,
        help = HELP,
        fn = function(p, args)
            if not running() then
                return ctx.say(p, " >  The replay resource is not running.")
            end
            local first = args[1] and args[1]:lower() or nil
            if first == "stop" then
                if not exports.replay:stopSession(p, "stopped") then
                    ctx.say(p, " >  You are not replaying.")
                end
                return
            end
            if first == "list" then
                return list(p, args[2])
            end
            if not args[1] or not args[2] then
                return ctx.say(p, " >  Usage: %s", USAGE)
            end
            local words = {}
            for i = 2, #args do
                words[#words + 1] = args[i]
            end
            local from, to = exports.replay:parseRange(words)
            if not from then
                return ctx.say(p, " >  %s", tostring(to))
            end
            local ok, why = exports.replay:startSession(p, { target = args[1], from = from, to = to })
            if not ok then
                return ctx.say(p, " >  Replay: %s", tostring(why))
            end
        end,
    })

    return M
end
