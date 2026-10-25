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
        tooltips = row.tooltips ~= 0,
        active = row.active ~= 0,
    }
end

function accounts.new(deps)
    local self = { attempts = {} } -- serial -> { n = failures, since = tick of the first failure }
    local now = deps.now or getTickCount
    -- hashing and verifying are asynchronous: the player may have quit by the time they return
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
        local sql = "SELECT id, name, password_hash, admin_level, lang, tooltips, active, last_ip, last_serial"
            .. " FROM accounts WHERE name = ?"
        deps.db.one(sql, { name }, function(row)
            cb(row)
        end)
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
                        local account = {
                            id = insertId,
                            name = name,
                            adminLevel = 0,
                            lang = "en",
                            tooltips = true,
                            active = true,
                        }
                        cb(true, "OK", account)
                    end
                )
            end)
        end)
    end

    -- cb(ok, code, account, attempts): a wrong password, or one shorter than four characters (upstream counts
    -- those as a try too), comes back as BAD_PASSWORD with the running attempt count.
    function self.login(player, name, pw, cb)
        local serial = tostring(deps.serial(player))
        local a = attemptsFor(serial)
        if a and a.n >= MAX_ATTEMPTS then
            return cb(false, "TOO_MANY_ATTEMPTS")
        end
        local function failed()
            local cur = attemptsFor(serial) or { n = 0, since = now() }
            cur.n = cur.n + 1
            self.attempts[serial] = cur
            return cb(false, "BAD_PASSWORD", nil, cur.n)
        end
        if #pw < 4 then
            return failed()
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
                    return failed()
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

    -- cb(ok, code): OK, WEAK_PASSWORD (new one outside 4..32), NO_MATCH (old one wrong) or DB_ERROR.
    function self.changePassword(accountId, oldPw, newPw, cb)
        local valid, reason = rules.validatePassword(newPw)
        if not valid then
            return cb(false, reason)
        end
        deps.db.one("SELECT password_hash FROM accounts WHERE id = ?", { accountId }, function(row)
            if not row then
                return cb(false, "DB_ERROR")
            end
            deps.verify(oldPw, row.password_hash, function(match)
                if not match then
                    return cb(false, "NO_MATCH")
                end
                deps.hash(newPw, function(hash)
                    local sql = "UPDATE accounts SET password_hash = ? WHERE id = ?"
                    deps.db.exec(sql, { hash, accountId }, function(ok)
                        cb(ok and true or false, ok and "OK" or "DB_ERROR")
                    end)
                end)
            end)
        end)
    end

    -- Auto-login (access.autoLoginAllowed already matched the row's IP and serial): no password, same bookkeeping.
    function self.loginTrusted(player, row, cb)
        self.attempts[tostring(deps.serial(player))] = nil
        local sql = "UPDATE accounts SET last_login_at = NOW(), last_ip = ?, last_serial = ? WHERE id = ?"
        deps.db.exec(sql, { deps.ip(player), deps.serial(player), row.id })
        cb(true, "OK", toAccount(row))
    end

    return self
end

return accounts
