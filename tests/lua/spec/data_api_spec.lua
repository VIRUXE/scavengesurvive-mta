local mock = require("tests.lua.helpers.mta_mock")
describe("Data api", function()
    before_each(function()
        mock.install()
        -- emulate MTA file access for the loader
        _G.fileExists = function(p) local f = io.open("resources/[scavengesurvive]/data/" .. p, "rb"); if f then f:close(); return true end; return false end
        _G.fileOpen = function(p) return io.open("resources/[scavengesurvive]/data/" .. p, "rb") end
        _G.fileGetSize = function(f) local cur = f:seek(); local size = f:seek("end"); f:seek("set", cur); return size end
        _G.fileRead = function(f, n) return f:read(n) end
        _G.fileClose = function(f) f:close() end
        _G.Data = nil
        dofile("resources/[scavengesurvive]/data/shared/lang.lua")
        dofile("resources/[scavengesurvive]/data/shared/api.lua")
    end)
    it("exposes item types with resolved models", function()
        local knife = Data.itemType("Knife")
        assert.equals(335, knife.mtaModel); assert.is_false(knife.sampOnly)
        local wrench = Data.itemType("Wrench")
        assert.is_true(wrench.sampOnly); assert.equals(1974, wrench.mtaModel)
        assert.is_nil(Data.itemType("Nope"))
        assert.equals("NULL", Data.itemTypes()[1])
    end)
    it("exposes loot tables and calibres", function()
        assert.is_true(#Data.lootTable("world_civilian").entries > 10)
        assert.equals(0.25, Data.calibreBleed("9mm"))
    end)
    it("translates with fallback and formatting", function()
        assert.equals(" >  #FFFF00Language changed to English!", Data.t("en", "LANGCHANGE"))
        assert.equals("Wounded: leg\nSeverity: Minor", Data.t("en", "WOUNDEDMSSG", "leg", "Minor"))
        assert.equals("NOPE_KEY", Data.t("en", "NOPE_KEY"))
        assert.equals(Data.t("en", "LANGCHANGE"), Data.t("xx", "LANGCHANGE"))
        assert.is_true(#Data.languages() >= 10)
    end)
end)
