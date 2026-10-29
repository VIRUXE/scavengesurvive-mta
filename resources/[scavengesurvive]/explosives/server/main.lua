local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()

local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=explosives/" .. path))()
end

local logic = loadModule("shared/logic/explosives.lua")

local function defenceState(data)
    if type(data) ~= "table" then
        return nil
    end
    local d = data.defence or (type(data[1]) == "table" and data[1].defence)
    if type(d) == "table" and d.active == true then
        return d
    end
    return nil
end

db.connect("explosives")

local activeArming = {} -- player -> { itemId, timer }
local pendingArm = {} -- player -> { itemId, trigger }
local activeProx = {} -- colshape -> { itemId, x, y, z }
local proxByItem = {} -- itemId -> colshape
local lastArmTick = {} -- player -> tick

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function itemType(uname)
    return exports.data:itemType(uname)
end

local function decodeData(raw)
    if not raw or raw == "" or raw == "null" then
        return {}
    end
    if type(raw) == "table" then
        return raw
    end
    local val = fromJSON(raw)
    if type(val) == "table" and #val == 1 and type(val[1]) == "table" and not val[1][1] then
        return val[1]
    end
    return val or {}
end

local function encodeData(t)
    if not t or (type(t) == "table" and not next(t)) then
        return nil
    end
    local s = toJSON(t)
    return s and s:sub(2, -2) or nil
end

local function toast(player, code)
    if isElement(player) then
        triggerClientEvent(player, "toastShown", player, code)
    end
end

local function cancelArming(player)
    pendingArm[player] = nil
    local a = activeArming[player]
    if not a then
        return
    end
    if isTimer(a.timer) then
        killTimer(a.timer)
    end
    activeArming[player] = nil
    if isElement(player) then
        setPedAnimation(player)
    end
end

local detonateItem

