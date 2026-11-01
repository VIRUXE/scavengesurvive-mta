-- The worn Parachute (server/parachute.lua): GTA takes weapon 46 away once the parachute has carried the player down,
-- and only this client sees it go, so it tells the server (parachuteSpent) and the item is destroyed there. It counts
-- only when the player was airborne a moment before (small.parachuteSpent): a parachute taken off on the ground or
-- lost to a death is not reported, and the server ignores a report for one it no longer has worn.
return function(small)
    local POLL_MS = 250
    local had, lastAirborne = false, nil

    local function hasParachute()
        local slot = small.PARACHUTE_SLOT
        return getPedWeapon(localPlayer, slot) == small.PARACHUTE_WEAPON and getPedTotalAmmo(localPlayer, slot) > 0
    end

    setTimer(function()
        local now = getTickCount()
        if not isPedOnGround(localPlayer) and not getPedOccupiedVehicle(localPlayer) then
            lastAirborne = now
        end
        local has = hasParachute()
        local since = lastAirborne and now - lastAirborne
        if small.parachuteSpent(had, has, isPedDead(localPlayer), since) then
            triggerServerEvent("parachuteSpent", localPlayer)
        end
        if has and not had then
            lastAirborne = nil -- a fall before it was put on does not count
        end
        had = has
    end, POLL_MS, 0)
end
