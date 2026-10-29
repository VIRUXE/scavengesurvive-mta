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

    describe("calculateSpawnPosition", function()
        it("spawns 0.5m ahead at cardinal angles with z - 0.9 floor offset", function()
            -- North (0 degrees): dx = 0, dy = +0.5
            local sx, sy, sz, srz = itemSpawn.calculateSpawnPosition(100, 200, 10, 0)
            assert.near(100, sx, 1e-4)
            assert.near(200.5, sy, 1e-4)
            assert.near(9.1, sz, 1e-4)
            assert.equals(0, srz)

            -- West (90 degrees): dx = -0.5, dy = 0
            sx, sy, sz, srz = itemSpawn.calculateSpawnPosition(100, 200, 10, 90)
            assert.near(99.5, sx, 1e-4)
            assert.near(200, sy, 1e-4)
            assert.near(9.1, sz, 1e-4)
            assert.equals(90, srz)

            -- South (180 degrees): dx = 0, dy = -0.5
            sx, sy, sz, srz = itemSpawn.calculateSpawnPosition(100, 200, 10, 180)
            assert.near(100, sx, 1e-4)
            assert.near(199.5, sy, 1e-4)
            assert.near(9.1, sz, 1e-4)
            assert.equals(180, srz)

            -- East (270 degrees): dx = +0.5, dy = 0
            sx, sy, sz, srz = itemSpawn.calculateSpawnPosition(100, 200, 10, 270)
            assert.near(100.5, sx, 1e-4)
            assert.near(200, sy, 1e-4)
            assert.near(9.1, sz, 1e-4)
            assert.equals(270, srz)
        end)
    end)

    describe("resolveItemType", function()
        local generatedItems = dofile("resources/[scavengesurvive]/data/generated/item_types.lua")

        it("resolves by integer ID (0-based upstream item type id)", function()
            assert.equals("NULL", itemSpawn.resolveItemType(0, generatedItems))
            assert.equals("NULL", itemSpawn.resolveItemType("0", generatedItems))
            assert.equals("Knuckles", itemSpawn.resolveItemType(1, generatedItems))
            assert.equals("Knuckles", itemSpawn.resolveItemType("1", generatedItems))
            assert.equals("M9Pistol", itemSpawn.resolveItemType(22, generatedItems))
            assert.equals("M9Pistol", itemSpawn.resolveItemType("22", generatedItems))
            assert.equals("GasCan", itemSpawn.resolveItemType(92, generatedItems))
            assert.equals("GasCan", itemSpawn.resolveItemType("92", generatedItems))
        end)

        it("returns integer error when id is negative or out of bounds", function()
            local uname, err = itemSpawn.resolveItemType(-1, generatedItems)
            assert.is_nil(uname)
            assert.equals("Invalid item type from integer: '-1'", err)

            uname, err = itemSpawn.resolveItemType("-5", generatedItems)
            assert.is_nil(uname)
            assert.equals("Invalid item type from integer: '-5'", err)

            uname, err = itemSpawn.resolveItemType(99999, generatedItems)
            assert.is_nil(uname)
            assert.equals("Invalid item type from integer: '99999'", err)
        end)

        it("resolves by unique name case-insensitive substring match", function()
            assert.equals("GasCan", itemSpawn.resolveItemType("gascan", generatedItems))
            assert.equals("GasCan", itemSpawn.resolveItemType("GASCAN", generatedItems))
            assert.equals("M9Pistol", itemSpawn.resolveItemType("m9", generatedItems))
            assert.equals("Knife", itemSpawn.resolveItemType("knife", generatedItems))
        end)

        it("resolves by display name case-insensitive substring match when uname does not match", function()
            assert.equals("GasCan", itemSpawn.resolveItemType("petrol can", generatedItems))
            assert.equals("Knife", itemSpawn.resolveItemType("combat knife", generatedItems))
            assert.equals("Bat", itemSpawn.resolveItemType("baseball bat", generatedItems))
        end)

        it("returns string error when string is not found in uname or display name", function()
            local uname, err = itemSpawn.resolveItemType("nonexistent_item_xyz", generatedItems)
            assert.is_nil(uname)
            assert.equals("Invalid item type from string: 'nonexistent_item_xyz'", err)
        end)

        it("handles missing query", function()
            local uname, err = itemSpawn.resolveItemType(nil, generatedItems)
            assert.is_nil(uname)
            assert.is_truthy(err)

            uname, err = itemSpawn.resolveItemType("", generatedItems)
            assert.is_nil(uname)
            assert.is_truthy(err)
        end)
    end)

    describe("parseExtraData", function()
        it("returns nil when specifiers are nil or empty", function()
            assert.is_nil(itemSpawn.parseExtraData(nil, nil))
            assert.is_nil(itemSpawn.parseExtraData("", ""))
            assert.is_nil(itemSpawn.parseExtraData("   ", nil))
        end)

        it("parses single float value correctly (e.g. gascan f 20)", function()
            local res, err = itemSpawn.parseExtraData("f", "20")
            assert.is_nil(err)
            assert.same({ 20 }, res)

            res, err = itemSpawn.parseExtraData("f", "4.5")
            assert.is_nil(err)
            assert.same({ 4.5 }, res)
        end)

        it("parses multiple specifiers (e.g. gascan df 1, 4.5)", function()
            local res, err = itemSpawn.parseExtraData("df", "1, 4.5")
            assert.is_nil(err)
            assert.same({ 1, 4.5 }, res)

            res, err = itemSpawn.parseExtraData("df", "1,4.5")
            assert.is_nil(err)
            assert.same({ 1, 4.5 }, res)
        end)

        it("parses integer, string and boolean types", function()
            local res, err = itemSpawn.parseExtraData("ds", "10, Petrol")
            assert.is_nil(err)
            assert.same({ 10, "Petrol" }, res)

            res, err = itemSpawn.parseExtraData("b", "true")
            assert.is_nil(err)
            assert.same({ true }, res)

            res, err = itemSpawn.parseExtraData("b", "0")
            assert.is_nil(err)
            assert.same({ false }, res)
        end)

        it("returns sscanf error when data does not match specifier format", function()
            -- float where int expected
            local res, err = itemSpawn.parseExtraData("df", "1.5, 4.5")
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<df>'", err)

            -- string where float expected
            res, err = itemSpawn.parseExtraData("df", "1, abc")
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<df>'", err)

            -- count mismatch (too few values)
            res, err = itemSpawn.parseExtraData("df", "1")
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<df>'", err)

            -- count mismatch (too many values)
            res, err = itemSpawn.parseExtraData("f", "1, 2")
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<f>'", err)

            -- missing data
            res, err = itemSpawn.parseExtraData("f", nil)
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<f>'", err)

            res, err = itemSpawn.parseExtraData("f", "")
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<f>'", err)

            -- invalid specifier character
            res, err = itemSpawn.parseExtraData("x", "1")
            assert.is_nil(res)
            assert.equals("Format of exdata did not match specifier: 'p<,>e<x>'", err)
        end)
    end)

    describe("encodeJsonArray", function()
        it("encodes parsed arrays into MTA-wrapped JSON array strings", function()
            assert.equals("[[20]]", itemSpawn.encodeJsonArray({ 20 }))
            assert.equals("[[1,4.5]]", itemSpawn.encodeJsonArray({ 1, 4.5 }))
            assert.equals('[[1,"Petrol"]]', itemSpawn.encodeJsonArray({ 1, "Petrol" }))
            assert.equals("[[true,false]]", itemSpawn.encodeJsonArray({ true, false }))
        end)

        it("returns nil for non-tables", function()
            assert.is_nil(itemSpawn.encodeJsonArray(nil))
            assert.is_nil(itemSpawn.encodeJsonArray("not_a_table"))
        end)
    end)
end)
