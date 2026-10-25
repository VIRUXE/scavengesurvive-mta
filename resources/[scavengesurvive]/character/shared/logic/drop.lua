-- Where the death drop and /dropall put items: a ring of RING_SLOTS spots RADIUS m around the player (slot n at
-- n * 40 degrees, item n in slot n mod RING_SLOTS) plus the death Clothes 1 m east (upstream death.pwn). The
-- server cannot see collision, so the player's client measures the ground under each spot; a height that is
-- missing or implausible next to the player falls back to the player's Z minus upstream's ITEM_FLOOR_OFFSET.
-- Pure logic: no MTA calls.
local drop = {}
drop.RING_SLOTS = 9
drop.RADIUS = 1.5
drop.FLOOR_OFFSET = 0.9
drop.MAX_RISE = 1.5 -- ground this far above the player's Z still counts (uphill on a slope)
drop.MAX_FALL = 5.0 -- and this far below (downhill); further means a miss, water or a ledge

-- Spots for the given centre: ring first, then the Clothes spot. Each is { x, y }.
function drop.spots(x, y)
    local out = {}
    for n = 0, drop.RING_SLOTS - 1 do
        local a = math.rad(n * 40)
        out[#out + 1] = { x + drop.RADIUS * math.cos(a), y + drop.RADIUS * math.sin(a) }
    end
    out[#out + 1] = { x + 1.0, y }
    return out
end

-- Gives each spot its z from the client's heights (a list in spot order, false for none), or the fallback.
function drop.settle(spots, heights, playerZ)
    local fallback = playerZ - drop.FLOOR_OFFSET
    for i, s in ipairs(spots) do
        local g = type(heights) == "table" and tonumber(heights[i]) or nil
        if g and g <= playerZ + drop.MAX_RISE and g >= playerZ - drop.MAX_FALL then
            s[3] = g
        else
            s[3] = fallback
        end
    end
    return spots
end

-- The ring as the procedures take it ([[x, y, z], ...]) and the Clothes spot on its own.
function drop.split(spots)
    local ring = {}
    for i = 1, drop.RING_SLOTS do
        ring[i] = spots[i]
    end
    return ring, spots[drop.RING_SLOTS + 1]
end

return drop
