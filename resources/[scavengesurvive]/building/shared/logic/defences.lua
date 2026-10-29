-- Pure logic module for defences, keypads, and plot poles.
-- Ported from upstream Scavenge & Survive (core/itemtype/defences.pwn, core/item/plot-pole.pwn, core/ui/keypad.pwn).
local M = {}

M.DEFENCES = {
    LargeFrame = true,
    Door = true,
    MetalGate = true,
    TallFrame = true,
    MetalFrame = true,
    CorPanel = true,
    CrateDoor = true,
}

M.DOORS = {
    Door = true,
    MetalGate = true,
    CrateDoor = true,
}

function M.isDefenceItem(uname)
    return M.DEFENCES[uname] == true
end

function M.isDoorOrGate(uname)
    return M.DOORS[uname] == true
end

function M.verifyPasscode(expected, input)
    if not expected or expected == "" then
        return true
    end
    if not input then
        return false
    end
    local expStr = string.format("%04d", tonumber(expected) or 0)
    local inpStr = string.format("%04d", tonumber(input) or 0)
    return expStr == inpStr
end

function M.formatKeypadDisplay(inputDigits)
    local len = string.len(inputDigits or "")
    local display = ""
    for i = 1, 4 do
        if i <= len then
            display = display .. "*"
        else
            display = display .. "_"
        end
        if i < 4 then
            display = display .. " "
        end
    end
    return display
end

function M.isInsidePlotPole(px, py, poleX, poleY, radius)
    radius = radius or 20.0
    local dx = px - poleX
    local dy = py - poleY
    return (dx * dx + dy * dy) <= (radius * radius)
end

-- Building a defence (upstream StartBuildingDefence / ConvertItemToDefenceItem). The item type's `defence`
-- (DefineDefenceItem, generated into data) holds the rotation it stands at and lies at; a Screwdriver stands it up,
-- a Hammer lays it down, both after a 10 s hold shortened by the Construction skill.
M.BUILD_MS = 10000
M.REMOVE_MS = 10000
M.TOOL_POSE = { Screwdriver = "vertical", Hammer = "horizontal" }

-- the `defence` table a world item's data carries once built, or nil (data as fromJSON gives it: either the table
-- or the table wrapped in a one-element array)
function M.state(data)
    if type(data) ~= "table" then
        return nil
    end
    local d = data.defence or (type(data[1]) == "table" and data[1].defence)
    if type(d) == "table" and d.active == true then
        return d
    end
    return nil
end

-- The row a lying item becomes when built: the vertical pose is raised by zOffset, and the pose's rz is added to the
-- heading together with the type's rest rotz, so the client draws the object at (rx, ry, rz) as stored.
-- def = type.defence, restRz = type.rotz; returns z, rz and the state to store as data.defence.
function M.build(def, pose, z, rz, restRz)
    local rot = def[pose]
    if pose == "vertical" then
        z = z + (def.zOffset or 0)
    end
    rz = ((rz or 0) + (restRz or 0) + rot[3]) % 360
    return z, rz, { active = true, pose = pose, rx = rot[1], ry = rot[2] }
end

-- the reverse of build: the lying item's z and heading
function M.unbuild(def, state, z, rz, restRz)
    if state.pose == "vertical" then
        z = z - (def.zOffset or 0)
    end
    return z, ((rz or 0) - (restRz or 0) - def[state.pose][3]) % 360
end

-- A crowbar only works from the defence's back side (upstream _InteractDefenceWithItem): the angle between the
-- defence's facing and the direction to the player is between 90 and 270 degrees.
function M.isBehind(def, rz, x, y, px, py)
    local toPlayer = (-math.deg(math.atan2(px - x, py - y))) % 360
    local angle = ((rz or 0) - def.vertical[3] - toPlayer) % 360
    return angle > 90 and angle < 270
end

function M.calculateDoorRotation(baseRz, isOpen)
    baseRz = baseRz or 0
    if isOpen then
        return (baseRz + 90) % 360
    end
    return baseRz % 360
end

return M
