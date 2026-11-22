-- Who breathes how much of the cloud (server authoritative). Once a second, for every character in the main world
-- that the cloud is over or whose shelter still holds gas:
--   the gas outside is the cloud's strength where they stand;
--   the place's openness comes from the ray fan on the server's collision (shared/logic/enclosure.lua), or from
--     the vehicle's cabin; the gas around them follows the gas outside through the openings (enclosure.seep);
--   the worn mask keeps its share out and wears (items:maskBreathed);
--   what is left is the dose (character:addToxic, where Poison Resistance takes its share).
-- The fan is the costly part (some 70 rays): it is cast again only when the player has moved, or after FAN_KEEP_MS
-- for a door that opened meanwhile, and at most FANS_A_TICK of them a second.
-- The server's collision has the map but not what only clients build: the doors hung in the enterable houses and
-- everything players put up (walls, doors, tents, roof panels). So a house with its door shut and a sealed base
-- read as open to it. Each client in the gas therefore reports the openness it measures on its own collision, and
-- the server takes the lower of the two where that can be true: under a roof it sees itself, or on a claimed plot.
-- Anywhere else (out in the open) the report is ignored, so it cannot be used to walk through the cloud unharmed.
-- ctx = { geom, enclosure, net, concentrationAt(x, y, z), setting(key, default) } from server/main.lua.
return function(ctx)
    local geom, enclosure = ctx.geom, ctx.enclosure
    local TICK_MS = 1000
    local FAN_MOVE = 1 -- metres moved before the fan is cast again
    local FAN_KEEP_MS = 10000
    local FANS_A_TICK = 12
    local HEAD = 0.6 -- metres over the ped's position: where it breathes
    local GONE = 0.005 -- gas strength under which a place is clear
    local SEND_STEP = 0.03 -- change in the gas around a player that is worth telling their client
    local REPORT_KEEP_MS = 15000 -- how long a client's reported openness stands
    -- models with a seat in the open air: no cabin to speak of
    local ROOFLESS = {
        [424] = true, -- BF Injection
        [429] = true, -- Banshee
        [439] = true, -- Stallion
        [457] = true, -- Caddy
        [480] = true, -- Comet
        [485] = true, -- Baggage
        [486] = true, -- Dozer
        [530] = true, -- Forklift
        [531] = true, -- Tractor
        [533] = true, -- Feltzer
        [536] = true, -- Blade
        [539] = true, -- Vortex
        [555] = true, -- Windsor
        [567] = true, -- Savanna
        [568] = true, -- Bandito
        [571] = true, -- Kart
        [572] = true, -- Mower
        [575] = true, -- Broadway
        [583] = true, -- Tug
    }
    local ROOFLESS_TYPE = { Bike = true, BMX = true, Quad = true, Boat = true }
    local WINDSCREEN, PANEL_GONE = 4, 3
    local byPlayer = {} -- player -> { inside, openness, fx, fy, fz, fanTick, roofed, sentInside, sentOpenness }
    local reported = {} -- player -> { openness, tick }: what the client measured (see the header)

    local function cabinOf(vehicle)
        local c = { doors = {}, ratios = {} }
        c.roofless = ROOFLESS_TYPE[getVehicleType(vehicle)] or ROOFLESS[getElementModel(vehicle)] or false
        c.windscreen = getVehiclePanelState(vehicle, WINDSCREEN) < PANEL_GONE
        for door = 2, 5 do
            c.doors[#c.doors + 1] = getVehicleDoorState(vehicle, door)
            c.ratios[#c.ratios + 1] = getVehicleDoorOpenRatio(vehicle, door)
        end
        return enclosure.cabin(c)
    end

    -- the fan on the server's collision: the openness and whether a roof is overhead; without the collision (still
    -- loading) every place counts as the open air
    local function fanAt(x, y, z)
        if not geom.ready() then
            return 1, false
        end
        local openness, found = enclosure.measure(geom.ray, x, y, z)
        return openness, found.roof
    end

    local function onPlot(x, y)
        local building = getResourceFromName("building")
        return building and getResourceState(building) == "running" and exports.building:isInsideAnyPlotPole(x, y)
    end

    -- the lower of the server's reading and the client's, where the client's may be believed
    local function withReport(player, st, x, y, now)
        local r = reported[player]
        if not r or now - r.tick > REPORT_KEEP_MS or r.openness >= st.measured then
            return st.measured
        end
        if st.roofed or onPlot(x, y) then
            return r.openness
        end
        return st.measured
    end

    local function tell(player, st)
        local changed = math.abs(st.inside - (st.sentInside or 0)) >= SEND_STEP
            or math.abs(st.openness - (st.sentOpenness or -1)) >= SEND_STEP
            or (st.inside == 0 and (st.sentInside or 0) ~= 0)
        if changed then
            st.sentInside, st.sentOpenness = st.inside, st.openness
            triggerClientEvent(player, "toxicExposureSynced", player, st.inside, st.openness)
        end
    end

    local function tick()
        local now, fans, dt = getTickCount(), 0, TICK_MS / 1000
        local rate = ctx.setting("toxic.intake_rate", 1)
        for _, player in ipairs(getElementsByType("player")) do
            local st = byPlayer[player]
            local inWorld = getElementInterior(player) == 0 and getElementDimension(player) == 0
            -- a staff member on duty is out of the game: no poison, and their mask does not wear
            local alive = not isPedDead(player)
                and getElementData(player, "staff.duty") ~= true
                and exports.character:getCharacterId(player)
            local x, y, z = getElementPosition(player)
            -- the game's own interiors are sealed rooms somewhere else: no gas gets in
            local outside = inWorld and alive and ctx.concentrationAt(x, y, z + HEAD) or 0
            if alive and (outside > 0 or (st and st.inside > GONE)) then
                if not st then
                    st = { inside = 0, openness = 1 }
                    byPlayer[player] = st
                end
                local vehicle = getPedOccupiedVehicle(player)
                if vehicle then
                    st.openness, st.fanTick = cabinOf(vehicle), nil
                elseif not inWorld then
                    st.openness, st.fanTick = 0, nil
                else
                    local moved = not st.fanTick
                        or (x - st.fx) ^ 2 + (y - st.fy) ^ 2 + (z - st.fz) ^ 2 >= FAN_MOVE * FAN_MOVE
                    if (moved or now - st.fanTick >= FAN_KEEP_MS) and fans < FANS_A_TICK then
                        fans = fans + 1
                        st.measured, st.roofed = fanAt(x, y, z + HEAD)
                        st.fx, st.fy, st.fz, st.fanTick = x, y, z, now
                    end
                    if st.measured then
                        st.openness = withReport(player, st, x, y, now)
                    end
                end
                st.inside = enclosure.seep(st.inside, outside, st.openness, dt)
                if st.inside > GONE then
                    local kept = exports.items:maskBreathed(player, st.inside, dt) or 0
                    exports.character:addToxic(player, rate * st.inside * (1 - kept) * dt)
                elseif outside <= 0 then
                    st.inside = 0 -- the last trace airs out; while gas is outside a slow leak keeps adding up
                end
                tell(player, st)
            elseif st then
                st.inside = 0
                tell(player, st)
                byPlayer[player] = nil
            end
        end
    end

    ctx.net.handler("toxicShelterReported", function(player, openness)
        openness = tonumber(openness)
        if openness and openness == openness then
            reported[player] = { openness = math.max(0, math.min(1, openness)), tick = getTickCount() }
        end
    end, { rate = 2 })

    addEventHandler("onPlayerQuit", root, function()
        byPlayer[source] = nil
        reported[source] = nil
    end)
    setTimer(tick, TICK_MS, 0)

    -- for staff and tests: the gas around a player and the openness of where they are, or nil when clear
    local function of(player)
        local st = byPlayer[player]
        if not st then
            return nil
        end
        return st.inside, st.openness
    end

    return { of = of }
end
