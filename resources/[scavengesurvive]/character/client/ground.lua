-- Ground under the drop spots for the server (server/death.lua): getGroundPosition is client-only. Each spot is
-- probed from a little above the player's Z so a floor under the feet wins over a ceiling; false when there is
-- no ground. The server checks every height against the player's Z before using it.
local PROBE_ABOVE = 1.0

addEventHandler("groundHeightsRequested", localPlayer, function(id, spots, z)
    local heights = {}
    for i, s in ipairs(spots) do
        heights[i] = getGroundPosition(s[1], s[2], z + PROBE_ABOVE) or false
    end
    triggerServerEvent("groundHeightsReported", localPlayer, id, heights)
end)
