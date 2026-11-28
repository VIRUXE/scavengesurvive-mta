-- The Flashlight in the hand (shared/logic/flashlight.lua): the goggles key switches it on and off. Who has one on is
-- element data ("items.torch", hands.publishTorch): every client then raises that player's arm and draws the beam
-- (client/flashlight.lua). It goes off whenever it leaves the hand (hands.clearHeld).
-- ctx = { net, state, hands, flashlight, charId, log, isBadInteract } built by server/main.lua.
return function(ctx)
    local state, hands, flashlight, log = ctx.state, ctx.hands, ctx.flashlight, ctx.log

    ctx.net.handler("flashlightToggleRequested", function(player)
        local held = state.held[player]
        if not ctx.charId(player) or not held or held.uname ~= flashlight.UNAME or ctx.isBadInteract(player) then
            return
        end
        local on = state.torchOn[player] ~= true
        state.torchOn[player] = on or nil
        hands.publishTorch(player)
        log.event("items.flashlightSwitched", { player = player, item_id = held.id, on = on })
    end, { rate = 4 })
end
