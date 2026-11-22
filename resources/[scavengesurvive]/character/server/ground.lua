-- Under-map rescue for players on foot (vehicles/server/ground.lua does the vehicles). A player pushed through the
-- ground (2026-11-22: a panel raised next to its builder) falls until GTA itself puts them back on some surface
-- hundreds of metres away, which the anticheat then reports as a teleport. Every SCAN_MS the server tests each living
-- character on foot against its own copy of the world (lib geom.lua, ml_sageom):
--   ok      a surface within STAND metres under them: the place is remembered
--   under   falling (DROP metres lower than the scan before), nothing within BELOW metres under them, a surface more
--           than DEPTH metres over them and no water surface near or under them (a diver, or a fall under a bridge
--           over the sea, is left alone): they are put back where they last stood when that is within BACK metres,
--           else on the topmost surface over them
--   anything else (a jump, a fall through open air, a place the server's world does not know) is left alone.
-- Main world only, never staff on duty. While the server's world is not ready (lib geom.lua) nothing is tested.
-- ctx = { log, state, onDuty }
return function(ctx)
    local geom = assert(loadstring(exports.lib:getModule("geom"), "=lib/geom.lua"))()
    local SCAN_MS = 500
    local STAND = 2.5 -- a ped's origin is about a metre over what it stands on
    local DROP = 1.0
    local BELOW = 150
    local DEPTH = 3
    local TOP = 1500
    local WATER = 10
    local BACK = 30
    local LIFT = 0.3 -- over the remembered origin
    local LIFT_SURFACE = 1.5 -- over a surface: the origin's height plus a little

    local stood = setmetatable({}, { __mode = "k" }) -- player -> { x, y, z } where they last stood on something
    local lastZ = setmetatable({}, { __mode = "k" }) -- player -> z at the scan before

    local function forget(player)
        stood[player], lastZ[player] = nil, nil
    end

    -- the topmost surface over an under-map position, or nil when this is not one
    local function surfaceOver(x, y, z)
        if geom.below(x, y, z, 0.5, BELOW) then
            return nil
        end
        local surface = geom.below(x, y, TOP, 0, TOP - z - 0.5)
        local wz = geom.water(x, y)
        if not surface or surface < z + DEPTH or (wz and z > wz - WATER) then
            return nil
        end
        return surface
    end

    local function rescue(player, x, y, z, surface)
        local s = stood[player]
        local tx, ty, tz = x, y, surface + LIFT_SURFACE
        if s and s.z > z and getDistanceBetweenPoints2D(x, y, s.x, s.y) <= BACK then
            tx, ty, tz = s.x, s.y, s.z + LIFT
        end
        setElementVelocity(player, 0, 0, 0)
        setElementPosition(player, tx, ty, tz) -- a server-side move: MTA's onPlayerTeleport (anticheat) skips it
        forget(player)
        ctx.log.event("character.rescued", {
            player = player,
            reason = "under_map",
            from_x = x,
            from_y = y,
            from_z = z,
            x = tx,
            y = ty,
            z = tz,
        }, "warn")
    end

    local function scan()
        if not geom.ready() then
            return
        end
        for player, st in pairs(ctx.state.byPlayer) do
            if
                not isElement(player)
                or st.dead
                or isPedDead(player)
                or ctx.onDuty(player)
                or getPedOccupiedVehicle(player)
                or getElementInterior(player) ~= 0
                or getElementDimension(player) ~= 0
            then
                forget(player)
            else
                local x, y, z = getElementPosition(player)
                local before = lastZ[player]
                lastZ[player] = z
                if geom.below(x, y, z, 0, STAND) then
                    stood[player] = { x = x, y = y, z = z }
                elseif before and before - z >= DROP then
                    local surface = surfaceOver(x, y, z)
                    if surface then
                        rescue(player, x, y, z, surface)
                    end
                end
            end
        end
    end

    setTimer(scan, SCAN_MS, 0)
end
