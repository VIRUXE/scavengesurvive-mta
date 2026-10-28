local mock = require("tests.lua.helpers.mta_mock")
local load = require("tests.lua.helpers.load_module")
local ITEMS = "resources/[scavengesurvive]/items/"

-- hands.queueData / hands.flushData: per-shot ammo writes wait per item and reach the DB in one item_data_flush call
describe("items hands data batching", function()
    local state, db, hands

    -- the rows of a CALL item_data_flush(?) query, keyed by item id (MTA's toJSON wraps them in an outer array)
    local function flushRows(q)
        local decoded = mock.json.decode(q.params[1])
        if decoded[1] and decoded[1][1] then
            decoded = decoded[1]
        end
        local byId = {}
        for _, r in ipairs(decoded) do
            byId[r.id] = r.data
        end
        return byId, #decoded
    end

    local function flushQueries()
        local out = {}
        for _, q in ipairs(mock.queries) do
            if q.sql:find("item_data_flush", 1, true) then
                out[#out + 1] = q
            end
        end
        return out
    end

    before_each(function()
        mock.install()
        mock.settings = {}
        state = { settings = {}, sent = {}, held = {}, worn = {}, typeCache = {} }
        db = load("db")
        db.connect("items")
        _G.takeWeapon = function() end
        local fakeAmmo = {
            encodeData = function(data)
                return mock.json.encode(data)
            end,
        }
        hands = dofile(ITEMS .. "server/hands.lua")({
            db = db,
            net = load("net"),
            state = state,
            geometry = dofile(ITEMS .. "shared/logic/geometry.lua"),
            world = {},
            ammo = fakeAmmo,
            type = function()
                return { category = "generic" }
            end,
            charId = function()
                return 7
            end,
            toast = function() end,
        })
    end)

    it("keeps only the latest data per item and flushes every pending item in one call", function()
        hands.queueData({ id = 1, data = { mag = 10 } })
        hands.queueData({ id = 1, data = { mag = 9 } })
        hands.queueData({ id = 2, data = { mag = 4 } })
        assert.equals(0, #mock.queries)
        hands.flushData()
        local qs = flushQueries()
        assert.equals(1, #qs)
        assert.equals("CALL item_data_flush(?)", qs[1].sql)
        local rows, n = flushRows(qs[1])
        assert.equals(2, n)
        assert.same({ mag = 9 }, mock.json.decode(rows[1]))
        assert.same({ mag = 4 }, mock.json.decode(rows[2]))
        -- the pending rows are gone: a second flush sends nothing
        hands.flushData()
        assert.equals(1, #flushQueries())
    end)

    it("flushData(id) sends only that item and keeps the others pending", function()
        hands.queueData({ id = 1, data = { mag = 1 } })
        hands.queueData({ id = 2, data = { mag = 2 } })
        hands.flushData(2)
        local qs = flushQueries()
        assert.equals(1, #qs)
        local rows, n = flushRows(qs[1])
        assert.equals(1, n)
        assert.same({ mag = 2 }, mock.json.decode(rows[2]))
        hands.flushData()
        qs = flushQueries()
        assert.equals(2, #qs)
        rows, n = flushRows(qs[2])
        assert.equals(1, n)
        assert.same({ mag = 1 }, mock.json.decode(rows[1]))
    end)

    it("sends nothing when no data waits", function()
        hands.flushData()
        hands.flushData(5)
        assert.equals(0, #mock.queries)
    end)

    it("logs a failed flush", function()
        hands.queueData({ id = 3, data = { mag = 1 } })
        hands.flushData()
        mock.fail(#mock.queries, 1213, "deadlock")
        local logged = false
        for _, c in ipairs(mock.calls) do
            if c[1] == "outputDebugString" and tostring(c[2]):find("item_data_flush failed", 1, true) then
                logged = true
            end
        end
        assert.is_true(logged)
    end)

    it("queues a failed batch again unless newer data arrived meanwhile", function()
        hands.queueData({ id = 3, data = { mag = 1 } })
        hands.queueData({ id = 4, data = { mag = 5 } })
        hands.flushData()
        hands.queueData({ id = 4, data = { mag = 4 } }) -- fired while the batch was in flight
        mock.fail(#mock.queries, 1213, "deadlock")
        hands.flushData()
        local qs = flushQueries()
        assert.equals(2, #qs)
        local rows, n = flushRows(qs[2])
        assert.equals(2, n)
        assert.same({ mag = 1 }, mock.json.decode(rows[3]))
        assert.same({ mag = 4 }, mock.json.decode(rows[4]))
    end)

    it("clearHeld flushes the held item's data and leaves other items pending", function()
        mock.addElement("p1")
        state.held["p1"] = { id = 11, uname = "M9Pistol", data = { mag = 3 } }
        hands.queueData(state.held["p1"])
        hands.queueData({ id = 12, data = { mag = 7 } })
        hands.clearHeld("p1")
        assert.is_nil(state.held["p1"])
        local qs = flushQueries()
        assert.equals(1, #qs)
        local rows, n = flushRows(qs[1])
        assert.equals(1, n)
        assert.same({ mag = 3 }, mock.json.decode(rows[11]))
        hands.flushData()
        rows = flushRows(flushQueries()[2])
        assert.same({ mag = 7 }, mock.json.decode(rows[12]))
    end)

    it("flushData(nil, true) writes synchronously through dbQuery/dbPoll", function()
        local seen = {}
        _G.dbQuery = function(conn, sql, arg)
            seen.conn, seen.sql, seen.arg = conn, sql, arg
            return "qh"
        end
        _G.dbPoll = function(qh, timeout)
            seen.qh, seen.timeout = qh, timeout
            return { { ok = 1 } }
        end
        hands.queueData({ id = 21, data = { mag = 5 } })
        hands.queueData({ id = 22, data = { mag = 6 } })
        local res = hands.flushData(nil, true)
        assert.same({ { ok = 1 } }, res)
        assert.equals("conn", seen.conn)
        assert.equals("CALL item_data_flush(?)", seen.sql)
        assert.equals("qh", seen.qh)
        assert.equals(-1, seen.timeout)
        local decoded = mock.json.decode(seen.arg)
        assert.equals(2, #decoded)
        -- nothing is left to flush afterwards
        seen = {}
        hands.flushData(nil, true)
        assert.is_nil(seen.sql)
    end)

    it("queues data the ammo module does not encode (a Petrol Can's amount) as MTA JSON", function()
        local bare = dofile(ITEMS .. "server/hands.lua")({ db = db, net = load("net"), state = state, world = {} })
        bare.queueData({ id = 31, data = { amount = 19.4 } })
        bare.queueData({ id = 32, data = {} })
        bare.flushData()
        local rows = flushRows(flushQueries()[1])
        assert.same({ amount = 19.4 }, mock.json.decode(rows[31]))
        assert.is_nil(rows[32])
    end)

    it("queues without the ammo module too", function()
        local bare = dofile(ITEMS .. "server/hands.lua")({
            db = db,
            net = load("net"),
            state = state,
            geometry = dofile(ITEMS .. "shared/logic/geometry.lua"),
            world = {},
            type = function() end,
            charId = function()
                return 7
            end,
            toast = function() end,
        })
        bare.queueData({ id = 1, data = { mag = 1 } })
        bare.flushData()
        assert.equals(1, #mock.queries)
    end)

    it("decodeData safely preserves Lua tables and parses JSON strings", function()
        assert.same({}, hands.decodeData(nil))
        assert.same({}, hands.decodeData(""))
        assert.same({}, hands.decodeData(false))
        assert.same({}, hands.decodeData(123))

        -- A table is returned directly without corrupting or wiping
        local tbl = { mag = 2, reserve = 0, ammoItem = "AmmoHomeBuck" }
        local res = hands.decodeData(tbl)
        assert.are.equal(tbl, res)
        assert.equals(2, res.mag)

        -- A valid JSON string is parsed into a table
        local jsonStr = '{"mag":3,"reserve":0,"ammoItem":"AmmoBuck"}'
        local parsed = hands.decodeData(jsonStr)
        assert.same({ mag = 3, reserve = 0, ammoItem = "AmmoBuck" }, parsed)
    end)

    it("clearHeld flushes held weapon data even if not previously queued by fire", function()
        mock.addElement("p1")
        state.held["p1"] = { id = 42, uname = "PumpShotgun", data = { mag = 1, reserve = 0, ammoItem = "AmmoBuck" } }
        -- Not explicitly queued with hands.queueData before
        hands.clearHeld("p1")
        assert.is_nil(state.held["p1"])
        local qs = flushQueries()
        assert.equals(1, #qs)
        local rows, n = flushRows(qs[1])
        assert.equals(1, n)
        assert.same({ mag = 1, reserve = 0, ammoItem = "AmmoBuck" }, mock.json.decode(rows[42]))
    end)

    it("itemDropRequested flushes held weapon data before calling item_drop", function()
        mock.addElement("p1")
        _G.client, _G.source = "p1", "p1"
        state.held["p1"] = { id = 55, uname = "PumpShotgun", data = { mag = 2, reserve = 0, ammoItem = "AmmoBuck" } }
        _G.getElementPosition = function() return 100, 200, 10 end
        _G.getElementRotation = function() return 0, 0, 90 end
        _G.getElementInterior = function() return 0 end
        _G.getElementDimension = function() return 0 end

        mock.fire("itemDropRequested")
        local qs = mock.queries
        -- First query should be item_data_flush
        assert.is_true(#qs >= 2)
        assert.matches("CALL item_data_flush", qs[1].sql)
        local rows = flushRows(qs[1])
        assert.same({ mag = 2, reserve = 0, ammoItem = "AmmoBuck" }, mock.json.decode(rows[55]))
        -- Second query should be item_drop
        assert.matches("CALL item_drop", qs[2].sql)
    end)
end)
