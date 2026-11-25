-- Run from the repository root: lua tests/lua/item_reach_test.lua
loadstring = loadstring or load
localPlayer, root, resourceRoot = {}, {}, {}
local now, mode, heldTool = 0, "wall", nil
local playerZ, playerDimension, playerInterior = 0, 0, 0
local geomReady = true
local function collision(sx, sy, sz, tx, ty, tz)
    if mode == "clear" then
        return false
    end
    if mode == "map floor" or mode == "built floor" then
        local floor = -0.65
        if (sz > floor) == (tz > floor) then
            return false
        end
        local fraction = (floor - sz) / (tz - sz)
        return true, sx + (tx - sx) * fraction, sy + (ty - sy) * fraction, floor
    end
    if sx == tx and sy == ty then
        return false
    end
    if mode == "edge" and math.abs(tx) > 0.5 then
        return false
    end
    local wall = mode == "thin wall" and 0.9 or 0.5
    return ty >= wall, 0, wall, 0
end

exports = {
    lib = {
        getModule = function(_, name)
            if name == "geom" then
                return "return itemReachGeom"
            elseif name == "spatial" then
                return "return { bounds = function() return 'spatial_bounds' end }"
            end
            return "return { onChange = function() end }"
        end,
    },
}
function addEventHandler() end
function setTimer() end
function getElementsByType()
    return {}
end
function getTickCount()
    return now
end
function getElementPosition()
    return 0, 0, playerZ
end
function getElementDimension()
    return playerDimension
end
function getElementInterior()
    return playerInterior
end
function getElementRotation()
    return 0, 0, 0
end
function isElement(el)
    return el ~= nil
end
function getElementAttachedTo()
    return nil
end
function getDistanceBetweenPoints3D(x, y, z, a, b, c)
    return math.sqrt((x - a) ^ 2 + (y - b) ^ 2 + (z - c) ^ 2)
end

local builtFloor = {}
function processLineOfSight(...)
    local hit, x, y, z = collision(...)
    return hit, x, y, z, mode == "built floor" and builtFloor or nil
end
itemReachGeom = {
    ready = function()
        return geomReady
    end,
    clear = function(...)
        assert(mode ~= "built floor", "the server collision has map geometry only")
        return not collision(...)
    end,
}

local models = {
    onChanged = function() end,
    bounds = function()
        return -1, -0.1, -0.1, 1, 0.1, 0.1
    end,
}
function getElementMatrix()
    return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 0, 1, 0 } }
end
local world = dofile("resources/[scavengesurvive]/items/client/world.lua")({
    models = models,
    cooking = {},
    machines = {
        isMachine = function()
            return false
        end,
    },
    heldUname = function()
        return heldTool
    end,
})
local function up(fn, key)
    for i = 1, 100 do
        local name, value = debug.getupvalue(fn, i)
        if name == key then
            return value
        end
        if not name then
            break
        end
    end
    error("missing upvalue " .. key)
end

local objects = up(world.pickupCandidates, "objects")
local reachable = up(world.pickupCandidates, "reachable")
local types = up(up(reachable, "itemType"), "typeCache")
local defenceElements = up(up(reachable, "rayClear"), "defenceElements")
defenceElements[builtFloor] = true
types.Door = { size = 9 }
types.Thermal = { size = 1 }
objects[1] = { obj = {}, uname = "Door", x = 0, y = 1, z = 0, row = {} }

local function reaches(m)
    mode, now = m, now + 300
    return reachable(1, objects[1])
end
assert(not reaches("wall"), "a fully hidden large item stays blocked")
assert(reaches("edge"), "an unobstructed edge permits pickup")
assert(reaches("clear"), "a clear centre permits pickup")
types.Door.size = 1
assert(not reaches("edge"), "small items retain centre checks")
types.Door.size = 9
objects[1].defence = true
assert(not reaches("edge"), "built defences retain centre checks")
heldTool = "Crowbar"
assert(reaches("thin wall"), "a crowbar reaches a panel recessed 10 cm into a wall")
heldTool = nil
assert(not reachable(1, objects[1]), "changing tools invalidates the cached crowbar exception")
heldTool = "Screwdriver"
assert(not reaches("thin wall"), "other tools require an unobstructed ray")
heldTool = "Crowbar"
assert(not reaches("wall"), "a full wall blocks crowbar work")
objects[1].defence = false
assert(not reaches("thin wall"), "a crowbar cannot reach a loose item through a thin wall")
heldTool = nil

