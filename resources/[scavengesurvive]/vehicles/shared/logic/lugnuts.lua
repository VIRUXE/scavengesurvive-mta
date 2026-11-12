-- Threading the lug nuts on a wheel (vehicles/client/lugnuts.lua, vehicles/server/lugnuts.lua).
-- Progress is 0 when the nut sits at the end of its stud and 1 when it is tight. Taking a wheel
-- off runs each nut out (negative radians); fitting one runs each nut in.
local M = {}

M.TURN = 2 * math.pi * 3 -- radians of wrench travel for one nut, before the Repair skill
M.SPEED = 2 * math.pi * 1.6 -- radians a second the wrench turns while the player holds it on a nut
M.LOOSE = 0.02
M.TIGHT = 0.98
M.MAX_STEP = math.rad(100) -- largest turn one client report may apply

function M.apply(progress, delta, sign, turn)
    if turn == nil or turn <= 0 then
        return progress
    end
    local useful = sign > 0 and math.max(0, delta) or math.max(0, -delta)
    if useful <= 0 then
        return progress
    end
    local nextProgress = progress + sign * (useful / turn)
    if nextProgress < 0 then
        nextProgress = 0
    elseif nextProgress > 1 then
        nextProgress = 1
    end
    return nextProgress
end

function M.done(progress, sign)
    if sign < 0 then
        return progress <= M.LOOSE
    end
    return progress >= M.TIGHT
end

function M.allDone(states, sign)
    for index = 1, #states do
        if not M.done(states[index], sign) then
            return false
        end
    end
    return #states > 0
end

-- The next nut still to be done, walking the ring in `step` (1 or -1) from `index`; nil when none is left.
function M.nextOpen(states, sign, index, step)
    local count = #states
    for offset = 1, count do
        local candidate = ((index - 1 + step * offset) % count) + 1
        if not M.done(states[candidate], sign) then
            return candidate
        end
    end
    return nil
end

-- Offsets for a ring of nuts on the hub face. The first sits at the top; the rest run clockwise
-- as seen from outside the wheel (Y grows downward).
function M.layout(count, radius)
    local out = {}
    for index = 1, count do
        local angle = -math.pi / 2 + (index - 1) * (2 * math.pi / count)
        out[index] = { x = math.cos(angle) * radius, y = math.sin(angle) * radius }
    end
    return out
end

return M
