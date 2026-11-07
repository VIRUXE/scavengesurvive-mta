-- The snack machine's glass (shared/logic/vending.lua): the server never sees a hit on a client-side object, so this
-- client reports its own player's. The intact pane collides, and every punch, swing or bullet that lands on it is
-- an onClientObjectDamage with this player as the attacker: that hit goes to the server (vendingGlassHit), which
-- checks it and keeps the count. A shot whose path crosses a pane is reported as well, in case the bullet passed it.
-- When a pane gives, everyone near sees it burst (vendingGlassBroken). ctx = { world, vending }.
return function(ctx)
    local world, vending = ctx.world, ctx.vending

    local function report(id)
        triggerServerEvent("vendingGlassHit", localPlayer, id, getPedWeapon(localPlayer))
    end

    addEventHandler("onClientObjectDamage", root, function(_, attacker)
        local id = world.machineOfPane(source)
        if not id then
            return
        end
        setElementHealth(source, 1000) -- the server keeps the count; GTA's own damage never wears it out
        if attacker == localPlayer then
            report(id)
        end
    end)

    addEventHandler(
        "onClientPlayerWeaponFire",
        localPlayer,
        function(weapon, _, _, hitX, hitY, hitZ, hitElement, startX, startY, startZ)
            if (tonumber(weapon) or 0) < 16 or not hitX or world.machineOfPane(hitElement) then
                return -- the pane's own damage event reports a bullet that hit it
            end
            local sx, sy, sz = startX, startY, startZ
            if not sx then
                sx, sy, sz = getPedWeaponMuzzlePosition(localPlayer)
            end
            local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
            for _, m in ipairs(world.intactMachines()) do
                if
                    m.int == int
                    and m.dim == dim
                    and vending.segmentHitsGlass(m.x, m.y, m.z, m.rz, sx, sy, sz, hitX, hitY, hitZ)
                then
                    return report(m.id)
                end
            end
        end
    )

    -- a pane gave: glass bursts out of the whole window and rains onto the pavement
    addEventHandler("vendingGlassBroken", resourceRoot, function(id)
        local x, y, z, rz = world.machineAt(id)
        if not x then
            return
        end
        local w = vending.WINDOW
        local a = math.rad(rz)
        local ly = vending.GLASS_Y - 0.03
        for i = 0, 3 do
            for k = 0, 5 do
                local lx = w.x0 + (w.x1 - w.x0) * (0.12 + 0.25 * i)
                local lz = w.z0 + (w.z1 - w.z0) * (0.08 + 0.17 * k)
                local wx = x + lx * math.cos(a) - ly * math.sin(a)
                local wy = y + lx * math.sin(a) + ly * math.cos(a)
                fxAddGlass(wx, wy, z + lz, 210, 225, 235, 220, 0.9, 6)
            end
        end
    end)
end
