-- Hunger bar (core/char/food.pwn, progress2) and the brightness overlay (core/player/brightness.pwn).
local bars = {}

-- CreatePlayerProgressBar(548, 36, 62, 3.2, 0x1FF81FFF, 100): the width of the stock health bar, above it (SA-MP's
-- health bar sits at 548..610 x 56). Drawn as GTA's own bar, the same size as MTA's stock health bar: at 1080p its
-- track is 1645..1817 x 222..236 px = 517.8 + 76.9 x 98.7 + 6.7 units right-anchored. The armour bar's frame ends
-- at 171 px and the health bar's starts at 216 px, so the hunger bar's frame (180..207 px) sits centred between.
bars.HUNGER = { x = 517.8, y = 82.7, w = 76.9, h = 6.7, r = 0x1F, g = 0xF8, b = 0x1F, a = 0xFF, max = 100 }
-- Upstream weapon.pwn:77 draws "%d/%d" at (520.41, 62.65) inside the bottom of SA-MP's weapon icon frame.
-- At 1080p MTA's stock weapon icon sits at 1485..1637 x 25..194 px = 446.7..514.2 x 11.1..86.2 right-anchored units.
bars.AMMO = { x = 480.4, y = 75.5 }

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
