-- The Generator's engine and what it powers (shared/logic/machines.lua has the tank and the burn):
--   a tap on one lying there starts or stops it (machines.lua M.interact hands the tap here); it starts only with
--     fuel in the tank, and stops when it is picked up or the tank runs dry;
--   an Extension Cord in hand at a building's mains inlet (the power resource) is plugged in: the cord is laid on the
--     floor under the inlet ({ site, gen } in its data) to the nearest Generator within the cord's reach; it comes
--     out only at one of its ends (cordUnplugRequested: at the mains box, where it lies, or at its Generator) and
--     back into the hands unplugged, and a Generator picked up unplugs every cord on it;
--   every TICK_MS each running Generator burns fuel for its load (idle, plus a lit mains site's lights and the
--     Flood Lights running off it) in one generator_burn call;
--   a site's feed (power:setFeed) is the running Generator its cord reaches, worked out again on every change.
-- ctx = { db, net, state, toast, world, hands, charId, decodeData, updateHeldData, machines } built by
-- server/main.lua.
return function(ctx)
    local db, net, state, world, hands, machines = ctx.db, ctx.net, ctx.state, ctx.world, ctx.hands, ctx.machines
    local decodeData, toast = ctx.decodeData, ctx.toast
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

    local CORD_UNAME = "ExtensionCord"
    local CORD_LENGTH = 15.0 -- metres from the inlet to the Generator (power shared/logic/mains.lua)
    local PLUG_REACH = 3.5 -- metres from the inlet a plug is taken from (the client's 2.5, and a step of slack)
    local FLOOD_WATTS = 500 -- a halogen work light
    local FLOOD_REACH = 8.0 -- the Flood Light's cable (floodlight.lua GENERATOR_REACH)
    local TICK_MS = 30000

    local WORLD = "x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"
    local GENS = "SELECT id, data, x, y, z, interior, dimension FROM items WHERE type_uname = 'Generator' AND " .. WORLD
    local CORDS = "SELECT id, data, x, y, z, interior, dimension FROM items WHERE type_uname = 'ExtensionCord' AND "
        .. WORLD
        .. " AND (JSON_VALUE(data, '$.site') IS NOT NULL OR JSON_VALUE(data, '$[0].site') IS NOT NULL)"
    local LIT_FLOODS = "SELECT id, x, y, z, interior, dimension FROM items WHERE type_uname = 'FloodLight' AND "
        .. WORLD
        .. " AND (JSON_VALUE(data, '$.lit') = 1 OR JSON_VALUE(data, '$[0].lit') = 1)"
    local TEXT = machines.TEXT
    -- lang:begin
    local CORD_TEXT = {
        PLUGGED = "Cord plugged into the mains: Generator %d metres away",
        NOGEN = "No Generator within 15 metres of the inlet",
        UNPLUGGED = "Cord unplugged",
    }
    -- lang:end

    local function say(player, fmt, ...)
        toast(player, lang.formatFor(player, fmt, ...))
    end

    local function raw(row)
        return (row.data and row.data ~= false) and row.data or ""
    end

    local function encode(t)
        return toJSON(t, true):sub(2, -2)
    end

    local function first(data)
        local d = type(data) == "table" and data or {}
        return type(d[1]) == "table" and d[1] or d
    end

    local function power()
        local res = getResourceFromName("power")
        return res and getResourceState(res) == "running" and exports.power or nil
    end

    local function sameWorld(a, int, dim)
        return (a.interior or 0) == (int or 0) and (a.dimension or 0) == (dim or 0)
    end

    -- the site's inlet: x, y, z, interior, dimension (power), or nil
    local function inletOf(p, siteId)
        local ok, x, y, z, int, dim = pcall(function()
            return p:inletOf(siteId)
        end)
        if ok and x then
            return x, y, z, int, dim
        end
        return nil
    end

    -- Feeds ----------------------------------------------------------------------------------------------------

    -- every site's feed worked out from the cords lying plugged in and the Generators running; cb(gens, feeds) with
    -- gens' rows carrying .st (machines.state) and feeds site id -> generator row
    local function evaluate(cb)
        db.query(GENS, {}, function(gens)
            gens = gens or {}
            local byId = {}
            for _, g in ipairs(gens) do
                g.st = machines.state(decodeData(g.data))
                byId[g.id] = g
            end
            db.query(CORDS, {}, function(cords)
                local p, feeds = power(), {}
                if p then
                    for _, c in ipairs(cords or {}) do
                        local d = first(decodeData(c.data))
                        local site, g = d.site, byId[tonumber(d.gen) or -1]
                        if type(site) == "string" and g and g.st.running then
                            local x, y, z, int, dim = inletOf(p, site)
                            local reach = x and getDistanceBetweenPoints3D(x, y, z, g.x, g.y, g.z) or math.huge
                            if sameWorld(g, int, dim) and reach <= CORD_LENGTH + 1.0 then
                                feeds[site] = g
                            end
                        end
                    end
                    local ok, sites = pcall(function()
                        return p:getSites()
                    end)
                    for _, s in ipairs(ok and sites or {}) do
                        local g = feeds[s.id]
                        pcall(function()
                            p:setFeed(s.id, g and g.id or false)
                        end)
                    end
                end
                if cb then
                    cb(gens, feeds)
                end
            end)
        end)
    end

    -- Starting and stopping ----------------------------------------------------------------------------------------

    -- the Generator's next data, written only if nobody changed the row since it was read; cb(done)
    local function write(row, st, cb)
        local text = encode(machines.encode(decodeData(row.data), st))
        local sql = "UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL AND IFNULL(data, '') = ?"
        db.exec(sql, { text, row.id, raw(row) }, function(ok, _, affected)
            local done = ok and tonumber(affected) == 1
            if done then
                row.data = text
                world.resendEverywhere(row.id)
            end
            if cb then
                cb(done)
            end
        end)
    end

    local function fields(player, row, extra)
        extra.player, extra.item_id = player, row.id
        extra.x, extra.y, extra.z = math.floor(row.x), math.floor(row.y), math.floor(row.z)
        return extra
    end

    -- machines.lua M.interact: a tap on a Generator lying there
    local function toggle(player, row)
        local st = machines.state(decodeData(row.data))
        if st.running then
            st.running = nil
            return write(row, st, function(done)
                if not done then
                    return toast(player, "BUSY")
                end
                log.event("generator.stopped", fields(player, row, { fuel = st.fuel, why = "player", ok = true }))
                say(player, TEXT.GENSTOPPED)
                evaluate()
            end)
        end
        if st.fuel <= 0 then
            log.event("generator.started", fields(player, row, { fuel = 0, ok = false, code = "NO_FUEL" }))
            return say(player, TEXT.GENEMPTY)
        end
        st.running = true
        write(row, st, function(done)
            if not done then
                return toast(player, "BUSY")
            end
            log.event("generator.started", fields(player, row, { fuel = st.fuel, ok = true }))
            say(player, TEXT.GENSTARTED, st.fuel)
            evaluate()
        end)
    end

    -- Cords ------------------------------------------------------------------------------------------------------

    net.handler("cordPlugRequested", function(player, siteId)
        local held, p = state.held[player], power()
        if not p or type(siteId) ~= "string" or not held or held.uname ~= CORD_UNAME or not ctx.charId(player) then
            return
        end
        local ix, iy, iz, int, dim = inletOf(p, siteId)
        local px, py, pz = getElementPosition(player)
        if
            not ix
            or getElementInterior(player) ~= (int or 0)
            or getElementDimension(player) ~= (dim or 0)
            or getDistanceBetweenPoints3D(px, py, pz, ix, iy, iz) > PLUG_REACH
        then
            return
        end
        db.query(GENS, {}, function(gens)
            if not isElement(player) then
                return
            end
            local best, bestD = nil, CORD_LENGTH
            for _, g in ipairs(gens or {}) do
                local d = getDistanceBetweenPoints3D(ix, iy, iz, g.x, g.y, g.z)
                if sameWorld(g, int, dim) and d <= bestD then
                    best, bestD = g, d
                end
            end
            local cur = state.held[player]
            if not cur or cur.id ~= held.id then
                return
            end
            if not best then
                log.event(
                    "cord.plugged",
                    { player = player, item_id = held.id, site_id = siteId, ok = false, code = "NO_GENERATOR" }
                )
                return say(player, CORD_TEXT.NOGEN)
            end
            local ok, rx, ry, rz, rrz = pcall(function()
                return p:cordRestOf(siteId)
            end)
            if not ok or not rx then
                return
            end
            local done, err = hands.dropHeld(player, {
                at = { x = rx, y = ry, z = rz, rz = rrz },
                data = { site = siteId, gen = best.id },
            })
            if not done then
                return toast(player, err or "BUSY")
            end
            log.event("cord.plugged", {
                player = player,
                item_id = held.id,
                site_id = siteId,
                generator_id = best.id,
                metres = math.floor(bestD + 0.5),
                ok = true,
            })
            setPedAnimation(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
            say(player, CORD_TEXT.PLUGGED, math.floor(bestD + 0.5))
            -- the drop lands once item_drop is done
            setTimer(evaluate, 1000, 1)
        end)
    end, { rate = 3 })

    -- the interaction chooser's "Unplug the cord" at either end: at the box (where the cord lies) or at its Generator
    local CORD_ROW = "SELECT id, type_uname AS uname, hitpoints AS hp, data, x, y, z, rz, interior, dimension "
        .. "FROM items WHERE id = ? AND type_uname = 'ExtensionCord' AND "
        .. WORLD
    local GEN_AT = "SELECT id, x, y, z, interior, dimension FROM items WHERE id = ? AND type_uname = 'Generator' AND "
        .. WORLD
    local UNPLUG_REACH = 3.0 -- metres from the cord's end (the chooser's 2, and a step of slack)

    local function near(player, row)
        if not row or not isElement(player) then
            return false
        end
        local px, py, pz = getElementPosition(player)
        return getElementInterior(player) == (row.interior or 0)
            and getElementDimension(player) == (row.dimension or 0)
            and getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) <= UNPLUG_REACH
    end

    net.handler("cordUnplugRequested", function(player, cordId)
        local cid = ctx.charId(player)
        cordId = tonumber(cordId)
        if not cid or not cordId or state.held[player] then
            return
        end
        db.one(CORD_ROW, { cordId }, function(row)
            local gen = row and tonumber(first(decodeData(row.data)).gen)
            if not gen then
                return
            end
            db.one(GEN_AT, { gen }, function(g)
                if not isElement(player) or state.held[player] or not (near(player, row) or near(player, g)) then
                    return
                end
                hands.pickup(player, cid, row)
            end)
        end)
    end, { rate = 3 })

    -- picked up: a cord comes unplugged, a Generator stops and every cord on it comes unplugged
    addEventHandler("itemMoved", root, function(itemId, from, to)
        local held = state.held[source]
        if from ~= "world" or to ~= "held" or not held or held.id ~= itemId then
            return
        end
        if held.uname == CORD_UNAME then
            local d = first(held.data)
            if d.site or d.gen then
                ctx.updateHeldData(source, {})
                log.event(
                    "cord.unplugged",
                    { player = source, item_id = itemId, site_id = d.site, generator_id = tonumber(d.gen) }
                )
                say(source, CORD_TEXT.UNPLUGGED)
                evaluate()
            end
        elseif held.uname == machines.GENERATOR_UNAME then
            local st = machines.state(held.data)
            if st.running then
                st.running = nil
                ctx.updateHeldData(source, machines.encode(held.data, st))
                log.event("generator.stopped", { player = source, item_id = itemId, fuel = st.fuel, why = "lifted" })
            end
            db.query(CORDS, {}, function(cords)
                for _, c in ipairs(cords or {}) do
                    if tonumber(first(decodeData(c.data)).gen) == itemId then
                        db.exec("UPDATE items SET data = NULL WHERE id = ? AND x IS NOT NULL", { c.id }, function()
                            world.resendEverywhere(c.id)
                        end)
                        log.event("cord.unplugged", { item_id = c.id, generator_id = itemId, why = "generator_lifted" })
                    end
                end
                evaluate()
            end)
        end
    end)

    -- a pulled lever changes the load; a restart of power wants the feeds again
    addEventHandler("mainsLeverChanged", root, function()
        evaluate()
    end)

    -- The burn ---------------------------------------------------------------------------------------------------

    local function tick()
        evaluate(function(gens, feeds)
            local running = {}
            for _, g in ipairs(gens) do
                if g.st.running then
                    running[#running + 1] = g
                    g.watts = 0
                end
            end
            if #running == 0 then
                return
            end
            local p = power()
            for site, g in pairs(feeds) do
                local ok, on = pcall(function()
                    return p:isLeverOn(site)
                end)
                if ok and on then
                    local okS, sites = pcall(function()
                        return p:getSites()
                    end)
                    for _, s in ipairs(okS and sites or {}) do
                        if s.id == site then
                            g.watts = g.watts + (tonumber(s.watts) or 0)
                        end
                    end
                end
            end
            db.query(LIT_FLOODS, {}, function(floods)
                for _, f in ipairs(floods or {}) do
                    local best, bestD = nil, FLOOD_REACH
                    for _, g in ipairs(running) do
                        local d = getDistanceBetweenPoints3D(f.x, f.y, f.z, g.x, g.y, g.z)
                        if sameWorld(g, f.interior, f.dimension) and d <= bestD then
                            best, bestD = g, d
                        end
                    end
                    if best then
                        best.watts = best.watts + FLOOD_WATTS
                    end
                end
                local rows, emptied = {}, {}
                for _, g in ipairs(running) do
                    local burn = machines.genBurn(g.watts, TICK_MS / 1000)
                    rows[#rows + 1] = { g = g.id, f = burn }
                    if g.st.fuel - burn <= 0 then
                        emptied[#emptied + 1] = g
                    end
                end
                db.call("generator_burn", { encode(rows) }, function(res)
                    if not res or not res.ok then
                        log.event("generator.burned", { ok = false, code = res and res.code or "DB_ERROR" }, "warn")
                        return
                    end
                    log.event("generator.burned", { count = #rows, ok = true }, "debug")
                    for _, g in ipairs(running) do
                        world.resendEverywhere(g.id)
                    end
                    for _, g in ipairs(emptied) do
                        log.event("generator.stopped", {
                            item_id = g.id,
                            why = "empty",
                            x = math.floor(g.x),
                            y = math.floor(g.y),
                            z = math.floor(g.z),
                        })
                    end
                    if #emptied > 0 then
                        evaluate()
                    end
                end)
            end)
        end)
    end

    local function start()
        setTimer(tick, TICK_MS, 0)
        evaluate()
    end

    return { toggle = toggle, evaluate = evaluate, start = start, CORD_UNAME = CORD_UNAME }
end
