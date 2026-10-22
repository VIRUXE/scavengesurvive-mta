-- Hunger bar (core/char/food.pwn, progress2) and the brightness overlay (core/player/brightness.pwn).
local bars = {}

-- CreatePlayerProgressBar(548, 36, 62, 3.2, 0x1FF81FFF, 100): a short bar under the stock HUD, right-anchored.
bars.HUNGER = { x = 548, y = 36, w = 62, h = 3.2, r = 0x1F, g = 0xF8, b = 0x1F, a = 0xFF, max = 100 }

function bars.fill(value, max)
    if not max or max <= 0 then
        return 0
    end
    return math.max(0, math.min(1, (value or 0) / max))
end

-- Alpha of the black full-screen box for a health value: dark below 40 hp, (40 - hp) * 4.4 capped at 255.
function bars.brightness(hp)
    hp = tonumber(hp) or 100
    if hp >= 40 then
        return 0
    end
    return math.min(255, math.floor((40 - hp) * 4.4 + 0.5))
end

-- Upstream fades the overlay 4 per 100 ms towards the target; one step from `current` towards `target`.
function bars.brightnessStep(current, target)
    if current < target then
        return target
    end
    return math.max(target, current - 4)
end

return bars