local function armProximityMine(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end
    db.one(
        "SELECT id, x, y, z, interior, dimension FROM items "
            .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL AND x IS NOT NULL",
        { itemId },
        function(row)
            if not row or not row.x then
                return
            end
            db.exec("UPDATE items SET data = JSON_SET(COALESCE(data, '{}'), '$.armed', 1) WHERE id = ?", { itemId })
            local col = createColSphere(row.x, row.y, row.z, logic.PROX_RADIUS)
            if isElement(col) then
                setElementInterior(col, row.interior or 0)
                setElementDimension(col, row.dimension or 0)
                activeProx[col] = { itemId = row.id, x = row.x, y = row.y, z = row.z }
                proxByItem[row.id] = col
            end
        end
    )
end

local function loadArmedProxMines()
    local sql = "SELECT id, type_uname, x, y, z, interior, dimension, data FROM items "
        .. "WHERE container_id IS NULL AND holder_char_id IS NULL AND x IS NOT NULL "
        .. "AND JSON_UNQUOTE(JSON_EXTRACT(data, '$.armed')) = '1'"
    db.query(sql, {}, function(rows)
        if not rows then
            return
        end
        for _, row in ipairs(rows) do
            local t = itemType(row.type_uname)
            if t and t.explosive and t.explosive.trigger == logic.TRIGGERS.PROXIMITY then
                local col = createColSphere(row.x, row.y, row.z, logic.PROX_RADIUS)
                if isElement(col) then
                    setElementInterior(col, row.interior or 0)
                    setElementDimension(col, row.dimension or 0)
                    activeProx[col] = { itemId = row.id, x = row.x, y = row.y, z = row.z }
                    proxByItem[row.id] = col
                end
            end
        end
    end)
end
loadArmedProxMines()

addEventHandler("onColShapeHit", resourceRoot, function(hitElement, matchingDimension)
    if not matchingDimension or getElementType(hitElement) ~= "player" or isPedDead(hitElement) then
        return
    end
    local data = activeProx[source]
    if not data then
        return
    end
    activeProx[source] = nil
    proxByItem[data.itemId] = nil
    if isElement(source) then
        destroyElement(source)
    end
    outputServerLog(string.format("[EXPLOSIVE] Prox bomb %d triggered by %s", data.itemId, getPlayerName(hitElement)))
    triggerClientEvent(hitElement, "toastShown", hitElement, "PROXMIARMED")
    setTimer(detonateItem, logic.PROX_TRIGGER_DELAY_MS, 1, data.itemId)
end)

local function finishArming(player, itemId, trigger)
    if not isElement(player) then
        return
    end
    cancelArming(player)
    if trigger == logic.TRIGGERS.TIMED then
        outputServerLog(string.format("[EXPLOSIVE] Time bomb %d placed by %s", itemId, getPlayerName(player)))
        toast(player, "ARMEDBOMB5S")
        setTimer(detonateItem, logic.TIMED_FUSE_MS, 1, itemId)
    elseif trigger == logic.TRIGGERS.PROXIMITY then
        outputServerLog(string.format("[EXPLOSIVE] Prox bomb %d placed by %s", itemId, getPlayerName(player)))
        toast(player, "PROXMIARMED")
        setTimer(armProximityMine, logic.PROX_ARM_DELAY_MS, 1, itemId)
    elseif trigger == logic.TRIGGERS.MOTION then
        outputServerLog(string.format("[EXPLOSIVE] Trip bomb %d placed by %s", itemId, getPlayerName(player)))
        toast(player, "ARMEDBOMB")
        db.exec("UPDATE items SET data = JSON_SET(COALESCE(data, '{}'), '$.armed', 1) WHERE id = ?", { itemId })
    end
end

addEventHandler("itemMoved", root, function(itemId, from, to)
    local player = source
    if not isElement(player) then
        return
    end
    local pending = pendingArm[player]
    if pending and pending.itemId == itemId and from == "held" and to == "world" then
        pendingArm[player] = nil
        setPedAnimation(player, "BOMBER", "BOM_Plant_Loop", -1, true, false, false, false)
        toast(player, "ARMINGBOMB")
        local timer = setTimer(finishArming, logic.ARM_HOLD_MS, 1, player, itemId, pending.trigger)
        activeArming[player] = { itemId = itemId, timer = timer }
    end
end)

local function startArming(player, heldItem, trigger)
    if not isElement(player) or not heldItem then
        return
    end
    pendingArm[player] = { itemId = heldItem.id, trigger = trigger }
    local ok = exports.items:dropHeld(player)
    if not ok then
        pendingArm[player] = nil
    end
end

detonateItem = function(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end
    local col = proxByItem[itemId]
    if col and isElement(col) then
        activeProx[col] = nil
        proxByItem[itemId] = nil
        destroyElement(col)
    end
    db.one(
        "SELECT id, type_uname, hitpoints, data, x, y, z, interior, dimension, container_id, holder_char_id "
            .. "FROM items WHERE id = ?",
        { itemId },
        function(row)
            if not row then
                return
            end
            local t = itemType(row.type_uname)
            if not t or not t.explosive then
                return
            end
            local preset = logic.getPreset(t.explosive.preset)
            if not preset then
                return
            end

            local function executeExplosion(x, y, z, int, dim, parentPlayer, parentVehicle)
                -- Delete the detonating explosive itself wherever it is
                if row.holder_char_id and parentPlayer then
                    exports.items:destroyItem(row.id, parentPlayer)
                elseif row.container_id then
                    exports.items:destroyContainerItem(row.id)
                else
                    exports.items:destroyWorldItem(row.id)
                end

                if not x or not y or not z then
                    return
                end

                if parentPlayer and isElement(parentPlayer) then
                    killPed(parentPlayer)
                end
                if parentVehicle and isElement(parentVehicle) then
                    blowVehicle(parentVehicle)
                end

                outputServerLog(
                    string.format(
                        "[EXPLOSIVE] Item %d Type %s detonated at %f, %f, %f",
                        row.id,
                        t.explosive.trigger,
                        x,
                        y,
                        z
                    )
                )

                if preset.emp then
                    local empObj = createObject(logic.EMP_OBJECT_MODEL, x, y, z - 1.0)
                    if isElement(empObj) then
                        setElementInterior(empObj, int)
                        setElementDimension(empObj, dim)
                        setTimer(function()
                            if isElement(empObj) then
                                destroyElement(empObj)
                            end
                        end, logic.EMP_OBJECT_LIFETIME_MS, 1)
                    end
                    for _, p in ipairs(getElementsByType("player")) do
                        if getElementInterior(p) == int and getElementDimension(p) == dim then
                            local px, py, pz = getElementPosition(p)
                            if logic.isItemInRange(px, py, pz, x, y, z, preset.size) then
                                exports.character:knockOutPlayer(p, logic.EMP_KNOCKOUT_MS)
                            end
                        end
                    end
                    for _, v in ipairs(getElementsByType("vehicle")) do
                        if getElementInterior(v) == int and getElementDimension(v) == dim then
                            local vx, vy, vz = getElementPosition(v)
                            if logic.isItemInRange(vx, vy, vz, x, y, z, preset.size) then
                                setVehicleEngineState(v, false)
                            end
                        end
                    end
                elseif preset.shrapnel then
                    createExplosion(x, y, z, preset.anim)
                    for _, p in ipairs(getElementsByType("player")) do
                        if getElementInterior(p) == int and getElementDimension(p) == dim and not isPedDead(p) then
                            local px, py, pz = getElementPosition(p)
                            if logic.isItemInRange(px, py, pz, x, y, z, preset.knockRange) then
                                exports.character:knockOutPlayer(p, preset.knockDurationMs)
                            end
                            if logic.isItemInRange(px, py, pz, x, y, z, preset.bleedRange) then
                                exports.character:applyWound(p, preset.bleedRate, preset.hpLoss, nil, "Explosion")
                            end
                        end
                    end
                else
                    createExplosion(x, y, z, preset.anim)
                end

                -- World items damage
                if preset.itemDmg and preset.itemDmg > 0 then
                    local sql = "SELECT i.id, i.type_uname, i.hitpoints, i.data, i.x, i.y, i.z, i.rz, "
                        .. "i.interior, i.dimension FROM world_items_pos p JOIN items i ON i.id = p.item_id "
                        .. "WHERE ST_Distance(p.pos, POINT(?, ?)) <= ? AND i.id != ?"
                    db.query(sql, { x, y, preset.size, row.id }, function(nearby)
                        if not nearby or #nearby == 0 then
                            return
                        end
                        local inRange = logic.filterItemsInRange(nearby, x, y, z, preset.size, int, dim)
                        if #inRange == 0 then
                            return
                        end
                        local batch = {}
                        for _, it in ipairs(inRange) do
                            batch[#batch + 1] = { id = it.id, dmg = preset.itemDmg }
                        end
                        db.call("explosion_damage", { toJSON(batch) }, function(res)
                            if not res or not res.payload then
                                return
                            end
                            local payload = res.payload
                            local destroyed = payload.destroyed or {}
                            for _, it in ipairs(destroyed) do
                                exports.items:forgetWorldItem(it.id)
                                triggerEvent("itemDestroyed", resourceRoot, it.id)

                                local itType = itemType(it.uname)
                                local d = decodeData(it.data)
                                local st = defenceState(d)
                                if st then
                                    outputServerLog(
                                        string.format(
                                            "[DESTRUCTION] Defence %d (%s) Object: (%d, %f, %f, %f, %f, %f, %f)",
                                            it.id,
                                            it.uname,
                                            itType and itType.model or 0,
                                            it.x or 0,
                                            it.y or 0,
                                            it.z or 0,
                                            st.rx or 0,
                                            st.ry or 0,
                                            it.rz or 0
                                        )
                                    )
                                end
                            end
                        end)
                    end)
                end
            end

            -- Resolve position
            if row.holder_char_id then
                local foundPlayer = nil
                for _, p in ipairs(getElementsByType("player")) do
                    if charId(p) == row.holder_char_id then
                        foundPlayer = p
                        break
                    end
                end
                if foundPlayer then
                    local px, py, pz = getElementPosition(foundPlayer)
                    local pint, pdim = getElementInterior(foundPlayer), getElementDimension(foundPlayer)
                    executeExplosion(px, py, pz, pint, pdim, foundPlayer, nil)
                end
            elseif row.container_id then
                db.one(
                    "SELECT id, kind, owner_item_id, owner_vehicle_id, owner_char_id FROM containers WHERE id = ?",
                    { row.container_id },
                    function(cRow)
                        if not cRow then
                            return
                        end
                        if cRow.owner_vehicle_id then
                            local foundVeh = nil
                            for _, v in ipairs(getElementsByType("vehicle")) do
                                local vid = getElementData(v, "vehicles.id")
                                if not vid then
                                    local vehRes = getResourceFromName("vehicles")
                                    if vehRes and getResourceState(vehRes) == "running" then
                                        vid = exports.vehicles:getVehicleDbId(v)
                                    end
                                end
                                if vid == cRow.owner_vehicle_id then
                                    foundVeh = v
                                    break
                                end
                            end
                            if foundVeh then
                                local vx, vy, vz = getElementPosition(foundVeh)
                                local vint, vdim = getElementInterior(foundVeh), getElementDimension(foundVeh)
                                executeExplosion(vx, vy, vz, vint, vdim, nil, foundVeh)
                            end
                        elseif cRow.owner_char_id then
                            local foundPlayer = nil
                            for _, p in ipairs(getElementsByType("player")) do
                                if charId(p) == cRow.owner_char_id then
                                    foundPlayer = p
                                    break
                                end
                            end
                            if foundPlayer then
                                local px, py, pz = getElementPosition(foundPlayer)
                                local pint, pdim = getElementInterior(foundPlayer), getElementDimension(foundPlayer)
                                executeExplosion(px, py, pz, pint, pdim, foundPlayer, nil)
                            end
                        elseif cRow.owner_item_id then
                            db.one(
                                "SELECT x, y, z, interior, dimension FROM items WHERE id = ?",
                                { cRow.owner_item_id },
                                function(iRow)
                                    if iRow and iRow.x then
                                        executeExplosion(
                                            iRow.x,
                                            iRow.y,
                                            iRow.z,
                                            iRow.interior or 0,
                                            iRow.dimension or 0,
                                            nil,
                                            nil
                                        )
                                    end
                                end
                            )
                        end
                    end
                )
            else
                executeExplosion(row.x, row.y, row.z, row.interior or 0, row.dimension or 0, nil, nil)
            end
        end
    )
end

function checkTripMine(player, itemRow)
    if not itemRow then
        return false
    end
    local t = itemType(itemRow.type_uname or itemRow.uname)
    local d = decodeData(itemRow.data)
    if logic.isArmedTripMine(t, d) then
        outputServerLog(string.format("[EXPLOSIVE] Trip bomb %d triggered by %s", itemRow.id, getPlayerName(player)))
        detonateItem(itemRow.id)
        return true
    end
    return false
end

function linkPhoneBomb(player, itemA, itemB)
    if not isElement(player) or not itemA or not itemB then
        return false
    end
    local phone, bomb
    if itemA.uname == logic.RADIO_TRIGGER_ITEM then
        phone, bomb = itemA, itemB
    elseif itemB.uname == logic.RADIO_TRIGGER_ITEM then
        phone, bomb = itemB, itemA
    else
        return false
    end

    local bType = itemType(bomb.uname)
    if not bType or not bType.explosive or bType.explosive.trigger ~= logic.TRIGGERS.RADIO then
        return false
    end

    local phoneData = decodeData(phone.data)
    phoneData.bombId = bomb.id

    local bombData = decodeData(bomb.data)
    bombData.armed = 1

    db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(phoneData), phone.id })
    db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(bombData), bomb.id })

    local held = exports.items:getHeld(player)
    if held then
        if held.id == phone.id then
            exports.items:updateHeldData(player, phoneData)
        elseif held.id == bomb.id then
            exports.items:updateHeldData(player, bombData)
        end
    end

    setPedAnimation(player, "BOMBER", "BOM_PLANT_IN", -1, false, false, false, false)
    lastArmTick[player] = getTickCount()
    toast(player, "ARMEDRADIOB")
    return true
