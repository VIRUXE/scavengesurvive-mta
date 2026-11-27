-- Where the death drop and /dropall put items: a ring of RING_SLOTS spots RADIUS m around the player (slot n at
-- n * 40 degrees, item n in slot n mod RING_SLOTS) plus the death Clothes 1 m east (upstream death.pwn). The
-- spots are pulled in from walls (pullIn), then the ground and its slope under each one is measured; a height
-- that is missing or implausible next to the player falls back to the player's Z minus upstream's ITEM_FLOOR_OFFSET
-- (and lies flat), a slope steeper than MAX_TILT lies flat. The procedures give each item a random heading.
-- Pure logic: no MTA calls.
local drop = {}
drop.RING_SLOTS = 9
drop.RADIUS = 1.5
drop.FLOOR_OFFSET = 0.9
drop.MAX_RISE = 1.5 -- ground this far above the player's Z still counts (uphill on a slope)
drop.MAX_FALL = 5.0 -- and this far below (downhill); further means a miss, water or a ledge
drop.MAX_TILT = 45 -- degrees; a steeper surface (a wall, a kerb's side) is not something an item lies on
drop.PULL = { 1, 2 / 3, 1 / 3 } -- fractions of a spot's distance tried, outermost first, before it goes under the body
drop.MARGIN = 0.3 -- the way must be clear this far past a spot, so the item's model does not poke into the wall

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

-- Pulls each spot in towards the centre (x, y) until nothing hides it: blocked(px, py) answers whether a wall stands
-- between the body and (px, py), checked MARGIN past each candidate. A spot no fraction of PULL clears goes under the
-- body. Without this a body against a wall put half its ring through it (2026-11-27, a Spas 12 inside a wall).
function drop.pullIn(spots, x, y, blocked)
    for _, s in ipairs(spots) do
        local dx, dy = s[1] - x, s[2] - y
        local d = math.sqrt(dx * dx + dy * dy)
        local px, py = x, y
        if d > 1e-6 then
            local ux, uy = dx / d, dy / d
            for _, f in ipairs(drop.PULL) do
                local r = d * f
                if not blocked(x + ux * (r + drop.MARGIN), y + uy * (r + drop.MARGIN)) then
                    px, py = x + ux * r, y + uy * r
                    break
                end
            end
        end
        s[1], s[2] = px, py
    end
    return spots
end

-- Takes the client's pulled-in spots ({ x, y } in spot order) where each is no further from the centre than the spot
-- it replaces (a client cannot send an item anywhere else); a missing or wrong one keeps the spot as it was.
function drop.applyMoved(spots, moved, x, y)
    if type(moved) ~= "table" then
        return spots
    end
    for i, s in ipairs(spots) do
        local m = moved[i]
        local mx, my = type(m) == "table" and tonumber(m[1]), type(m) == "table" and tonumber(m[2])
        if mx and my then
            local limit = (s[1] - x) ^ 2 + (s[2] - y) ^ 2 + 1e-3
            if (mx - x) ^ 2 + (my - y) ^ 2 <= limit then
                s[1], s[2] = mx, my
            end
        end
    end
    return spots
end

-- The unit ground normal's x and y from a reported { z, nx, ny, nz }, or 0, 0 (flat) when it is not a usable
-- slope: missing, not a number, upside down or steeper than MAX_TILT.
local function slope(hit)
    local nx, ny, nz = tonumber(hit[2]), tonumber(hit[3]), tonumber(hit[4])
    if not (nx and ny and nz) then
        return 0, 0
    end
    local len = math.sqrt(nx * nx + ny * ny + nz * nz)
    if len < 1e-6 or nz / len < math.cos(math.rad(drop.MAX_TILT)) then
        return 0, 0
    end
    return nx / len, ny / len
end

-- Makes each spot { x, y, z, nx, ny } from the client's hits (a list in spot order of { z, nx, ny, nz }, false for
-- none): the hit's height and slope when the height is plausible, else the fallback height lying flat.
function drop.settle(spots, hits, playerZ)
    local fallback = playerZ - drop.FLOOR_OFFSET
    for i, s in ipairs(spots) do
        local hit = type(hits) == "table" and hits[i]
        local g = type(hit) == "table" and tonumber(hit[1]) or nil
        if g and g <= playerZ + drop.MAX_RISE and g >= playerZ - drop.MAX_FALL then
            s[3], s[4], s[5] = g, slope(hit)
        else
            s[3], s[4], s[5] = fallback, 0, 0
        end
    end
    return spots
end

-- The ring as the procedures take it ([[x, y, z, nx, ny], ...]) and the Clothes spot on its own.
function drop.split(spots)
    local ring = {}
    for i = 1, drop.RING_SLOTS do
        ring[i] = spots[i]
    end
    return ring, spots[drop.RING_SLOTS + 1]
end

return drop
