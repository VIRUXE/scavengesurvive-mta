-- Tow Bars and towing ropes.
--
-- A Tow Bar in hand is bolted to the rear of a wheeled car or truck whose type has no hitch of its own
-- (vlogic.canFitTowbar), with a hold at its rear; vehicles.towbar keeps it. It gives the vehicle a "small" hitch
-- (vlogic.hitchOf): the trailer key hooks small trailers as on a Bobcat, and it is a rope's rear anchor. It comes off
-- again into empty hands ("Remove tow bar" in the interaction list at the rear) while nothing hangs on it.
--
-- A Rope in hand is tied first to a hitch (a stock one or a Tow Bar: F at the vehicle's rear), then to the front of
-- another vehicle (F at its front): vehicles.rope_tow_id of the tower names the towed one, and the Rope item is used up
-- until it is untied ("Untie rope" at either end) into empty hands. The rope is the clients' (client/towing.lua): each
-- client pulls the towed vehicles it syncs, and draws every rope it streams in. While the tower has a driver and the
-- towed vehicle none, that driver syncs the towed vehicle, so both ends move on one client. A rope whose vehicles end
-- up further apart than rope.SNAP_DISTANCE, or one of which is gone, falls to the ground by the tower.
--
-- Element data, both "broadcast" and set here only: "vehicles.towbar" (true on a vehicle with a fitted bar) and
-- "vehicles.ropeTow" (on a tower, the vehicle its rope pulls).
-- ctx = { db, info, toast, activeActions, cancelHoldAction, vlogic, rope, toLocal, log, vehicleLine, charId,
-- rebindTow, markUsed } built by server/main.lua.
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
return function(ctx)
    local db, info, toast, activeActions = ctx.db, ctx.info, ctx.toast, ctx.activeActions
    local vlogic, rope, log, vehicleLine = ctx.vlogic, ctx.rope, ctx.log, ctx.vehicleLine
    local cancelHoldAction, charId, rebindTow = ctx.cancelHoldAction, ctx.charId, ctx.rebindTow
    local markUsed = ctx.markUsed
    local M = {}

    local FIT_MS = 6000
    local REMOVE_MS = 5000
    local CHECK_MS = 1000

    local towOf = {} -- tower -> towed vehicle
    local towerOf = {} -- towed vehicle -> tower
    local pending = {} -- player -> { tower, since } while a rope is tied to a hitch and not yet to a front

    local function vehicleType(v)
        local inf = info[v]
        return inf and exports.data:vehicleType(inf.uname)
    end

    -- the hitch a vehicle tows with (its type's, or the tow bar's), nil without one
    function M.hitch(v)
        local inf = info[v]
        return inf and vlogic.hitchOf(vehicleType(v), inf.towbar) or nil
    end

    local function publish(v)
        local inf = info[v]
        if inf and isElement(v) then
            setElementData(v, "vehicles.towbar", inf.towbar == true, "broadcast", "deny")
            setElementData(v, "vehicles.ropeTow", towOf[v] or false, "broadcast", "deny")
        end
    end

    -- An empty GTA vehicle holds its brakes (it stops from 36 km/h in 0.2 s), so a rope would drag it like a
    -- skid. While it hangs on a rope with nobody at its wheel its brakes are all but off (it rolls like a car in
    -- neutral, a little drag left so it does not coast into the tower); a driver getting in, or the rope coming off,
    -- gives them back.
    local LOOSE_BRAKES = 0.15
    local brakesOf = {} -- towed vehicle -> its own brakeDeceleration while loosened

    local function setBrakes(towed, loose)
        if loose and not brakesOf[towed] then
            brakesOf[towed] = getVehicleHandling(towed).brakeDeceleration
            setVehicleHandling(towed, "brakeDeceleration", LOOSE_BRAKES)
        elseif not loose and brakesOf[towed] then
            if isElement(towed) then
                setVehicleHandling(towed, "brakeDeceleration", brakesOf[towed])
            end
            brakesOf[towed] = nil
        end
    end

    -- who drives the pair: the tower's driver syncs an empty towed vehicle; anything else is MTA's choice again
    function M.resync(v)
        local tower = towOf[v] and v or towerOf[v]
        local towed = tower and towOf[tower]
        if not towed or not isElement(tower) or not isElement(towed) then
            return
        end
        local empty = not getVehicleController(towed)
        setBrakes(towed, empty)
        local driver = getVehicleController(tower)
        if driver and empty then
            setElementSyncer(towed, driver, true)
        else
            local syncer = getElementSyncer(towed)
            if syncer then
                setElementSyncer(towed, syncer, false)
            end
        end
    end

    local function link(tower, towed)
        towOf[tower], towerOf[towed] = towed, tower
        publish(tower)
        M.resync(tower)
    end

    local function unlink(tower)
        local towed = towOf[tower]
        towOf[tower] = nil
        if towed then
            towerOf[towed] = nil
            setBrakes(towed, false)
            if isElement(towed) then
                local syncer = getElementSyncer(towed)
                if syncer then
                    setElementSyncer(towed, syncer, false)
                end
            end
        end
        if isElement(tower) then
            publish(tower)
        end
        return towed
    end

    -- vehicles.create: the stored tow bar and rope of a row (the rope is linked by M.restore once all are spawned)
    function M.load(v, row)
        local inf = info[v]
        if not inf then
            return
        end
        inf.towbar = (tonumber(row.towbar) or 0) == 1
        inf.ropeTowId = row.rope_tow_id and tonumber(row.rope_tow_id) or nil
        publish(v)
    end

    -- every vehicle is spawned: tie the stored ropes again
    function M.restore(byId)
        for v, inf in pairs(info) do
            local towed = inf.ropeTowId and byId(inf.ropeTowId)
            if towed and isElement(v) then
                link(v, towed)
            end
        end
    end

    -- a rope comes off its tower: into `player`'s empty hands, or onto the ground by the tower (reason: why)
    local function untie(tower, player, reason)
        local inf = info[tower]
        local towed = towOf[tower]
        if not inf then
            return
        end
        local x, y, z = getElementPosition(tower)
        local cid = player and charId(player) or nil
        local args = { inf.id, cid or nil, x, y, z - 0.5, getElementInterior(tower), getElementDimension(tower), n = 7 }
        db.call("vehicle_rope_untie", args, function(res)
            local ok, code = res and res.ok or false, res and res.code or "DB_ERROR"
            local fields = vehicleLine(tower, {
                player = player,
                towed_id = towed and info[towed] and info[towed].id or nil,
                reason = reason,
                ok = ok,
                code = code,
            })
            fields.vehicle_id = inf.id -- the tower may be gone from info by now (a removal)
            if not ok then
                log.event("vehicle.ropeUntied", fields, "warn")
                if player then
                    toast(player, code == "HANDS_FULL" and "HANDS_FULL" or "DB_ERROR")
                end
                return
            end
            local itemId = tonumber(res.payload.item_id)
            fields.item_id = itemId
            log.event("vehicle.ropeUntied", fields)
            inf.ropeTowId = nil
            unlink(tower)
            if tonumber(res.payload.held) == 1 and isElement(player) then
                exports.items:setHeld(player, { id = itemId, uname = "Rope", hp = 3 })
                toast(player, lang.textFor(player, "Rope untied"))
            else
                triggerEvent("itemCreated", resourceRoot, itemId)
            end
        end)
    end

    local function tie(player, tower, towed, held)
        local inf, tinf = info[tower], info[towed]
        local cid = charId(player)
        if not cid then
            return
        end
        db.call("vehicle_rope_tie", { inf.id, tinf.id, held.id, cid }, function(res)
            local ok, code = res and res.ok or false, res and res.code or "DB_ERROR"
            local fields = { player = player, towed_id = tinf.id, item_id = held.id, ok = ok, code = code }
            log.event("vehicle.ropeTied", vehicleLine(tower, fields), ok and "info" or "warn")
            if not ok then
                return toast(player, "DB_ERROR")
            end
            triggerEvent("itemDestroyed", resourceRoot, held.id)
            if isElement(player) then
                exports.items:clearHeld(player)
                exports.items:refreshPlayer(player)
                toast(player, lang.textFor(player, "Rope tied: drive off gently"))
            end
            if isElement(tower) and isElement(towed) and info[tower] then
                info[tower].ropeTowId = tinf.id
                link(tower, towed)
                markUsed(towed) -- dragging it is using it: a restart must not heal it back onto the stall
            end
        end)
    end

    local function setPending(player, tower)
        pending[player] = tower and { tower = tower, since = getTickCount() } or nil
        if isElement(player) then
            triggerClientEvent(player, "vehicleRopeTieStarted", player, tower or false)
        end
    end

    local function busyHitch(v)
        return towOf[v] ~= nil or getVehicleTowedByVehicle(v) ~= false
    end

    local function hold(player, vehicle, ms, label, actionType, finish)
        cancelHoldAction(player)
        setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
        triggerClientEvent(player, "vehicleHoldStarted", player, label, ms)
        local timer = setTimer(function()
            activeActions[player] = nil
            if not isElement(player) then
                return
            end
            setPedAnimation(player, nil)
            triggerClientEvent(player, "vehicleHoldStopped", player)
            if isElement(vehicle) and info[vehicle] and not isPedDead(player) then
                finish()
            end
        end, ms, 1)
        activeActions[player] = { actionType = actionType, vehicle = vehicle, timer = timer }
    end

    local function fitTowbar(player, vehicle, held)
        local inf = info[vehicle]
        if inf.towbar then
            return toast(player, lang.textFor(player, "This vehicle already has a tow bar"))
        end
        if not vlogic.canFitTowbar(vehicleType(vehicle)) then
            return toast(player, lang.textFor(player, "A tow bar does not fit this vehicle"))
        end
        hold(player, vehicle, FIT_MS, lang.textFor(player, "Fitting tow bar"), "towbar", function()
            local cur = exports.items:getHeld(player)
            local cid = charId(player)
            if not cur or cur.id ~= held.id or not cid then
                return
            end
            db.call("vehicle_towbar_fit", { inf.id, held.id, cid }, function(res)
                local ok, code = res and res.ok or false, res and res.code or "DB_ERROR"
                local fields = { player = player, item_id = held.id, ok = ok, code = code }
                log.event("vehicle.towbarFitted", vehicleLine(vehicle, fields), ok and "info" or "warn")
                if not ok then
                    return toast(player, "DB_ERROR")
                end
                triggerEvent("itemDestroyed", resourceRoot, held.id)
                if isElement(player) then
                    exports.items:clearHeld(player)
                    exports.items:refreshPlayer(player)
                    toast(player, lang.textFor(player, "Tow bar fitted"))
                end
                if isElement(vehicle) and info[vehicle] then
                    info[vehicle].towbar = true
                    publish(vehicle)
                    rebindTow(vehicle)
                end
            end)
        end)
    end

    local function removeTowbar(player, vehicle)
        local inf = info[vehicle]
        if not inf.towbar then
            return
        end
        if busyHitch(vehicle) then
            return toast(player, lang.textFor(player, "Take the rope or trailer off the tow bar first"))
        end
        if exports.items:getHeld(player) then
            return toast(player, "HANDS_FULL")
        end
        hold(player, vehicle, REMOVE_MS, lang.textFor(player, "Removing tow bar"), "towbar", function()
            local cid = charId(player)
            if not cid then
                return
            end
            db.call("vehicle_towbar_remove", { inf.id, cid }, function(res)
                local ok, code = res and res.ok or false, res and res.code or "DB_ERROR"
                local itemId = ok and tonumber(res.payload.item_id) or nil
                local fields = { player = player, item_id = itemId, ok = ok, code = code }
                log.event("vehicle.towbarRemoved", vehicleLine(vehicle, fields), ok and "info" or "warn")
                if not ok then
                    local text = code == "HANDS_FULL" and "HANDS_FULL"
                        or code == "TOWING" and lang.textFor(player, "Take the rope or trailer off the tow bar first")
                        or "DB_ERROR"
                    return toast(player, text)
                end
                if isElement(player) then
                    exports.items:setHeld(player, { id = itemId, uname = "TowBar", hp = 5 })
                    toast(player, lang.textFor(player, "Tow bar removed"))
                end
                if isElement(vehicle) and info[vehicle] then
                    info[vehicle].towbar = false
                    publish(vehicle)
                    rebindTow(vehicle)
                end
            end)
        end)
    end

    local function ropeAt(player, vehicle, held, angle)
        if vlogic.isRear(angle) then
            -- F again at the hitch the rope is tied to takes it back off, still in hand
            local p = pending[player]
            if p and p.tower == vehicle then
                setPending(player, nil)
                return toast(player, lang.textFor(player, "Rope untied"))
            end
            if not M.hitch(vehicle) then
                return toast(player, lang.textFor(player, "Fit a tow bar to tie a rope here"))
            end
            if busyHitch(vehicle) then
                return toast(player, lang.textFor(player, "Something is already hitched there"))
            end
            setPending(player, vehicle)
            return toast(player, lang.textFor(player, "Now tie the rope to the front of another vehicle"))
        end
        if not vlogic.isFront(angle) then
            return toast(player, lang.textFor(player, "Tie the rope to a tow bar or hitch first"))
        end
        local p = pending[player]
        local tower = p and p.tower
        if not tower or not isElement(tower) or not info[tower] then
            return toast(player, lang.textFor(player, "Tie the rope to a tow bar or hitch first"))
        end
        if tower == vehicle then
            return toast(player, lang.textFor(player, "Now tie the rope to the front of another vehicle"))
        end
        if towerOf[vehicle] or towOf[vehicle] == tower then
            return toast(player, lang.textFor(player, "Something is already hitched there"))
        end
        if busyHitch(tower) then
            setPending(player, nil)
            return toast(player, lang.textFor(player, "Something is already hitched there"))
        end
        local ax, ay, az = getElementPosition(tower)
        local bx, by, bz = getElementPosition(vehicle)
        if getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz) > rope.TIE_REACH then
            return toast(player, lang.textFor(player, "The rope does not reach that far"))
        end
        setPending(player, nil)
        tie(player, tower, vehicle, held)
    end

    -- vehicleInteractRequested with a Tow Bar or a Rope in hand; true when it was one of them
    function M.interact(player, vehicle, held, angle)
        local uname = held and held.uname
        if uname ~= "TowBar" and uname ~= "Rope" then
            return false
        end
        if activeActions[player] or getPedOccupiedVehicle(player) then
            return true
        end
        if uname == "TowBar" then
            if not vlogic.isRear(angle) then
                toast(player, lang.textFor(player, "A tow bar goes on the rear"))
            else
                fitTowbar(player, vehicle, held)
            end
            return true
        end
        ropeAt(player, vehicle, held, angle)
        return true
    end

    -- the interaction list's tow actions (client/towing.lua entries): "remove_towbar", "untie_rope"
    function M.action(player, vehicle, action, angle)
        if not info[vehicle] or activeActions[player] or getPedOccupiedVehicle(player) then
            return
        end
        if action == "remove_towbar" and vlogic.isRear(angle) then
            return removeTowbar(player, vehicle)
        end
        if action == "untie_rope" then
            local tower = towOf[vehicle] and vehicle or towerOf[vehicle]
            if not tower then
                return
            end
            if exports.items:getHeld(player) then
                return toast(player, "HANDS_FULL")
            end
            untie(tower, player, "player")
        end
    end

    -- a vehicle about to go (exploded, removed, despawned): its rope, either end, falls to the ground
    function M.lost(v, reason)
        local tower = towOf[v] and v or towerOf[v]
        if tower then
            untie(tower, nil, reason)
        end
    end

    -- the hitch is taken by the rope: no trailer goes on a roped tower
    function M.roped(v)
        return towOf[v] ~= nil
    end

    -- the other end of a rope: nobody pushes it by hand
    function M.towed(v)
        return towerOf[v] ~= nil
    end

    -- snaps, stale pending ties
    setTimer(function()
        for tower, towed in pairs(towOf) do
            if not isElement(tower) or not isElement(towed) or not info[tower] or not info[towed] then
                if isElement(tower) and info[tower] then
                    untie(tower, nil, "lost")
                else
                    towOf[tower] = nil
                    towerOf[towed] = nil
                    setBrakes(towed, false)
                end
            else
                local ax, ay, az = getElementPosition(tower)
                local bx, by, bz = getElementPosition(towed)
                local apart = getDistanceBetweenPoints3D(ax, ay, az, bx, by, bz)
                local other = getElementDimension(tower) ~= getElementDimension(towed)
                if apart > rope.SNAP_DISTANCE or other then
                    untie(tower, nil, "snapped")
                end
            end
        end
        local now = getTickCount()
        for player, p in pairs(pending) do
            local held = isElement(player) and exports.items:getHeld(player)
            local px, py, pz = 0, 0, 0
            if isElement(player) then
                px, py, pz = getElementPosition(player)
            end
            local tx, ty, tz = 0, 0, 0
            if isElement(p.tower) then
                tx, ty, tz = getElementPosition(p.tower)
            end
            if
                not held
                or held.uname ~= "Rope"
                or not isElement(p.tower)
                or now - p.since > rope.PENDING_MS
                or getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz) > rope.PENDING_REACH
            then
                setPending(player, nil)
            end
        end
    end, CHECK_MS, 0)

    addEventHandler("onPlayerQuit", root, function()
        pending[source] = nil
    end)
    addEventHandler("onPlayerWasted", root, function()
        if pending[source] then
            setPending(source, nil)
        end
    end)
    addEventHandler("onVehicleEnter", resourceRoot, function()
        M.resync(source)
    end)
    addEventHandler("onVehicleExit", resourceRoot, function()
        M.resync(source)
    end)

    return M
end
