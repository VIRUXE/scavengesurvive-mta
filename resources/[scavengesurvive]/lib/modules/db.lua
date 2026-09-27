local db = { conn = false, tag = "game" }
local OPTIONS = "share=1;batch=0;autoreconnect=1;multi_statements=0;queue=game;log=1;suppress=1062;tag="

local function setting(key)
    local v = get("lib." .. key)
    return v ~= false and tostring(v) or nil
end

-- errors go to the debug console and the server log (like util.log with level "error")
local function logError(msg)
    msg = "[" .. db.tag .. "] " .. msg
    outputDebugString(msg, 1)
    outputServerLog(msg)
end

function db.options()
    return OPTIONS .. db.tag
end

function db.connect(tag)
    db.tag = tag or "game"
    local host = "dbname="
        .. (setting("db_name") or "scavengesurvive")
        .. ";host="
        .. (setting("db_host") or "127.0.0.1")
        .. ";port="
        .. (setting("db_port") or "3306")
        .. ";charset=utf8mb4"
    db.conn = dbConnect("mysql", host, setting("db_user") or "root", setting("db_pass") or "", db.options())
    if not db.conn then
        logError("dbConnect failed")
        return false
    end
    return true
end

local function poll(qh, sql)
    local rows, a, b = dbPoll(qh, 0)
    if rows == false then
        logError("SQL error " .. tostring(a) .. ": " .. tostring(b) .. " in " .. sql)
        return false
    end
    return rows, a, b
end

function db.query(sql, params, cb, ctx)
    params = params or {}
    return dbQuery(function(qh)
        local rows = poll(qh, sql)
        if cb then
            cb(rows, ctx)
        end
    end, {}, db.conn, sql, unpack(params))
end

function db.one(sql, params, cb, ctx)
    return db.query(sql, params, function(rows, c)
        if rows == false then
            return cb(false, c)
        end
        cb(rows[1], c)
    end, ctx)
end

function db.exec(sql, params, cb, ctx)
    params = params or {}
    return dbQuery(function(qh)
        local rows, affected, insertId = poll(qh, sql)
        if cb then
            cb(rows ~= false, ctx, affected, insertId)
        end
    end, {}, db.conn, sql, unpack(params))
end

function db.call(proc, params, cb, ctx)
    params = params or {}
    local n = params.n or #params -- Lua 5.1 cannot count a table with trailing nils; callers pass n
    local marks = {}
    for i = 1, n do
        marks[i] = "?"
    end
    local sql = "CALL " .. proc .. "(" .. table.concat(marks, ", ") .. ")"
    return dbQuery(function(qh)
        local rows = poll(qh, sql)
        if rows == false then
            return cb(false, ctx)
        end
        local row = rows[1] or {}
        local payload = nil
        if row.payload and row.payload ~= false and row.payload ~= "" then
            payload = fromJSON(row.payload)
        end
        cb({ ok = tonumber(row.ok) == 1, code = row.code or "NO_RESULT", payload = payload }, ctx)
    end, {}, db.conn, sql, unpack(params, 1, n))
end

function db.settings(cb)
    db.query("SELECT skey, svalue FROM settings", {}, function(rows)
        local map = {}
        if rows then
            for _, r in ipairs(rows) do
                map[r.skey] = r.svalue
            end
        end
        cb(map)
    end)
end

return db
