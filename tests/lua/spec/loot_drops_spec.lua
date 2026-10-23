local drops = dofile("resources/[scavengesurvive]/loot/shared/logic/drops.lua")
local roll = dofile("resources/[scavengesurvive]/loot/shared/logic/roll.lua")

local function const(v)
    return function()
        return v
    end
end

describe("supply drop types", function()
    it("carries the five upstream types in init.pwn order", function()
        assert.equals(5, #drops.TYPES)
        assert.equals("airdrop_food_medical", drops.TYPES[1].table)
        assert.same({ 10800, 10800, 8 }, { drops.TYPES[5].interval, drops.TYPES[5].random, drops.TYPES[5].required })
    end)
    it("picks the first type that has enough players and has cooled down", function()
        local st = drops.newTypeState(drops.TYPES, 0, const(0)) -- offsets 0: everything due at tick 0
        assert.is_nil(drops.pickType(drops.TYPES, st, 2, 0)) -- nobody: food needs 3
        assert.equals(1, drops.pickType(drops.TYPES, st, 3, 0))
        drops.markDropped(drops.TYPES, st, 1, 0, const(0))
        assert.is_nil(drops.pickType(drops.TYPES, st, 3, 1000))
        assert.equals(2, drops.pickType(drops.TYPES, st, 4, 1000)) -- next type in the cycle
        assert.equals(1, drops.pickType(drops.TYPES, st, 3, 900 * 1000))
    end)
    it("adds a random offset after a drop", function()
        local st = drops.newTypeState(drops.TYPES, 0, const(0.5))
        assert.equals(300 * 1000, st[1].offset)
        drops.markDropped(drops.TYPES, st, 1, 50, const(0.25))
        assert.same({ 50, 150 * 1000 }, { st[1].lastDrop, st[1].offset })
        -- three players: only the food drop qualifies, and it waits interval + offset (900 + 150 s)
        assert.is_nil(drops.pickType(drops.TYPES, st, 3, 50 + 900 * 1000))
        assert.equals(1, drops.pickType(drops.TYPES, st, 3, 50 + 1050 * 1000))
        -- once the food drop has just fallen again, the next type in the cycle (low weapons, due at
        -- 2400 + 600 s) is the one taken when enough players are online
        drops.markDropped(drops.TYPES, st, 1, 2999 * 1000, const(0.25))
        assert.equals(2, drops.pickType(drops.TYPES, st, 9, 3000 * 1000))
    end)
    it("names half the drops and calls the rest Unknown", function()
        assert.equals("Food and Medical", drops.announceName("Food and Medical", const(0.2)))
        assert.equals("Unknown", drops.announceName("Food and Medical", const(0.7)))
        assert.matches('SUPPLY DROP: #33CCFF"Unknown"', drops.supplyText("Unknown", "Fort Carson"))
    end)
end)

describe("supply drop geometry", function()
    it("descends at 3.5 units per second from z 1000", function()
        assert.equals(math.floor(980 / 3.5 * 1000), drops.descentMs(1000, 20))
        assert.equals(1000, drops.descentMs(5, 4.9))
    end)
    it("fills 4..19 crate items and 22..32 cache items", function()
        assert.equals(4, drops.supplyCount(const(0)))
        assert.equals(19, drops.supplyCount(const(0.999)))
        assert.equals(22, drops.cacheCount(const(0)))
        assert.equals(32, drops.cacheCount(const(0.999)))
    end)
    it("splits loot between the crate slots and the ground, in rings of eight", function()
        local inside, around = drops.splitForCrate({ "a", "b", "c", "d", "e" }, 3)
        assert.same({ "a", "b", "c" }, inside)
        assert.same({ "d", "e" }, around)
        local pos = drops.ringPositions(0, 0, 10, const(0))
        assert.equals(10, #pos)
        assert.near(1.5, pos[1].x, 1e-6)
        assert.near(2.7, pos[9].x, 1e-6) -- second ring
    end)
    it("pushes a player off the landing spot", function()
        local x, y = drops.pushOut(1, 0, 0, 0, 3)
        assert.near(3, x, 1e-6)
        assert.near(0, y, 1e-6)
        assert.is_nil(drops.pushOut(5, 0, 0, 0, 3))
        local ox, oy = drops.pushOut(0, 0, 0, 0, 3) -- standing exactly on it
        assert.near(3, math.sqrt(ox * ox + oy * oy), 1e-6)
    end)
end)

describe("weapons cache signal", function()
    local points = { { x = 0, y = 0 }, { x = 0, y = 100 }, { x = 5000, y = 5000 } }
    it("computes a compass bearing and distance from a reference point", function()
        local b, d = drops.bearing(0, 0, 0, 100)
        assert.near(0, b, 1e-6) -- due north
        assert.near(100, d, 1e-6)
        b = drops.bearing(0, 0, 100, 0)
        assert.near(90, b, 1e-6) -- east
        b = drops.bearing(0, 0, -100, 0)
        assert.near(270, b, 1e-6)
    end)
    it("picks a reference cache point within 1000 m that is not the cache itself", function()
        local ref = drops.signalReference(points, 0, 0, const(0))
        assert.same({ 0, 100 }, { ref.x, ref.y })
        assert.is_nil(drops.signalReference({ { x = 0, y = 0 } }, 0, 0, const(0)))
        assert.equals(
            " >  [EBS]: WEAPONS CACHE SIGNAL: BEARING: 180.0DEG DISTANCE: 100.0M",
            drops.signalText(ref, 0, 0)
        )
    end)
end)

describe("roll.fill", function()
    it("takes count picks with replacement from the weighted sample", function()
        local tbl = { entries = { { weight = 100, uname = "A" }, { weight = 0, uname = "B" } } }
        assert.same({ "A", "A", "A" }, roll.fill(tbl, 3, const(0.5)))
        assert.same({}, roll.fill({ entries = { { weight = 0, uname = "B" } } }, 3, const(0.5)))
    end)
end)
