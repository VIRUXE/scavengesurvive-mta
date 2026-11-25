-- Run from the repository root: lua tests/lua/defence_collision_test.lua
local base = "resources/[scavengesurvive]/"
local building = base .. "building/"
local models = dofile(building .. "server/defence_collision_models.lua")
local touchesDefence = dofile(building .. "server/defence_collision.lua")(models)
local defences = dofile(building .. "shared/logic/defences.lua")
local items = dofile(base .. "data/generated/item_types.lua").byUname

for uname, t in pairs(items) do
    if t.defence then
        assert(models[t.model], "Missing defence collision for " .. uname)
    end
end

local function placed(uname, pose, rz)
    local t = items[uname]
    local row = { type_uname = uname, x = 0, y = 0, z = 0 }
    local x, y, z, rotation, state = defences.build(t.defence, pose, row.x, row.y, row.z, rz, t.rotz)
    return touchesDefence(row, t.model, state, x, y, z, rotation), z
end

local touchesPanel, panelZ = placed("CorPanel", "vertical", 0)
assert(touchesPanel(0, 0.39, panelZ), "contact with the face of the panel")
assert(not touchesPanel(0, 0.40, panelZ), "one centimetre clear of the face")
assert(touchesPanel(1.5, 0, panelZ), "contact at the panel's end")
assert(not touchesPanel(1.6, 0.30, panelZ), "clear of a corner despite overlapping the expanded box")
assert(not touchesPanel(0, 0, panelZ + 2), "clear above the panel")

local touchesRotatedPanel = placed("CorPanel", "vertical", 90)
assert(touchesRotatedPanel(-0.39, 0, panelZ), "rotated panel face")
assert(not touchesRotatedPanel(1, 0, panelZ), "rotation moves the wall away")

local touchesFrame, frameZ = placed("LargeFrame", "vertical", 0)
assert(not touchesFrame(0, 0, frameZ), "the frame is open in the middle")
assert(touchesFrame(2, 2, frameZ), "a frame post can touch someone outside the old radius")

local touchesDoorway, doorwayZ = placed("InsulDoor", "vertical", 0)
assert(not touchesDoorway(0, 0, doorwayZ - 0.8), "the doorway opening stays clear")
assert(touchesDoorway(1.4, 0, doorwayZ - 0.8), "the side of the doorway blocks placement")

local touchesRamp, rampZ = placed("WoodPanel", "vertical", 0)
assert(touchesRamp(0, 0, rampZ), "the angled ramp's mesh touches a ped through its centre")
assert(not touchesRamp(0, -2.01, rampZ), "a ped near the angled ramp can stand clear")

local floor = { type_uname = "SmallPanel", x = 0, y = 0, z = 0, ground_nx = 0.6, ground_ny = 0 }
local flat = { pose = "horizontal", rx = 0, ry = 0 }
assert(touchesDefence(floor, 19843, flat, 0, 0, 0, 90)(-0.35, 0, 0.76), "rotation-only updates keep ground tilt")
assert(not touchesDefence(floor, 19843, flat, 0, 0.01, 0, 90)(-0.35, 0, 0.76), "moving clears the loose-item tilt")

local shiftedPanel = touchesDefence(
    { type_uname = "CorPanel" },
    items.CorPanel.model,
    { pose = "vertical", rx = 0, ry = 90 },
    0,
    0.05,
    panelZ,
    0
)
assert(shiftedPanel(0, 0.40, panelZ), "a tweak that brings the panel into contact is blocked")

print("defence_collision_test passed")
