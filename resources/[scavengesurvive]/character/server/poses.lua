-- Server side of the poses and the aim shout (#140, shared/logic/poses.lua): the client asks (sitRequested,
-- standRequested, handsUpRequested, aimShoutRequested), the server checks the character can (spawned, alive, on
-- foot, not knocked out or cuffed, standing still for a sit) and plays the animation so everyone sees it; the
-- shout is the line /aimshout stored for the session, sent as the player's local chat.
-- ctx = { net, state, poses, isKnockedOut, isPlayerCuffed, lang } built by server/main.lua.
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

-- lang:begin
local HANDS_TIP = "Your hands are up. Crouch to lower them."
local TIP_FOOTER = "Type /tooltips to toggle these messages"
-- lang:end

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

    -- upstream played the hands-up animation frozen and position-locked, so the player stood still until the hands
    -- came down again; sprint and crouch stay on: crouch lowers the hands (client/poses.lua), and so does the
    -- animation ending some other way, so the controls never stay off once the hands look down (2026-11-15, a
    -- player stood stuck with no animation and no idea that only sprint and crouch together undid it)
    local HOLD_CONTROLS = { "forwards", "backwards", "left", "right", "jump", "enter_exit" }
    local function hold(player, on)
        for _, ctrl in ipairs(HOLD_CONTROLS) do
            toggleControl(player, ctrl, not on)
        end
        if on then
            exports.ui:showTip(player, lang.textFor(player, HANDS_TIP), lang.textFor(player, TIP_FOOTER), 8000)
        else
            exports.ui:hideTip(player)
        end
    end

    local function logPose(player, from, to, reason)
        log.event(
            "character.poseChanged",
            { player = player, from = from or "standing", to = to or "standing", reason = reason }
        )
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
        local was = posed[player]
        posed[player] = nil
        if isElement(player) then
            if was == "handsUp" then
                hold(player, false)
            end
            if was then
                logPose(player, was, nil, "cleared")
            end
            triggerClientEvent(player, "poseChanged", player, false)
        end
    end

    local function request(player, action)
        if not able(player) then
            return
        end
        local lowering = action == "hands" and posed[player] == "handsUp"
        if action ~= "stand" and not lowering and not still(player) then
            return
        end
        local was = posed[player]
        local nextPose, anim = poses.next(was, action)
        if not anim then
            return
        end
        stopSitTimer(player)
        if (was == "handsUp") ~= (nextPose == "handsUp") then
            hold(player, nextPose == "handsUp")
        end
        logPose(player, was, nextPose, action)
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

    -- a restart of this resource must not leave anyone with the hands-up controls off
    addEventHandler("onResourceStop", resourceRoot, function()
        for player, p in pairs(posed) do
            if p == "handsUp" and isElement(player) then
                hold(player, false)
            end
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
