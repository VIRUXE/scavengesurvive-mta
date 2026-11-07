-- The snack machine's glass (shared/logic/vending.lua): the server never sees a hit on a client-side object, so this
-- client reports its own player's: a shot whose path crosses an intact pane, or a swing (fists or a melee weapon) at
-- one in reach in front of it. The server checks each report and keeps the count; when a pane gives, everyone near
-- sees it burst (vendingGlassBroken). ctx = { world, vending }.
return function(ctx)
    local world, vending = ctx.world, ctx.vending
    local SWING_DELAY_MS = 250 -- the fist lands a moment after the button
    local lastSwing = 0

    local function report(id)
        triggerServerEvent("vendingGlassHit", localPlayer, id, getPedWeapon(localPlayer))
    end

    local function sameWorld(m)
        return m.int == getElementInterior(localPlayer) and m.dim == getElementDimension(localPlayer)
    end

    addEventHandler(
        "onClientPlayerWeaponFire",
        localPlayer,
        function(weapon, _, _, hitX, hitY, hitZ, _, startX, startY, startZ)
            if (tonumber(weapon) or 0) < 16 or not hitX then
                return
            end
            local sx, sy, sz = startX, startY, startZ
            if not sx then
                sx, sy, sz = getPedWeaponMuzzlePosition(localPlayer)
            end
            for _, m in ipairs(world.intactMachines()) do
                if sameWorld(m) and vending.segmentHitsGlass(m.x, m.y, m.z, m.rz, sx, sy, sz, hitX, hitY, hitZ) then
                    return report(m.id)
                end
            end
        end
    )

    bindKey("fire", "down", function()
        if isPedInVehicle(localPlayer) or isPedDead(localPlayer) or isCursorShowing() then
            return
        end
        if getPedWeaponSlot(localPlayer) > 1 then -- slot 0 fists, 1 melee weapons
            return
        end
        local now = getTickCount()
        if now - lastSwing < 450 then
            return
        end
        lastSwing = now
        local px, py, pz = getElementPosition(localPlayer)
        local _, _, prz = getElementRotation(localPlayer)
        for _, m in ipairs(world.intactMachines()) do
            if sameWorld(m) and vending.inSwingReach(m.x, m.y, m.z, m.rz, px, py, pz, prz) then
                local id = m.id
                return setTimer(report, SWING_DELAY_MS, 1, id)
            end
        end
    end)

    -- a pane gave: glass bursts out of the window, low and high
    addEventHandler("vendingGlassBroken", resourceRoot, function(id)
        local x, y, z, rz = world.machineAt(id)
        if not x then
            return
        end
        local w = vending.WINDOW
        local a = math.rad(rz)
        for i = 0, 4 do
            local lx = w.x0 + (w.x1 - w.x0) * (0.2 + 0.15 * i)
            local lz = w.z0 + (w.z1 - w.z0) * (0.15 + 0.17 * i)
            local ly = vending.GLASS_Y - 0.05
            local wx = x + lx * math.cos(a) - ly * math.sin(a)
            local wy = y + lx * math.sin(a) + ly * math.cos(a)
            fxAddGlass(wx, wy, z + lz, 200, 215, 225, 180, 0.6, 8)
        end
    end)
end
