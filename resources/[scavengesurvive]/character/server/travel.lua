-- Server side of the travel stats (#138, shared/logic/travel.lua): the survival tick hands every spawned
-- character's second here, the kind is read from what the server sees (vehicle, water, crouch, the distance
-- moved), the Endurance skill gains on the rules, jumps come from the client (rate-limited, counted on foot only)
-- and /mstats shows the counters in an info window. The counters live for the session (upstream saved them with
-- the character).
-- ctx = { net, travel, state, gainSkill, isKnockedOut } built by server/main.lua.
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
return function(ctx)
    local net, travel, state = ctx.net, ctx.travel, ctx.state
    local byPlayer = {} -- player -> travel.new() plus lastX/lastY/lastZ
    local M = {}

    local function of(player)
        local t = byPlayer[player]
        if not t then
            t = travel.new()
            byPlayer[player] = t
        end
        return t
    end

    local RIDE_RANGE = 4.5 -- metres from a vehicle's centre: close enough to be standing in or on it

    local function nearestVehicle(x, y, z)
        local best, bestDist = nil, RIDE_RANGE
        for _, v in ipairs(getElementsWithinRange(x, y, z, RIDE_RANGE, "vehicle")) do
            local vx, vy, vz = getElementPosition(v)
            local d = getDistanceBetweenPoints3D(x, y, z, vx, vy, vz)
            if d < bestDist then
                best, bestDist = v, d
            end
        end
        return best
    end

    function M.reset(player)
        byPlayer[player] = travel.new()
    end

    -- one second of a spawned, living character
    function M.tick(player, ms)
        local t = of(player)
        local x, y, z = getElementPosition(player)
        -- standing on a vehicle (a towed Airstream): only the movement relative to it counts, not the ride
        local ride = not getPedOccupiedVehicle(player) and nearestVehicle(x, y, z) or nil
        local rx, ry, rz = 0, 0, 0
        if ride then
            rx, ry, rz = getElementPosition(ride)
        end
        local dist = 0
        if t.lastX then
            local sameRide = ride and t.ride == ride
            local dx, dy, dz =
                sameRide and rx - t.rideX or 0, sameRide and ry - t.rideY or 0, sameRide and rz - t.rideZ or 0
            dist = getDistanceBetweenPoints3D(t.lastX + dx, t.lastY + dy, t.lastZ + dz, x, y, z)
            if ride and not sameRide then
                dist = 0
            end
        end
        t.lastX, t.lastY, t.lastZ = x, y, z
        t.ride, t.rideX, t.rideY, t.rideZ = ride, rx, ry, rz
        if ctx.isKnockedOut(player) then
            t.knockedOutMs = t.knockedOutMs + ms
            return
        end
        local _, _, vz = getElementVelocity(player)
        local kind = travel.classify({
            inVehicle = getPedOccupiedVehicle(player) ~= false,
            inWater = isElementInWater(player),
            ducked = isPedDucked(player),
            falling = not isPedOnGround(player) and vz < -0.1,
            speed = dist * 1000 / ms,
        })
        if travel.record(t, kind, dist, ms, getTickCount()) then
            ctx.gainSkill(player, "Endurance")
        end
    end

    net.handler("playerJumped", function(player)
        local st = state.byPlayer[player]
        if not st or st.dead or getPedOccupiedVehicle(player) or ctx.isKnockedOut(player) then
            return
        end
        if travel.jump(of(player)) then
            ctx.gainSkill(player, "Endurance")
        end
    end, { rate = 3 })

    addCommandHandler("mstats", function(player)
        if not state.byPlayer[player] then
            return
        end
        exports.ui:showInfo(
            player,
            travel.window(of(player), function(text)
                return lang.textFor(player, text)
            end)
        )
    end)

    addEventHandler("characterSpawned", root, function()
        M.reset(source)
    end)

    addEventHandler("onPlayerQuit", root, function()
        byPlayer[source] = nil
    end)

    return M
end
