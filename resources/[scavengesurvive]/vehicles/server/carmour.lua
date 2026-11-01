-- Server side of carmour (shared/logic/carmour.lua): welding a defence panel onto a vehicle with a Welder (any
-- vehicle model with slots; only the towable Airstream has them for now), the armour's persistence in
-- vehicles.carmour, the heavier trailer and the slower tower, the walk-in door's hitpoints and the damage panels
-- soak up. Clients build the panels themselves from the element data "vehicles.carmour" (client/carmour.lua):
-- server-made objects cannot carry SA-MP or port models.
-- ctx = { db, info, toast, activeActions, cancelHoldAction, carmour, slots, breakLock } built by server/main.lua.
return function(ctx)
    local db, info, toast, activeActions = ctx.db, ctx.info, ctx.toast, ctx.activeActions
    local carmour, slotsByModel, cancelHoldAction = ctx.carmour, ctx.slots, ctx.cancelHoldAction
    local M = {}

    local panelNames = {}
    for uname in pairs(carmour.PANELS) do
        panelNames[#panelNames + 1] = "'" .. uname .. "'"
    end
    local PANELS = "SELECT id, type_uname AS uname, hitpoints AS hp, data, x, y, z FROM items WHERE x IS NOT NULL "
        .. "AND container_id IS NULL AND holder_char_id IS NULL AND IFNULL(interior, 0) = ? "
        .. "AND IFNULL(dimension, 0) = ? AND ABS(x - ?) <= ? AND ABS(y - ?) <= ? AND type_uname IN ("
        .. table.concat(panelNames, ",")
        .. ")"
    local TANKS = "SELECT i.id, i.data FROM items i JOIN containers c ON c.id = i.container_id "
        .. "WHERE i.type_uname = 'GasTank' AND (c.owner_char_id = ? OR c.owner_item_id IN "
        .. "(SELECT id FROM items WHERE holder_char_id = ? AND holder_kind = 'bag')) ORDER BY i.id"

    local SAVE = "UPDATE vehicles SET carmour = ? WHERE id = ?"
    -- a Generator lying within the Welder's cable; its fuel is read from the data in Lua and drawn in one statement
    local GENERATORS = "SELECT id, x, y, z, data FROM items WHERE type_uname = 'Generator' AND x IS NOT NULL "
        .. "AND container_id IS NULL AND holder_char_id IS NULL AND IFNULL(interior, 0) = ? "
        .. "AND IFNULL(dimension, 0) = ? AND ABS(x - ?) <= ? AND ABS(y - ?) <= ?"
    -- the item data is either {machine} or [{machine}] (fuelOf below): the fuel's path in whichever it is
    local PATH = "IF(JSON_VALUE(data, '$.machine.fuel') IS NULL, '$[0].machine.fuel', '$.machine.fuel')"
    local FUEL = "CAST(JSON_VALUE(data, " .. PATH .. ") AS DECIMAL(10, 2))"
    local DRAW = "UPDATE items SET data = JSON_SET(data, "
        .. PATH
        .. ", "
        .. FUEL
        .. " - ?) "
        .. "WHERE id = ? AND type_uname = 'Generator' AND x IS NOT NULL AND "
        .. FUEL
        .. " >= ?"

    local function slotDefs(vehicle)
        return slotsByModel[getElementModel(vehicle)]
    end

    function M.hasSlots(vehicle)
        return slotDefs(vehicle) ~= nil
    end

    function M.state(vehicle)
        local inf = info[vehicle]
        return inf and inf.carmour or carmour.new()
    end

    function M.armoured(vehicle)
        local inf = info[vehicle]
        return inf ~= nil and inf.carmour ~= nil and carmour.panelCount(inf.carmour) > 0
    end

    local function decodeData(data)
        if type(data) == "string" and data ~= "" then
            return fromJSON(data)
        end
        return nil
    end

    -- the tower's engine, slower by the panels the trailer behind it carries
    local function slowTower(truck, trailer)
        if not isElement(truck) then
            return
        end
        local n = M.armoured(trailer) and carmour.panelCount(info[trailer].carmour) or 0
        if n == 0 then
            setVehicleHandling(truck, "engineAcceleration", nil)
            return
        end
        local stock = getModelHandling(getElementModel(truck)).engineAcceleration
        setVehicleHandling(truck, "engineAcceleration", carmour.towAccel(stock, n))
    end

    -- a trailer (or its tower) changed: the tower's engine follows the trailer's armour
    function M.refreshTow(trailer)
        local truck = getVehicleTowingVehicle(trailer)
        if truck then
            slowTower(truck, trailer)
        end
    end

    -- the tower let go of its trailer
    function M.towEnded(truck)
        if isElement(truck) then
            setVehicleHandling(truck, "engineAcceleration", nil)
        end
    end

    -- armour changed or loaded: element data for the clients, the trailer's mass, the tower, the damage shield
    function M.apply(vehicle)
        local inf = info[vehicle]
        if not inf or not isElement(vehicle) then
            return
        end
        local st = inf.carmour or carmour.new()
        local n = carmour.panelCount(st)
        local has = slotDefs(vehicle) ~= nil
        setElementData(vehicle, "vehicles.carmour", has and carmour.encode(st) or false, "broadcast", "deny")
        setElementData(vehicle, "vehicles.doorHp", has and carmour.doorHp(st) or false, "broadcast", "deny")
        if n == 0 then
            setVehicleHandling(vehicle, "mass", nil)
        else
            setVehicleHandling(vehicle, "mass", carmour.trailerMass(getModelHandling(getElementModel(vehicle)).mass, n))
        end
        setVehicleDamageProof(vehicle, n > 0)
        M.refreshTow(vehicle)
    end

    -- vehicles.create: the stored armour of a row
    function M.load(vehicle, text)
        local inf = info[vehicle]
        if not inf or not slotDefs(vehicle) then
            return
        end
        inf.carmour = carmour.decode(text and text ~= "" and text ~= false and fromJSON(text) or nil)
        M.apply(vehicle)
    end

    local function save(vehicle)
        local inf = info[vehicle]
        local json = toJSON(carmour.encode(inf.carmour), true):sub(2, -2)
        db.exec(SAVE, { json, inf.id })
    end

    -- Damage to the armour (explosives): the panels soak it up, then the door's own hitpoint, whose loss breaks the
    -- lock. Returns the panels shed.
    function M.damage(vehicle, dmg)
        local defs = isElement(vehicle) and info[vehicle] and slotDefs(vehicle)
        if not defs then
            return 0
        end
        local inf = info[vehicle]
        local st = inf.carmour or carmour.new()
        local nextSt, shed, broken = carmour.applyDamage(st, dmg, defs)
        inf.carmour = nextSt
        M.apply(vehicle)
        save(vehicle)
        if broken then
            ctx.breakLock(vehicle)
        end
        return #shed
    end

    -- Welding -------------------------------------------------------------------------------------------------

    local function nearestPanel(rows, x, y, z)
        local best, bestDist = nil, carmour.PANEL_REACH
        for _, r in ipairs(rows or {}) do
            local d = getDistanceBetweenPoints3D(x, y, z, r.x, r.y, r.z)
            local data = decodeData(r.data)
            local built = type(data) == "table" and type(data.defence) == "table" and data.defence.active == true
            if d <= bestDist and not built then
                best, bestDist = r, d
            end
        end
        return best
    end

    -- the Generator's fuel from its item data ({ machine = { fuel } }, either JSON shape)
    local function fuelOf(data)
        local d = decodeData(data)
        d = type(d) == "table" and (type(d[1]) == "table" and d[1] or d) or {}
        return type(d.machine) == "table" and tonumber(d.machine.fuel) or 0
    end

    local function nearestGenerator(rows, x, y, z)
        local best, bestDist = nil, carmour.GENERATOR_REACH
        for _, r in ipairs(rows or {}) do
            local d = getDistanceBetweenPoints3D(x, y, z, r.x, r.y, r.z)
            if d <= bestDist and fuelOf(r.data) >= carmour.FUEL_PER_WELD then
                best, bestDist = r, d
            end
        end
        return best
    end

    local function fail(player, code)
        toast(player, code)
    end

    -- the hold's end: the generator pays its fuel, then one procedure uses the panel and the tank up and stores the
    -- armour
    local function finish(player, vehicle, slot, panel, tankId, genId)
        activeActions[player] = nil
        if not isElement(player) or not isElement(vehicle) or not info[vehicle] then
            return
        end
        setPedAnimation(player, nil)
        triggerClientEvent(player, "vehicleHoldStopped", player)
        local fuel = carmour.FUEL_PER_WELD
        db.exec(DRAW, { fuel, genId, fuel }, function(ok, _, affected)
            if not ok or tonumber(affected) ~= 1 then
                return fail(player, "WELD_NOPOWER")
            end
            local inf = info[vehicle]
            if not inf then
                return
            end
            local defs = slotDefs(vehicle)
            local st = inf.carmour or carmour.new()
            if not defs or st.slots[slot] then
                return fail(player, "WELD_FULL")
            end
            local nextSt = carmour.weld(st, slot, panel.uname, panel.hp)
            local json = toJSON(carmour.encode(nextSt), true):sub(2, -2)
            db.call("carmour_weld", { inf.id, panel.id, tankId, json }, function(res)
                if not res or not res.ok then
                    return fail(player, res and res.code == "NO_GAS" and "WELD_NOGAS" or "WELD_NOPANEL")
                end
                inf.carmour = nextSt
                M.apply(vehicle)
                exports.items:forgetWorldItem(panel.id)
                if isElement(player) then
                    exports.items:refreshPlayer(player)
                    toast(player, "WELDED")
                end
                local who, line = getPlayerName(player), "[CARMOUR] %s welded %s onto vehicle %d slot %d"
                outputServerLog(string.format(line, who, panel.uname, inf.id, slot))
            end)
        end)
    end

    -- vehicleInteractRequested with a Welder in hand at an armourable vehicle
    function M.weld(player, vehicle)
        local inf = info[vehicle]
        local defs = inf and slotDefs(vehicle)
        if not inf or activeActions[player] then
            return
        end
        if not defs then
            return fail(player, "WELD_NOSLOTS")
        end
        local st = inf.carmour or carmour.new()
        local slot = carmour.freeSlot(st, defs)
        if not slot then
            return fail(player, "WELD_FULL")
        end
        local cid = exports.character:getCharacterId(player)
        local px, py, pz = getElementPosition(player)
        local int, dim = getElementInterior(player), getElementDimension(player)
        local reach = carmour.PANEL_REACH
        db.query(PANELS, { int, dim, px, reach, py, reach }, function(rows)
            if not isElement(player) then
                return
            end
            local panel = nearestPanel(rows, px, py, pz)
            if not panel then
                return fail(player, "WELD_NOPANEL")
            end
            db.query(TANKS, { cid, cid }, function(tanks)
                local tank = nil
                for _, t in ipairs(tanks or {}) do
                    if carmour.gasOf(decodeData(t.data)) >= carmour.GAS_PER_WELD then
                        tank = t
                        break
                    end
                end
                if not tank then
                    return fail(player, "WELD_NOGAS")
                end
                local cable = carmour.GENERATOR_REACH
                db.query(GENERATORS, { int, dim, px, cable, py, cable }, function(gens)
                    local gen = nearestGenerator(gens, px, py, pz)
                    if not gen then
                        return fail(player, "WELD_NOPOWER")
                    end
                    if not isElement(player) or not isElement(vehicle) or activeActions[player] then
                        return
                    end
                    cancelHoldAction(player)
                    setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
                    local ms = exports.character:skillTimeModifier(player, carmour.WELD_MS, "Repair")
                    triggerClientEvent(player, "vehicleHoldStarted", player, "Welding", ms)
                    triggerClientEvent(root, "weldStarted", player, ms)
                    local timer = setTimer(finish, ms, 1, player, vehicle, slot, panel, tank.id, gen.id)
                    activeActions[player] = { actionType = "weld", vehicle = vehicle, timer = timer }
                end)
            end)
        end)
    end

    return M
end
