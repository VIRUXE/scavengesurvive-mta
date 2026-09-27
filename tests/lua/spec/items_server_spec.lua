local mock = require("tests.lua.helpers.mta_mock")
describe("items server sql builders", function()
    before_each(function()
        mock.install()
        _G.Items = { settings = {} }
        _G.exports = setmetatable({}, {
            __index = function()
                return setmetatable({}, {
                    __index = function()
                        return function()
                            return false
                        end
                    end,
                })
            end,
        })
        _G.fileOpen = function(p)
            return io.open("resources/[scavengesurvive]/items/" .. p, "rb")
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
        dofile("resources/[scavengesurvive]/items/server/world.lua")
    end)
    it("uses a spatial MBRContains query with an inline polygon and no raw question marks in literals", function()
        local sql = Items.syncSql(100, 200, 150)
        assert.matches(
            "MBRContains%(ST_GeomFromText%('POLYGON%(%(%-50 50,250 50,250 350,%-50 350,%-50 50%)%)'%), p.pos%)",
            sql
        )
        assert.is_nil(sql:find("?", 1, true))
    end)
    it("ignores DB callbacks for a player who quit before the query returned", function()
        local load = require("tests.lua.helpers.load_module")
        mock.settings = {}
        Items.db, Items.net, Items.util = load("db"), load("net"), load("util")
        Items.db.connect("items")
        Items.sent, Items.held, Items.heldObject, Items.typeCache = {}, {}, {}, {}
        Items.type = function()
            return { mtaModel = 335, category = "generic" }
        end
        Items.charId = function()
            return 7
        end
        Items.toast = function() end
        _G.createObject = function()
            mock.calls[#mock.calls + 1] = { "createObject" }
            return "obj"
        end
        _G.attachElements, _G.setElementCollisionsEnabled, _G.destroyElement =
            function() end, function() end, function() end
        dofile("resources/[scavengesurvive]/items/server/hands.lua")
        mock.addElement("p1")
        Items.rebuildHeld("p1")
        mock.removeElement("p1")
        mock.answer(#mock.queries, { { id = 5, uname = "Knife", hp = 1, data = false } })
        for _, c in ipairs(mock.calls) do
            assert.not_equals("createObject", c[1])
        end
        assert.is_nil(Items.held["p1"])
    end)
    describe("setHeld weapons", function()
        local given
        local types = {
            M9Pistol = { mtaModel = 346, category = "weapon", categoryData = { baseWeapon = 22, magSize = 10 } },
            Knife = { mtaModel = 335, category = "weapon", categoryData = { baseWeapon = 4, magSize = 14 } },
        }
        before_each(function()
            local load = require("tests.lua.helpers.load_module")
            mock.settings = {}
            Items.db, Items.net, Items.util = load("db"), load("net"), load("util")
            Items.sent, Items.held, Items.heldObject = {}, {}, {}
            Items.type = function(uname)
                return types[uname]
            end
            given = {}
            _G.createObject = function()
                return "obj"
            end
            _G.attachElements, _G.setElementCollisionsEnabled, _G.destroyElement =
                function() end, function() end, function() end
            _G.setElementInterior, _G.setElementDimension = function() end, function() end
            _G.getElementInterior, _G.getElementDimension = function()
                return 0
            end, function()
                return 0
            end
            _G.takeWeapon = function() end
            _G.giveWeapon = function(_, w, ammo)
                given[#given + 1] = { w, ammo }
            end
            dofile("resources/[scavengesurvive]/items/server/hands.lua")
            mock.addElement("p1")
        end)
        it("gives a firearm without a stored magazine a full one", function()
            Items.setHeld("p1", { id = 1, uname = "M9Pistol", hp = 1, data = {} })
            assert.same({ { 22, 10 } }, given)
        end)
        it("gives vanilla melee exactly one", function()
            Items.setHeld("p1", { id = 2, uname = "Knife", hp = 1 })
            assert.same({ { 4, 1 } }, given)
        end)
        it("keeps a stored magazine count", function()
            Items.setHeld("p1", { id = 3, uname = "M9Pistol", hp = 1, data = { mag = 4 } })
            assert.same({ { 22, 4 } }, given)
        end)
    end)
    it("orders nearest-first with a distance cap", function()
        local sql = Items.findNearestSql(1, 2, 2.0)
        assert.matches("ST_Distance%(p.pos, POINT%(1, 2%)%) <= 2", sql)
        assert.matches("ORDER BY ST_Distance", sql)
        assert.matches("LIMIT 1", sql)
    end)
end)
