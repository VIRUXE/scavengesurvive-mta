-- Detection fields: /field draws four-point polygons with a Z band that the anticheat resource logs entries into
-- (anticheat/server/fields.lua); they never punish anyone. Upstream: admin/detfield*.pwn. Deviation: upstream's
-- dialog editor and per-field player exceptions are not ported (docs/anticheat.md), the command covers add,
-- list, log and remove, and every add and remove is a staff_actions row.
return function(ctx)
    local db, logic = ctx.db, ctx.logic
    local M = {}
    local USAGE = " >  Usage: /field add <name> <x1 y1 x2 y2 x3 y3 x4 y4 minZ maxZ> | list | log <name> | remove <name>"
    local ERRORS = {
        ARGS = " >  Usage: /field add <name> <x1 y1 x2 y2 x3 y3 x4 y4 minZ maxZ>",
        NAME = " >  Field names are letters, digits, '_' and '-' (64 at most).",
        NUMBER = " >  Every field coordinate must be a number.",
        ZBAND = " >  minZ must be lower than maxZ.",
    }

    -- anticheat includes staff, not the other way round: only poke it while it runs.
    local function refreshAnticheat()
        local res = getResourceFromName("anticheat")
        if res and getResourceState(res) == "running" then
            exports.anticheat:refreshFields()
        end
    end

    local function add(p, args)
        local field, err = logic.parseField(args)
        if not field then
            return ctx.say(p, ERRORS[err] or USAGE)
        end
        local sql = "INSERT INTO anticheat_fields (name, points, min_z, max_z) VALUES (?, ?, ?, ?)"
        db.exec(sql, { field.name, toJSON(field.points), field.minZ, field.maxZ, n = 4 }, function(ok, actor)
            if not ok then
                return ctx.say(actor, " >  Could not add '%s'; the name may already be in use.", field.name)
            end
            refreshAnticheat()
            ctx.say(actor, " >  Detection field '%s' added.", field.name)
            ctx.log(actor, "field_add", nil, nil, logic.fieldSummary(field))
        end, p)
    end

    local function remove(p, name)
        db.exec("DELETE FROM anticheat_fields WHERE name = ?", { name }, function(ok, actor, affected)
            if not ok or (tonumber(affected) or 0) == 0 then
                return ctx.say(actor, " >  There is no detection field called '%s'.", name)
            end
            refreshAnticheat()
            ctx.say(actor, " >  Detection field '%s' removed.", name)
            ctx.log(actor, "field_remove", nil, nil, name)
        end, p)
    end

    local function list(p)
        db.query("SELECT name, min_z, max_z FROM anticheat_fields ORDER BY name", {}, function(rows, actor)
            if not rows or #rows == 0 then
                return ctx.say(actor, " >  There are no detection fields.")
            end
            for _, row in ipairs(rows) do
                ctx.say(actor, " >  %s (Z %.1f to %.1f)", row.name, tonumber(row.min_z), tonumber(row.max_z))
            end
        end, p)
    end

    local function log(p, name)
        local sql = "SELECT l.player_name, l.x, l.y, l.z, l.logged_at FROM anticheat_field_logs l"
            .. " JOIN anticheat_fields f ON f.id = l.field_id WHERE f.name = ? ORDER BY l.id DESC LIMIT 10"
        db.query(sql, { name }, function(rows, actor)
            if not rows or #rows == 0 then
                return ctx.say(actor, " >  No entries recorded for '%s'.", name)
            end
            for _, row in ipairs(rows) do
                local x, y, z = tonumber(row.x), tonumber(row.y), tonumber(row.z)
                ctx.say(actor, " >  %s at %.1f, %.1f, %.1f (%s)", row.player_name, x, y, z, tostring(row.logged_at))
            end
        end, p)
    end

    ctx.command({
        name = "field",
        level = 2,
        usage = "/field add|list|log|remove ...",
        help = "Detection fields: log who enters a staff-drawn area",
        fn = function(p, args)
            local action, name = args[1], args[2]
            if action == "add" then
                add(p, { unpack(args, 2) })
            elseif action == "remove" and name then
                remove(p, name)
            elseif action == "list" then
                list(p)
            elseif action == "log" and name then
                log(p, name)
            else
                ctx.say(p, USAGE)
            end
        end,
    })

    return M
end
