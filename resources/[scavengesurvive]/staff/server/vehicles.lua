-- /veh: upstream admin/level3.pwn /vehicle (get/goto/enter/owner/delete/respawn/reset/lock/unlock/removekey/destroy)
-- merged with the port's model spawn (/veh <name|model>, also in dev as /spawnveh). Level 3 like upstream; whatever
-- changes a vehicle needs duty below lead (upstream's rule; only the spawn and the read-only owner/info skip it),
-- which also keeps the caller out of anticheat's TELE/VTP checks.
-- Deviations: vehicles are picked by database id (the on-duty ESP label), the one the caller sits in or the nearest
-- within 10 m; "owner" shows the vehicle's state (the port has no vehicle owners); "reset" is "respawn" (upstream
-- recreated the SA-MP element to clear desync, which MTA has no need for); "get" leaves the caller in the driver seat.
return function(ctx)
    local db, state = ctx.db, ctx.state
    local M = {}

    local LOCK_OPEN, LOCK_EXTERNAL = 0, 1 -- vehicles/shared/logic/vehicle.lua
    local NEAREST = 10
    -- anticheat/server/vehicles.lua kicks the player standing within 10 m of an empty vehicle that jumps 15-500 m
    local VTP_RADIUS, VTP_MIN, VTP_MAX = 12, 15, 500

    local SPAWN_POINT_SQL = "SELECT s.id, s.x, s.y, s.z, s.rz FROM vehicles v"
        .. " JOIN vehicle_spawns s ON s.id = v.spawn_id WHERE v.id = ?"
    local INFO_SQL = "SELECT spawn_id, left_spawn, last_used_at, created_at FROM vehicles WHERE id = ?"

    local USAGE = "/veh <name|model> | get|goto|enter|owner|delete|respawn|reset|lock|unlock|removekey|destroy [id]"

    local function needsDuty(p, lvl)
        if state.duty[p] or lvl >= 4 then -- Lead, upstream STAFF_LEVEL_LEAD
            return false
        end
        ctx.say(p, " >  You must be on duty (/duty) to do that.")
        return true
    end

    -- By database id, else the one the caller sits in, else the nearest within 10 m (as /delveh).
    local function pick(p, idArg)
        if idArg then
            local id = tonumber(idArg)
            local v = id and exports.vehicles:getVehicleById(id)
            if not v then
                ctx.say(p, " >  No vehicle with id %s.", idArg)
            end
            return v or nil
        end
        local v = getPedOccupiedVehicle(p)
        if not v then
            local x, y, z = getElementPosition(p)
            local best = NEAREST
            for _, o in ipairs(getElementsWithinRange(x, y, z, best, "vehicle")) do
                local d = getDistanceBetweenPoints3D(x, y, z, getElementPosition(o))
                if d <= best and getElementDimension(o) == getElementDimension(p) then
                    v, best = o, d
                end
            end
        end
        if not v or not exports.vehicles:getVehicleDbId(v) then
            ctx.say(p, " >  No world vehicle here: sit in one, stand within 10 m of one, or give its id.")
            return nil
        end
        return v
    end

    local function label(v)
        local uname = getElementData(v, "vehicles.type")
        local t = uname and exports.data:vehicleType(uname)
        return string.format(
            "%s #%d",
            t and t.name or uname or tostring(getElementModel(v)),
            exports.vehicles:getVehicleDbId(v)
        )
    end

    -- Someone other than p in the vehicle (moving it would carry them along).
    local function otherOccupant(v, p)
        for seat = 0, getVehicleMaxPassengers(v) or 0 do
            local o = getVehicleOccupant(v, seat)
            if o and o ~= p then
                return o
            end
        end
        return nil
    end

    -- An off-duty player anticheat would blame for an empty vehicle jumping from (ax, ay, az) to (bx, by, bz).
    local function vtpBystander(ax, ay, az, bx, by, bz)
        local jump = getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
        if jump < VTP_MIN or jump >= VTP_MAX then
            return nil
        end
        for _, o in ipairs(getElementsByType("player")) do
            if not state.duty[o] then
                local x, y, z = getElementPosition(o)
                if
                    getDistanceBetweenPoints3D(x, y, z, ax, ay, az) <= VTP_RADIUS
                    or getDistanceBetweenPoints3D(x, y, z, bx, by, bz) <= VTP_RADIUS
                then
                    return o
                end
            end
        end
        return nil
    end

    local function freeSeat(v)
        for seat = 0, getVehicleMaxPassengers(v) or 0 do
            if not getVehicleOccupant(v, seat) then
                return seat
            end
        end
        return nil
    end

    local function respawn(p, v)
        local id = exports.vehicles:getVehicleDbId(v)
        db.query(SPAWN_POINT_SQL, { id }, function(rows)
            if not isElement(v) then
                return
            end
            local s = rows and rows[1]
            if not s then
                return ctx.say(p, " >  %s has no spawn point (spawned with /veh).", label(v))
            end
            local who = otherOccupant(v, nil)
            if who then
                return ctx.say(p, " >  %s is in it.", getPlayerName(who))
            end
            local x, y, z = getElementPosition(v)
            local sx, sy, sz, rz = tonumber(s.x), tonumber(s.y), tonumber(s.z), tonumber(s.rz)
            local bystander = vtpBystander(x, y, z, sx, sy, sz)
            if bystander then
                return ctx.say(
                    p,
                    " >  %s is next to it or its spawn point and off duty; move them first.",
                    getPlayerName(bystander)
                )
            end
            setElementVelocity(v, 0, 0, 0)
            setElementInterior(v, 0)
            setElementDimension(v, 0)
            setElementPosition(v, sx, sy, sz)
            setElementRotation(v, 0, 0, rz)
            ctx.say(p, " >  %s back on spawn point #%d", label(v), tonumber(s.id))
            ctx.log(p, "veh respawn", nil, nil, label(v))
        end)
    end

    local function info(p, v)
        local id = exports.vehicles:getVehicleDbId(v)
        db.query(INFO_SQL, { id }, function(rows)
            if not isElement(v) then
                return
            end
            local r = rows and rows[1] or {}
            local driver = getVehicleOccupant(v, 0)
            local locked = exports.vehicles:getVehicleLockState(v)
            ctx.say(
                p,
                " >  %s: health %.0f, fuel %.1f, %s, %s, driver %s",
                label(v),
                getElementHealth(v),
                tonumber(exports.vehicles:getVehicleFuel(v)) or 0,
                locked == LOCK_OPEN and "unlocked" or "locked",
                exports.vehicles:getVehicleKeyCode(v) and "has a key" or "no key",
                driver and getPlayerName(driver) or "none"
            )
            ctx.say(
                p,
                " >  spawn point %s%s, created %s, last used %s",
                r.spawn_id and ("#" .. tostring(r.spawn_id)) or "none",
                tonumber(r.left_spawn) == 1 and " (left it)" or "",
                tostring(r.created_at or "?"),
                tostring(r.last_used_at or "never")
            )
        end)
    end

    local actions = {}

    actions.get = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        local who = otherOccupant(v, p)
        if who then
            return ctx.say(p, " >  %s is in it.", getPlayerName(who))
        end
        local x, y, z = getElementPosition(p)
        local _, _, rz = getElementRotation(p)
        local interior, dimension = getElementInterior(p), getElementDimension(p)
        if getPedOccupiedVehicle(p) ~= v then
            removePedFromVehicle(p)
        end
        -- seated first, so the jump is an occupied vehicle's (anticheat only checks empty ones)
        warpPedIntoVehicle(p, v, 0)
        setElementVelocity(v, 0, 0, 0)
        setElementInterior(v, interior)
        setElementDimension(v, dimension)
        setElementPosition(v, x, y, z + 0.5)
        setElementRotation(v, 0, 0, rz)
        ctx.say(p, " >  Brought %s to you", label(v))
        return true
    end

    actions["goto"] = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        local x, y, z = getElementPosition(v)
        ctx.teleportGrace(p)
        removePedFromVehicle(p)
        setElementInterior(p, getElementInterior(v))
        setElementDimension(p, getElementDimension(v))
        setElementPosition(p, x, y, z + 2)
        ctx.say(p, " >  Teleported to %s", label(v))
        return true
    end

    actions.enter = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        local seat = freeSeat(v)
        if not seat then
            return ctx.say(p, " >  %s is full.", label(v))
        end
        ctx.teleportGrace(p)
        removePedFromVehicle(p)
        setElementInterior(p, getElementInterior(v))
        setElementDimension(p, getElementDimension(v))
        warpPedIntoVehicle(p, v, seat)
        ctx.say(p, " >  Entered %s (seat %d)", label(v), seat)
        return true
    end

    actions.owner = function(p, v)
        info(p, v)
    end
    actions.info = actions.owner

    actions.delete = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        local id, name = exports.vehicles:deleteVehicle(v, p)
        if not id then
            return ctx.say(p, " >  That vehicle is not a world vehicle.")
        end
        ctx.say(p, " >  Deleted %s #%d", name, id)
        ctx.log(p, "veh delete", nil, nil, string.format("%s #%d", name, id))
    end

    actions.respawn = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        respawn(p, v) -- logs once the spawn point is known
    end
    actions.reset = actions.respawn

    actions.lock = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        exports.vehicles:setVehicleLockState(v, LOCK_EXTERNAL)
        ctx.say(p, " >  %s locked", label(v))
        return true
    end

    actions.unlock = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        exports.vehicles:setVehicleLockState(v, LOCK_OPEN)
        ctx.say(p, " >  %s unlocked", label(v))
        return true
    end

    -- the in-memory code goes now; the row is written here because the periodic flush does not carry key_code
    actions.removekey = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        exports.vehicles:setVehicleKeyCode(v, nil)
        db.exec("UPDATE vehicles SET key_code = NULL WHERE id = ?", { exports.vehicles:getVehicleDbId(v) })
        ctx.say(p, " >  %s key removed", label(v))
        return true
    end

    actions.destroy = function(p, v, lvl)
        if needsDuty(p, lvl) then
            return
        end
        setElementHealth(v, 0)
        ctx.say(p, " >  %s set on fire", label(v))
        return true
    end

    ctx.command({
        name = "veh",
        aliases = { "vehicle" },
        level = 3,
        playerOnly = true,
        usage = "/veh <name|model> or /veh <get|goto|enter|owner|delete|respawn|lock|unlock|removekey|destroy> [id]",
        help = "Spawn a vehicle by name or model, or control one (by id, the one you are in, or the nearest)",
        needsDb = false,
        fn = function(p, args, lvl)
            local sub = args[1] and args[1]:lower()
            if not sub then
                return ctx.say(p, " >  Usage: %s", USAGE)
            end
            local act = actions[sub]
            if not act then
                if sub == "spawn" then
                    table.remove(args, 1)
                end
                local query = table.concat(args, " ")
                if query == "" then
                    return ctx.say(p, " >  Usage: %s", USAGE)
                end
                local ok, res = exports.vehicles:spawnVehicle(p, query)
                if not ok then
                    return ctx.say(p, " >  /veh %s: %s", query, tostring(res))
                end
                ctx.log(p, "veh spawn", nil, nil, tostring(res))
                return
            end
            local v = pick(p, args[2])
            if not v then
                return
            end
            if act(p, v, lvl) then
                ctx.log(p, "veh " .. sub, nil, nil, label(v))
            end
        end,
    })

    return M
end
