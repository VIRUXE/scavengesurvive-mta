-- Server side of the travel stats (#138, shared/logic/travel.lua): the survival tick hands every spawned
-- character's second here, the kind is read from what the server sees (vehicle, water, crouch, the distance
-- moved), the Endurance skill gains on the rules, jumps come from the client (rate-limited, counted on foot only)
-- and /mstats prints the counters. The counters live for the session (upstream saved them with the character).
-- ctx = { net, travel, state, gainSkill, isKnockedOut } built by server/main.lua.
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

    function M.reset(player)
        byPlayer[player] = travel.new()
    end

    -- one second of a spawned, living character
    function M.tick(player, ms)
        local t = of(player)
        local x, y, z = getElementPosition(player)
        local dist = 0
        if t.lastX then
            dist = getDistanceBetweenPoints3D(t.lastX, t.lastY, t.lastZ, x, y, z)
        end
        t.lastX, t.lastY, t.lastZ = x, y, z
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
        for _, line in ipairs(travel.lines(of(player))) do
            outputChatBox(line, player, 200, 200, 200)
        end
    end)

    addEventHandler("characterSpawned", root, function()
        M.reset(source)
    end)

    addEventHandler("onPlayerQuit", root, function()
        byPlayer[source] = nil
    end)

    return M
end
