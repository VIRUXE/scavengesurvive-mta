-- Server side of carmour (shared/logic/carmour.lua, shared/logic/carmour_place.lua): attaching a held defence to a
-- vehicle where the player aims (the client sends its camera ray, the server places the panel from it with the same
-- rules), the Welder's torch (grabbed off a Welder lying on the ground, tethered to it by its lead), welding an
-- attached panel on, prying an unwelded one off with a Crowbar, the armour's persistence in vehicles.carmour, the
-- heavier trailer and the slower tower, grinding a welded panel off with an Angle Grinder, the walk-in door's
-- hitpoints and the damage panels soak up.
-- Clients build the panels themselves from the element data "vehicles.carmour" (client/carmour.lua): server-made
-- objects cannot carry SA-MP or port models. A player's torch is the element data "vehicles.torch".
-- ctx = { db, info, toast, activeActions, cancelHoldAction, carmour, place, geo, breakLock } built by server/main.lua.
return function(ctx)
    local db, info, toast, activeActions = ctx.db, ctx.info, ctx.toast, ctx.activeActions
    local carmour, place, geo, cancelHoldAction = ctx.carmour, ctx.place, ctx.geo, ctx.cancelHoldAction
    local M = {}
    local torches = {} -- player -> { id, x, y, z, rz, int, dim } of the Welder whose torch the player holds

    -- The Welder's gas: a Gas Cylinder (the Canister item) or a Gas Bottle lying on the ground, hooked up to a Welder
    -- lying on the ground within the hose's reach; the link is the Welder's item data { cylinder = id, wx, wy, gx, gy }
    -- with where the Welder (w) and the gas (g) lay when hooked up: moving either undoes it (a carried Welder's data
    -- comes back with it when it is put down, so the link cannot rest on the data being cleared)
    local GROUND = "x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"
    local GAS = "('Canister', 'GasBottle')"
    local LINKED = "CAST(JSON_VALUE(w.data, '$.cylinder') AS UNSIGNED)"
    local HOOKED = "SELECT c.id, c.type_uname, c.x, c.y, c.z, c.data FROM items w JOIN items c ON c.id = "
        .. LINKED
        .. " WHERE w.id = ? AND c.type_uname IN "
        .. GAS
        .. " AND c.x IS NOT NULL AND c.container_id IS NULL AND c.holder_char_id IS NULL"
    local CYLINDER = "SELECT id, x, y, z, interior, dimension FROM items WHERE id = ? AND type_uname IN "
        .. GAS
        .. " AND "
        .. GROUND
    local WELDERS_NEAR = "SELECT id, x, y, z, data FROM items WHERE type_uname = 'Welder' AND "
        .. GROUND
        .. " AND IFNULL(interior, 0) = ? AND IFNULL(dimension, 0) = ? AND ABS(x - ?) <= ? AND ABS(y - ?) <= ?"
    local LINK = "UPDATE items SET data = JSON_OBJECT('cylinder', ?, 'wx', x, 'wy', y, 'gx', ?, 'gy', ?) "
        .. "WHERE id = ? AND type_uname = 'Welder'"
    local UNLINK = "UPDATE items SET data = NULL WHERE type_uname = 'Welder' AND (id = ? OR "
        .. "CAST(JSON_VALUE(data, '$.cylinder') AS UNSIGNED) = ?)"
    -- a link whose Welder or gas was picked up or moved comes undone
    local MOVED = "ABS(w.x - CAST(JSON_VALUE(w.data, '$.wx') AS DOUBLE)) > 0.1 OR "
        .. "ABS(w.y - CAST(JSON_VALUE(w.data, '$.wy') AS DOUBLE)) > 0.1 OR "
        .. "ABS(c.x - CAST(JSON_VALUE(w.data, '$.gx') AS DOUBLE)) > 0.1 OR "
        .. "ABS(c.y - CAST(JSON_VALUE(w.data, '$.gy') AS DOUBLE)) > 0.1"
    local LOOSE = "UPDATE items w LEFT JOIN items c ON c.id = "
        .. LINKED
        .. " SET w.data = NULL WHERE w.type_uname = 'Welder' AND JSON_VALUE(w.data, '$.cylinder') IS NOT NULL AND "
        .. "(w.x IS NULL OR c.id IS NULL OR c.x IS NULL OR c.type_uname NOT IN "
        .. GAS
        .. " OR c.container_id IS NOT NULL "
        .. "OR c.holder_char_id IS NOT NULL OR (w.x - c.x) * (w.x - c.x) + (w.y - c.y) * (w.y - c.y) > ? OR "
        .. MOVED
        .. ")"
    local HOSES = "SELECT w.id AS w, "
        .. LINKED
        .. " AS c FROM items w WHERE w.type_uname = 'Welder' AND w.x IS NOT NULL AND "
        .. "JSON_VALUE(w.data, '$.cylinder') IS NOT NULL"
    -- the character's items of one type in the inventory or a worn bag (the Grinder's Batteries and Grinding Discs)
    local CARRIED = "SELECT i.id, i.data FROM items i JOIN containers c ON c.id = i.container_id "
        .. "WHERE i.type_uname = ? AND (c.owner_char_id = ? OR c.owner_item_id IN "
        .. "(SELECT id FROM items WHERE holder_char_id = ? AND holder_kind = 'bag')) ORDER BY i.id"
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
    local WELDER = "SELECT id, x, y, z, rz, interior, dimension FROM items WHERE id = ? AND type_uname = 'Welder' "
        .. "AND x IS NOT NULL AND container_id IS NULL AND holder_char_id IS NULL"

    local function takesArmour(vehicle)
        return isElement(vehicle) and getElementModel(vehicle) == geo.model
    end

    function M.hasSlots(vehicle)
        return takesArmour(vehicle)
    end

    local function stateOf(vehicle)
        local inf = info[vehicle]
        return inf and inf.carmour or carmour.new()
    end

    -- at least one panel welded on: the vehicle takes no damage and cannot blow up
    function M.armoured(vehicle)
        local inf = info[vehicle]
        return inf ~= nil and inf.carmour ~= nil and carmour.weldedCount(inf.carmour) > 0
    end

    local function decodeData(data)
        if type(data) == "string" and data ~= "" then
            return fromJSON(data)
        end
        return nil
    end

    -- a world point in the vehicle's frame
    local function toLocal(vehicle, x, y, z)
        local m = getElementMatrix(vehicle)
        local dx, dy, dz = x - m[4][1], y - m[4][2], z - m[4][3]
        return {
            dx * m[1][1] + dy * m[1][2] + dz * m[1][3],
            dx * m[2][1] + dy * m[2][2] + dz * m[2][3],
            dx * m[3][1] + dy * m[3][2] + dz * m[3][3],
        }
    end

    local function toWorld(vehicle, p)
        local m = getElementMatrix(vehicle)
        local x = p[1] * m[1][1] + p[2] * m[2][1] + p[3] * m[3][1] + m[4][1]
        local y = p[1] * m[1][2] + p[2] * m[2][2] + p[3] * m[3][2] + m[4][2]
        local z = p[1] * m[1][3] + p[2] * m[2][3] + p[3] * m[3][3] + m[4][3]
        return x, y, z
    end

    -- the tower's engine, slower by the panels the trailer behind it carries
    local function slowTower(truck, trailer)
        if not isElement(truck) then
            return
        end
        local inf = info[trailer]
        local n = inf and inf.carmour and carmour.panelCount(inf.carmour) or 0
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
        local has = takesArmour(vehicle)
        setElementData(vehicle, "vehicles.carmour", has and carmour.encode(st) or false, "broadcast", "deny")
        setElementData(vehicle, "vehicles.doorHp", has and carmour.doorHp(st) or false, "broadcast", "deny")
        local n = carmour.panelCount(st)
        if n == 0 then
            setVehicleHandling(vehicle, "mass", nil)
        else
            setVehicleHandling(vehicle, "mass", carmour.trailerMass(getModelHandling(getElementModel(vehicle)).mass, n))
        end
        setVehicleDamageProof(vehicle, carmour.weldedCount(st) > 0)
        M.refreshTow(vehicle)
    end

    -- vehicles.create: the stored armour of a row
    function M.load(vehicle, text)
        local inf = info[vehicle]
        if not inf or not takesArmour(vehicle) then
            return
        end
        local t = text and text ~= "" and text ~= false and fromJSON(text) or nil
        inf.carmour = carmour.decode(t, geo.panels)
        M.apply(vehicle)
    end

    local function json(st)
        return toJSON(carmour.encode(st), true):sub(2, -2)
    end

    -- the records that came off, as ground items beside the vehicle under where each was
    local function dropRows(vehicle, recs)
        local rows = {}
        local int, dim = getElementInterior(vehicle), getElementDimension(vehicle)
        local _, _, vz = getElementPosition(vehicle)
        local _, _, rz = getElementRotation(vehicle)
        for _, rec in ipairs(recs) do
            local x, y = toWorld(vehicle, { rec.c[1] * 1.15, rec.c[2], rec.c[3] })
            rows[#rows + 1] = {
                u = rec.u,
                hp = math.max(1, rec.hp),
                x = x,
                y = y,
                z = vz - carmour.GROUND_DROP,
                rz = rz,
                int = int,
                dim = dim,
            }
        end
        return rows
    end

    -- the vehicle's armour becomes st, and recs come off onto the ground (one procedure); then(ok) after
    local function detach(vehicle, st, recs, andThen)
        local inf = info[vehicle]
        local rows = dropRows(vehicle, recs)
        local items = #rows > 0 and toJSON(rows, true):sub(2, -2) or "[]" -- toJSON wraps its argument in a list
        db.call("carmour_detach", { inf.id, json(st), items }, function(res)
            if not res or not res.ok then
                return andThen and andThen(false)
            end
            inf.carmour = st
            M.apply(vehicle)
            local p = type(res.payload) == "string" and fromJSON(res.payload) or res.payload
            local first, count = p and tonumber(p.first), p and tonumber(p.count) or 0
            for i = 0, count - 1 do
                if first then
                    exports.items:resendWorldItem(first + i)
                end
            end
            return andThen and andThen(true)
        end)
    end

    -- Damage to the armour (explosives): every attached, unwelded panel falls off, the welded ones soak it up, then
    -- the door's own hitpoint, whose loss breaks the lock. Returns the panels that came off.
    function M.damage(vehicle, dmg)
        local inf = isElement(vehicle) and info[vehicle]
        if not inf or not takesArmour(vehicle) then
            return 0
        end
        local st = inf.carmour or carmour.new()
        local nextSt, off, broken = carmour.applyDamage(st, dmg)
        local loose = {}
        for _, rec in ipairs(off) do
            if rec.knocked then
                loose[#loose + 1] = rec -- an unwelded panel lands whole; a shed welded one is wrecked
            end
        end
        inf.carmour = nextSt
        M.apply(vehicle)
        detach(vehicle, nextSt, loose)
        if broken then
            ctx.breakLock(vehicle)
        end
        return #off
    end

    -- Attaching ------------------------------------------------------------------------------------------------

    local REFUSALS = {
        MISS = "ATTACH_MISS",
        DOOR_ONLY = "ATTACH_DOOR_ONLY",
        NOT_DOOR = "ATTACH_NOT_DOOR",
        UNSUPPORTED = "ATTACH_UNSUPPORTED",
        BLOCKS_DOOR = "ATTACH_BLOCKS_DOOR",
        CLASH = "ATTACH_CLASH",
        NOT_DEFENCE = "ATTACH_NOT_DEFENCE",
    }

    local function vec(t)
        if type(t) ~= "table" then
            return nil
        end
        local x, y, z = tonumber(t[1]), tonumber(t[2]), tonumber(t[3])
        return x and y and z and { x, y, z } or nil
    end

    -- the client's camera ray (o, d in the vehicle's frame) with the defence the player holds: placed by the server
    function M.attach(player, vehicle, o, d)
        o, d = vec(o), vec(d)
        local inf = info[vehicle]
        if not inf or not takesArmour(vehicle) or not o or not d or activeActions[player] then
            return
        end
        d = place.vec.norm(d)
        local held = exports.items:getHeld(player)
        if not held or not geo.panels[held.uname] then
            return toast(player, "ATTACH_NOT_DEFENCE")
        end
        if not d or place.vec.dot(o, o) > 225 then -- the camera within 15 m of the vehicle
            return
        end
        local st = stateOf(vehicle)
        local rec, why = place.place(geo, held.uname, o, d, st.panels)
        if not rec then
            return toast(player, REFUSALS[why] or "ATTACH_MISS")
        end
        local px, py, pz = getElementPosition(player)
        local me = toLocal(vehicle, px, py, pz)
        local gap = place.vec.sub(rec.c, me)
        if place.vec.dot(gap, gap) > carmour.ATTACH_REACH * carmour.ATTACH_REACH then
            return toast(player, "ATTACH_FAR")
        end
        local nextSt = carmour.attach(st, rec, held.uname, held.hp)
        local cid = exports.character:getCharacterId(player)
        db.call("carmour_attach", { inf.id, held.id, cid, json(nextSt) }, function(res)
            if not res or not res.ok then
                return toast(player, "ATTACH_NOT_DEFENCE")
            end
            inf.carmour = nextSt
            M.apply(vehicle)
            if isElement(player) then
                exports.items:clearHeld(player)
                triggerClientEvent(player, "heldItemChanged", player, false) -- the hud and inventory let go of it
                exports.items:refreshPlayer(player)
                toast(player, "ATTACHED")
            end
            local who, line = getPlayerName(player), "[CARMOUR] %s attached %s to vehicle %d"
            outputServerLog(string.format(line, who, held.uname, inf.id))
        end)
    end

    -- The torch ------------------------------------------------------------------------------------------------

    local function setTorch(player, t)
        torches[player] = t
        if isElement(player) then
            local data = t and { id = t.id, x = t.x, y = t.y, z = t.z, rz = t.rz } or false
            setElementData(player, "vehicles.torch", data, "broadcast", "deny")
        end
    end

    function M.hasTorch(player)
        return torches[player] ~= nil
    end

    function M.stowTorch(player)
        if torches[player] then
            setTorch(player, nil)
        end
    end

    local function torchTaken(id)
        for _, t in pairs(torches) do
            if t.id == id then
                return true
            end
        end
        return false
    end

    -- empty hands take the torch off a Welder lying within reach
    function M.grabTorch(player, welderId)
        welderId = tonumber(welderId)
        if not welderId or torches[player] or exports.items:getHeld(player) or activeActions[player] then
            return
        end
        if getPedOccupiedVehicle(player) or isPedDead(player) then
            return
        end
        db.query(WELDER, { welderId }, function(rows)
            local r = rows and rows[1]
            if not r or not isElement(player) then
                return
            end
            local px, py, pz = getElementPosition(player)
            if getDistanceBetweenPoints3D(px, py, pz, r.x, r.y, r.z) > 2.5 or torchTaken(welderId) then
                return
            end
            local t = { id = welderId, x = r.x, y = r.y, z = r.z, rz = tonumber(r.rz) or 0 }
            t.int, t.dim = tonumber(r.interior) or 0, tonumber(r.dimension) or 0
            setTorch(player, t)
        end)
    end

    -- the torch goes back when its holder walks past the lead, takes something in hand, gets in a vehicle or dies,
    -- or the Welder is no longer where it was
    local checks = 0
    setTimer(function()
        checks = checks + 1
        for player, t in pairs(torches) do
            local drop = not isElement(player) or isPedDead(player) or getPedOccupiedVehicle(player)
            if not drop then
                local px, py, pz = getElementPosition(player)
                local far = getDistanceBetweenPoints3D(px, py, pz, t.x, t.y, t.z) > carmour.LEAD
                drop = far or exports.items:getHeld(player) ~= false or getElementDimension(player) ~= t.dim
            end
            if drop then
                setTorch(player, nil)
                if isElement(player) then
                    toast(player, "TORCH_STOWED")
                end
            elseif checks % 8 == 0 then
                db.query(WELDER, { t.id }, function(rows)
                    local r = rows and rows[1]
                    local moved = not r or math.abs(r.x - t.x) > 0.05 or math.abs(r.y - t.y) > 0.05
                    if moved and torches[player] == t then
                        setTorch(player, nil)
                    end
                end)
            end
        end
    end, 250, 0)

    addEventHandler("onPlayerQuit", root, function()
        torches[source] = nil
    end)

    -- Welding --------------------------------------------------------------------------------------------------

    -- the Generator's fuel from its item data ({ machine = { fuel } }, either JSON shape)
    local function fuelOf(data)
        local d = decodeData(data)
        d = type(d) == "table" and (type(d[1]) == "table" and d[1] or d) or {}
        return type(d.machine) == "table" and tonumber(d.machine.fuel) or 0
    end

    local function nearestGenerator(rows, x, y, z)
        local best, bestDist = nil, carmour.GENERATOR_REACH
        for _, r in ipairs(rows or {}) do
            local dist = getDistanceBetweenPoints3D(x, y, z, r.x, r.y, r.z)
            if dist <= bestDist and fuelOf(r.data) >= carmour.FUEL_PER_WELD then
                best, bestDist = r, dist
            end
        end
        return best
    end

    -- the attached panel within reach of the player that wants(rec), or nil
    local function panelNear(player, vehicle, wants)
        local px, py, pz = getElementPosition(player)
        local me = toLocal(vehicle, px, py, pz)
        return carmour.nearest(stateOf(vehicle), place, geo, me, carmour.WORK_REACH, wants)
    end

    local function unwelded(rec)
        return not rec.w
    end

    -- the hold's end: the generator pays its fuel, then one procedure takes the gas and stores the welded panel
    local function finish(player, vehicle, panelId, tankId, genId, kg)
        activeActions[player] = nil
        if not isElement(player) or not isElement(vehicle) or not info[vehicle] then
            return
        end
        setPedAnimation(player, nil)
        triggerClientEvent(player, "vehicleHoldStopped", player)
        if not torches[player] then
            return
        end
        local fuel = carmour.FUEL_PER_WELD
        db.exec(DRAW, { fuel, genId, fuel }, function(ok, _, affected)
            if not ok or tonumber(affected) ~= 1 then
                return toast(player, "WELD_NOPOWER")
            end
            local inf = info[vehicle]
            local rec = inf and carmour.find(stateOf(vehicle), panelId)
            if not rec or rec.w then
                return
            end
            local nextSt = carmour.weld(stateOf(vehicle), panelId)
            db.call("carmour_weld", { inf.id, tankId, json(nextSt), kg }, function(res)
                if not res or not res.ok then
                    return toast(player, "WELD_NOGAS")
                end
                inf.carmour = nextSt
                M.apply(vehicle)
                if isElement(player) then
                    exports.items:refreshPlayer(player)
                    toast(player, "WELDED")
                end
                local who, line = getPlayerName(player), "[CARMOUR] %s welded %s onto vehicle %d"
                outputServerLog(string.format(line, who, rec.u, inf.id))
            end)
        end)
    end

    -- F with the torch at a vehicle that takes armour: the nearest attached, unwelded panel is welded on
    function M.weld(player, vehicle)
        local inf = info[vehicle]
        local torch = torches[player]
        if not inf or not torch or activeActions[player] then
            return
        end
        if not takesArmour(vehicle) then
            return toast(player, "WELD_NOSLOTS")
        end
        local rec = panelNear(player, vehicle, unwelded)
        if not rec then
            return toast(player, "WELD_NOPANEL")
        end
        -- the gas it burns follows the hitpoints the defence can take, from the cylinder hooked up to the Welder
        local t = exports.data:itemType(rec.u)
        local kg = carmour.weldGas(t and t.maxHitpoints or rec.hp)
        db.query(HOOKED, { torch.id }, function(rows)
            local tank = rows and rows[1]
            local hose = tank and getDistanceBetweenPoints2D(tank.x, tank.y, torch.x, torch.y) <= carmour.HOSE
            if not hose then
                return toast(player, "WELD_NOCYLINDER")
            end
            if carmour.gasOf(decodeData(tank.data), tank.type_uname) < kg - 0.001 then
                return toast(player, "WELD_NOGAS")
            end
            local cable = carmour.GENERATOR_REACH
            db.query(GENERATORS, { torch.int, torch.dim, torch.x, cable, torch.y, cable }, function(gens)
                local gen = nearestGenerator(gens, torch.x, torch.y, torch.z)
                if not gen then
                    return toast(player, "WELD_NOPOWER")
                end
                if not isElement(player) or not isElement(vehicle) or activeActions[player] or not torches[player] then
                    return
                end
                cancelHoldAction(player)
                setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
                local ms = exports.character:skillTimeModifier(player, carmour.WELD_MS, "Repair")
                triggerClientEvent(player, "vehicleHoldStarted", player, "Welding", ms)
                triggerClientEvent(root, "weldStarted", player, ms)
                local timer = setTimer(finish, ms, 1, player, vehicle, rec.id, tank.id, gen.id, kg)
                activeActions[player] = { actionType = "weld", vehicle = vehicle, timer = timer }
            end)
        end)
    end

    -- Hooking a Gas Cylinder up -------------------------------------------------------------------------------------

    -- the links the clients draw hoses for: { { welder id, cylinder id }, ... } on the resource root; hooked[welder]
    -- is the gas a Welder is really hooked up to (stale data a carried Welder brought back is not)
    local hooked = {}
    local function publishHoses(andThen)
        db.query(HOSES, {}, function(rows)
            local list = {}
            hooked = {}
            for _, r in ipairs(rows or {}) do
                list[#list + 1] = { tonumber(r.w), tonumber(r.c) }
                hooked[tonumber(r.w)] = tonumber(r.c)
            end
            if andThen then
                andThen()
            end
            setElementData(resourceRoot, "vehicles.hoses", list, "broadcast", "deny")
        end)
    end

    local function tidyHoses(andThen)
        db.exec(LOOSE, { carmour.HOSE * carmour.HOSE }, function()
            publishHoses(andThen)
        end)
    end
    -- every 4 s; the first a second in, once main.lua's onResourceStart has connected the database
    setTimer(tidyHoses, 4000, 0)
    setTimer(tidyHoses, 1000, 1)

    -- Empty hands at a Gas Cylinder lying near a Welder: it is hooked up to the nearest Welder within the hose's
    -- reach (any other link of either undone), or unhooked when it already was
    function M.hookCylinder(player, cylinderId)
        cylinderId = tonumber(cylinderId)
        if
            not cylinderId
            or exports.items:getHeld(player)
            or activeActions[player]
            or getPedOccupiedVehicle(player)
        then
            return
        end
        db.query(CYLINDER, { cylinderId }, function(rows)
            local c = rows and rows[1]
            if not c or not isElement(player) then
                return
            end
            local px, py = getElementPosition(player)
            if getDistanceBetweenPoints2D(px, py, c.x, c.y) > 2.5 then
                return
            end
            local reach = carmour.HOSE
            local int, dim = tonumber(c.interior) or 0, tonumber(c.dimension) or 0
            db.query(WELDERS_NEAR, { int, dim, c.x, reach, c.y, reach }, function(welders)
                local best, bestDist = nil, reach
                for _, w in ipairs(welders or {}) do
                    local d = getDistanceBetweenPoints2D(c.x, c.y, w.x, w.y)
                    if d <= bestDist then
                        best, bestDist = w, d
                    end
                end
                if not best then
                    return toast(player, "HOSE_NOWELDER")
                end
                tidyHoses(function()
                    M.toggleHose(player, best.id, cylinderId, c)
                end)
            end)
        end)
    end

    -- hooks gas cylinderId (row c) up to Welder welderId, or unhooks it when it already was
    function M.toggleHose(player, welderId, cylinderId, c)
        local linked = hooked[welderId] == cylinderId
        db.exec(UNLINK, { welderId, cylinderId }, function()
            local function done()
                publishHoses(nil)
                if isElement(player) then
                    toast(player, linked and "HOSE_OFF" or "HOSE_ON")
                end
            end
            if linked then
                return done()
            end
            db.exec(LINK, { cylinderId, c.x, c.y, welderId }, done)
        end)
    end

    -- Prying -----------------------------------------------------------------------------------------------------

    -- a Crowbar at a vehicle with an attached, unwelded panel within reach (vehicleInteractRequested asks first)
    function M.canPry(player, vehicle)
        return takesArmour(vehicle) and panelNear(player, vehicle, unwelded) ~= nil
    end

    -- a Crowbar at a welded panel only (nothing to pry): it says so
    function M.weldedNear(player, vehicle)
        return takesArmour(vehicle)
            and panelNear(player, vehicle, function(rec)
                return rec.w
            end) ~= nil
    end

    -- the Crowbar takes the nearest attached, unwelded panel off; it lands on the ground beside the vehicle
    function M.pry(player, vehicle)
        local rec = panelNear(player, vehicle, unwelded)
        if not rec or activeActions[player] then
            return
        end
        cancelHoldAction(player)
        setPedAnimation(player, "POLICE", "DOOR_KICK", -1, true, false, false, false)
        triggerClientEvent(player, "vehicleHoldStarted", player, "Prying off", carmour.PRY_MS)
        local timer = setTimer(function()
            activeActions[player] = nil
            if not isElement(player) or not isElement(vehicle) or not info[vehicle] then
                return
            end
            setPedAnimation(player, nil)
            triggerClientEvent(player, "vehicleHoldStopped", player)
            local cur = carmour.find(stateOf(vehicle), rec.id)
            if not cur or cur.w then
                return
            end
            local nextSt, gone = carmour.remove(stateOf(vehicle), rec.id)
            detach(vehicle, nextSt, { gone }, function(ok)
                if ok and isElement(player) then
                    toast(player, "PRIED")
                end
            end)
        end, carmour.PRY_MS, 1)
        activeActions[player] = { actionType = "pry", vehicle = vehicle, timer = timer }
    end

    -- Grinding -------------------------------------------------------------------------------------------------

    local function welded(rec)
        return rec.w
    end

    -- the first of rows whose data `left(data)` says has a pass in it
    local function firstWith(rows, left)
        for _, r in ipairs(rows or {}) do
            if left(decodeData(r.data)) >= 1 then
                return r
            end
        end
        return nil
    end

    -- the pass's end: one procedure takes a Battery charge and a disc's wear and stores the panel's progress; the
    -- pass that cuts it through takes the panel off onto the ground
    local function grindPass(player, vehicle, panelId, batteryId, discId)
        activeActions[player] = nil
        if not isElement(player) or not isElement(vehicle) or not info[vehicle] then
            return
        end
        setPedAnimation(player, nil)
        triggerClientEvent(player, "vehicleHoldStopped", player)
        local inf = info[vehicle]
        local held = exports.items:getHeld(player)
        local rec = carmour.find(stateOf(vehicle), panelId)
        if not held or held.uname ~= "Grinder" or not rec or not rec.w then
            return
        end
        local nextSt, cut = carmour.grind(stateOf(vehicle), panelId)
        local args = { inf.id, batteryId, discId, json(nextSt), carmour.BATTERY_CHARGES, carmour.DISC_WEAR }
        db.call("carmour_grind", args, function(res)
            if not res or not res.ok then
                return toast(player, res and res.code == "NO_DISC" and "GRIND_NODISC" or "GRIND_NOBATTERY")
            end
            inf.carmour = nextSt
            if isElement(player) then
                exports.items:refreshPlayer(player)
            end
            if not cut then
                M.apply(vehicle)
                local done = carmour.find(nextSt, panelId)
                return toast(player, string.format("GRIND_PASS:%d:%d", done and done.g or 0, carmour.GRIND_PASSES))
            end
            local offSt, gone = carmour.remove(nextSt, panelId)
            gone.w = false
            detach(vehicle, offSt, { gone }, function(ok)
                if ok and isElement(player) then
                    toast(player, "GRIND_CUT")
                end
            end)
            local who, line = getPlayerName(player), "[CARMOUR] %s ground %s off vehicle %d"
            outputServerLog(string.format(line, who, rec.u, inf.id))
        end)
    end

    -- an Angle Grinder at a vehicle that takes armour: one pass at the nearest welded panel, with a charged Battery
    -- and a Grinding Disc with wear left in the inventory or the bag
    function M.grind(player, vehicle)
        local inf = info[vehicle]
        if not inf or activeActions[player] then
            return
        end
        if not takesArmour(vehicle) then
            return toast(player, "WELD_NOSLOTS")
        end
        local rec = panelNear(player, vehicle, welded)
        if not rec then
            return toast(player, "GRIND_NOPANEL")
        end
        local cid = exports.character:getCharacterId(player)
        db.query(CARRIED, { "Battery", cid, cid }, function(batteries)
            local battery = firstWith(batteries, carmour.chargeOf)
            if not battery then
                return toast(player, "GRIND_NOBATTERY")
            end
            db.query(CARRIED, { "GrindDisc", cid, cid }, function(discs)
                local disc = firstWith(discs, carmour.wearOf)
                if not disc then
                    return toast(player, "GRIND_NODISC")
                end
                if not isElement(player) or not isElement(vehicle) or activeActions[player] then
                    return
                end
                cancelHoldAction(player)
                setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
                local ms = carmour.GRIND_PASS_MS
                triggerClientEvent(player, "vehicleHoldStarted", player, "Grinding", ms)
                triggerClientEvent(root, "grindStarted", player, ms)
                local timer = setTimer(grindPass, ms, 1, player, vehicle, rec.id, battery.id, disc.id)
                activeActions[player] = { actionType = "grind", vehicle = vehicle, timer = timer }
            end)
        end)
    end

    return M
end
