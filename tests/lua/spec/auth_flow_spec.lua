local mock = require("tests.lua.helpers.mta_mock")
local load = require("tests.lua.helpers.load_module")
local accounts = dofile("resources/[scavengesurvive]/auth/server/accounts.lua")
describe("auth flow", function()
    local acc, db
    before_each(function()
        mock.install()
        mock.settings = {}
        db = load("db")
        db.connect("auth")
        acc = accounts.new({
            db = db,
            hash = function(pw, cb)
                cb("$2y$hash-of-" .. pw)
            end,
            verify = function(pw, hash, cb)
                cb(hash == "$2y$hash-of-" .. pw)
            end,
            serial = function()
                return "SERIAL"
            end,
            ip = function()
                return "127.0.0.1"
            end,
        })
        mock.addElement("p1")
    end)
    it("registers a new account and returns it", function()
        local got
        acc.register("p1", "Bob", "secret", function(ok, code, account)
            got = { ok, code, account }
        end)
        mock.answer(1, {}) -- lookup: no account
        mock.answer(2, {}, 1, 42) -- INSERT accounts -> insertId 42
        assert.same({ true, "OK" }, { got[1], got[2] })
        assert.equals(42, got[3].id)
        assert.equals("Bob", got[3].name)
        assert.matches("INSERT INTO accounts", mock.queries[2].sql)
    end)
    it("refuses registration when the name exists or the password is weak", function()
        local code
        acc.register("p1", "Bob", "abc", function(_, c)
            code = c
        end)
        assert.equals("WEAK_PASSWORD", code)
        acc.register("p1", "Bob", "secret", function(_, c)
            code = c
        end)
        mock.answer(1, { { id = 1, name = "Bob", password_hash = "x", admin_level = 0, lang = "en", active = 1 } })
        assert.equals("EXISTS", code)
    end)
    it("refuses registration with an invalid MTA name", function()
        local code
        acc.register("p1", "has space", "secret", function(_, c)
            code = c
        end)
        assert.equals("BAD_NAME", code)
        assert.equals(0, #mock.queries)
    end)
    it("logs in with the right password and locks after 5 failures", function()
        local codes = {}
        local row =
            { id = 7, name = "Bob", password_hash = "$2y$hash-of-secret", admin_level = 2, lang = "pt", active = 1 }
        acc.login("p1", "Bob", "wrong", function(_, c)
            codes[#codes + 1] = c
        end)
        mock.answer(1, { row })
        assert.equals("BAD_PASSWORD", codes[1])
        for _ = 1, 4 do
            acc.login("p1", "Bob", "wrong", function(_, c)
                codes[#codes + 1] = c
            end)
            mock.answer(#mock.queries, { row })
        end
        acc.login("p1", "Bob", "secret", function(_, c)
            codes[#codes + 1] = c
        end)
        assert.equals("TOO_MANY_ATTEMPTS", codes[#codes])
    end)
    it("counts a short password as a try and reports the attempt number", function()
        local got
        acc.login("p1", "Bob", "abc", function(ok, code, account, attempts)
            got = { ok, code, account, attempts }
        end)
        assert.same({ false, "BAD_PASSWORD", nil, 1 }, got)
        assert.equals(0, #mock.queries) -- no lookup, no bcrypt for a password that cannot be right
        local row =
            { id = 7, name = "Bob", password_hash = "$2y$hash-of-secret", admin_level = 0, lang = "en", active = 1 }
        acc.login("p1", "Bob", "wrong", function(_, _, _, attempts)
            got = attempts
        end)
        mock.answer(1, { row })
        assert.equals(2, got)
    end)
    it("logs in successfully and updates last login", function()
        local got
        local row =
            { id = 7, name = "Bob", password_hash = "$2y$hash-of-secret", admin_level = 2, lang = "pt", active = 1 }
        acc.login("p1", "Bob", "secret", function(ok, c, a)
            got = { ok, c, a }
        end)
        mock.answer(1, { row })
        assert.same({ true, "OK" }, { got[1], got[2] })
        assert.equals(2, got[3].adminLevel)
        assert.equals("pt", got[3].lang)
        assert.matches("UPDATE accounts SET last_login_at", mock.queries[2].sql)
    end)
    it("changes the password after verifying the old one", function()
        local got
        acc.changePassword(7, "secret", "newpass", function(ok, code)
            got = { ok, code }
        end)
        mock.answer(1, { { password_hash = "$2y$hash-of-secret" } })
        assert.matches("UPDATE accounts SET password_hash", mock.queries[2].sql)
        assert.same({ "$2y$hash-of-newpass", 7 }, mock.queries[2].params)
        mock.answer(2, {}, 1)
        assert.same({ true, "OK" }, got)
    end)
    it("refuses a password change on a wrong old password or a weak new one", function()
        local code
        acc.changePassword(7, "secret", "abc", function(_, c)
            code = c
        end)
        assert.equals("WEAK_PASSWORD", code)
        assert.equals(0, #mock.queries)
        acc.changePassword(7, "wrong", "newpass", function(_, c)
            code = c
        end)
        mock.answer(1, { { password_hash = "$2y$hash-of-secret" } })
        assert.equals("NO_MATCH", code)
        assert.equals(1, #mock.queries)
    end)
    it("logs in a trusted row without a password and records the login", function()
        local got
        local row = { id = 7, name = "Bob", admin_level = 0, lang = "en", active = 1 }
        acc.loginTrusted("p1", row, function(ok, code, account)
            got = { ok, code, account }
        end)
        assert.same({ true, "OK" }, { got[1], got[2] })
        assert.equals(7, got[3].id)
        assert.matches("UPDATE accounts SET last_login_at", mock.queries[1].sql)
    end)
end)
