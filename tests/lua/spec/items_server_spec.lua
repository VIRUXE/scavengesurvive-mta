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
        Items.sent, Items.held, Items.heldObject, Items.wornObject, Items.typeCache = {}, {}, {}, {}, {}
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
        Items.rebuildCarried("p1")
        mock.removeElement("p1")
        mock.answer(#mock.queries, { { id = 5, uname = "Knife", hp = 1, data = false, kind = "held" } })
        for _, c in ipairs(mock.calls) do
            assert.not_equals("createObject", c[1])
        end
        assert.is_nil(Items.held["p1"])
    end)
    it("gives a held firearm a full magazine when the item carries no ammo", function()
        local load = require("tests.lua.helpers.load_module")
        mock.settings = {}
        Items.db, Items.net, Items.util = load("db"), load("net"), load("util")
        Items.sent, Items.held, Items.heldObject, Items.wornObject, Items.typeCache = {}, {}, {}, {}, {}
        local types = {
            M9Pistol = { mtaModel = 346, category = "weapon", categoryData = { baseWeapon = 22, magSize = 10 } },
            Knife = { mtaModel = 335, category = "weapon", categoryData = { baseWeapon = 4, magSize = 14 } },
            Grenade = { mtaModel = 342, category = "weapon", categoryData = { baseWeapon = 16, magSize = 0 } },
            Wrench = { mtaModel = 18633, category = "generic" },
        }
        Items.type = function(uname)
            return types[uname]
        end
        Items.charId = function()
            return 7
        end
        Items.toast = function() end
        _G.createObject = function()
            return "obj"
        end
        _G.attachElements, _G.setElementCollisionsEnabled, _G.destroyElement =
            function() end, function() end, function() end
        _G.setElementInterior, _G.setElementDimension, _G.getElementInterior, _G.getElementDimension =
            function() end, function() end, function()
                return 0
            end, function()
                return 0
            end
        local given = {}
        _G.giveWeapon = function(player, weapon, ammo, setCurrent)
            given[#given + 1] = { player, weapon, ammo, setCurrent }
        end
        _G.takeWeapon = function() end
        dofile("resources/[scavengesurvive]/items/server/hands.lua")
        mock.addElement("p1")
        Items.setHeld("p1", { id = 1, uname = "M9Pistol", hp = 1, data = {} })
        Items.setHeld("p1", { id = 2, uname = "M9Pistol", hp = 1, data = { mag = 3 } })
        Items.setHeld("p1", { id = 3, uname = "Knife", hp = 1, data = {} })
        Items.setHeld("p1", { id = 4, uname = "Grenade", hp = 1, data = {} })
        Items.setHeld("p1", { id = 5, uname = "Wrench", hp = 1, data = {} })
        assert.same({ "p1", 22, 10, true }, given[1])
        assert.same({ "p1", 22, 3, true }, given[2])
        assert.same({ "p1", 4, 1, true }, given[3])
        assert.same({ "p1", 16, 1, true }, given[4])
        assert.equals(4, #given)
    end)
    it("orders nearest-first with a distance cap", function()
        local sql = Items.findNearestSql(1, 2, 2.0)
        assert.matches("ST_Distance%(p.pos, POINT%(1, 2%)%) <= 2", sql)
        assert.matches("ORDER BY ST_Distance", sql)
        assert.matches("LIMIT 1", sql)
    end)
end)
