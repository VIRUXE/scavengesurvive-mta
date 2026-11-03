-- Handcuffs (upstream item/handcuffs.pwn): holding the interact key next to a player for 3 s cuffs them with the
-- Handcuffs in hand, or, with empty hands, uncuffs a cuffed one and takes the cuffs. The target must hold no item and
-- no weapon either way. Letting go of the key, moving, the target walking out of reach or into someone else's cuffing
-- cancels it. ctx = { db, state, hands, destroy, charId, toast, isPlayerCuffed, setPlayerCuffed, isOnDuty } built by
-- server/main.lua; items' treatmentCancelRequested (key released) routes to M.cancel.
return function(ctx)
    local db, state, hands = ctx.db, ctx.state, ctx.hands
    local charId, toast, isOnDuty = ctx.charId, ctx.toast, ctx.isOnDuty
    local isPlayerCuffed, setPlayerCuffed = ctx.isPlayerCuffed, ctx.setPlayerCuffed
    local HOLD_MS, CHECK_MS, MAX_MOVE, REACH = 3000, 250, 0.8, 2.5
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    local active = {} -- player -> { target, cuffing, itemId, x, y, z, left, timer }
    local beingCuffed = {} -- target -> player
    local M = {}

    local function stop(player)
        local a = active[player]
        if not a then
            return
        end
        if isTimer(a.timer) then
            killTimer(a.timer)
        end
        active[player] = nil
        if beingCuffed[a.target] == player then
            beingCuffed[a.target] = nil
        end
        if isElement(player) then
            setPedAnimation(player)
            triggerClientEvent(player, "treatmentStopped", player)
        end
    end

    -- upstream CanPlayerHandcuffPlayer: next to each other, the target holds no weapon and no item
    local function canReach(player, target)
        if not isElement(target) or isPedDead(target) or getPedOccupiedVehicle(target) then
            return false
        end
        local x, y, z = getElementPosition(player)
        local tx, ty, tz = getElementPosition(target)
        if getDistanceBetweenPoints3D(x, y, z, tx, ty, tz) > REACH then
            return false
        end
        return not state.held[target] and getPedWeapon(target) == 0
    end

    local function finish(player, a)
        stop(player)
        local target = a.target
        local held = state.held[player]
        if not canReach(player, target) or (isPlayerCuffed(target) == true) == a.cuffing then
            return
        end
        if a.cuffing then
            if not held or held.id ~= a.itemId then
                return
            end
            ctx.destroy(held.id, player, function(ok)
                if not ok or not isElement(target) then
                    return
                end
                setPlayerCuffed(target, true)
                if isElement(player) then
                    toast(player, "CUFFED")
                end
            end)
            return
        end
        local cid = charId(player)
        if held or not cid then
            return
        end
        db.call("item_create_held", { "HandCuffs", cid }, function(res, c)
            if not isElement(c.player) or not res or not res.ok then
                return
            end
            if isElement(c.target) then
                setPlayerCuffed(c.target, false)
            end
            hands.setHeld(c.player, { id = res.payload.item_id, uname = "HandCuffs", hp = 5, data = {} })
            triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
            toast(c.player, "UNCUFFED")
        end, { player = player, target = target })
    end

    local function tick(player)
        local a = active[player]
        if not a or not isElement(player) then
            return
        end
        local x, y, z = getElementPosition(player)
        local held = state.held[player]
        if isPedDead(player) or getDistanceBetweenPoints3D(x, y, z, a.x, a.y, a.z) > MAX_MOVE then
            return stop(player)
        end
        if a.cuffing and (not held or held.id ~= a.itemId) then
            return stop(player)
        end
        if not a.cuffing and held then
            return stop(player)
        end
        if not canReach(player, a.target) then
            return stop(player)
        end
        a.left = a.left - CHECK_MS
        if a.left <= 0 then
            finish(player, a)
        end
    end

    -- target = the player next to the actor (items hands.lua findNearbyPlayer); held = the actor's item or nil.
    -- Handcuffs in hand cuff an uncuffed target, empty hands uncuff a cuffed one. true when a hold was started.
    function M.tryStart(player, held, target)
        local cuffing = held ~= nil and held.uname == "HandCuffs"
        if active[player] or beingCuffed[target] or (held and not cuffing) then
            return false
        end
        if isOnDuty(target) or getPedOccupiedVehicle(player) or not canReach(player, target) then
            return false
        end
        if cuffing == (isPlayerCuffed(target) == true) or (not cuffing and getPedWeapon(player) ~= 0) then
            return false
        end
        local x, y, z = getElementPosition(player)
        local a = { target = target, cuffing = cuffing, itemId = held and held.id, x = x, y = y, z = z }
        a.left = HOLD_MS
        a.timer = setTimer(tick, CHECK_MS, 0, player)
        active[player] = a
        beingCuffed[target] = player
        local label = cuffing and lang.textFor(player, "Handcuffing") or lang.textFor(player, "Removing handcuffs")
        setPedAnimation(player, "CASINO", "DEALONE", -1, true, false, false, false)
        triggerClientEvent(player, "treatmentStarted", player, HOLD_MS, true, label)
        return true
    end

    function M.cancel(player)
        stop(player)
    end

    addEventHandler("onPlayerQuit", root, function()
        stop(source)
        local by = beingCuffed[source]
        if by then
            stop(by)
        end
    end)

    return M
end
