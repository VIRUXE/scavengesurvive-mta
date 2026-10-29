local itemSpawn = dofile("resources/[scavengesurvive]/dev/shared/logic/item_spawn.lua")

describe("dev item_spawn logic", function()
    describe("isKingSergio", function()
        it("identifies KingSergio by player name case-insensitively", function()
            assert.is_true(itemSpawn.isKingSergio("KingSergio"))
            assert.is_true(itemSpawn.isKingSergio("kingsergio"))
            assert.is_true(itemSpawn.isKingSergio("KINGSERGIO"))
            assert.is_false(itemSpawn.isKingSergio("OtherPlayer"))
            assert.is_false(itemSpawn.isKingSergio(nil))
        end)

        it("identifies KingSergio by account name", function()
            assert.is_true(itemSpawn.isKingSergio("SomeNick", "KingSergio", nil))
            assert.is_true(itemSpawn.isKingSergio(nil, "kingsergio", nil))
            assert.is_false(itemSpawn.isKingSergio("SomeNick", "OtherAccount", nil))
        end)

        it("identifies KingSergio by account id 6", function()
            assert.is_true(itemSpawn.isKingSergio(nil, nil, 6))
            assert.is_true(itemSpawn.isKingSergio(nil, nil, "6"))
            assert.is_false(itemSpawn.isKingSergio(nil, nil, 7))
        end)
    end)

    describe("isAllowed", function()
        it("allows console", function()
            assert.is_true(itemSpawn.isAllowed({ isConsole = true }))
        end)

        it("allows anyone when open is true", function()
            assert.is_true(itemSpawn.isAllowed({ isOpen = true, adminLevel = 0 }))
        end)

        it("allows any staff with admin_level > 0", function()
            assert.is_true(itemSpawn.isAllowed({ adminLevel = 1 }))
            assert.is_true(itemSpawn.isAllowed({ adminLevel = 5 }))
        end)

        it("allows KingSergio even with adminLevel 0 and closed", function()
            assert.is_true(itemSpawn.isAllowed({
                adminLevel = 0,
                isOpen = false,
                playerName = "KingSergio",
            }))
            assert.is_true(itemSpawn.isAllowed({
                adminLevel = 0,
                isOpen = false,
                accountName = "KingSergio",
            }))
            assert.is_true(itemSpawn.isAllowed({
                adminLevel = 0,
                isOpen = false,
                accountId = 6,
            }))
        end)

        it("allows users listed in allowedList", function()
            assert.is_true(itemSpawn.isAllowed({
                adminLevel = 0,
                isOpen = false,
                playerName = "CustomTester",
                allowedList = "alice, customtester, bob",
            }))
            assert.is_true(itemSpawn.isAllowed({
                adminLevel = 0,
                isOpen = false,
                playerName = "CustomTester",
                allowedList = { "Alice", "CustomTester" },
            }))
        end)

        it("denies regular players with adminLevel 0 and not listed", function()
            assert.is_false(itemSpawn.isAllowed({
                adminLevel = 0,
                isOpen = false,
                playerName = "RandomPlayer",
                accountName = "RandomPlayer",
                accountId = 99,
            }))
            assert.is_false(itemSpawn.isAllowed(nil))
        end)
    end)

    describe("shouldLogItemSpawn", function()
        it("returns true for levels below max level 5", function()
            assert.is_true(itemSpawn.shouldLogItemSpawn(0))
            assert.is_true(itemSpawn.shouldLogItemSpawn(1))
            assert.is_true(itemSpawn.shouldLogItemSpawn(2))
            assert.is_true(itemSpawn.shouldLogItemSpawn(3))
            assert.is_true(itemSpawn.shouldLogItemSpawn(4))
            assert.is_true(itemSpawn.shouldLogItemSpawn(nil))
        end)

        it("returns false for max level 5 and above", function()
            assert.is_false(itemSpawn.shouldLogItemSpawn(5))
            assert.is_false(itemSpawn.shouldLogItemSpawn(6))
        end)
    end)

    describe("formatLog", function()
        it("formats discord message cleanly with zone and ID", function()
            local msg = itemSpawn.formatLog("KingSergio", "M9Pistol", 101, "Fort Carson")
            assert.equals(":package: **KingSergio** spawned item **M9Pistol** (ID: 101) in Fort Carson", msg)
        end)

        it("handles missing optional zone or ID", function()
            local msg = itemSpawn.formatLog("KingSergio", "Wrench", nil, nil)
            assert.equals(":package: **KingSergio** spawned item **Wrench**", msg)
        end)
    end)
end)
