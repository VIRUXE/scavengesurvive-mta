-- Run from the repository root: lua tests/lua/item_reach_test.lua
loadstring = loadstring or load
localPlayer, root, resourceRoot = {}, {}, {}
local now, mode, size, heldTool = 0, "blocked", 9, nil
exports = { lib = { getModule = function() return 'return { onChange = function() end }' end } }
function addEventHandler() end
function getElementsByType() return {} end
function getTickCount() return now end
function getElementPosition() return 0, 0, 0 end
function getElementDimension() return 0 end
function getElementInterior() return 0 end
function isElement(el) return el ~= nil end
function getElementAttachedTo() return nil end
function getElementBoundingBox() return -1, -0.1, -0.1, 1, 0.1, 0.1 end
function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,1,0}} end
function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
function processLineOfSight(_,_,_,tx,ty)
    if mode == 'thinwall' then return ty >= 0.9, 0, 0.9, 0, nil end
    if mode == 'thickwall' then return ty >= 0.5, 0, 0.5, 0, nil end
    if mode == 'clear' or (mode == 'edge' and math.abs(tx) > 0.5) then return false end
    return true, 0, 0, 0, nil
end
local world = dofile('resources/[scavengesurvive]/items/client/world.lua')({
    models = { onChanged = function() end }, cooking = {},
    heldUname = function() return heldTool end,
})
local function up(fn, key)
    for i=1,100 do
        local name, value = debug.getupvalue(fn,i)
        if name == key then return value end
        if not name then break end
    end
    error('missing upvalue '..key)
end
local objects = up(world.blockedNear, 'objects')
local reachable = up(world.blockedNear, 'reachable')
local itemType = up(reachable, 'itemType')
up(itemType, 'typeCache').Door = { size = size }
objects[1] = { obj = {}, uname = 'Door', x=0, y=1, z=0, row={} }
local function blocked(m)
    mode, now = m, now+300
    return #world.blockedNear(2) > 0
end
assert(blocked('blocked'), 'a fully hidden large item stays blocked')
assert(not blocked('edge'), 'a reachable edge permits pickup')
assert(not blocked('clear'), 'a clear centre permits pickup')
up(itemType, 'typeCache').Door.size = 1
assert(blocked('edge'), 'small items retain centre checks')
up(itemType, 'typeCache').Door.size = 9
objects[1].defence = true
assert(blocked('edge'), 'built defences retain centre checks')
heldTool = 'Crowbar'
assert(not blocked('thinwall'), 'crowbar reaches a mounted panel recessed 10 cm into a wall')
heldTool = nil
assert(#world.blockedNear(2) == 1, 'switching tools invalidates the cached crowbar exception immediately')
heldTool = 'Screwdriver'
assert(blocked('thinwall'), 'other tools do not get the crowbar allowance')
heldTool = 'Crowbar'
assert(blocked('thickwall'), 'a full wall in front of the mounted panel still blocks crowbar work')
objects[1].defence = false
assert(blocked('thinwall'), 'loose items behind a thin wall remain blocked even with a crowbar')
assert(blocked('thickwall'), 'loose items behind a full wall remain blocked')
objects[1].defence = true
assert(blocked('blocked'), 'the crowbar allowance still requires a clear ray to the near surface')
print('item reach regression checks passed')
