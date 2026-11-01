-- The Parachute (upstream core/item/parachute.pwn, whose _EquipParachute only said "Not implemented."; the rules are
-- in shared/logic/smallitems.lua):
--   Y (upstream KEY_YES, containers.lua putaway) or F (use.lua) with it in hand, while no bag is worn (upstream's
--     check), puts it on: the item leaves the hand for the 'parachute' holder
--     slot (item_wear) and the player gets GTA's parachute, weapon 46, without switching to it (hands.setGear);
--   the drop key with empty hands takes it off into the hand (upstream's N, hud keys.lua: itemUnwearRequested
--     "parachute"), or into the inventory when the server finds the hand taken;
--   GTA takes the weapon away once the parachute has carried the player down: the client says so (parachuteSpent,
--     client/parachute.lua) and the item is destroyed;
--   a death drops it on the ground with everything else (character_drop_items), a logout keeps it worn and the next
--     spawn gives the weapon back (hands.rebuildCarried). Upstream recreated the item on take-off; here the one row
--     moves, so it is never duplicated.
-- ctx = { db, net, state, charId, toast, destroy, hands, small } built by server/main.lua.
return function(ctx)
    local net, state, hands, small = ctx.net, ctx.state, ctx.hands, ctx.small
    local charId, toast = ctx.charId, ctx.toast
    local M = {}

    -- hands.setGear's "parachute" slot: the weapon follows the worn item (given once, never made the current weapon)
    function M.apply(player, item)
        if not isElement(player) then
            return
        end
        local weapon, slot = small.PARACHUTE_WEAPON, small.PARACHUTE_SLOT
        if not item then
            return takeWeapon(player, weapon)
        end
        if getPedWeapon(player, slot) ~= weapon or getPedTotalAmmo(player, slot) <= 0 then
            giveWeapon(player, weapon, 1, false)
        end
    end

    -- use.lua and containers.lua: the Parachute in hand put on
    function M.equip(player, itemId)
        local cid, held = charId(player), state.held[player]
        if not cid or not held or held.id ~= itemId then
            return
        end
        if state.worn[player] then
            return toast(player, "PARABAGWORN")
        end
        if state.parachute[player] then
            return toast(player, "PARAWORN")
        end
        ctx.db.call("item_wear", { itemId, cid, "parachute", nil, n = 4 }, function(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            local cur = state.held[c.player]
            if cur and cur.id == c.item.id then
                hands.setHeld(c.player, nil)
            end
            hands.setGear(c.player, "parachute", c.item)
            toast(c.player, "EQUIPPED")
            triggerEvent("itemMoved", c.player, c.item.id, "held", "parachute")
        end, { player = player, item = held })
    end

    -- the client saw GTA spend it; a parachute taken off or dropped by a death is no longer in state.parachute
    net.handler("parachuteSpent", function(player)
        local item = state.parachute[player]
        if not item or not charId(player) or isPedDead(player) then
            return
        end
        hands.setGear(player, "parachute", nil)
        ctx.destroy(item.id, player)
    end, { rate = 2 })

    return M
end