-- Keep the hidden row inside 2 m to exercise the line-of-sight filter independently of distance.
objects[1].uname, objects[1].z = "Thermal", -1
for _, floor in ipairs({ "map floor", "built floor" }) do
    assert(not reaches(floor), "the raised ray must stay below the " .. floor)
    local ids, blocked = world.pickupCandidates(2)
    assert(#ids == 0 and blocked, "F excludes items under the " .. floor)
    assert(not world.canCarryWorldItem(1, 2), "holding F excludes items under the " .. floor)
    playerZ = -1.35
    assert(world.pickupCandidates(2)[1] == 1, "F works from the item's side of the " .. floor)
    playerZ = 0
end

mode = "clear"
assert(world.pickupCandidates(2)[1] == 1, "ordinary ground loot is eligible")
mode = "map floor"
assert(#world.pickupCandidates(2) == 0, "an F press rechecks a previously visible item")
mode = "clear"
objects[1].z = -4
assert(#world.pickupCandidates(2) == 0, "pickup distance includes height")
assert(not world.canCarryWorldItem(1, 2), "carry distance includes height")

-- More blocked items than the previous exclusion list could contain.
mode = "wall"
for id = 1, 70 do
    objects[id] = { obj = {}, uname = "Thermal", x = 0, y = 1, z = 0, row = {} }
end
objects[71] = { obj = {}, uname = "Thermal", x = 0, y = 0.3, z = 0, row = {} }
local ids, blocked = world.pickupCandidates(2)
assert(#ids == 1 and ids[1] == 71 and blocked, "blocked loot cannot displace a visible pickup")

local serverWorld =
    dofile("resources/[scavengesurvive]/items/server/world.lua")({ state = {}, net = { handler = function() end } })
local row = { x = 0, y = 1, z = -1 }
mode = "map floor"
assert(not serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal), "server map collision rejects floor pickup")
mode = "wall"
assert(not serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal), "server map collision rejects wall pickup")
mode = "clear"
assert(serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal), "server permits clear pickup")
playerZ = 3
assert(not serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal), "server rejects a distant floor")
playerZ, playerDimension = 0, 1
assert(not serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal), "server rejects a different dimension")
playerDimension, playerInterior = 0, 1
assert(not serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal), "server rejects a different interior")
playerInterior, geomReady = 0, false
assert(
    serverWorld.inPickupReach(localPlayer, row, 2, types.Thermal),
    "client reach remains usable during collision reload"
)
local sql = serverWorld.findNearestSql(0, 0, 2, 0, 0, nil, { z = 1, ids = { 71 } })
assert(sql:find("POWER(i.z - 1.000000000, 2)", 1, true), "query filters altitude before selecting the nearest row")
assert(sql:find("i.id IN (71)", 1, true), "query accepts only eligible IDs")
local clean = serverWorld.cleanIds({ -1, 1.5, "71", 2147483648, math.huge })
assert(#clean == 1 and clean[1] == 71, "candidate IDs fit the database key range")
local taken, furnitureSql
local function pickup(_, _, target)
    taken = target.id
end
local tableRow = { id = 50, uname = "Table", x = 0, y = 1, z = 0 }
local topRow = { id = 51, uname = "Thermal", x = 0, y = 1, z = 0.8 }
local furniture = dofile("resources/[scavengesurvive]/items/server/furniture.lua")({
    state = { held = {} },
    db = {
        one = function(query, _, callback)
            furnitureSql = query
            callback(query:find("i.id IN (50, 51)", 1, true) and topRow or nil)
        end,
    },
    world = serverWorld,
    hands = { pickup = pickup },
    furniture = dofile("resources/[scavengesurvive]/items/shared/logic/furniture.lua"),
    charId = function()
        return 1
    end,
    type = function(uname)
        return types[uname]
    end,
})
furniture.interact(localPlayer, 1, nil, tableRow, { 50 }, 2)
assert(furnitureSql:find("i.id IN (50)", 1, true) and taken == 50, "furniture skips ineligible loot above it")
furniture.interact(localPlayer, 1, nil, tableRow, { 50, 51 }, 2)
assert(taken == 51, "a reachable item on top of furniture can still be taken")
topRow.z, taken = 4, nil
furniture.interact(localPlayer, 1, nil, tableRow, { 50, 51 }, 2)
assert(taken == nil, "furniture rechecks the selected item's distance before pickup")
print("item reach regression checks passed")
