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
    local self = { attempts = {} }

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
        local key = tostring(player)
        if (self.attempts[key] or 0) >= MAX_ATTEMPTS then
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
                    self.attempts[key] = (self.attempts[key] or 0) + 1
                    return cb(false, "BAD_PASSWORD")
                end
                self.attempts[key] = nil
                deps.db.exec(
                    "UPDATE accounts SET last_login_at = NOW(), last_ip = ?, last_serial = ? WHERE id = ?",
                    { deps.ip(player), deps.serial(player), row.id }
                )
                cb(true, "OK", toAccount(row))
            end)
        end)
    end

    function self.forget(player)
        self.attempts[tostring(player)] = nil
    end

    return self
end

return accounts
