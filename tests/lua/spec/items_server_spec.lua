local mock = require("tests.lua.helpers.mta_mock")
local load = require("tests.lua.helpers.load_module")
local ITEMS = "resources/[scavengesurvive]/items/"
describe("items server sql builders", function()
    local state, geometry, diff, db
    local function charId()
        return 7
    end
    local function newWorld()
        return dofile(ITEMS .. "server/world.lua")({
            db = db,
            state = state,
            geometry = geometry,
            diff = diff,
            charId = charId,
        })
    end
    -- hands with the world module it needs, a fixed character id, a silent toast and the given type lookup
    local function newHands(typeFn)
        return dofile(ITEMS .. "server/hands.lua")({
            db = db,
            net = load("net"),
            state = state,
            geometry = geometry,
            world = newWorld(),
            type = typeFn,
            charId = charId,
            toast = function() end,
        })
    end
    before_each(function()
        mock.install()
        mock.settings = {}
        state = { settings = {}, sent = {}, held = {}, worn = {}, holster = {}, hat = {}, mask = {}, armour = {}, typeCache = {} }
        geometry = dofile(ITEMS .. "shared/logic/geometry.lua")
        diff = dofile(ITEMS .. "shared/logic/diff.lua")
        db = load("db")
    end)
    it("uses a spatial MBRContains query with an inline polygon and no raw question marks in literals", function()
        local sql = newWorld().syncSql(100, 200, 150)
        assert.matches(
            "MBRContains%(ST_GeomFromText%('POLYGON%(%(%-50 50,250 50,250 350,%-50 350,%-50 50%)%)'%), p.pos%)",
            sql
        )
        assert.is_nil(sql:find("?", 1, true))
    end)
    it("sanitizes world defence passcodes before sending to clients", function()
        local world = newWorld()
        local data1 = {
            defence = { active = true, motor = true, keypad = 1, passcode = "1234" },
        }
        world.sanitizeData(data1)
        assert.is_nil(data1.defence.passcode)
        assert.is_true(data1.defence.locked)

        local data1b = {
            defence = { active = true, motor = true, keypad = 1, passcode = "0000" },
        }
        world.sanitizeData(data1b)
        assert.is_nil(data1b.defence.passcode)
        assert.is_false(data1b.defence.locked)

        local data2 = {
            { defence = { active = true, motor = true, keypad = 2, passcode = "4321" } },
        }
        world.sanitizeData(data2)
        assert.is_nil(data2[1].defence.passcode)
        assert.is_true(data2[1].defence.locked)

        local data3 = { passcode = "9999" }
        world.sanitizeData(data3)
        assert.is_nil(data3.passcode)
    end)
    it("ignores DB callbacks for a player who quit before the query returned", function()
        db.connect("items")
        _G.createObject = function()
            mock.calls[#mock.calls + 1] = { "createObject" }
            return "obj"
        end
        _G.attachElements, _G.setElementCollisionsEnabled, _G.destroyElement =
            function() end, function() end, function() end
        local hands = newHands(function()
            return { mtaModel = 335, category = "generic" }
        end)
        mock.addElement("p1")
        hands.rebuildCarried("p1")
        mock.removeElement("p1")
        mock.answer(#mock.queries, { { id = 5, uname = "Knife", hp = 1, data = false, kind = "held" } })
        for _, c in ipairs(mock.calls) do
            assert.not_equals("createObject", c[1])
        end
        assert.is_nil(state.held["p1"])
    end)
    it("gives a held firearm a full magazine when the item carries no ammo", function()
        local types = {
            M9Pistol = { mtaModel = 346, category = "weapon", categoryData = { baseWeapon = 22, magSize = 10 } },
            Knife = { mtaModel = 335, category = "weapon", categoryData = { baseWeapon = 4, magSize = 14 } },
            Grenade = { mtaModel = 342, category = "weapon", categoryData = { baseWeapon = 16, magSize = 0 } },
            Wrench = { mtaModel = 18633, category = "generic" },
        }
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
        local hands = newHands(function(uname)
            return types[uname]
        end)
        mock.addElement("p1")
        hands.setHeld("p1", { id = 1, uname = "M9Pistol", hp = 1, data = {} })
        hands.setHeld("p1", { id = 2, uname = "M9Pistol", hp = 1, data = { mag = 3 } })
        hands.setHeld("p1", { id = 3, uname = "Knife", hp = 1, data = {} })
        hands.setHeld("p1", { id = 4, uname = "Grenade", hp = 1, data = {} })
        hands.setHeld("p1", { id = 5, uname = "Wrench", hp = 1, data = {} })
        assert.same({ "p1", 22, 10, true }, given[1])
        assert.same({ "p1", 22, 3, true }, given[2])
        assert.same({ "p1", 4, 1, true }, given[3])
        assert.same({ "p1", 16, 1, true }, given[4])
        assert.equals(4, #given)
    end)
    it("holding a carried item (Wheel) does not set a carry animation loop that freezes movement", function()
        local animCalls = {}
        _G.setPedAnimation = function(player, block, anim, time, loop)
            animCalls[#animCalls + 1] = { player = player, block = block, anim = anim, time = time, loop = loop }
        end
        local hands = newHands(function(uname)
            return { uname = uname, useCarryAnim = true }
        end)
        mock.addElement("p1")
        hands.setHeld("p1", { id = 42, uname = "Wheel", hp = 5, data = {} })
        mock.runTimers()
        for _, call in ipairs(animCalls) do
            assert.not_equals("crry_prtial", call.anim)
        end
        assert.equals(42, state.held["p1"].id)
    end)
    it("orders nearest-first with a distance cap", function()
        local sql = newWorld().findNearestSql(1, 2, 2.0)
        assert.matches("ST_Distance%(p.pos, POINT%(1, 2%)%) <= 2", sql)
        assert.matches("ORDER BY ST_Distance", sql)
        assert.matches("LIMIT 1", sql)
    end)
    -- #73: hands.lua reaches the tent logic through the module, not through a client-trusting remote event
    it("pitches a tent through containers.pitchTent without a remote client", function()
        db.connect("items")
        _G.getElementPosition = function()
            return 10, 20, 3
        end
        _G.getDistanceBetweenPoints3D = function()
            return 1.0
        end
        local containers = dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function() end,
            charId = charId,
            toast = function() end,
            hands = {},
            world = newWorld(),
        })
        mock.addElement("p1")
        state.sent = { p1 = { [5] = true }, p2 = { [5] = true } }
        state.held["p1"] = { id = 9, uname = "Hammer" }
        assert.is_function(containers.pitchTent)
        assert.is_function(containers.dismantleTent)
        containers.pitchTent("p1", "5")
        mock.answer(#mock.queries, { { id = 5, uname = "TentPack", data = false, x = 10, y = 20, z = 3 } })
        mock.runTimers()
        local sqls = {}
        for _, q in ipairs(mock.queries) do
            sqls[#sqls + 1] = q.sql
        end
        assert.truthy(table.concat(sqls, "\n"):find("UPDATE items SET data = '{\"pitched\":true}'", 1, true))
        assert.truthy(table.concat(sqls, "\n"):find("INSERT INTO containers (kind, size, owner_item_id)", 1, true))
        -- every client that shows the pack gets the row again on its next sync (the model swaps to the tent)
        assert.is_nil(state.sent.p1[5])
        assert.is_nil(state.sent.p2[5])
    end)
    -- #97: GasCan and FireLighter look for a Barbecue in reach; Crowbar looks for a TentPack then deconstructs
    it("filters itemPickupRequested to Barbecue for GasCan/FireLighter and tents/defences/deconstruct for Crowbar", function()
        db.connect("items")
        _G.getElementPosition = function()
            return 10, 20, 3
        end
        _G.getElementInterior, _G.getElementDimension =
            function()
                return 0
            end, function()
                return 0
            end
        local crafted = {}
        _G.getResourceFromName = function(name)
            return name == "crafting" and "res_crafting" or nil
        end
        _G.getResourceState = function()
            return "running"
        end
        _G.exports = {
            crafting = {
                deconstruct = function(_, p)
                    crafted[#crafted + 1] = { "deconstruct", p }
                end,
                groundCraft = function(_, p)
                    crafted[#crafted + 1] = { "groundCraft", p }
                end,
            },
            data = {
                itemTypes = function()
                    return { "TentPack", "CorPanel", "Knife" }
                end,
            },
        }
        newHands(function(uname)
            if uname == "CorPanel" then
                return { category = "generic", defence = { vertical = { 0, 90, 0 }, horizontal = { 90, 90, 0 } } }
            end
            return { category = "generic" }
        end)
        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        state.held["p1"] = { id = 1, uname = "GasCan", hp = 3, data = { amount = 20 } }
        mock.fire("itemPickupRequested")
        assert.matches("i%.type_uname IN %('Barbecue'%)", mock.queries[#mock.queries].sql)

        mock.tick = 1000
        state.held["p1"] = { id = 2, uname = "FireLighter", hp = 1, data = {} }
        mock.fire("itemPickupRequested")
        assert.matches("i%.type_uname IN %('Barbecue'%)", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, {}) -- no barbecue in reach -> ground craft (e.g. 2 WoodLogs -> Campfire)
        assert.same({ { "groundCraft", "p1" } }, crafted)

        mock.tick = 2000
        state.held["p1"] = { id = 3, uname = "Crowbar", hp = 2, data = {} }
        mock.fire("itemPickupRequested")
        -- a crowbar also reaches defences, to take a built one down (building resource)
        assert.matches("i%.type_uname IN %('TentPack', 'CorPanel'%)", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, {}) -- no tent or defence in reach -> deconstruct
        assert.same({ { "groundCraft", "p1" }, { "deconstruct", "p1" } }, crafted)

        -- Motor, Keypad, AdvancedKeypad target defence types
        mock.tick = 3000
        state.held["p1"] = { id = 4, uname = "Motor", hp = 1, data = {} }
        mock.fire("itemPickupRequested")
        assert.matches("i%.type_uname IN %('CorPanel'%)", mock.queries[#mock.queries].sql)

        mock.tick = 4000
        state.held["p1"] = { id = 5, uname = "Keypad", hp = 1, data = {} }
        mock.fire("itemPickupRequested")
        assert.matches("i%.type_uname IN %('CorPanel'%)", mock.queries[#mock.queries].sql)

        mock.tick = 5000
        state.held["p1"] = { id = 6, uname = "AdvancedKeypad", hp = 1, data = {} }
        mock.fire("itemPickupRequested")
        assert.matches("i%.type_uname IN %('CorPanel'%)", mock.queries[#mock.queries].sql)
    end)

    it("holstering and unholstering with itemPutAwayRequested does not open inventory", function()
        db.connect("items")
        local apparel = {
            slotFor = function(uname)
                return uname == "M9Pistol" and "holster" or nil
            end,
            holsterAnim = function()
                return { block = "PED", anim = "PHONE_IN", time = 300 }
            end,
        }
        _G.setPedAnimation = function() end
        _G.getPedOccupiedVehicle = function()
            return false
        end

        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(uname)
                return { uname = uname, category = "weapon" }
            end,
            apparel = apparel,
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = {
                setGear = function(p, slot, it)
                    state[slot] = state[slot] or {}
                    state[slot][p] = it
                end,
                setHeld = function(p, it)
                    state.held[p] = it
                end,
                decodeData = function(d)
                    return d
                end,
            },
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        state.held["p1"] = { id = 10, uname = "M9Pistol", hp = 1, data = {} }

        -- 1. Holster held weapon
        mock.fire("itemPutAwayRequested")
        mock.runTimers()
        assert.matches("CALL item_wear", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_nil(state.held["p1"])
        assert.is_table(state.holster["p1"])
        assert.equals(10, state.holster["p1"].id)

        -- Verify inventoryOpened was NOT triggered
        for _, c in ipairs(mock.calls) do
            assert.is_false(c[1] == "triggerClientEvent" and c[3] == "inventoryOpened")
        end

        -- 2. Unholster weapon
        mock.tick = mock.tick + 2000
        mock.fire("itemPutAwayRequested")
        mock.runTimers()
        assert.matches("CALL item_unwear", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_nil(state.holster["p1"])
        assert.is_table(state.held["p1"])
        assert.equals(10, state.held["p1"].id)

        -- Verify inventoryOpened was still NOT triggered
        for _, c in ipairs(mock.calls) do
            assert.is_false(c[1] == "triggerClientEvent" and c[3] == "inventoryOpened")
        end
    end)

    it("holstering a shotgun with 2 bullets and unholstering preserves 2 bullets without replenishing", function()
        db.connect("items")
        local types = {
            PumpShotgun = {
                name = "Shotgun",
                category = "weapon",
                categoryData = { baseWeapon = 25, calibre = "12g", magSize = 6, maxReserveMags = 1 },
            },
        }
        local apparel = {
            slotFor = function(uname)
                return uname == "PumpShotgun" and "holster" or nil
            end,
            holsterAnim = function()
                return { block = "PED", anim = "PHONE_IN", time = 300 }
            end,
        }
        _G.setPedAnimation = function() end
        _G.getPedOccupiedVehicle = function() return false end
        _G.giveWeapon = function() end
        _G.takeWeapon = function() end

        local realHands = dofile(ITEMS .. "server/hands.lua")({
            db = db,
            net = load("net"),
            state = state,
            geometry = geometry,
            world = newWorld(),
            type = function(u) return types[u] end,
            charId = charId,
            toast = function() end,
            ammo = dofile(ITEMS .. "shared/logic/ammo.lua"),
        })

        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(u) return types[u] end,
            apparel = apparel,
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = realHands,
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        realHands.setHeld("p1", { id = 10, uname = "PumpShotgun", hp = 5, data = { mag = 2, reserve = 0, ammoItem = "AmmoHomeBuck" } })
        assert.equals(2, state.held["p1"].data.mag)

        -- 1. Holster held weapon
        mock.fire("itemPutAwayRequested")
        mock.runTimers()
        assert.matches("CALL item_wear", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_nil(state.held["p1"])
        assert.is_table(state.holster["p1"])
        assert.equals(10, state.holster["p1"].id)
        assert.equals(2, state.holster["p1"].data.mag)
        assert.equals("AmmoHomeBuck", state.holster["p1"].data.ammoItem)

        -- 2. Unholster weapon
        mock.tick = mock.tick + 2000
        mock.fire("itemPutAwayRequested")
        mock.runTimers()
        assert.matches("CALL item_unwear", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_nil(state.holster["p1"])
        assert.is_table(state.held["p1"])
        assert.equals(10, state.held["p1"].id)
        assert.equals(2, state.held["p1"].data.mag)
        assert.equals("AmmoHomeBuck", state.held["p1"].data.ammoItem)
    end)

    it("holstering a Mac10 (Uzi) with 14 bullets and unholstering preserves 14 bullets", function()
        db.connect("items")
        local types = {
            Mac10 = {
                name = "Mac-10",
                category = "weapon",
                categoryData = { baseWeapon = 28, calibre = "9mm", magSize = 30, maxReserveMags = 1 },
            },
        }
        local apparel = {
            slotFor = function(uname)
                return uname == "Mac10" and "holster" or nil
            end,
            holsterAnim = function()
                return { block = "PED", anim = "PHONE_IN", time = 300 }
            end,
        }
        _G.setPedAnimation = function() end
        _G.getPedOccupiedVehicle = function() return false end
        _G.giveWeapon = function() end
        _G.takeWeapon = function() end

        local realHands = dofile(ITEMS .. "server/hands.lua")({
            db = db,
            net = load("net"),
            state = state,
            geometry = geometry,
            world = newWorld(),
            type = function(u) return types[u] end,
            charId = charId,
            toast = function() end,
            ammo = dofile(ITEMS .. "shared/logic/ammo.lua"),
        })

        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(u) return types[u] end,
            apparel = apparel,
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = realHands,
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        realHands.setHeld("p1", { id = 20, uname = "Mac10", hp = 5, data = { mag = 14, reserve = 0, ammoItem = "Ammo9mm" } })
        assert.equals(14, state.held["p1"].data.mag)

        -- Holster
        mock.fire("itemPutAwayRequested")
        mock.runTimers()
        assert.matches("CALL item_wear", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_table(state.holster["p1"])
        assert.equals(14, state.holster["p1"].data.mag)

        -- Unholster
        mock.tick = mock.tick + 2000
        mock.fire("itemPutAwayRequested")
        mock.runTimers()
        assert.matches("CALL item_unwear", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_table(state.held["p1"])
        assert.equals(14, state.held["p1"].data.mag)
    end)

    it("itemPutAwayRequested with target = 'bag' flushes held data before calling container_put", function()
        db.connect("items")
        local flushedId = nil
        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(uname)
                return { uname = uname, category = "weapon" }
            end,
            apparel = {
                slotFor = function() return nil end,
            },
            charId = charId,
            toast = function() end,
            hands = {
                setHeld = function(p, it)
                    state.held[p] = it
                end,
                queueData = function(it) end,
                flushData = function(id)
                    flushedId = id
                end,
                decodeData = function(d) return d end,
            },
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        state.held["p1"] = { id = 44, uname = "PumpShotgun", hp = 5, data = { mag = 1, reserve = 0, ammoItem = "AmmoBuck" } }

        mock.fire("itemPutAwayRequested", "bag")
        -- wornBag query
        mock.answer(#mock.queries, { { id = 99, uname = "Backpack" } })

        assert.equals(44, flushedId)
        assert.matches("CALL container_put", mock.queries[#mock.queries].sql)
    end)

    it("itemPutAwayRequested with target = 'bag' stores held item into the worn bag directly", function()
        db.connect("items")
        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(uname)
                return { uname = uname, category = "misc" }
            end,
            apparel = {
                slotFor = function()
                    return nil
                end,
            },
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = {
                setHeld = function(p, it)
                    state.held[p] = it
                end,
                decodeData = function(d)
                    return d
                end,
            },
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        state.held["p1"] = { id = 42, uname = "Burger", hp = 1, data = {} }

        mock.fire("itemPutAwayRequested", "bag")
        -- wornBag queries items JOIN containers to find the worn bag's container ID
        assert.matches("holder_kind = 'bag'", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { id = 77, size = 16, uname = "Backpack" } })

        -- then calls container_put with bag container id (77)
        assert.matches("CALL container_put", mock.queries[#mock.queries].sql)
        assert.same({ 42, 7, 77 }, mock.queries[#mock.queries].params)
        mock.answer(#mock.queries, { { ok = 1, code = "OK", payload = "{}" } })

        assert.is_nil(state.held["p1"])
        assert.same({ "toast", "p1", "PUT_AWAY" }, mock.calls[#mock.calls])
    end)

    it("itemContainerMoveRequested with target = 'inventory' moves item to character inventory", function()
        db.connect("items")
        _G.exports = {
            character = {
                getInventoryContainerId = function()
                    return 55
                end,
            },
        }

        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(uname)
                return { uname = uname, category = "misc" }
            end,
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = {},
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"

        mock.fire("itemContainerMoveRequested", 99, "inventory")
        assert.matches("CALL container_move", mock.queries[#mock.queries].sql)
        assert.same({ 99, 7, 55, nil }, mock.queries[#mock.queries].params)
    end)

    it("itemPutAwayRequested with held Clothes wears them instead of putting into inventory", function()
        db.connect("items")
        local clothesUsed = {}
        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(uname)
                return { uname = uname, category = "generic" }
            end,
            apparel = {
                slotFor = function()
                    return nil
                end,
            },
            clothes = {
                use = function(p, itemId, data, fromHand)
                    clothesUsed[#clothesUsed + 1] = { player = p, itemId = itemId, data = data, fromHand = fromHand }
                end,
            },
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = {
                setHeld = function(p, it)
                    state.held[p] = it
                end,
                decodeData = function(d)
                    return d
                end,
            },
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        state.held["p1"] = { id = 777, uname = "Clothes", hp = 2, data = { skin = 60 } }

        mock.fire("itemPutAwayRequested")
        assert.equals(1, #clothesUsed)
        assert.equals("p1", clothesUsed[1].player)
        assert.equals(777, clothesUsed[1].itemId)
        assert.is_true(clothesUsed[1].fromHand)
    end)

    it("itemWearRequested with Clothes wears them via clothes.use", function()
        db.connect("items")
        local clothesUsed = {}
        dofile(ITEMS .. "server/containers.lua")({
            db = db,
            net = load("net"),
            state = state,
            type = function(uname)
                return { uname = uname, category = "generic" }
            end,
            apparel = {
                slotFor = function()
                    return nil
                end,
            },
            clothes = {
                use = function(p, itemId, data, fromHand, openContainerId)
                    clothesUsed[#clothesUsed + 1] = {
                        player = p,
                        itemId = itemId,
                        data = data,
                        fromHand = fromHand,
                        openContainerId = openContainerId,
                    }
                end,
            },
            charId = charId,
            toast = function(p, code)
                mock.calls[#mock.calls + 1] = { "toast", p, code }
            end,
            hands = {
                decodeData = function(d)
                    return d
                end,
            },
            world = newWorld(),
        })

        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"

        mock.fire("itemWearRequested", 888)
        assert.matches("SELECT id, type_uname AS uname", mock.queries[#mock.queries].sql)
        mock.answer(#mock.queries, { { id = 888, uname = "Clothes", hp = 2, data = { skin = 192 } } })

        assert.equals(1, #clothesUsed)
        assert.equals("p1", clothesUsed[1].player)
        assert.equals(888, clothesUsed[1].itemId)
        assert.is_false(clothesUsed[1].fromHand)
    end)
end)
