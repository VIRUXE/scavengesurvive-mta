-- Ground under the drop spots for the server (server/death.lua) where its own world (lib geom.lua) does not reach:
-- interiors, house shells, or before that world is ready. Each spot is first pulled in towards the body until no wall
-- hides it (shared/logic/drop.lua pullIn, the same chest-to-floor check as the server's), then a ray straight down,
-- from a little above the player's Z so a floor under the feet wins over a ceiling, reports the hit's height and
-- surface normal; false when nothing is hit. Vehicles and peds are skipped (an item lying on them would float once
-- they move); world items have no collision. The server checks every hit and every moved spot before using it.
local PROBE_ABOVE, PROBE_BELOW = 1.0, 6.0
local BODY_DROP = 0.9 -- as server/death.lua: items lie this far below the ped's origin

-- read and closed again: a handle left open locks the client's cached copy, so a changed file fails to download
local drop
do
    local f = fileOpen("shared/logic/drop.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    drop = assert(loadstring(src, "=character/drop.lua"))()
end

local function clear(x1, y1, z1, x2, y2, z2)
    return isLineOfSightClear(x1, y1, z1, x2, y2, z2, true, false, false, true, false)
end

addEventHandler("groundSurfaceRequested", localPlayer, function(id, spots, x, y, z)
    local sz, gz = z + 0.5, z - BODY_DROP
    drop.pullIn(spots, x, y, function(px, py)
        return not clear(x, y, sz, px, py, gz + 0.15) and not clear(x, y, sz, px, py, gz + 0.6)
    end)
    local hits, moved = {}, {}
    for i, s in ipairs(spots) do
        local top, bottom = z + PROBE_ABOVE, z - PROBE_BELOW
        local hit, _, _, hz, _, nx, ny, nz = processLineOfSight(s[1], s[2], top, s[1], s[2], bottom, true, false, false)
        hits[i] = hit and { hz, nx, ny, nz } or false
        moved[i] = { s[1], s[2] }
    end
    triggerServerEvent("groundSurfaceReported", localPlayer, id, hits, moved)
end)
