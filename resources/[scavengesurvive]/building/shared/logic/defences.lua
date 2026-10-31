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

function M.isDefenceItem(uname)
    return M.DEFENCES[uname] == true
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

-- Where the type's pivot lands in the world for an object drawn at (rx, ry, rz): R * pivot with MTA's object rotation
-- R = Rz * Rx * Ry (right-handed, the same as GTA's CMatrix::SetRotate). def.pivot is set for the hinged doors drawn
-- from re-pivoted copies (tools/port_defences.py): their model's origin is the middle of the door, upstream's was the
-- hinge, so a row's position is the hinge plus this offset. Zero for every other defence.
function M.pivotOffset(def, rx, ry, rz)
    local p = def.pivot
    if not p then
        return 0, 0, 0
    end
    local a, b, c = math.rad(rx or 0), math.rad(ry or 0), math.rad(rz or 0)
    -- Ry, then Rx, then Rz applied to the pivot
    local x1, z1 = p[1] * math.cos(b) + p[3] * math.sin(b), -p[1] * math.sin(b) + p[3] * math.cos(b)
    local y2, z2 = p[2] * math.cos(a) - z1 * math.sin(a), p[2] * math.sin(a) + z1 * math.cos(a)
    return x1 * math.cos(c) - y2 * math.sin(c), x1 * math.sin(c) + y2 * math.cos(c), z2
end

-- The row a lying item becomes when built: the vertical pose is raised by zOffset, and the pose's rz is added to the
-- heading together with the type's rest rotz, so the client draws the object at (rx, ry, rz) as stored. The hinge
-- stays where the lying item's origin was (upstream), so a re-pivoted door's row moves by its rotated pivot.
-- def = type.defence, restRz = type.rotz; returns x, y, z, rz and the state to store as data.defence.
function M.build(def, pose, x, y, z, rz, restRz)
    local rot = def[pose]
    if pose == "vertical" then
        z = z + (def.zOffset or 0)
    end
    rz = ((rz or 0) + (restRz or 0) + rot[3]) % 360
    local dx, dy, dz = M.pivotOffset(def, rot[1], rot[2], rz)
    return x + dx, y + dy, z + dz, rz, { active = true, pose = pose, rx = rot[1], ry = rot[2] }
end

-- the pose's rotation as the built state stores it
local function poseRotation(def, state)
    local rot = def[state.pose] or def.vertical
    return state.rx or rot[1], state.ry or rot[2]
end

-- the reverse of build: the lying item's x, y, z and heading (its origin back on the hinge)
function M.unbuild(def, state, x, y, z, rz, restRz)
    local rx, ry = poseRotation(def, state)
    local dx, dy, dz = M.pivotOffset(def, rx, ry, rz)
    x, y, z = x - dx, y - dy, z - dz
    if state.pose == "vertical" then
        z = z - (def.zOffset or 0)
    end
    return x, y, z, ((rz or 0) - (restRz or 0) - def[state.pose][3]) % 360
end

-- Toggling a built defence between vertical and horizontal poses (upstream MoveDefence / motor movement), about the
-- hinge as upstream did: vertical to horizontal lowers z by zOffset and rotates by (horizontal[3] - vertical[3]),
-- horizontal to vertical raises z by zOffset and rotates by (vertical[3] - horizontal[3]); a re-pivoted door's row
-- then moves from the old pose's pivot offset to the new one's.
-- Returns new x, y, z, rz and a new state table with the updated pose and rotations, preserving other metadata.
function M.toggle(def, state, x, y, z, rz)
    local curPose = (state and state.pose) or "vertical"
    local nextPose = (curPose == "vertical") and "horizontal" or "vertical"
    local curRx, curRy = poseRotation(def, { pose = curPose, rx = state and state.rx, ry = state and state.ry })
    local ox, oy, oz = M.pivotOffset(def, curRx, curRy, rz)
    local newZ, newRz
    if curPose == "vertical" then
        newZ = (z or 0) - oz - (def.zOffset or 0)
        newRz = ((rz or 0) + (def.horizontal[3] - def.vertical[3])) % 360
    else
        newZ = (z or 0) - oz + (def.zOffset or 0)
        newRz = ((rz or 0) + (def.vertical[3] - def.horizontal[3])) % 360
    end
    local rot = def[nextPose]
    local nx, ny, nz = M.pivotOffset(def, rot[1], rot[2], newRz)
    local newState = {}
    if type(state) == "table" then
        for k, v in pairs(state) do
            newState[k] = v
        end
    end
    newState.active = true
    newState.pose = nextPose
    newState.rx = rot[1]
    newState.ry = rot[2]
    return (x or 0) - ox + nx, (y or 0) - oy + ny, newZ + nz, newRz, newState
end

-- Upstream item/largeframe.pwn (its OnPlayerInteractDefence hook): every interaction with a built Large Frame puts a
-- covering panel over it or takes it off again. The panel is state.covered, drawn by the items client.
M.COVERABLE = { LargeFrame = true }

function M.isCoverable(uname)
    return M.COVERABLE[uname] == true
end

-- the state with the covering flipped, other fields kept
function M.toggleCovering(state)
    local newState = {}
    for k, v in pairs(state) do
        newState[k] = v
    end
    newState.covered = state.covered ~= true or nil
    return newState
end

-- A crowbar, motor, or keypad only works from the defence's back side (upstream _InteractDefenceWithItem): the angle
-- between the defence's facing and the direction to the player is between 90 and 270 degrees.
function M.isBehind(def, rz, x, y, px, py, pose)
    local poseRotZ = (pose and def and def[pose] and def[pose][3]) or (def and def.vertical and def.vertical[3]) or 0
    local toPlayer = (-math.deg(math.atan2(px - x, py - y))) % 360
    local angle = ((rz or 0) - poseRotZ - toPlayer) % 360
    return angle > 90 and angle < 270
end

return M
