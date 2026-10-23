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

function M.calculateDoorRotation(baseRz, isOpen)
    baseRz = baseRz or 0
    if isOpen then
        return (baseRz + 90) % 360
    end
    return baseRz % 360
end

return M
