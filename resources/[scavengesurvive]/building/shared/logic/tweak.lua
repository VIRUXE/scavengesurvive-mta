-- Nudging a freshly built item (upstream core/world/item-tweak.pwn, TweakItem): after a defence is built or an item
-- constructed on the ground, its builder moves it 5 cm at a time and turns it 2 degrees at a time, never further
-- than 1.5 m from where it was built, and never while anyone (the builder included) stands within 2.2 m of it.
-- Pure geometry and layout; the server applies the steps, the client draws the pad and the arrow.
local M = {}

M.STEP = 0.05 -- metres per move click (upstream _twk_AdjustItemPos distance)
M.TURN = 2.0 -- degrees per rotate click
M.MAX_RANGE = 1.5 -- MAX_MOVEMENT_RANGE from the build position
M.NO_GO = 2.2 -- NO_GO_ZONE_SIZE: no player this close to the item while it moves
M.REACH = 10.0 -- the builder further away than this is no longer tweaking (no upstream rule; guards the request)

-- action -> { distance, direction (degrees from the item's front, counter-clockwise), rotation }
M.ACTIONS = {
    forward = { M.STEP, 0, 0 },
    back = { M.STEP, 180, 0 },
    left = { M.STEP, 90, 0 },
    right = { M.STEP, -90, 0 },
    rotl = { 0, 0, M.TURN },
    rotr = { 0, 0, -M.TURN },
}

-- The heading the item's front faces: its stored rz less the pose rotation of its defence type
-- (building/shared/logic/defences.lua isBehind uses the same reference). def = type.defence or nil.
function M.heading(rz, def, pose)
    local poseRz = 0
    if def then
        local rot = pose and def[pose] or def.vertical
        poseRz = rot and rot[3] or 0
    end
    return ((rz or 0) - poseRz) % 360
end

-- Applies one action to a position and heading. Returns the new x, y, heading, or nil for an unknown action.
-- GTA's heading h faces (-sin h, cos h): h = 0 is north, turning counter-clockwise.
function M.apply(action, x, y, heading)
    local a = M.ACTIONS[action]
    if not a then
        return nil
    end
    local dist, dir, turn = a[1], a[2], a[3]
    local rad = math.rad(heading + dir)
    return x - dist * math.sin(rad), y + dist * math.cos(rad), (heading + turn) % 360
end

-- Whether (x, y) still lies within MAX_RANGE of the build position.
function M.inRange(x, y, ox, oy)
    local dx, dy = x - ox, y - oy
    return (dx * dx + dy * dy) < (M.MAX_RANGE * M.MAX_RANGE)
end

-- Whether a player at (px, py, pz) stands inside the item's no-go sphere.
function M.blocks(px, py, pz, x, y, z)
    local dx, dy, dz = px - x, py - y, pz - z
    return (dx * dx + dy * dy + dz * dz) < (M.NO_GO * M.NO_GO)
end

-- The arrow the client draws on a built defence (upstream object 19132): a shaft of `len` metres from the item
-- along its heading at z + lift, and two barbs back from the tip. Returns a list of { x1, y1, z1, x2, y2, z2 }.
function M.arrow(x, y, z, heading, len, lift)
    len = len or 1.0
    lift = lift or 0.3
    local rad = math.rad(heading)
    local fx, fy = -math.sin(rad), math.cos(rad)
    local tx, ty, tz = x + fx * len, y + fy * len, z + lift
    local barb = len * 0.3
    local lines = { { x, y, tz, tx, ty, tz } }
    for _, side in ipairs({ 150, -150 }) do
        local br = math.rad(heading + side)
        lines[#lines + 1] = { tx, ty, tz, tx - math.sin(br) * barb, ty + math.cos(br) * barb, tz }
    end
    return lines
end

-- The pad (upstream's player textdraws at 550-630 x 310-440 on the 640x480 canvas), in canvas units anchored to
-- the right screen edge. id is the action sent to the server, or "toggle" (show/hide the mouse) and "done".
M.BUTTONS = {
    { id = "rotl", label = "L", x = 550, y = 310, w = 20, h = 20 },
    { id = "rotr", label = "R", x = 610, y = 310, w = 20, h = 20 },
    { id = "forward", label = "^", x = 580, y = 320, w = 20, h = 20 },
    { id = "left", label = "<", x = 556, y = 340, w = 20, h = 20 },
    { id = "right", label = ">", x = 604, y = 340, w = 20, h = 20 },
    { id = "back", label = "v", x = 580, y = 360, w = 20, h = 20 },
    { id = "toggle", label = "Move", x = 550, y = 390, w = 80, h = 20 },
    { id = "done", label = "Done", x = 550, y = 420, w = 80, h = 20 },
}

-- Pixel rectangles of the buttons for a canvas instance c (ui/shared/logic/canvas.lua).
function M.layout(canvas, c)
    local rects = {}
    for i, b in ipairs(M.BUTTONS) do
        rects[i] = {
            id = b.id,
            x = canvas.x(c, b.x, "right"),
            y = canvas.y(c, b.y),
            w = canvas.len(c, b.w),
            h = canvas.len(c, b.h),
        }
    end
    return rects
end

-- The button id under a pixel, or nil.
function M.hit(rects, px, py)
    for _, r in ipairs(rects) do
        if px >= r.x and px <= r.x + r.w and py >= r.y and py <= r.y + r.h then
            return r.id
        end
    end
    return nil
end

return M
