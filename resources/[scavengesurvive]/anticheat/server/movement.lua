-- Once a second, on foot (upstream hack-detect.pwn AntiCheatUpdate): moving while frozen, a jetpack and the
-- swim-fly check. The big-jump teleport alert is MTA's onPlayerTeleport in main.lua.
return function(ctx)
    local water, insidePolygon = ctx.water, ctx.fields.insidePolygon
    local last = {} -- player -> { x, y, z, frozen } of the previous sample
    local lastFrozenReport = {}
    local swimStrikes = {}
    local M = {}

    local SWIM_STRIKES = 3 -- consecutive seconds a client may claim water where there is none before the ban
    local FROZEN_MOVE = 1.0
    local REPORT_GAP_MS = 10000

    local function sample(player, now)
        local x, y, z = getElementPosition(player)
        if not ctx.spawnReady(player, x, y, z) then
            M.forget(player)
            return
        end
        local prev = last[player]
        local frozen = exports.staff:isFrozen(player)
        last[player] = { x, y, z, frozen }

        if
            ctx.exempt(player)
            or not ctx.alive(player)
            or ctx.sinceJoin(player) < 10000
            or ctx.sinceSpawn(player) < 1000
        then
            swimStrikes[player] = nil
            last[player] = { x, y, z, false }
            return
        end
        if getPedOccupiedVehicle(player) then
            swimStrikes[player] = nil
            return
        end

        if isPedWearingJetpack(player) then
            ctx.report(player, "FLY", "Having a jetpack (jetpacks aren't in this server, must be a hack)")
            return ctx.autoBan(player, "Having a jetpack (Jetpacks aren't in this server, must be a hack)")
        end

        -- frozen: the sample before it was frozen too, so the freeze itself did not move the player
        if
            frozen
            and prev
            and prev[4]
            and getDistanceBetweenPoints3D(x, y, z, prev[1], prev[2], prev[3]) > FROZEN_MOVE
        then
            if not lastFrozenReport[player] or now - lastFrozenReport[player] > REPORT_GAP_MS then
                lastFrozenReport[player] = now
                local moved = getDistanceBetweenPoints3D(x, y, z, prev[1], prev[2], prev[3])
                local from = string.format("%.0f, %.0f, %.0f", prev[1], prev[2], prev[3])
                local to = string.format("%.0f, %.0f, %.0f", x, y, z)
                local detail = string.format("Moved %.0fm while frozen (%s > %s)", moved, from, to)
                ctx.report(player, "TELE", detail)
            end
            setElementPosition(player, prev[1], prev[2], prev[3])
            last[player] = prev
            return
        end

        -- swim-fly: the client says it is in water, the map says it is not
        if
            getElementInterior(player) == 0
            and isElementInWater(player)
            and not water.isWater(x, y, z, insidePolygon)
        then
            swimStrikes[player] = (swimStrikes[player] or 0) + 1
            if swimStrikes[player] >= SWIM_STRIKES then
                local reason = string.format("Used swimming animation at %.0f, %.0f, %.0f", x, y, z)
                ctx.report(player, "FLY", reason)
                ctx.autoBan(player, reason)
                swimStrikes[player] = nil
            end
        else
            swimStrikes[player] = nil
        end
    end

    function M.update()
        local now = getTickCount()
        for _, player in ipairs(getElementsByType("player")) do
            sample(player, now)
        end
    end

    function M.forget(player)
        last[player], lastFrozenReport[player], swimStrikes[player] = nil, nil, nil
    end

    return M
end
