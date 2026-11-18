-- Pushing a vehicle by hand (shared/logic/push.lua has the numbers, client/push.lua the movement and the pose).
-- "Push" at an empty vehicle's front or rear makes the player its syncer, so the pushing client moves it, and marks
-- both: "vehicles.pushedBy" on the vehicle (every client stops holding it still) and "vehicles.pushing" on the
-- player (every client poses the arms against it). It ends when the player asks, walks off, gets in anything,
-- dies or leaves, or someone else gets into the vehicle; a push that moved it far enough trains Strength.
-- ctx = { info, vlogic, plogic, log, vehicleLine, isTowed } built by server/main.lua.
return function(ctx)
    local info, vlogic, plogic, log, vehicleLine = ctx.info, ctx.vlogic, ctx.plogic, ctx.log, ctx.vehicleLine
    local M = {}

    local pushes = {} -- player -> { vehicle, x, y, z } where the vehicle stood when the push began
    local pusherOf = {} -- vehicle -> player

    local function refuse(player, vehicle, code)
        log.event("vehicle.pushed", vehicleLine(vehicle, { player = player, ok = false, code = code }), "info")
        return false
    end

    function M.stop(player, reason)
        local p = pushes[player]
        if not p then
            return
        end
        pushes[player] = nil
        local v = p.vehicle
        if pusherOf[v] == player then
            pusherOf[v] = nil
        end
        if isElement(player) then
            setElementData(player, "vehicles.pushing", false, "broadcast", "deny")
            triggerClientEvent(player, "vehiclePushStopped", player)
        end
        if not isElement(v) then
            return
        end
        setElementData(v, "vehicles.pushedBy", false, "broadcast", "deny")
        local syncer = getElementSyncer(v)
        if syncer then
            setElementSyncer(v, syncer, false)
        end
        local x, y, z = getElementPosition(v)
        local dist = getDistanceBetweenPoints3D(p.x, p.y, p.z, x, y, z)
        local mult = plogic.skillMult(dist)
        if mult and isElement(player) then
            exports.character:gainSkill(player, plogic.SKILL, mult)
        end
        local fields = { player = player, ok = true, distance = math.floor(dist * 10 + 0.5) / 10, reason = reason }
        log.event("vehicle.pushed", vehicleLine(v, fields), "info")
    end

    function M.start(player, vehicle)
        if pushes[player] then
            M.stop(player, "restarted")
        end
        if
            isPedDead(player)
            or getPedOccupiedVehicle(player)
            or getElementData(player, "character.knockedOut") == true
            or getElementData(player, "character.cuffed") == true
        then
            return refuse(player, vehicle, "PLAYER_BUSY")
        end
        if exports.items:getHeld(player) then
            return refuse(player, vehicle, "HANDS_FULL")
        end
        if getVehicleController(vehicle) or next(getVehicleOccupants(vehicle) or {}) then
            return refuse(player, vehicle, "OCCUPIED")
        end
        if pusherOf[vehicle] and isElement(pusherOf[vehicle]) then
            return refuse(player, vehicle, "ALREADY_PUSHED")
        end
        if
            not plogic.TYPES[getVehicleType(vehicle)]
            or isElementFrozen(vehicle)
            or isElementAttached(vehicle)
            or getVehicleTowingVehicle(vehicle)
            or ctx.isTowed(vehicle)
        then
            return refuse(player, vehicle, "CANNOT_PUSH")
        end
        local handling = getVehicleHandling(vehicle)
        if (handling and handling.mass or 0) > plogic.MAX_MASS then
            return refuse(player, vehicle, "TOO_HEAVY")
        end
        local px, py, pz = getElementPosition(player)
        local vx, vy, vz = getElementPosition(vehicle)
        local vt = exports.data:vehicleType(info[vehicle].uname)
        if getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > vlogic.maxReachDistance(vt and vt.size) then
            return refuse(player, vehicle, "TOO_FAR")
        end
        local _, _, rz = getElementRotation(vehicle)
        local sign = plogic.side(vlogic.angleToVehicle(px, py, vx, vy, rz))
        if not sign then
            return refuse(player, vehicle, "NOT_AT_END")
        end
        local stats = exports.character:getStats(player)
        local skill = exports.character:getSkill(player, plogic.SKILL)
        local speed = plogic.speed(skill, stats and stats.hp or 100, handling and handling.mass)
        pushes[player] = { vehicle = vehicle, x = vx, y = vy, z = vz }
        pusherOf[vehicle] = player
        setElementSyncer(vehicle, player, true)
        setElementData(vehicle, "vehicles.pushedBy", player, "broadcast", "deny")
        setElementData(player, "vehicles.pushing", vehicle, "broadcast", "deny")
        triggerClientEvent(player, "vehiclePushStarted", vehicle, speed, sign)
        return true
    end

    function M.pusher(vehicle)
        return pusherOf[vehicle]
    end

    -- the pushing client may vanish without a word: a push whose player wandered off ends here
    setTimer(function()
        for player, p in pairs(pushes) do
            local v = p.vehicle
            if not isElement(player) or not isElement(v) then
                M.stop(player, "gone")
            else
                local px, py, pz = getElementPosition(player)
                local vx, vy, vz = getElementPosition(v)
                if
                    isPedDead(player)
                    or getPedOccupiedVehicle(player)
                    or getVehicleController(v)
                    or getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz) > 12
                then
                    M.stop(player, "left")
                end
            end
        end
    end, 1000, 0)

    addEventHandler("onVehicleStartEnter", root, function()
        local player = pusherOf[source]
        if player then
            M.stop(player, "entered")
        end
    end)

    addEventHandler("onElementDestroy", root, function()
        if getElementType(source) == "vehicle" and pusherOf[source] then
            M.stop(pusherOf[source], "gone")
        end
    end)

    addEventHandler("onPlayerQuit", root, function()
        M.stop(source, "quit")
    end)

    addEventHandler("onPlayerWasted", root, function()
        M.stop(source, "died")
    end)

    return M
end
