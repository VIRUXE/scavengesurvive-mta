-- Worn Night Vision and Thermal Vision goggles (shared/logic/goggles.lua): the goggles key switches them on and
-- off, a battery runs down while they are on and a Tool Battery from the hand trades places with it. Which vision
-- shows is element data ("items.vision", hands.publishEyes): the wearer's client draws it (client/goggles.lua) and
-- every client flips the goggles down over the wearer's eyes. The battery lives in the goggles' item data and
-- reaches the DB through hands.queueData, like a mask's filter.
-- ctx = { net, state, hands, goggles, charId, toast, log, isBadInteract, sendInventory } built by server/main.lua.
-- luacheck: read globals isPedInVehicle
return function(ctx)
    local state, hands, goggles = ctx.state, ctx.hands, ctx.goggles
    local toast, sendInventory, log = ctx.toast, ctx.sendInventory, ctx.log
    local TICK_MS = 5000
    local PUT_ON_MS = 700 -- GTA's own goggles animation
    local shown = {} -- player -> the whole % the inventory last showed, so it is resent only when that changes

    local function switch(player, on)
        state.eyesOn[player] = on or nil
        hands.publishEyes(player)
        if not isPedInVehicle(player) then
            setPedAnimation(player, "GOGGLES", "goggles_put_on", PUT_ON_MS, false, true, true, false)
        end
    end

    ctx.net.handler("gogglesToggleRequested", function(player)
        local item = state.eyes[player]
        if not ctx.charId(player) or not item or not goggles.spec(item.uname) or ctx.isBadInteract(player) then
            return
        end
        local on = state.eyesOn[player] ~= true
        local left = goggles.battery(item.data)
        if on and left <= 0 then
            log.event("items.gogglesSwitched", {
                player = player,
                item_id = item.id,
                uname = item.uname,
                ok = false,
                code = "GOGGLES_FLAT",
            })
            return toast(player, "GOGGLES_FLAT")
        end
        switch(player, on)
        log.event("items.gogglesSwitched", {
            player = player,
            item_id = item.id,
            uname = item.uname,
            on = on,
            battery = goggles.percent(left),
        })
    end, { rate = 3 })

    -- A Tool Battery used from the hand: it goes into the worn goggles and the one inside comes out into the hand,
    -- unless that one is no emptier. True when handled.
    local function useBattery(player, batteryId)
        local item, held = state.eyes[player], state.held[player]
        if not item or not goggles.spec(item.uname) or not held or held.id ~= batteryId then
            return false
        end
        local charge = goggles.toolCharge(held.data)
        local out = goggles.swap(item, charge)
        if not out then
            toast(player, charge <= 0 and "GOGGLES_TOOL_FLAT" or "GOGGLES_NO_GAIN")
            return true
        end
        held.data = { charge = out }
        hands.queueData(item)
        hands.queueData(held)
        shown[player] = nil
        hands.publishEyes(player)
        hands.sendHeld(player, held)
        sendInventory(player)
        toast(player, "GOGGLES_BATTERY")
        log.event("items.gogglesBatterySwapped", {
            player = player,
            item_id = item.id,
            uname = item.uname,
            battery_id = held.id,
            battery = goggles.percent(charge),
            battery_out = goggles.percent(out),
        })
        return true
    end

    -- every pair switched on runs its battery down; a flat one switches itself off
    setTimer(function()
        for player in pairs(state.eyesOn) do
            local item = isElement(player) and state.eyes[player]
            if not item then
                state.eyesOn[player] = nil
            else
                local flat = goggles.drain(item, TICK_MS / 1000) == "flat"
                hands.queueData(item)
                if flat then
                    state.eyesOn[player] = nil
                    toast(player, "GOGGLES_FLAT")
                    log.event("items.gogglesSwitched", {
                        player = player,
                        item_id = item.id,
                        uname = item.uname,
                        on = false,
                        battery = 0,
                    })
                end
                local now = goggles.percent(goggles.battery(item.data))
                if flat or shown[player] ~= now then
                    shown[player] = now
                    hands.publishEyes(player)
                    sendInventory(player)
                end
            end
        end
    end, TICK_MS, 0)

    addEventHandler("onPlayerQuit", root, function()
        shown[source] = nil
    end)

    return { useBattery = useBattery }
end
