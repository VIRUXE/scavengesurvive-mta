-- Server side of the Flood Light (shared/logic/floodlight.lua has the rules):
--   a Tool Battery in hand used on one lying there goes into it (the battery item is used up, its charge kept);
--   the interaction chooser at one (client/floodlight.lua) switches it on or off (floodLightActionRequested "toggle")
--     and takes its battery out into the empty hands ("battery");
--   every TICK_MS the lit ones draw their power in one floodlight_drain call: a running Generator within its cable
--     powers it (the Generator's burn, server/generators.lua, counts the light's load), else the battery does; one
--     with neither goes dark and every client is sent it again;
--   picked up, it switches off.
-- ctx = { db, net, state, toast, world, hands, destroy, charId, decodeData, updateHeldData, flood, machines } built by
-- server/main.lua.
return function(ctx)
    local db, net, state, world, hands = ctx.db, ctx.net, ctx.state, ctx.world, ctx.hands
    local flood, machines, decodeData, toast = ctx.flood, ctx.machines, ctx.decodeData, ctx.toast
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
    local ROW = "SELECT id, type_uname AS uname, data, x, y, z, interior, dimension FROM items "
        .. "WHERE id = ? AND type_uname = 'FloodLight' AND x IS NOT NULL AND container_id IS NULL "
        .. "AND holder_char_id IS NULL"
    -- the lit ones lying in the world (either JSON shape of the data)
    local LIT = "SELECT id, data, x, y, z, interior, dimension FROM items WHERE type_uname = 'FloodLight' "
        .. "AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL "
        .. "AND (JSON_VALUE(data, '$.lit') = 1 OR JSON_VALUE(data, '$[0].lit') = 1)"
    -- Generators lying in the world: all of them for the tick, or those within a box round one light
    local GENERATORS = "SELECT id, data, x, y, z, interior, dimension FROM items WHERE type_uname = 'Generator' "
        .. "AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"
    local GENERATORS_NEAR = GENERATORS
        .. " AND IFNULL(interior, 0) = ? AND IFNULL(dimension, 0) = ? AND ABS(x - ?) <= ? AND ABS(y - ?) <= ?"

    local function raw(row)
        return (row.data and row.data ~= false) and row.data or ""
    end

    local function encode(t)
        return toJSON(t, true):sub(2, -2)
    end

    local function say(player, key, ...)
        toast(player, lang.formatFor(player, flood.TEXT[key] or key, ...))
    end

    local function fields(player, row, extra)
        extra.player, extra.item_id = player, row.id
        extra.x, extra.y, extra.z = math.floor(row.x), math.floor(row.y), math.floor(row.z)
        return extra
    end

    -- the light's next data, written only if nobody changed the row since it was read; cb(done)
    local function write(row, nextData, cb)
        local sql = "UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL AND IFNULL(data, '') = ?"
        local text = encode(nextData)
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

    local function sameWorld(a, b)
        return (a.interior or 0) == (b.interior or 0) and (a.dimension or 0) == (b.dimension or 0)
    end

    local function dist(a, b)
        return getDistanceBetweenPoints3D(a.x, a.y, a.z, b.x, b.y, b.z)
    end

    local function running(gen)
        return machines.state(decodeData(gen.data)).running == true
    end

    -- the nearest running Generator in `gens` within the cable of `light`, or nil
    local function nearestGenerator(gens, light)
        local best, bestDist = nil, flood.GENERATOR_REACH
        for _, g in ipairs(gens) do
            local d = sameWorld(g, light) and dist(g, light)
            if d and d <= bestDist and running(g) then
                best, bestDist = g, d
            end
        end
        return best
    end

    local function generatorNear(row, cb)
        local r = flood.GENERATOR_REACH
        local params = { row.interior or 0, row.dimension or 0, row.x, r, row.y, r }
        db.query(GENERATORS_NEAR, params, function(gens)
            cb(nearestGenerator(gens or {}, row))
        end)
    end

    local function inReach(player, row)
        if not isElement(player) or not row then
            return false
        end
        local px, py, pz = getElementPosition(player)
        return getElementInterior(player) == (row.interior or 0)
            and getElementDimension(player) == (row.dimension or 0)
            and getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) <= flood.REACH
    end

    -- Installing a battery: a Tool Battery in hand used on a Flood Light lying there (hands.lua's held-with-world) --

    local function targets(uname)
        return uname == flood.BATTERY_UNAME and { flood.UNAME } or nil
    end

    local function interact(player, held, row)
        if not held or held.uname ~= flood.BATTERY_UNAME or row.uname ~= flood.UNAME then
            return false
        end
        local d = flood.data(decodeData(row.data))
        if d.battery then
            say(player, "HASBATTERY")
            return true
        end
        local charge = flood.toolCharge(held.data)
        if charge <= 0 then
            say(player, "FLAT")
            return true
        end
        d.battery = charge
        -- the battery goes into the light first, so a light someone else changed meanwhile costs no battery; the
        -- battery item then goes, and if it cannot (gone from the hand) the light gives the charge back
        write(row, d, function(done)
            if not isElement(player) then
                return
            end
            if not done then
                return toast(player, "BUSY")
            end
            ctx.destroy(held.id, player, function(ok)
                log.event(
                    "floodlight.batteryInstalled",
                    fields(
                        player,
                        row,
                        { battery_id = held.id, charge = charge, ok = ok, code = ok and "OK" or "GONE" }
                    )
                )
                if not ok then
                    local back = flood.data(decodeData(row.data))
                    back.battery = nil
                    return write(row, back)
                end
                setPedAnimation(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
                say(player, "INSTALLED", flood.percent(charge))
            end, "installed")
        end)
        return true
    end

    -- Switching it on and off, and taking the battery out (the interaction chooser) ------------------------------

    local function toggle(player, row)
        local d = flood.data(decodeData(row.data))
        if d.lit then
            d.lit = nil
            return write(row, d, function(done)
                if done then
                    log.event("floodlight.toggled", fields(player, row, { lit = 0, ok = true }))
                    say(player, "OFF")
                end
            end)
        end
        generatorNear(row, function(gen)
            if not isElement(player) then
                return
            end
            local battery = d.battery or 0
            if not gen and battery <= 0 then
                log.event("floodlight.toggled", fields(player, row, { lit = 1, ok = false, code = "NO_POWER" }))
                return say(player, "NOPOWER")
            end
            d.lit = 1
            write(row, d, function(done)
                if not done then
                    return toast(player, "BUSY")
                end
                local source = gen and "generator" or "battery"
                log.event(
                    "floodlight.toggled",
                    fields(player, row, { lit = 1, source = source, generator_id = gen and gen.id or nil, ok = true })
                )
                if gen then
                    say(player, "ON_GENERATOR")
                else
                    say(player, "ON_BATTERY", flood.percent(battery))
                end
            end)
        end)
    end

    local function takeBattery(player, row)
        local cid = ctx.charId(player)
        if not cid then
            return
        end
        if state.held[player] then
            return toast(player, "HANDS_FULL")
        end
        local d = flood.data(decodeData(row.data))
        local charge = d.battery
        if not charge then
            return say(player, "NOBATTERY")
        end
        d.battery = nil
        write(row, d, function(done)
            if not isElement(player) then
                return
            end
            if not done then
                return toast(player, "BUSY")
            end
            db.call("item_create_held", { flood.BATTERY_UNAME, cid }, function(res)
                local newId = res and res.ok and res.payload and res.payload.item_id
                log.event(
                    "floodlight.batteryRemoved",
                    fields(player, row, {
                        battery_id = newId or nil,
                        charge = charge,
                        ok = newId ~= nil and newId ~= false,
                        code = res and res.code or "DB_ERROR",
                    })
                )
                if not newId then
                    -- no battery came out (hands filled meanwhile): it goes back into the light
                    local back = flood.data(decodeData(row.data))
                    back.battery = charge
                    write(row, back)
                    if isElement(player) then
                        toast(player, res and res.code or "DB_ERROR")
                    end
                    return
                end
                triggerEvent("itemCreated", resourceRoot, newId)
                local data = { charge = charge }
                db.exec("UPDATE items SET data = ? WHERE id = ?", { encode(data), newId })
                if isElement(player) then
                    hands.setHeld(player, { id = newId, uname = flood.BATTERY_UNAME, hp = 2, data = data })
                    say(player, "REMOVED", flood.percent(charge))
                end
            end)
        end)
    end

    net.handler("floodLightActionRequested", function(player, itemId, action)
        itemId = tonumber(itemId)
        if not itemId or not ctx.charId(player) or (action ~= "toggle" and action ~= "battery") then
            return
        end
        db.one(ROW, { itemId }, function(row, c)
            if not inReach(c.player, row) then
                return
            end
            if c.action == "toggle" then
                toggle(c.player, row)
            else
                takeBattery(c.player, row)
            end
        end, { player = player, action = action })
    end, { rate = 5 })

    -- picked up, it switches off: it lights only where it stands
    addEventHandler("itemMoved", root, function(itemId, from, to)
        local held = state.held[source]
        if from ~= "world" or to ~= "held" or not held or held.id ~= itemId or held.uname ~= flood.UNAME then
            return
        end
        local d = flood.data(held.data)
        if d.lit then
            d.lit = nil
            ctx.updateHeldData(source, d)
        end
    end)

    -- The power draw ------------------------------------------------------------------------------------------

    local function tick()
        db.query(LIT, {}, function(lights)
            if not lights or #lights == 0 then
                return
            end
            db.query(GENERATORS, {}, function(gens)
                gens = gens or {}
                local draw = flood.batteryDraw(flood.TICK_MS / 1000)
                local lightRows, dark = {}, {}
                for _, light in ipairs(lights) do
                    if not nearestGenerator(gens, light) then
                        local d = flood.data(decodeData(light.data))
                        local battery = d.battery or 0
                        if battery > draw then
                            d.battery = battery - draw
                        else
                            d.battery = d.battery and 0 or nil
                            d.lit = nil
                            dark[#dark + 1] = light
                        end
                        lightRows[#lightRows + 1] = { l = light.id, o = raw(light), d = encode(d) }
                    end
                end
                local lj = #lightRows > 0 and encode(lightRows) or "[]"
                db.call("floodlight_drain", { lj, "[]" }, function(res)
                    if not res or not res.ok then
                        log.event("floodlight.drained", { ok = false, code = res and res.code or "DB_ERROR" }, "warn")
                        return
                    end
                    for _, light in ipairs(dark) do
                        world.resendEverywhere(light.id)
                        log.event("floodlight.wentDark", {
                            item_id = light.id,
                            x = math.floor(light.x),
                            y = math.floor(light.y),
                            z = math.floor(light.z),
                        })
                    end
                end)
            end)
        end)
    end

    local function start()
        setTimer(tick, flood.TICK_MS, 0)
    end

    return { targets = targets, interact = interact, start = start }
end
