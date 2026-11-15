-- Under-map rescue. A vehicle that falls through the world (spawned into a slope, or before its syncer's collision had
-- loaded) keeps that position on the server even after GTA puts the client's copy back on a road, so F on what the
-- player sees is refused (2026-11-15, Sandking #318 at z -93). The server has no collision, so every SCAN_MS it hands
-- each player the server positions of the empty vehicles near them that it has not yet seen standing on something;
-- the client (client/ground.lua) answers per vehicle "ok" (ground under it), "unknown" (cannot tell: collision not
-- loaded, water above it, mid-air) or "under" with the topmost surface over it. An "under" answer is checked against
-- what was asked and the vehicle is put back on that surface. "sunk" (fully under water) marks it sunk (ctx.setSunk):
-- it stays there for staff to delete and the fleet refill replaces it; a later "ok" or "under" clears the mark.
return function(ctx)
    local SCAN_MS = 10000
    local RADIUS = 150 -- 2D; the client's collision is loaded around it
    local MAX_PER_ASK = 40
    local ASK_TTL_MS = 15000
    local MOVED = 1.0 -- metres a vehicle may drift before its last "ok" stops counting
    local LIFT = 1.0 -- metres above the surface the vehicle is put back at
    local MAX_Z = 1500

    local verified = setmetatable({}, { __mode = "k" }) -- vehicle -> { x, y, z } of its last "ok"
    local pending = setmetatable({}, { __mode = "k" }) -- vehicle -> { player, x, y, z, at }

    local function near(a, x, y, z)
        return a and math.abs(a.x - x) <= MOVED and math.abs(a.y - y) <= MOVED and math.abs(a.z - z) <= MOVED
    end

    local function empty(v)
        return next(getVehicleOccupants(v) or {}) == nil and not getVehicleTowingVehicle(v)
    end

    local function candidate(v, now)
        if not isElement(v) or getElementInterior(v) ~= 0 or getElementDimension(v) ~= 0 then
            return nil
        end
        local p = pending[v]
        if p and now - p.at < ASK_TTL_MS then
            return nil
        end
        local x, y, z = getElementPosition(v)
        if near(verified[v], x, y, z) or not empty(v) then
            return nil
        end
        return x, y, z
    end

    local function scan()
        local now = getTickCount()
        local players = {}
        for _, p in ipairs(getElementsByType("player")) do
            if getElementInterior(p) == 0 and getElementDimension(p) == 0 then
                local px, py = getElementPosition(p)
                players[#players + 1] = { p = p, x = px, y = py, list = {} }
            end
        end
        if #players == 0 then
            return
        end
        local r2 = RADIUS * RADIUS
        for v in pairs(ctx.info) do
            local x, y, z = candidate(v, now)
            if x then
                for _, pl in ipairs(players) do
                    local dx, dy = x - pl.x, y - pl.y
                    if dx * dx + dy * dy <= r2 and #pl.list < MAX_PER_ASK then
                        pl.list[#pl.list + 1] = { v, x, y, z }
                        pending[v] = { player = pl.p, x = x, y = y, z = z, at = now }
                        break
                    end
                end
            end
        end
        for _, pl in ipairs(players) do
            if #pl.list > 0 then
                triggerClientEvent(pl.p, "vehicleGroundCheckRequested", resourceRoot, pl.list)
            end
        end
    end

    local function rescue(player, v, p, surface)
        local _, _, rz = getElementRotation(v)
        setElementVelocity(v, 0, 0, 0)
        setElementAngularVelocity(v, 0, 0, 0)
        setElementPosition(v, p.x, p.y, surface + LIFT)
        setElementRotation(v, 0, 0, rz)
        ctx.log.event(
            "vehicle.rescued",
            -- player: the client whose answer moved it
            ctx.vehicleLine(v, { from_z = p.z, to_z = surface + LIFT, player = player, reason = "under_map" }),
            "warn"
        )
    end

    ctx.net.handler("vehicleGroundChecked", function(player, results)
        if type(results) ~= "table" then
            return
        end
        for n, r in ipairs(results) do
            if n > MAX_PER_ASK then
                break
            end
            local v, verdict, surface
            if type(r) == "table" then
                v, verdict, surface = r[1], r[2], tonumber(r[3])
            end
            local p = isElement(v) and pending[v]
            if p and p.player == player then
                pending[v] = nil
                local x, y, z = getElementPosition(v)
                if near(p, x, y, z) then
                    if verdict == "sunk" then
                        verified[v] = { x = p.x, y = p.y, z = p.z }
                        ctx.setSunk(v, true, player)
                    elseif verdict == "ok" then
                        verified[v] = { x = p.x, y = p.y, z = p.z }
                        ctx.setSunk(v, false, player)
                    elseif verdict == "under" and surface and surface > p.z + 2 and surface < MAX_Z and empty(v) then
                        verified[v] = nil
                        ctx.setSunk(v, false, player)
                        rescue(player, v, p, surface)
                    end
                end
            end
        end
    end, { rate = 2 })

    addEventHandler("onPlayerQuit", root, function()
        for v, p in pairs(pending) do
            if p.player == source then
                pending[v] = nil
            end
        end
    end)

    setTimer(scan, SCAN_MS, 0)
end
