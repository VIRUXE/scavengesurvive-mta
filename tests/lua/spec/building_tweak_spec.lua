-- Item tweaking (building/shared/logic/tweak.lua, upstream item-tweak.pwn, #133).
local tweak = dofile("resources/[scavengesurvive]/building/shared/logic/tweak.lua")
local canvas = dofile("resources/[scavengesurvive]/ui/shared/logic/canvas.lua")

local function near(a, b)
    return math.abs(a - b) < 1e-6
end

describe("item tweak", function()
    local DOOR = { vertical = { 0.0, 0.0, 90.0 }, horizontal = { 0.0, 90.0, 90.0 }, zOffset = 1.26817 }

    it("takes the heading from the stored rz less the built pose's rotation", function()
        assert.are.equal(30, tweak.heading(120, DOOR, "vertical"))
        assert.are.equal(30, tweak.heading(120, DOOR, "horizontal"))
        assert.are.equal(120, tweak.heading(120, nil, nil)) -- a constructed item that is not a defence
        assert.are.equal(350, tweak.heading(-10, nil, nil))
        assert.are.equal(270, tweak.heading(0, DOOR, nil)) -- no pose yet: the vertical rotation
    end)

    it("moves 5 cm along the front, back, left and right of the heading", function()
        local x, y, h = tweak.apply("forward", 10, 20, 0)
        assert.is_true(near(x, 10) and near(y, 20.05) and h == 0)
        x, y = tweak.apply("back", 10, 20, 0)
        assert.is_true(near(x, 10) and near(y, 19.95))
        x, y = tweak.apply("left", 10, 20, 0)
        assert.is_true(near(x, 9.95) and near(y, 20)) -- counter-clockwise of north is west
        x, y = tweak.apply("right", 10, 20, 0)
        assert.is_true(near(x, 10.05) and near(y, 20))
        x, y = tweak.apply("forward", 10, 20, 90) -- facing west
        assert.is_true(near(x, 9.95) and near(y, 20))
    end)

    it("turns 2 degrees either way and keeps the heading in [0, 360)", function()
        local x, y, h = tweak.apply("rotl", 1, 2, 359)
        assert.is_true(near(x, 1) and near(y, 2) and h == 1)
        local _, _, h2 = tweak.apply("rotr", 1, 2, 1)
        assert.are.equal(359, h2)
        assert.is_nil(tweak.apply("teleport", 1, 2, 0))
    end)

    it("keeps the item within 1.5 m of where it was built", function()
        assert.is_true(tweak.inRange(1.0, 1.0, 0, 0))
        assert.is_false(tweak.inRange(1.5, 0, 0, 0))
        assert.is_false(tweak.inRange(1.2, 1.2, 0, 0))
        -- 30 steps of 5 cm straight ahead stop at the range
        local x, y, h = 0, 0, 0
        local inside = 0
        for _ = 1, 40 do
            local nx, ny, nh = tweak.apply("forward", x, y, h)
            if tweak.inRange(nx, ny, 0, 0) then
                x, y, h = nx, ny, nh
                inside = inside + 1
            end
        end
        assert.are.equal(29, inside)
    end)

    it("blocks the move while anyone stands within 2.2 m of the item", function()
        assert.is_true(tweak.blocks(1, 1, 0, 0, 0, 0))
        assert.is_true(tweak.blocks(0, 0, 2.1, 0, 0, 0))
        assert.is_false(tweak.blocks(2.2, 0, 0, 0, 0, 0))
        assert.is_false(tweak.blocks(0, 0, 3, 0, 0, 0)) -- above it does not count as in the way
    end)

    it("draws the arrow from the item along its heading with two barbs at the tip", function()
        local lines = tweak.arrow(10, 20, 5, 0, 1.0, 0.3)
        assert.are.equal(3, #lines)
        assert.same({ 10, 20, 5.3, 10, 21, 5.3 }, {
            lines[1][1],
            lines[1][2],
            lines[1][3],
            lines[1][4],
            near(lines[1][5], 21) and 21 or lines[1][5],
            lines[1][6],
        })
        for i = 2, 3 do
            assert.is_true(near(lines[i][1], 10) and near(lines[i][2], 21)) -- both barbs start at the tip
            assert.is_true(lines[i][5] < 21) -- and point back towards the item
        end
        local west = tweak.arrow(0, 0, 0, 90)
        assert.is_true(near(west[1][4], -1) and near(west[1][5], 0))
    end)

    it("lays the pad out on the right edge of any screen and finds the button under the mouse", function()
        local wide = canvas.new(1920, 1080)
        local rects = tweak.layout(canvas, wide)
        assert.are.equal(#tweak.BUTTONS, #rects)
        local s = 1080 / 480
        local done = rects[#rects]
        assert.are.equal("done", done.id)
        assert.is_true(near(done.x, 1920 - (640 - 550) * s))
        assert.is_true(near(done.y, 420 * s) and near(done.w, 80 * s) and near(done.h, 20 * s))
        assert.are.equal("done", tweak.hit(rects, done.x + 5, done.y + 5))
        assert.are.equal("forward", tweak.hit(rects, rects[3].x + 1, rects[3].y + 1))
        assert.is_nil(tweak.hit(rects, 10, 10))
        -- the same canvas units land at the same place relative to the right edge on 4:3
        local narrow = tweak.layout(canvas, canvas.new(1024, 768))
        assert.is_true(near(1024 - narrow[#narrow].x, 1920 - done.x) == false) -- scale differs with height
        assert.is_true(near((1024 - narrow[#narrow].x) / (768 / 480), 90))
    end)

    it("lists every pad button with an action the server knows, plus toggle and done", function()
        local ids = {}
        for _, b in ipairs(tweak.BUTTONS) do
            ids[b.id] = true
            assert.is_true(tweak.ACTIONS[b.id] ~= nil or b.id == "toggle" or b.id == "done")
        end
        for action in pairs(tweak.ACTIONS) do
            assert.is_true(ids[action], action .. " has no button")
        end
    end)
end)
