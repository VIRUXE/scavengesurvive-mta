local lug = dofile("resources/[scavengesurvive]/vehicles/shared/logic/lugnuts.lua")

local function near(a, b)
    assert(math.abs(a - b) < 1e-6, ("expected %s got %s"):format(b, a))
end

local previous, following = lug.neighbours(5, 1)
assert(previous == 5 and following == 2)
previous, following = lug.neighbours(4, 4)
assert(previous == 3 and following == 1)

-- five tight nuts: the first one can only be cracked to the bind while its neighbours are seated
local tight = { 1, 1, 1, 1, 1 }
assert(lug.blocked(tight, 1, -1))
local progress, seized = lug.apply(1, -lug.TURN, -1, lug.TURN, true)
near(progress, 1 - lug.BIND)
assert(seized)
assert(not lug.done(progress, -1))

-- once both neighbours have been cracked, the nut runs off
local cracked = { 1, 1 - lug.BIND, 1, 1, 1 - lug.BIND }
assert(not lug.blocked(cracked, 1, -1))
progress, seized = lug.apply(1, -lug.TURN * 2, -1, lug.TURN, false)
near(progress, 0)
assert(not seized)
assert(lug.done(progress, -1))

-- installing starts loose and seizes at the bind the same way
local loose = { 0, 0, 0, 0 }
assert(lug.blocked(loose, 2, 1))
progress, seized = lug.apply(0, lug.TURN, 1, lug.TURN, true)
near(progress, lug.BIND)
assert(seized)
assert(not lug.done(progress, 1))
-- a counter-clockwise drag does not undo a nut that is being tightened
progress, seized = lug.apply(0.2, -1, 1, lug.TURN, false)
near(progress, 0.2)
assert(not seized)

local states = { 0, 0, 0, 0 }
assert(not lug.allDone(states, 1))
states = { 1, 1, 1, 1 }
assert(lug.allDone(states, 1))
assert(not lug.allDone(states, -1))

local layout = lug.layout(4, 10)
near(layout[1].x, 0)
near(layout[1].y, -10)
assert(layout[2].x > 0)

-- one report cannot finish a nut: the step cap is shorter than a full turn
local step = lug.MAX_STEP
progress = lug.apply(1, -step, -1, lug.TURN, false)
assert(progress > lug.LOOSE)

print("lug nut minigame checks passed")
