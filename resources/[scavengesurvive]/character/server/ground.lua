-- Under-map rescue for players on foot (vehicles/server/ground.lua does the vehicles). A player pushed through the
-- ground (2026-11-22: a panel raised next to its builder) falls until GTA itself puts them back on some surface
-- hundreds of metres away, which the anticheat then reports as a teleport. Every SCAN_MS the server tests each living
-- character on foot against its own copy of the world (lib geom.lua, ml_sageom):
--   ok      a surface within STAND metres under them: the place is remembered
--   under   falling (DROP metres lower than the scan before), nothing within BELOW metres under them, a surface more
--           than DEPTH metres over them and no water surface near or under them (a diver, or a fall under a bridge
--           over the sea, is left alone): they are put back where they last stood when that is within BACK metres,
--           else on the topmost surface over them
--   wedged  standing (not crouched) with a surface less than ROOM metres over what they stand on, so GTA cannot move
--           the ped at all (2026-11-23: off a bike under a quay overhang with 1.8 m of room; a reconnect spawned them
--           back in it), and still for WEDGE_MS: they are put on the nearest spot within FREE metres that has standing
--           room, a walkable surface and no water over it, one they could walk to in a straight line when there is
--           such a spot. The vehicle they last got out of comes along when it is still within CARRY metres of them,
--           empty and under the same low cover (GTA would wedge them again the next time they got off it there): it is
--           put on the nearest flat, open spot with room for its size (CAR_FOOTPRINT), away from where they were put.
--   anything else (a jump, a fall through open air, a place the server's world does not know) is left alone.
-- Main world only, never staff on duty. While the server's world is not ready (lib geom.lua) nothing is tested.
-- ctx = { log, state, onDuty }
return function(ctx)
    local geom = assert(loadstring(exports.lib:getModule("geom"), "=lib/geom.lua"))()
    local lang = assert(loadstring(exports.lib:getModule("lang"), "=lib/lang.lua"))()
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

    local ROOM = 1.9 -- floor to ceiling a standing ped needs
    local WEDGE_MS = 5000
    local STILL = 0.75 -- metres a wedged ped may jitter and still count as stuck
    local FREE = 25
    local FREE_STEP = 1.5
    local FREE_ANGLES = 16
    local FREE_UP = 6 -- a free spot's surface may be this much over the floor they are wedged on...
    local FREE_DOWN = 4 -- ...or this much under it
    local FLAT = 0.7 -- normal z of a surface a ped can stand on
    local HEADROOM = 2.2
    local LIFT_FREE = 1.1

    local CARRY = 10
    local CAR_ROOM = 2.6 -- floor to ceiling under which a vehicle counts as under the same low cover
    local CAR_HEADROOM = 3.0
    local CAR_LEVEL = 0.8 -- how much the ground under the footprint's edges may differ from its centre
    local CAR_LIFT = 1.0
    local CAR_FOOTPRINT = { BMX = 1.2, Bike = 1.4, Quad = 1.8, Automobile = 3.0, ["Monster Truck"] = 3.5 } -- radius, m

    local stood = setmetatable({}, { __mode = "k" }) -- player -> { x, y, z } where they last stood on something
    local lastZ = setmetatable({}, { __mode = "k" }) -- player -> z at the scan before
    local wedged = setmetatable({}, { __mode = "k" }) -- player -> { x, y, z, since } where they first stood wedged
    local lastVehicle = {} -- account id -> the vehicle they last got out of (kept across a reconnect)

    local function forget(player)
        stood[player], lastZ[player], wedged[player] = nil, nil, nil
    end

    -- the nearest spot around (x, y) for something wedged on `floor` that `fits` (tx, ty, surface): tx, ty, surface or
    -- nil. The first pass only takes spots in a straight, unblocked line from it (nothing is put through a wall), the
    -- second any.
    local function freeSpot(x, y, floor, fits)
        for pass = 1, 2 do
            for r = FREE_STEP, FREE, FREE_STEP do
                for i = 0, FREE_ANGLES - 1 do
                    local a = (i / FREE_ANGLES) * 2 * math.pi
                    local tx, ty = x + math.cos(a) * r, y + math.sin(a) * r
                    local hz, _, _, nz = geom.below(tx, ty, floor + FREE_UP, 0, FREE_UP + FREE_DOWN)
                    local wz = hz and geom.water(tx, ty)
                    if
                        hz
                        and nz >= FLAT
                        and not (wz and wz > hz)
                        and fits(tx, ty, hz)
                        and (pass == 2 or geom.clear(x, y, floor + 0.5, tx, ty, hz + 0.5))
                    then
                        return tx, ty, hz
                    end
                end
            end
        end
        return nil
    end

    local function pedFits(tx, ty, hz)
        return geom.clear(tx, ty, hz + 0.1, tx, ty, hz + HEADROOM)
    end

    -- a fits() for a vehicle of footprint radius r kept clear of (px, py): open over its centre and its four edges, and
    -- level ground under them
    local function vehicleFits(r, px, py)
        return function(tx, ty, hz)
            if getDistanceBetweenPoints2D(tx, ty, px, py) < r + 1.5 then
                return false
            end
            for _, d in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
                local ex, ey = tx + d[1], ty + d[2]
                local ez = geom.below(ex, ey, hz + CAR_LEVEL, 0, 2 * CAR_LEVEL)
                if
                    not ez
                    or math.abs(ez - hz) > CAR_LEVEL
                    or not geom.clear(ex, ey, ez + 0.1, ex, ey, ez + CAR_HEADROOM)
                then
                    return false
                end
            end
            return true
        end
    end

    -- the vehicle `player` last got out of, when it should come along with them out of the low cover at (x, y, z)
    local function carriedVehicle(player, x, y, z)
        local accountId = exports.auth:getAccountId(player)
        local v = accountId and lastVehicle[accountId]
        if not (v and isElement(v)) or getElementInterior(v) ~= 0 or getElementDimension(v) ~= 0 then
            return nil
        end
        local r = CAR_FOOTPRINT[getVehicleType(v)]
        local vx, vy, vz = getElementPosition(v)
        if
            not r
            or next(getVehicleOccupants(v) or {}) ~= nil
            or getVehicleTowingVehicle(v)
            or getVehicleTowedByVehicle(v)
            or isElementAttached(v)
            or getDistanceBetweenPoints3D(x, y, z, vx, vy, vz) > CARRY
        then
            return nil
        end
        local floor = geom.below(vx, vy, vz, 0.5, 3)
        if not floor or not geom.ray(vx, vy, floor + 0.1, vx, vy, floor + CAR_ROOM) then
            return nil
        end
        return v, r, vx, vy, vz, floor
    end

    -- every wedge rescue is also a staff record: a staff_actions row by "Server" and a line to staff online (level 1+),
    -- like the anticheat's own reports; nothing when the staff resource is not running
    local function tellStaff(player, text)
        local staff = getResourceFromName("staff")
        if not staff or getResourceState(staff) ~= "running" then
            return
        end
        local name = getPlayerName(player)
        exports.staff:logAction("Server", "unwedge", name, text)
        exports.staff:notifyStaff(1, string.format(" >  Server unwedged %s: %s", name, text))
    end

    -- moves the vehicle carried out with a freed player; true when it was moved
    local function carryVehicle(player, v, r, vx, vy, vz, floor, px, py)
        local tx, ty, hz = freeSpot(vx, vy, floor, vehicleFits(r, px, py))
        if not tx then
            ctx.log.event("character.vehicleNotCarried", {
                player = player,
                vehicle_id = getElementData(v, "vehicles.id"),
                x = vx,
                y = vy,
                z = vz,
            }, "warn")
            return false
        end
        local _, _, rz = getElementRotation(v)
        setElementVelocity(v, 0, 0, 0)
        setElementAngularVelocity(v, 0, 0, 0)
        setElementPosition(v, tx, ty, hz + CAR_LIFT)
        setElementRotation(v, 0, 0, rz)
        triggerEvent("vehicleRescued", v) -- the anticheat must not read the move as a teleport by whoever stands near
        ctx.log.event("character.vehicleCarried", {
            player = player,
            vehicle_id = getElementData(v, "vehicles.id"),
            model = getElementModel(v),
            from_x = vx,
            from_y = vy,
            from_z = vz,
            x = tx,
            y = ty,
            z = hz + CAR_LIFT,
        }, "warn")
        return true
    end

    -- true while the player stands on `floor` with too little room over it; frees them once they have been for WEDGE_MS
    local function checkWedged(player, x, y, z, floor)
        local cx, _, cz = geom.ray(x, y, z, x, y, floor + ROOM)
        if not cx or isPedDucked(player) then
            wedged[player] = nil
            return
        end
        local w = wedged[player]
        local now = getTickCount()
        if not w or getDistanceBetweenPoints3D(x, y, z, w.x, w.y, w.z) > STILL then
            wedged[player] = { x = x, y = y, z = z, since = now }
            return
        end
        if now - w.since < WEDGE_MS then
            return
        end
        local tx, ty, hz = freeSpot(x, y, floor, pedFits)
        if not tx then
            w.since = now -- nowhere to put them: try again later; the log and the staff hear it once per wedge
            if not w.reported then
                w.reported = true
                ctx.log.event("character.wedgedNoSpot", { player = player, x = x, y = y, z = z, ceiling = cz }, "warn")
                tellStaff(
                    player,
                    string.format("stuck at %.1f, %.1f, %.1f with no open ground near, help them", x, y, z)
                )
            end
            return
        end
        setElementVelocity(player, 0, 0, 0)
        setElementPosition(player, tx, ty, hz + LIFT_FREE) -- server-side: the anticheat's onPlayerTeleport skips it
        forget(player)
        local v, r, vx, vy, vz, vfloor = carriedVehicle(player, x, y, z)
        local text = v
                and carryVehicle(player, v, r, vx, vy, vz, vfloor, tx, ty)
                and lang.textFor(player, "You were stuck, so you and your vehicle were moved to open ground nearby.")
            or lang.textFor(player, "You were stuck, so you were moved to open ground nearby.")
        outputChatBox(text, player, 255, 220, 0)
        local vehicleNote = ""
        if v then
            local nx, ny, nz = getElementPosition(v)
            local moved = getDistanceBetweenPoints3D(vx, vy, vz, nx, ny, nz) > 0.5
            vehicleNote = string.format(
                moved and "; vehicle #%s carried to %.1f, %.1f, %.1f" or "; vehicle #%s left at %.1f, %.1f, %.1f",
                tostring(getElementData(v, "vehicles.id")),
                nx,
                ny,
                nz
            )
        end
        tellStaff(
            player,
            string.format("%.1f, %.1f, %.1f -> %.1f, %.1f, %.1f%s", x, y, z, tx, ty, hz + LIFT_FREE, vehicleNote)
        )
        ctx.log.event("character.rescued", {
            player = player,
            reason = "wedged",
            vehicle_id = v and getElementData(v, "vehicles.id") or nil,
            from_x = x,
            from_y = y,
            from_z = z,
            ceiling = cz,
            x = tx,
            y = ty,
            z = hz + LIFT_FREE,
        }, "warn")
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
                local floor = geom.below(x, y, z, 0, STAND)
                if floor then
                    stood[player] = { x = x, y = y, z = z }
                    checkWedged(player, x, y, z, floor)
                elseif before and before - z >= DROP then
                    local surface = surfaceOver(x, y, z)
                    if surface then
                        rescue(player, x, y, z, surface)
                    end
                end
            end
        end
    end

    addEventHandler("onPlayerVehicleExit", root, function(vehicle)
        local accountId = exports.auth:getAccountId(source)
        if accountId then
            lastVehicle[accountId] = vehicle
        end
    end)

    addEventHandler("onElementDestroy", root, function()
        if getElementType(source) == "vehicle" then
            for accountId, v in pairs(lastVehicle) do
                if v == source then
                    lastVehicle[accountId] = nil
                end
            end
        end
    end)

    setTimer(scan, SCAN_MS, 0)
end
