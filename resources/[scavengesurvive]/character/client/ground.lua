-- Ground under the drop spots for the server (server/death.lua): collision is client-only. A ray straight down at
-- each spot, from a little above the player's Z so a floor under the feet wins over a ceiling, reports the hit's
-- height and surface normal; false when nothing is hit. Vehicles and peds are skipped (an item lying on them would
-- float once they move); world items have no collision. The server checks every hit before using it.
local PROBE_ABOVE, PROBE_BELOW = 1.0, 6.0

addEventHandler("groundSurfaceRequested", localPlayer, function(id, spots, z)
    local hits = {}
    for i, s in ipairs(spots) do
        local top, bottom = z + PROBE_ABOVE, z - PROBE_BELOW
        local hit, _, _, hz, _, nx, ny, nz = processLineOfSight(s[1], s[2], top, s[1], s[2], bottom, true, false, false)
        hits[i] = hit and { hz, nx, ny, nz } or false
    end
    triggerServerEvent("groundSurfaceReported", localPlayer, id, hits)
end)
