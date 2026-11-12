local lug = dofile("resources/[scavengesurvive]/vehicles/shared/logic/lugnuts.lua")

local function near(a, b)
    assert(math.abs(a - b) < 1e-6, ("expected %s got %s"):format(b, a))
end

-- a tight nut runs all the way out, and no further
local progress = lug.apply(1, -lug.TURN * 2, -1, lug.TURN)
near(progress, 0)
assert(lug.done(progress, -1))
near(lug.apply(1, -lug.TURN / 2, -1, lug.TURN), 0.5)

-- fitting starts at the end of the stud and runs in
progress = lug.apply(0, lug.TURN / 4, 1, lug.TURN)
near(progress, 0.25)
assert(not lug.done(progress, 1))
-- turning the wrong way does not undo a nut that is being tightened
near(lug.apply(0.2, -1, 1, lug.TURN), 0.2)
near(lug.apply(0.2, 1, 1, 0), 0.2)

local states = { 0, 0, 0, 0 }
assert(not lug.allDone(states, 1))
states = { 1, 1, 1, 1 }
assert(lug.allDone(states, 1))
assert(not lug.allDone(states, -1))
assert(not lug.allDone({}, 1))

-- selection steps round the ring and skips the nuts that are already done
states = { 1, 0, 1, 0, 0 }
assert(lug.nextOpen(states, 1, 1, 1) == 2)
assert(lug.nextOpen(states, 1, 2, 1) == 4)
assert(lug.nextOpen(states, 1, 2, -1) == 5)
assert(lug.nextOpen(states, 1, 5, 1) == 2)
assert(lug.nextOpen({ 1, 0 }, 1, 2, 1) == 2)
assert(lug.nextOpen({ 1, 1 }, 1, 1, 1) == nil)

local layout = lug.layout(4, 10)
near(layout[1].x, 0)
near(layout[1].y, -10)
assert(layout[2].x > 0)

-- one report cannot finish a nut: the step cap is shorter than a full thread
progress = lug.apply(1, -lug.MAX_STEP, -1, lug.TURN)
assert(progress > lug.LOOSE)

print("lug nut threading checks passed")
