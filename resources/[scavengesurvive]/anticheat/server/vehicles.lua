-- Once a second (upstream hack-detect.pwn VehicleHealthCheck and OnUnoccupiedVehicleUpdate): a driver in a vehicle
-- healthier than the server can make one (the vehicles resource tops out at 990) is banned, and an empty vehicle
-- that jumps far while a player stands next to it gets that player kicked.
return function(ctx)
    local samples = {} -- vehicle -> { x, y, z, tick } of the previous sample while it stood empty
    local lastOccupied = {} -- vehicle -> tick it last had someone in it
    local M = {}

    local MAX_HEALTH = 990
    local JUMP_MIN, JUMP_MAX = 15.0, 500.0
    local BLAME_RADIUS = 10.0
    local SETTLE_MS = 5000
    local SPAWN_MS = 15000

    local function checkHealth(player, vehicle)
        if getPedOccupiedVehicleSeat(player) ~= 0 then
            return -- passengers see the driver's health; checking them banned the wrong player upstream
        end
        local health = getElementHealth(vehicle)
        if health <= MAX_HEALTH then
            return
        end
        local reason = string.format("Vehicle health of %.2f (impossible via server)", health)
        ctx.report(player, "VHP", reason)
        ctx.autoBan(player, reason)
        setTimer(function(v)
            if isElement(v) then
                setElementHealth(v, 300)
            end
        end, 1000, 1, vehicle)
    end

    local function blame(x, y, z, ox, oy, oz)
        local best, bestDist = nil, BLAME_RADIUS
        for _, p in ipairs(getElementsByType("player")) do
            local px, py, pz = getElementPosition(p)
            local dNow = getDistanceBetweenPoints3D(px, py, pz, x, y, z)
            local dBefore = getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz)
            local d = math.min(dNow, dBefore)
            if d < bestDist then
                best, bestDist = p, d
            end
        end
        return best
    end

    local function checkJump(vehicle, now)
        local x, y, z = getElementPosition(vehicle)
        local prev = samples[vehicle]
        samples[vehicle] = { x, y, z, now }
        if not prev or isVehicleBlown(vehicle) then
            return
        end
        if lastOccupied[vehicle] and now - lastOccupied[vehicle] < SETTLE_MS then
            return
        end
        local jump = getDistanceBetweenPoints3D(x, y, z, prev[1], prev[2], prev[3])
        local vx, vy, vz = getElementVelocity(vehicle)
        local allowed = JUMP_MIN + 2 * math.sqrt(vx * vx + vy * vy + vz * vz) * 50 * ((now - prev[4]) / 1000)
        if jump <= allowed or jump >= JUMP_MAX then
            return
        end
        local culprit = blame(x, y, z, prev[1], prev[2], prev[3])
        if not culprit or ctx.exempt(culprit) or ctx.sinceSpawn(culprit) < SPAWN_MS then
            return
        end
        local name = getVehicleName(vehicle)
        local reason = string.format("Teleported a %s %.0fm", name, jump)
        local info = string.format("%.1f, %.1f, %.1f", x, y, z)
        ctx.report(culprit, "VTP", reason, info)
        ctx.kick(culprit, reason, "VTP")
    end

    function M.update()
        local now = getTickCount()
        for _, vehicle in ipairs(getElementsByType("vehicle")) do
            local occupants = getVehicleOccupants(vehicle) or {}
            if next(occupants) then
                lastOccupied[vehicle] = now
                samples[vehicle] = nil
                local driver = occupants[0]
                if driver and not ctx.exempt(driver) then
                    checkHealth(driver, vehicle)
                end
            elseif
                getVehicleTowedByVehicle(vehicle)
                or getVehicleTowingVehicle(vehicle)
                or isElementAttached(vehicle)
            then
                samples[vehicle] = nil
            else
                checkJump(vehicle, now)
            end
        end
    end

    addEventHandler("onElementDestroy", root, function()
        if getElementType(source) == "vehicle" then
            samples[source], lastOccupied[source] = nil, nil
        end
    end)

    return M
end
