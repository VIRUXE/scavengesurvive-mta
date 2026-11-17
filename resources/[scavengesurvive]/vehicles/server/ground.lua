-- Under-map rescue. A vehicle that falls through the world (spawned into a slope, or before its syncer's collision had
-- loaded) keeps that position on the server even after GTA puts the client's copy back on a road, so F on what the
-- player sees is refused (2026-11-15, Sandking #318 at z -93). Every SCAN_MS the server tests each empty vehicle it
-- has not yet seen standing on something against its own copy of the world (lib geom.lua, ml_sageom):
--   ok      a surface within BELOW metres under it
--   sunk    fully under water: its top (TOP_ABOVE by size class over its origin) under the water surface, nothing
--           solid between it and that surface, and a bed under it; it stays there for staff to delete and the fleet
--           refill replaces it (ctx.setSunk); a later ok or rescue clears the mark
--   under   nothing under it but a surface over it: it is put back on that topmost surface, unless water lies within
--           WATER metres of it (a boat or a sinking car under a bridge must not be lifted onto the bridge; GTA's water
--           areas run on under the land along the coasts, so a car under the coastal ground has water far above it)
--   anything else (mid-air, open sky over deep water) is left alone.
-- Main world only. While the server's world is not ready (lib geom.lua) nothing is tested.
return function(ctx)
    local geom = ctx.geom
    local SCAN_MS = 10000
    local MOVED = 1.0 -- metres a vehicle may drift before its last "ok" stops counting
    local LIFT = 1.0 -- metres above the surface the vehicle is put back at
    local BELOW = 60
    local TOP = 1500
    local WATER = 10
    local BED = 200 -- how deep under a sunk vehicle the sea or lake bed is looked for
    -- how far a vehicle's highest point sits over its origin, by vehicle_types size; generous, so a vehicle half in
    -- the water is never called sunk
    local TOP_ABOVE = { small = 1.5, medium = 2.0, large = 3.0 }

    local verified = setmetatable({}, { __mode = "k" }) -- vehicle -> { x, y, z } of its last "ok"
    local sizes = {} -- type uname -> size class

    local function near(a, x, y, z)
        return a and math.abs(a.x - x) <= MOVED and math.abs(a.y - y) <= MOVED and math.abs(a.z - z) <= MOVED
    end

    local function empty(v)
        return next(getVehicleOccupants(v) or {}) == nil and not getVehicleTowingVehicle(v)
    end

    local function topAbove(v)
        local uname = ctx.info[v] and ctx.info[v].uname
        if uname and sizes[uname] == nil then
            local vt = exports.data:vehicleType(uname)
            sizes[uname] = type(vt) == "table" and vt.size or false
        end
        return TOP_ABOVE[uname and sizes[uname] or "medium"] or TOP_ABOVE.medium
    end

    local function sunk(v, x, y, z)
        local wz = geom.water(x, y)
        local top = z + topAbove(v)
        return wz ~= nil and wz > top and geom.clear(x, y, z, x, y, wz) == true and geom.below(x, y, z, 0, BED) ~= nil
    end

    local function verdict(v, x, y, z)
        if sunk(v, x, y, z) then
            return "sunk"
        end
        if geom.below(x, y, z, 0.5, BELOW) then
            return "ok"
        end
        local surface = geom.below(x, y, TOP, 0, TOP - z - 0.5)
        local wz = geom.water(x, y)
        if not surface or (wz and math.abs(wz - z) <= WATER) then
            return "unknown"
        end
        return "under", surface
    end

    local function rescue(v, x, y, z, surface)
        local _, _, rz = getElementRotation(v)
        setElementVelocity(v, 0, 0, 0)
        setElementAngularVelocity(v, 0, 0, 0)
        setElementPosition(v, x, y, surface + LIFT)
        setElementRotation(v, 0, 0, rz)
        ctx.log.event(
            "vehicle.rescued",
            ctx.vehicleLine(v, { from_z = z, to_z = surface + LIFT, reason = "under_map" }),
            "warn"
        )
    end

    local function scan()
        if not geom.ready() then
            return
        end
        for v in pairs(ctx.info) do
            if isElement(v) and getElementInterior(v) == 0 and getElementDimension(v) == 0 then
                local x, y, z = getElementPosition(v)
                if not near(verified[v], x, y, z) and empty(v) then
                    local what, surface = verdict(v, x, y, z)
                    if what == "sunk" then
                        verified[v] = { x = x, y = y, z = z }
                        ctx.setSunk(v, true)
                    elseif what == "ok" then
                        verified[v] = { x = x, y = y, z = z }
                        ctx.setSunk(v, false)
                    elseif what == "under" and surface > z + 2 then
                        verified[v] = nil
                        ctx.setSunk(v, false)
                        rescue(v, x, y, z, surface)
                    end
                end
            end
        end
    end

    setTimer(scan, SCAN_MS, 0)
end
