-- Hunger/thirst bars (core/char/food.pwn, progress2) and the brightness overlay (core/player/brightness.pwn).
local bars = {}

-- CreatePlayerProgressBar(548, 36, 62, 3.2, 0x1FF81FFF, 100): the width of the stock health bar, above it (SA-MP's
-- health bar sits at 548..610 x 56). Drawn as GTA's own bar: at 1080p the health track is 1645..1817 x 222..236 px
-- = 517.8 + 76.9 x 98.7 + 6.7 units right-anchored. Thirst and hunger are stacked above it at the same width and
-- height, thirst on top, the black frames of all three bars the same distance apart.
local BORDER = 6 / 2.25 -- canvas.BAR_BORDER
local HEALTH_FRAME_TOP = 98.7 - BORDER
local NEEDS_H, NEEDS_GAP = 6.7, 2
local STEP = NEEDS_H + 2 * BORDER + NEEDS_GAP
bars.THIRST = {
    x = 517.8,
    y = HEALTH_FRAME_TOP - 2 * STEP + BORDER,
    w = 76.9,
    h = NEEDS_H,
    r = 0x30,
    g = 0xB8,
    b = 0xF8,
    a = 0xFF,
    max = 100,
}
bars.HUNGER = {
    x = 517.8,
    y = HEALTH_FRAME_TOP - STEP + BORDER,
    w = 76.9,
    h = NEEDS_H,
    r = 0x1F,
    g = 0xF8,
    b = 0x1F,
    a = 0xFF,
    max = 100,
}
bars.STEP = STEP -- distance between two stacked bars
-- The worn vest's points (items.armourPoints), the same bar just above the health bar; while it is shown, hunger,
-- thirst and the protection bar move up one slot (bars.STEP). A vest starts at 25..149 points; the bar is full
-- from 100 up, the exact number stays in the inventory's TORSO caption.
bars.ARMOUR = {
    x = 517.8,
    y = HEALTH_FRAME_TOP - STEP + BORDER,
    w = 76.9,
    h = NEEDS_H,
    r = 0xC8,
    g = 0xC8,
    b = 0xD0,
    a = 0xFF,
    max = 100,
}
-- Protection from the toxic cloud: one more bar of the same size on top of thirst, in the gas's yellow.
bars.PROTECTION = {
    x = 517.8,
    y = HEALTH_FRAME_TOP - 3 * STEP + BORDER,
    w = 76.9,
    h = NEEDS_H,
    r = 0xD8,
    g = 0xD0,
    b = 0x30,
    a = 0xFF,
    max = 1,
}

-- Poison from the toxic cloud (the character's toxic level, 0..100): one more bar on top of the protection bar, in
-- a sickly purple, shown from POISON_SHOWN up. It fills as the poison builds and empties as it clears.
bars.POISON = {
    x = 517.8,
    y = HEALTH_FRAME_TOP - 4 * STEP + BORDER,
    w = 76.9,
    h = NEEDS_H,
    r = 0xB0,
    g = 0x48,
    b = 0xE0,
    a = 0xFF,
    max = 100,
}
bars.POISON_SHOWN = 1
bars.POISON_HURTS = 40 -- character survival.TOXIC_HURTS: from here it costs health

-- Upstream weapon.pwn:77 draws "%d/%d" at (520.41, 62.65) inside the bottom of SA-MP's weapon icon frame.
-- At 1080p MTA's stock weapon icon sits at 1485..1637 x 25..194 px = 446.7..514.2 x 11.1..86.2 right-anchored units.
bars.AMMO = { x = 480.4, y = 75.5 }

-- A needs bar that wants attention: from LOW down (where the character starts to feel it, character's hunger.START)
-- its colour breathes once every 1.2 s, from CRITICAL down (where HP drains) it turns red on and off twice a second.
bars.LOW, bars.CRITICAL = 30, 20
bars.ALERT = { r = 0xF0, g = 0x30, b = 0x30 }

-- r, g, b, a of the bar `bar` at `value`, `nowMs` into the client's clock
function bars.needColour(bar, value, nowMs)
    value = tonumber(value) or bar.max
    if value >= bars.LOW then
        return bar.r, bar.g, bar.b, bar.a
    end
    if value < bars.CRITICAL then
        if nowMs % 500 < 250 then
            return bars.ALERT.r, bars.ALERT.g, bars.ALERT.b, bar.a
        end
        return bar.r, bar.g, bar.b, bar.a
    end
    local k = 0.55 + 0.45 * (0.5 + 0.5 * math.cos(nowMs / 1200 * 2 * math.pi)) -- 1 down to 0.55 and back
    return math.floor(bar.r * k), math.floor(bar.g * k), math.floor(bar.b * k), bar.a
end

-- r, g, b, a of the protection bar: red on and off twice a second while gas is being breathed in and the
-- protection does not keep nearly all of it out, its own colour otherwise. breathing = the gas strength around the
-- player, 0..1.
bars.GAS_FELT, bars.PROTECTED = 0.02, 0.95

function bars.protectionColour(bar, total, breathing, nowMs)
    if bars.exposed(total, breathing) and nowMs % 500 < 250 then
        return bars.ALERT.r, bars.ALERT.g, bars.ALERT.b, bar.a
    end
    return bar.r, bar.g, bar.b, bar.a
end

-- r, g, b, a of the poison bar: it flickers bright and dim four times a second while gas is being taken in (the
-- level is rising), turns red on and off twice a second from POISON_HURTS up, and is steady while it clears.
function bars.poisonColour(bar, toxic, exposed, nowMs)
    if exposed and nowMs % 250 < 125 then
        return math.floor(bar.r * 0.55), math.floor(bar.g * 0.55), math.floor(bar.b * 0.55), bar.a
    end
    if (tonumber(toxic) or 0) >= bars.POISON_HURTS and nowMs % 500 < 250 then
        return bars.ALERT.r, bars.ALERT.g, bars.ALERT.b, bar.a
    end
    return bar.r, bar.g, bar.b, bar.a
end

-- whether gas is getting into the lungs: there is gas around the player and the protection lets some through
function bars.exposed(total, breathing)
    return (tonumber(breathing) or 0) > bars.GAS_FELT and (tonumber(total) or 0) < bars.PROTECTED
end

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
