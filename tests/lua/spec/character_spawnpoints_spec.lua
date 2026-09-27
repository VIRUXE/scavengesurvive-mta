local sp = dofile("resources/[scavengesurvive]/character/shared/logic/spawnpoints.lua")
describe("spawnpoints", function()
    it("has the 14 upstream shoreline points and never repeats the last one", function()
        assert.equals(14, #sp.list)
        assert.same({ -2923.4396, -70.4305, 0.7973, 269.0305 }, sp.list[1])
        local i = 0
        local rng = function(n)
            i = i + 1
            return ((i - 1) % n) + 1
        end
        local idx = sp.pick(1, rng)
        assert.not_equals(1, idx)
    end)
end)
