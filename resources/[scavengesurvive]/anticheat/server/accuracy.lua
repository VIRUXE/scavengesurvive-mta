-- Excess accuracy (upstream hack-detect.pwn OnPlayerWeaponShot): a ring of the last ten shots at moving players;
-- seven hits in a full ring warns staff of level 2+. It never punishes. MTA's onPlayerWeaponFire gives the hit
-- element; a shot at a player standing still is not recorded.
return function(ctx)
    local logic = ctx.accuracyLogic
    local rings = {}
    local M = {}

    addEventHandler("onPlayerWeaponFire", root, function(_, _, _, _, hitElement)
        local player = source
        if ctx.exempt(player) then
            return
        end
        local hit
        if hitElement and isElement(hitElement) and getElementType(hitElement) == "player" then
            local vx, vy, vz = getElementVelocity(hitElement)
            if vx == 0 and vy == 0 and vz == 0 then
                return
            end
            hit = true
        else
            hit = false
        end
        local ring = rings[player]
        if not ring then
            ring = logic.new()
            rings[player] = ring
        end
        local count = logic.record(ring, hit)
        if count then
            local name, ratio = getPlayerName(player), logic.ratio(ring)
            local stats = string.format("Shots: %d Hits: %d Accuracy: %.2f", ring.shots, ring.hits, ratio)
            local text =
                string.format(" >  Accuracy Warning: %s %s (%d/10) Checks: %d", name, stats, count, ring.checks)
            exports.staff:notifyStaff(2, text)
            ctx.log(player, "accuracy", text)
        end
    end)

    function M.forget(player)
        rings[player] = nil
    end

    return M
end
