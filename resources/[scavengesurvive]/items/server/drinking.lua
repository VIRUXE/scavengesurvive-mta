-- Drinking from a held liquid container (upstream itemtype/liquid-container.pwn _StartDrinking/_DrinkItem): the
-- interact key starts a 1 s hold with the drinking animation; every finished hold takes a sip (shared/logic/
-- liquids.lua) and starts the next one, so holding the key empties the container. Letting go, moving, a new item in
-- hand, dying or leaving stops it. The client side is the treatment hold bar (treatmentStarted / treatmentStopped
-- and treatmentCancelRequested on key release, items/client/main.lua).
-- ctx = { state, liquids, type, toast, writeHeldData } built by server/main.lua, which also routes
-- treatmentCancelRequested here.
return function(ctx)
    local state, liquids, itemType, toast = ctx.state, ctx.liquids, ctx.type, ctx.toast
    local CHECK_MS, MAX_MOVE = 250, 0.8
    local active = {} -- player -> { itemId, x, y, z, left, timer }
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
        if isElement(player) then
            setPedAnimation(player)
            triggerClientEvent(player, "treatmentStopped", player)
        end
    end

    local function begin(player, held, continuing)
        local x, y, z = getElementPosition(player)
        local a = { itemId = held.id, x = x, y = y, z = z, left = liquids.HOLD_MS }
        a.timer = setTimer(M.tick, CHECK_MS, 0, player)
        active[player] = a
        if not continuing then
            setPedAnimation(player, "BAR", "dnk_stndM_loop", -1, true, false, false, false)
        end
        triggerClientEvent(player, "treatmentStarted", player, liquids.HOLD_MS, true)
    end

    local function sip(player, a)
        local held = state.held[player]
        if not held or held.id ~= a.itemId then
            return stop(player)
        end
        local t = itemType(held.uname)
        local ok, nextData, food = liquids.sip(t, held.data)
        if not ok then
            stop(player)
            return toast(player, "LIQUID_EMPTY")
        end
        ctx.writeHeldData(player, held.id, nextData)
        if food ~= 0 then
            exports.character:modifyStat(player, "food", food)
        end
        if isTimer(a.timer) then
            killTimer(a.timer)
        end
        active[player] = nil
        if nextData.amount < liquids.EMPTY_BELOW then
            setPedAnimation(player)
            triggerClientEvent(player, "treatmentStopped", player)
            return toast(player, "LIQUID_EMPTY")
        end
        begin(player, held, true)
    end

    function M.tick(player)
        local a = active[player]
        if not a or not isElement(player) then
            return
        end
        local x, y, z = getElementPosition(player)
        local held = state.held[player]
        if isPedDead(player) or getDistanceBetweenPoints3D(x, y, z, a.x, a.y, a.z) > MAX_MOVE then
            return stop(player)
        end
        if not held or held.id ~= a.itemId then
            return stop(player)
        end
        a.left = a.left - CHECK_MS
        if a.left <= 0 then
            sip(player, a)
        end
    end

    -- From the hand only; an empty container says so at once.
    function M.start(player, held)
        if active[player] or exports.character:isKnockedOut(player) or getPedOccupiedVehicle(player) then
            return
        end
        local t = itemType(held.uname)
        if not liquids.isContainer(t) then
            return
        end
        local _, liquid = liquids.decode(t, held.data)
        if not liquid then
            return toast(player, "LIQUID_EMPTY")
        end
        begin(player, held, false)
    end

    function M.isDrinking(player)
        return active[player] ~= nil
    end

    function M.cancel(player)
        stop(player)
    end

    addEventHandler("onPlayerQuit", root, function()
        stop(source)
    end)

    addEventHandler("characterDied", root, function()
        stop(source)
    end)

    return M
end
