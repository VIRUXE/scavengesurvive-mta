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
        local hits = { { 9.2, 0, 0, 1 }, { 11.4, 0, 0, 1 }, { 4.9, 0, 0, 1 }, false, { "x", 0, 0, 1 } }
        drop.settle(spots, hits, 10)
        near(9.2, spots[1][3]) -- under the feet
        near(11.4, spots[2][3]) -- uphill
        near(10 - 0.9, spots[3][3]) -- more than 5 m down
        near(10 - 0.9, spots[4][3]) -- no ground found
        near(10 - 0.9, spots[5][3]) -- not a number
        near(10 - 0.9, spots[10][3]) -- not reported
        drop.settle(spots, nil, 3)
        near(3 - 0.9, spots[1][3])
        assert.same({ 0, 0 }, { spots[1][4], spots[1][5] })
    end)
    it("keeps the slope of the ground it lies on, flat beyond 45 degrees", function()
        local s30, c30 = math.sin(math.rad(30)), math.cos(math.rad(30))
        local s60, c60 = math.sin(math.rad(60)), math.cos(math.rad(60))
        local hits = {
            { 10, 2 * s30, 0, 2 * c30 }, -- 30 degrees, not unit length
            { 10, 0, -s60, c60 }, -- 60 degrees: a wall
            { 10, 0, 0, -1 }, -- upside down
            { 10, 0, 0, 0 }, -- no direction
            { 10, nil, 0, 1 }, -- incomplete
            { 4, s30, 0, c30 }, -- a fallback height lies flat
        }
        local spots = drop.settle(drop.spots(0, 0), hits, 10)
        near(s30, spots[1][4])
        near(0, spots[1][5])
        for i = 2, 6 do
            assert.same({ 0, 0 }, { spots[i][4], spots[i][5] })
        end
    end)
    it("splits the ring from the clothes spot", function()
        local ring, clothes = drop.split(drop.settle(drop.spots(0, 0), {}, 1))
        assert.equals(9, #ring)
        assert.equals(5, #clothes)
        assert.same({ 1, 0, 0, 0 }, { clothes[1], clothes[2], clothes[4], clothes[5] })
    end)
end)
