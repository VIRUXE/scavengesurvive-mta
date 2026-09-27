local bars = {}
function bars.fill(value, max)
    if max <= 0 then
        return 0
    end
    return math.max(0, math.min(1, value / max))
end
function bars.layout(_sw, sh, scale)
    return { x = 24 * scale, y = sh - 90 * scale, w = 220 * scale, h = 14 * scale, gap = 6 * scale }
end
function bars.colour(kind, fraction)
    if kind == "hp" then
        if fraction < 0.3 then
            return 140, 20, 20
        end
        return 220, 40, 40
    elseif kind == "food" then
        return 230, 150, 40
    elseif kind == "bleed" then
        return 120, 0, 0
    end
    return 200, 200, 200
end
return bars
