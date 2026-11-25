local spawn = dofile("resources/[scavengesurvive]/vehicles/shared/logic/spawn.lua")
local types = dofile("resources/[scavengesurvive]/data/generated/vehicle_types.lua")

local function zero()
    return 0
end

local function names(list)
    local out = {}
    for _, t in ipairs(list) do
        out[t.uname] = true
    end
    return out
end

local indexed = spawn.index({})
for _, uname in ipairs(types.order) do
    indexed.list[#indexed.list + 1] = types.byUname[uname]
    indexed.byUname[uname] = types.byUname[uname]
end

local land = { group_name = "Civilian", categories = "P", sizes = "SM", rz = 90 }
local water = { group_name = "Civilian", categories = "S", sizes = "SM", rz = 90 }
local cars = { group_name = "Civilian", categories = "C", sizes = "S", rz = 0 }

local onLand = names(spawn.candidates(land, indexed, zero))
local onWater = names(spawn.candidates(water, indexed, zero))
local toys = names(spawn.candidates(cars, indexed, zero))

assert(not onLand.Skimmer, "the Skimmer stays off airfields")
assert(onLand.Rustler, "a land plane still rolls at an airfield")
assert(onWater.Skimmer, "the Skimmer rolls on a boat point")
assert(not onWater.Rustler, "a land plane does not roll on the water")
assert(not toys.RCBandit and not toys.RCTiger and not toys.RCCam, "RC cars never pass a zero chance")
assert(spawn.roll({ group_name = "Civilian", categories = "P", sizes = "S", rz = 0, type_name = "Skimmer" }, indexed, 100, zero) == nil, "a named Skimmer point on land stays empty")
local named = spawn.roll({ group_name = "Civilian", categories = "S", sizes = "M", rz = 0, type_name = "Skimmer" }, indexed, 100, zero)
assert(named and named.type.uname == "Skimmer", "a named Skimmer point on the water still rolls")

for _, uname in ipairs({ "RCBandit", "RCTiger", "RCCam", "RCBaron", "RCRaider", "RCGoblin" }) do
    assert(types.byUname[uname].spawnChance == 0, uname .. " chance is zero")
end
assert(types.byUname.Skimmer.water == true)
assert(types.byUname.Firetruck.size == "large")
assert(types.byUname.Sentinel.spawnChance == 78)
assert(types.byUname.Bobcat.spawnChance == 76)

print("vehicle spawn chance checks passed")
