local v = dofile("resources/[scavengesurvive]/vehicles/shared/logic/vehicle.lua")

local TIP_TOOL = {
    TUTORVEHVER = "Spanner",
    TUTORVEHBRO = "Screwdriver",
    TUTORVEHBIT = "Hammer",
    TUTORVEHSLI = "Ratchet",
}

-- at every health (including the band edges and fractional values) the tip names exactly the tool that works,
-- and there is no tip when no tool would do anything
local h = 0
while h <= 1000 do
    local tool = v.repairToolForHealth(h)
    local key = v.repairTipKey(h)
    if tool then
        assert(TIP_TOOL[key] == tool, ("health %s: tip %s but tool %s"):format(h, tostring(key), tool))
    else
        assert(key == nil, ("health %s: tip %s but no tool works"):format(h, tostring(key)))
    end
    h = h + 0.5
end

-- band edges: the chunk value itself belongs to the band above
assert(v.repairTipKey(v.HEALTH_CHUNK_2 - 0.5) == "TUTORVEHVER")
assert(v.repairTipKey(v.HEALTH_CHUNK_2) == "TUTORVEHBRO")
assert(v.repairTipKey(v.HEALTH_CHUNK_3) == "TUTORVEHBIT")
assert(v.repairTipKey(v.HEALTH_CHUNK_4) == "TUTORVEHSLI")
-- a field-repaired car sits at the cap: no tip, the Ratchet reports it fully repaired
assert(v.repairTipKey(v.HEALTH_MAX) == nil)
assert(v.repairToolForHealth(v.HEALTH_MAX) == nil)
assert(v.repairTipKey(v.HEALTH_MAX - 0.1) == "TUTORVEHSLI")
assert(v.repairTipKey(1000) == nil)
assert(v.repairTipKey(nil) == nil)

print("vehicle_repair_tip_test ok")
