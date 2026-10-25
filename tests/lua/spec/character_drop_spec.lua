local drop = dofile("resources/[scavengesurvive]/character/shared/logic/drop.lua")

local function near(a, b)
    assert.is_true(math.abs(a - b) < 1e-6, string.format("%f ~= %f", a, b))
end

describe("item drop spots", function()
    it("rings nine spots 1.5 m out and puts the clothes 1 m east", function()
        local spots = drop.spots(100, 200)
        assert.equals(10, #spots)
        near(101.5, spots[1][1])
        near(200, spots[1][2])
        near(100 + 1.5 * math.cos(math.rad(80)), spots[3][1])
        near(200 + 1.5 * math.sin(math.rad(80)), spots[3][2])
        assert.same({ 101, 200 }, spots[10])
    end)
    it("takes the client's ground heights near the player and falls back otherwise", function()
        local spots = drop.spots(0, 0)
        local heights = { 9.2, 11.4, 4.9, false, 0 }
        drop.settle(spots, heights, 10, 135)
        near(9.2, spots[1][3]) -- under the feet
        near(135, spots[1][4]) -- facing like the player
        near(135, spots[10][4])
        near(11.4, spots[2][3]) -- uphill
        near(10 - 0.9, spots[3][3]) -- more than 5 m down
        near(10 - 0.9, spots[4][3]) -- no ground found
        near(10 - 0.9, spots[5][3]) -- outside the loaded map
        near(10 - 0.9, spots[10][3]) -- not reported
        drop.settle(spots, nil, 3)
        near(3 - 0.9, spots[1][3])
    end)
    it("splits the ring from the clothes spot", function()
        local ring, clothes = drop.split(drop.settle(drop.spots(0, 0), {}, 1))
        assert.equals(9, #ring)
        assert.same({ 1, 0, 0.1, 0 }, { clothes[1], clothes[2], math.floor(clothes[3] * 10 + 0.5) / 10, clothes[4] })
    end)
end)
