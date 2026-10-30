-- Server side of the poses and the aim shout (#140, shared/logic/poses.lua): the client asks (sitRequested,
-- standRequested, handsUpRequested, aimShoutRequested), the server checks the character can (spawned, alive, on
-- foot, not knocked out or cuffed, standing still for a sit) and plays the animation so everyone sees it; the
-- shout is the line /aimshout stored for the session, sent as the player's local chat.
-- ctx = { net, state, poses, isKnockedOut, isPlayerCuffed, lang } built by server/main.lua.
return function(ctx)
    local net, state, poses = ctx.net, ctx.state, ctx.poses
    local posed = {} -- player -> "sitting" | "handsUp"
    local sitTimers = {} -- player -> timer for the loop after PARKSIT_M_IN
    local shouts = {} -- player -> text
    local lastShout = {} -- player -> tick
    local M = {}

    local function able(player)
        local st = state.byPlayer[player]
        return st ~= nil
            and not st.dead
            and not isPedDead(player)
            and not getPedOccupiedVehicle(player)
            and not ctx.isKnockedOut(player)
            and not ctx.isPlayerCuffed(player)
    end

    local function still(player)
        local vx, vy, vz = getElementVelocity(player)
        return math.sqrt(vx * vx + vy * vy + vz * vz) < poses.STILL_SPEED
    end

    local function play(player, key)
        local a = poses.ANIMS[key]
        if key == "sitIn" then
            setPedAnimation(player, a[1], a[2], poses.SIT_IN_MS, false, false, false, true)
            sitTimers[player] = setTimer(function(pl)
                sitTimers[pl] = nil
                if isElement(pl) and posed[pl] == "sitting" then
                    local loop = poses.ANIMS.sitLoop
                    setPedAnimation(pl, loop[1], loop[2], -1, true, false, false, false)
                end
            end, poses.SIT_IN_MS, 1, player)
        elseif key == "sitOut" then
            setPedAnimation(player, a[1], a[2], -1, false, false, false, false)
        elseif key == "handsUp" then
            setPedAnimation(player, a[1], a[2], -1, false, false, false, true)
        else
            setPedAnimation(player)
        end
    end

    local function stopSitTimer(player)
        if isTimer(sitTimers[player]) then
            killTimer(sitTimers[player])
        end
        sitTimers[player] = nil
    end

    -- upstream's animation index 1381 test (disallow-actions.pwn): items refuse to work for a player with hands up
    function M.isHandsUp(player)
        return posed[player] == "handsUp"
    end

    -- the pose ends without an animation (death, knockout, a vehicle): forget it
    function M.clear(player)
        stopSitTimer(player)
        posed[player] = nil
        if isElement(player) then
            triggerClientEvent(player, "poseChanged", player, false)
        end
    end

    local function request(player, action)
        if not able(player) then
            return
        end
        if action ~= "stand" and not still(player) then
            return
        end
        local nextPose, anim = poses.next(posed[player], action)
        if not anim then
            return
        end
        stopSitTimer(player)
        posed[player] = nextPose
        play(player, anim)
        triggerClientEvent(player, "poseChanged", player, nextPose or false)
    end

    net.handler("sitRequested", function(player)
        request(player, "sit")
    end, { rate = 4 })

    net.handler("standRequested", function(player)
        request(player, "stand")
    end, { rate = 4 })

    net.handler("handsUpRequested", function(player)
        request(player, "hands")
    end, { rate = 4 })

    net.handler("aimShoutRequested", function(player)
        local text = shouts[player]
        if not text or text == "" or not state.byPlayer[player] or isPedDead(player) then
            return
        end
        local now = getTickCount()
        if not poses.canShout(lastShout[player], now) then
            return
        end
        lastShout[player] = now
        local chat = getResourceFromName("chat")
        if chat and getResourceState(chat) == "running" then
            exports.chat:sendAs(player, text, 0) -- local chat, whatever mode the player is in
        end
    end, { rate = 4 })

    addCommandHandler("aimshout", function(player, _, ...)
        if getElementType(player) ~= "player" then
            return
        end
        local text = poses.cleanShout(table.concat({ ... }, " "))
        if text == "" then
            return outputChatBox(ctx.lang(player, "AIMSHOUTHLP"), player, 255, 255, 0)
        end
        shouts[player] = text
        outputChatBox(ctx.lang(player, "AIMSHOUTSET", text), player, 255, 255, 0)
    end)

    addEventHandler("characterDied", root, function()
        M.clear(source)
    end)

    addEventHandler("onPlayerVehicleEnter", root, function()
        if posed[source] then
            M.clear(source)
        end
    end)

    addEventHandler("onPlayerQuit", root, function()
        stopSitTimer(source)
        posed[source] = nil
        shouts[source] = nil
        lastShout[source] = nil
    end)

    return M
end
