-- Turning the lug nuts on a wheel (vehicles/client/lugnuts.lua, vehicles/server/lugnuts.lua).
-- Progress is 0 when the nut is loose and 1 when it is tight. Removing drags counter-clockwise
-- (negative radians); installing drags clockwise. A nut stops at BIND while either neighbour is
-- still seated, so each nut has to be cracked loose (or snugged) before any of them can finish.
local M = {}

M.TURN = 2 * math.pi * 1.15 -- radians of wrench travel for one nut, before the Repair skill
M.BIND = 0.35 -- how far a nut will go while a neighbour is still seated
M.SEATED = 0.08 -- a neighbour counts as seated until it has moved this far
M.LOOSE = 0.02
M.TIGHT = 0.98
M.MAX_STEP = math.rad(100) -- largest turn one client report may apply

function M.neighbours(count, index)
    local previous = index - 1
    if previous < 1 then
        previous = count
    end
    local following = index + 1
    if following > count then
        following = 1
    end
    return previous, following
end

function M.blocked(states, index, sign)
    local start = sign < 0 and 1 or 0
    local function seated(progress)
        return math.abs(progress - start) < M.SEATED
    end
    local previous, following = M.neighbours(#states, index)
    return seated(states[previous]) or seated(states[following])
end

-- Returns the new progress and whether the nut seized against the neighbour rule.
function M.apply(progress, delta, sign, turn, blocked)
    if turn == nil or turn <= 0 then
        return progress, false
    end
    local useful = sign > 0 and math.max(0, delta) or math.max(0, -delta)
    if useful <= 0 then
        return progress, false
    end
    local nextProgress = progress + sign * (useful / turn)
    if nextProgress < 0 then
        nextProgress = 0
    elseif nextProgress > 1 then
        nextProgress = 1
    end
    if not blocked then
        return nextProgress, false
    end
    local start = sign < 0 and 1 or 0
    local limit = start + sign * M.BIND
    if sign < 0 and nextProgress < limit then
        return limit, true
    end
    if sign > 0 and nextProgress > limit then
        return limit, true
    end
    return nextProgress, false
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

-- Screen offsets for a ring of nuts. The first sits at the top; the rest run clockwise
-- once the Y offset is added to a screen coordinate (Y grows downward).
function M.layout(count, radius)
    local out = {}
    for index = 1, count do
        local angle = -math.pi / 2 + (index - 1) * (2 * math.pi / count)
        out[index] = { x = math.cos(angle) * radius, y = math.sin(angle) * radius }
    end
    return out
end

return M