end

addEventHandler("itemUseAttempted", root, function(itemId, uname)
    local player = source
    local t = itemType(uname)

    if uname == logic.RADIO_TRIGGER_ITEM then
        cancelEvent()
        local now = getTickCount()
        if lastArmTick[player] and now - lastArmTick[player] < logic.RADIO_DEBOUNCE_MS then
            return
        end
        local held = exports.items:getHeld(player)
        local phoneData = (held and held.id == itemId) and decodeData(held.data) or nil
        local function checkPhone(data)
            if not data or not data.bombId then
                return toast(player, "RADIONOSYNC")
            end
            db.one("SELECT id, type_uname, data FROM items WHERE id = ?", { data.bombId }, function(bombRow)
                if not isElement(player) then
                    return
                end
                if not bombRow then
                    return toast(player, "RADIONOSYNC")
                end
                local bType = itemType(bombRow.type_uname)
                local bData = decodeData(bombRow.data)
                bombRow.data = bData
                local ok, err = logic.canRadioDetonate(data, bombRow, bType)
                if not ok then
                    return toast(player, err)
                end
                outputServerLog(
                    string.format(
                        "[EXPLOSIVE] Player %s triggering remote explosive item %d",
                        getPlayerName(player),
                        bombRow.id
                    )
                )
                data.bombId = nil
                db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(data), itemId })
                if held and held.id == itemId then
                    exports.items:updateHeldData(player, data)
                end
                toast(player, "RADIOTRIGGD")
                detonateItem(bombRow.id)
            end)
        end

        if phoneData then
            checkPhone(phoneData)
        else
            db.one("SELECT data FROM items WHERE id = ?", { itemId }, function(row)
                if isElement(player) and row then
                    checkPhone(decodeData(row.data))
                end
            end)
        end
        return
    end

    if t and t.explosive then
        cancelEvent()
        local held = exports.items:getHeld(player)
        local isHeld = held and held.id == itemId

        if isHeld then
            startArming(player, held, t.explosive.trigger)
        else
            -- If in a container and trigger is MOTION, toggle arm/disarm
            if t.explosive.trigger == logic.TRIGGERS.MOTION then
                db.one("SELECT id, data FROM items WHERE id = ?", { itemId }, function(row)
                    if not isElement(player) or not row then
                        return
                    end
                    local d = decodeData(row.data)
                    local armed = (d.armed == 1) and 0 or 1
                    d.armed = armed
                    db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(d), itemId }, function()
                        if not isElement(player) then
                            return
                        end
                        toast(player, (armed == 1) and "ARMEDBOMB" or "DISARMEDBOM")
                        exports.items:sendInventory(player)
                    end)
                end)
            end
        end
    end
end)

net.handler("holdActionCancelRequested", function(player)
    cancelArming(player)
end)

addEventHandler("onPlayerQuit", root, function()
    cancelArming(source)
    lastArmTick[source] = nil
end)

addEventHandler("onPlayerWasted", root, function()
    cancelArming(source)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(activeArming) do
        cancelArming(player)
    end
    for col in pairs(activeProx) do
        if isElement(col) then
            destroyElement(col)
        end
    end
    activeProx = {}
    proxByItem = {}
end)
