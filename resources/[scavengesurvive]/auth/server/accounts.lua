local rules
do
    local f = fileOpen and fileOpen("shared/logic/rules.lua", true) or nil
    if f then
        local src = fileRead(f, fileGetSize(f))
        fileClose(f)
        rules = assert(loadstring(src, "=auth/rules.lua"))()
    else
        rules = dofile("resources/[scavengesurvive]/auth/shared/logic/rules.lua")
    end
end

local accounts = {}
local MAX_ATTEMPTS = 5
-- failed logins are counted per serial over this window, so reconnecting does not reset them
local LOCK_MS = 10 * 60 * 1000

local function toAccount(row)
    return {
        id = row.id,
        name = row.name,
        adminLevel = row.admin_level or 0,
        lang = row.lang or "en",
        active = row.active ~= 0,
    }
end

function accounts.new(deps)
    local self = { attempts = {} } -- serial -> { n = failures, since = tick of the first failure }
    local now = deps.now or getTickCount
    -- hashing is asynchronous: the player may have quit by the time it returns
    local present = deps.present or function()
        return true
    end

    local function attemptsFor(serial)
        local a = self.attempts[serial]
        if a and now() - a.since >= LOCK_MS then
            self.attempts[serial] = nil
            return nil
        end
        return a
    end

    function self.lookup(name, cb)
        deps.db.one(
            "SELECT id, name, password_hash, admin_level, lang, active FROM accounts WHERE name = ?",
            { name },
            function(row)
                cb(row)
            end
        )
    end

    function self.register(player, name, pw, cb)
        if not rules.validateName(name) then
            return cb(false, "BAD_NAME")
        end
        local ok, reason = rules.validatePassword(pw)
        if not ok then
            return cb(false, reason)
        end
        self.lookup(name, function(row)
            if row == false then
                return cb(false, "DB_ERROR")
            end
            if row then
                return cb(false, "EXISTS")
            end
            deps.hash(pw, function(hash)
                if not present(player) then
                    return cb(false, "GONE")
                end
                deps.db.exec(
                    "INSERT INTO accounts (name, password_hash, last_ip, last_serial, last_login_at)"
                        .. " VALUES (?, ?, ?, ?, NOW())",
                    { name, hash, deps.ip(player), deps.serial(player) },
                    function(ok2, _, _, insertId)
                        if not ok2 then
                            return cb(false, "DB_ERROR")
                        end
                        cb(true, "OK", { id = insertId, name = name, adminLevel = 0, lang = "en", active = true })
                    end
                )
            end)
        end)
    end

    function self.login(player, name, pw, cb)
        local serial = tostring(deps.serial(player))
        local a = attemptsFor(serial)
        if a and a.n >= MAX_ATTEMPTS then
            return cb(false, "TOO_MANY_ATTEMPTS")
        end
        self.lookup(name, function(row)
            if row == false then
                return cb(false, "DB_ERROR")
            end
            if not row then
                return cb(false, "NO_ACCOUNT")
            end
            if row.active == 0 then
                return cb(false, "INACTIVE")
            end
            deps.verify(pw, row.password_hash, function(match)
                if not match then
                    local cur = attemptsFor(serial) or { n = 0, since = now() }
                    cur.n = cur.n + 1
                    self.attempts[serial] = cur
                    return cb(false, "BAD_PASSWORD")
                end
                self.attempts[serial] = nil
                if not present(player) then
                    return cb(false, "GONE")
                end
                deps.db.exec(
                    "UPDATE accounts SET last_login_at = NOW(), last_ip = ?, last_serial = ? WHERE id = ?",
                    { deps.ip(player), deps.serial(player), row.id }
                )
                cb(true, "OK", toAccount(row))
            end)
        end)
    end

    return self
end

return accounts
