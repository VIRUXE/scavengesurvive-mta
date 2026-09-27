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
end)
