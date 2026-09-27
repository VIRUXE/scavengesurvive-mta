local mock = require("tests.lua.helpers.mta_mock")
local ROOT = "resources/[scavengesurvive]/character/"

local function findQuery(pattern)
    for i, q in ipairs(mock.queries) do
        if q.sql:find(pattern, 1, true) then
            return i, q
        end
    end
end

describe("character server flows", function()
    before_each(function()
        mock.install()
        mock.settings = {}
        _G.exports = {
            lib = {
                getModule = function(_, name)
                    local f = assert(io.open("resources/[scavengesurvive]/lib/modules/" .. name .. ".lua", "rb"))
                    local src = f:read("*a")
                    f:close()
                    return src
                end,
            },
            auth = {
                getAccountId = function()
                    return 3
                end,
            },
        }
        _G.fileOpen = function(p)
            return io.open(ROOT .. p, "rb")
        end
        _G.fileGetSize = function(f)
            local cur = f:seek()
            local size = f:seek("end")
            f:seek("set", cur)
            return size
        end
        _G.fileRead = function(f, n)
            return f:read(n)
        end
        _G.fileClose = function(f)
            f:close()
        end
        for _, name in ipairs({
            "spawnPlayer",
            "setElementHealth",
            "setCameraTarget",
            "fadeCamera",
            "setPlayerHudComponentVisible",
            "killPed",
        }) do
            _G[name] = function() end
        end
        _G.getElementPosition = function()
            return 10, 20, 5
        end
        _G.getElementInterior, _G.getElementDimension =
            function()
                return 0
            end, function()
                return 0
            end
        _G.isPedDead = function()
            return false
        end
        dofile(ROOT .. "server/main.lua")
        dofile(ROOT .. "server/death.lua")
        Character.db.connect("character")
        mock.addElement("p1")
        Character.byPlayer.p1 = { id = 42, hp = 50, food = 50, bleed = 0, wounds = 0, lastSent = {} }
        Character.byId[42] = "p1"
        _G.client, _G.source = "p1", "p1"
    end)

    it("refuses a respawn request while the character is alive", function()
        mock.fire("onCharacterRequestRespawn")
        assert.is_nil(findQuery("character_create"))
    end)

    it("dies once, and allows the respawn only after character_death_drop committed", function()
        assert.is_true(Character.die("p1", "killed", false))
        assert.is_false(Character.die("p1", "killed", false))
        local idx, q = findQuery("character_death_drop")
        assert.equals(5 - 0.9, q.params[4])
        mock.tick = 5000
        mock.fire("onCharacterRequestRespawn")
        assert.is_nil(findQuery("character_create"))
        mock.answer(idx, { { ok = 1, code = "OK", payload = '{"dropped":0}' } })
        assert.is_nil(Character.byPlayer.p1)
        mock.tick = 10000
        mock.fire("onCharacterRequestRespawn")
        assert.is_not_nil(findQuery("character_create"))
    end)

    it("keeps refusing the respawn when character_death_drop failed", function()
        Character.die("p1", "killed", false)
        mock.fail((findQuery("character_death_drop")), 1213, "deadlock")
        mock.fire("onCharacterRequestRespawn")
        assert.is_nil(findQuery("character_create"))
    end)
end)
