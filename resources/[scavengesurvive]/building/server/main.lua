-- Server-side building interactions, defences, keypads, and plot poles.
-- Ported from upstream Scavenge & Survive (core/itemtype/defences.pwn, core/item/plot-pole.pwn).
local db = assert(loadstring(exports.lib:getModule("db"), "=lib/db.lua"))()
local net = assert(loadstring(exports.lib:getModule("net"), "=lib/net.lua"))()
local util = assert(loadstring(exports.lib:getModule("util"), "=lib/util.lua"))()
db.connect("building")

local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=building/" .. path))()
end

local defences = loadModule("shared/logic/defences.lua")
local autoCloseTimers = {} -- itemId -> timer
local plotPoleColshapes = {} -- itemId -> colshape
local activeBreaks = {} -- player -> timer

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function cancelBreak(player)
    if activeBreaks[player] and isTimer(activeBreaks[player]) then
        killTimer(activeBreaks[player])
    end
    activeBreaks[player] = nil
end

addEventHandler("onPlayerQuit", root, function()
    cancelBreak(source)
end)

addEventHandler("characterDied", root, function()
    cancelBreak(source)
end)

local function toast(player, code)
    triggerClientEvent(player, "toastShown", player, code)
end

local function decodeData(data)
    if not data or data == "" or data == false then
        return {}
    end
    if type(data) == "table" then
        return data
    end
    if type(data) == "string" then
        local t = fromJSON(data)
        return type(t) == "table" and t or {}
    end
    return {}
end

local function encodeData(t)
    return toJSON(t, true)
end

local function setDoorOpenState(itemRow, isOpen, cb)
    local d = decodeData(itemRow.data)
    d.open = isOpen
    local baseRz = tonumber(d.baseRz) or tonumber(itemRow.rz) or 0
    d.baseRz = baseRz
    local newRz = defences.calculateDoorRotation(baseRz, isOpen)
    db.exec("UPDATE items SET rz = ?, data = ? WHERE id = ?", { newRz, encodeData(d), itemRow.id }, function()
        exports.items:resendWorldItem(itemRow.id) -- the sync only resends rows a client lacks (#73)
        if cb then
            cb(newRz)
        end
    end)
end

local function handleDefenceInteract(player, row)
    local cid = charId(player)
    if not cid then
        return
    end
    local held = exports.items:getHeld(player)
    local heldUname = held and held.uname
    local d = decodeData(row.data)

    -- 1. Installing a Keypad
    if heldUname == "Keypad" then
        if d.keypad then
            return toast(player, "KEYPAD_ALREADY")
        end
        exports.items:destroyItem(held.id, player)
        return triggerClientEvent(player, "keypadOpened", player, row.id, true)
    end

    -- 2. Lock breaking with LockBreaker
    if heldUname == "LockBreaker" and (d.keypad or d.passcode) then
        triggerClientEvent(player, "vehicleHoldStarted", player, "Breaking lock", 10000)
        local timer = setTimer(function(pl, itId)
            activeBreaks[pl] = nil
            if not isElement(pl) then
                return
            end
            db.one("SELECT id, type_uname, data, rz FROM items WHERE id = ?", { itId }, function(itRow, c)
                if not itRow or not isElement(c.player) then
                    return
                end
                local curD = decodeData(itRow.data)
                curD.keypad = nil
                curD.passcode = nil
                setDoorOpenState(itRow, true, function()
                    exports.items:refreshPlayer(c.player)
                    toast(c.player, "LOCKBROKEN")
                end)
            end, { player = pl })
        end, 10000, 1, player, row.id)
        activeBreaks[player] = timer
        return
    end

    -- 3. Hacking with HackDevice
    if heldUname == "HackDevice" and d.keypad then
        triggerClientEvent(player, "vehicleHoldStarted", player, "Hacking keypad", 8000)
        local timer = setTimer(function(pl, itId)
            activeBreaks[pl] = nil
            if not isElement(pl) then
                return
            end
            db.one("SELECT id, type_uname, data, rz FROM items WHERE id = ?", { itId }, function(itRow, c)
                if not itRow or not isElement(c.player) then
                    return
                end
                setDoorOpenState(itRow, true, function()
                    exports.items:refreshPlayer(c.player)
                    toast(c.player, "KEYPAD_HACKED")
                    if isTimer(autoCloseTimers[itId]) then
                        killTimer(autoCloseTimers[itId])
                    end
                    autoCloseTimers[itId] = setTimer(function(closingId)
                        autoCloseTimers[closingId] = nil
                        db.one("SELECT id, type_uname, data, rz FROM items WHERE id = ?", { closingId }, function(clRow)
                            if clRow then
                                setDoorOpenState(clRow, false, function()
                                    for _, p in ipairs(getElementsByType("player")) do
                                        exports.items:refreshPlayer(p)
                                    end
                                end)
                            end
                        end)
                    end, 10000, 1, itId)
                end)
            end, { player = pl })
        end, 8000, 1, player, row.id)
        activeBreaks[player] = timer
        return
    end

    -- 4. Locked with Keypad
    if d.keypad and d.passcode and d.passcode ~= "" then
        return triggerClientEvent(player, "keypadOpened", player, row.id, false)
    end

    -- 5. Normal door/gate open/close toggle (rows from items' nearest-item search name the type `uname`)
    if defences.isDoorOrGate(row.type_uname or row.uname) then
        local willOpen = (d.open ~= true)
        setDoorOpenState(row, willOpen, function()
            exports.items:refreshPlayer(player)
            toast(player, willOpen and "DOOR_OPENED" or "DOOR_CLOSED")
            if willOpen then
                if isTimer(autoCloseTimers[row.id]) then
                    killTimer(autoCloseTimers[row.id])
                end
                autoCloseTimers[row.id] = setTimer(function(itId)
                    autoCloseTimers[itId] = nil
                    db.one("SELECT id, type_uname, data, rz FROM items WHERE id = ?", { itId }, function(itRow)
                        if itRow then
                            setDoorOpenState(itRow, false, function()
                                for _, p in ipairs(getElementsByType("player")) do
                                    exports.items:refreshPlayer(p)
                                end
                            end)
                        end
                    end)
                end, 5000, 1, row.id)
            end
        end)
    end
end

-- Building and taking down defences (upstream StartBuildingDefence and the crowbar in _InteractDefenceWithItem).
-- Reached from items' interact key with a Hammer, Screwdriver or Crowbar in hand next to a defence item. Both re-check
-- the tool, the distance and the row when the hold ends, so walking off or swapping tools cancels.
local DEFENCE_ROW = "SELECT id, type_uname, data, x, y, z, rz FROM items "
    .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL"

local function heldUname(player)
    local held = exports.items:getHeld(player)
    return held and held.uname
end

local function holdDefenceAction(player, row, tool, label, ms, finish)
    cancelBreak(player)
    triggerClientEvent(player, "vehicleHoldStarted", player, label, ms)
    activeBreaks[player] = setTimer(function(pl, itemId, x, y, z)
        activeBreaks[pl] = nil
        if not isElement(pl) or heldUname(pl) ~= tool then
            return
        end
        local px, py, pz = getElementPosition(pl)
        if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > 3.5 then
            return
        end
        db.one(DEFENCE_ROW, { itemId }, function(cur, c)
            if cur and isElement(c.player) then
                finish(c.player, cur)
            end
        end, { player = pl })
    end, ms, 1, player, row.id, row.x, row.y, row.z)
end

function buildDefence(player, itemId)
    local tool = heldUname(player)
    local pose = defences.TOOL_POSE[tool]
    itemId = tonumber(itemId)
    if not charId(player) or not pose or not itemId then
        return
    end
    db.one(DEFENCE_ROW, { itemId }, function(row, c)
        if not row or not isElement(c.player) then
            return
        end
        local t = exports.data:itemType(row.type_uname)
        if not (t and t.defence) or defences.state(decodeData(row.data)) then
            return
        end
        local px, py, pz = getElementPosition(c.player)
        if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > 3.0 then
            return
        end
        local ms = exports.character:skillTimeModifier(c.player, defences.BUILD_MS, "Construction")
        holdDefenceAction(c.player, row, c.tool, "Building " .. t.name, ms, function(pl, cur)
            if defences.state(decodeData(cur.data)) then
                return
            end
            local z, rz, st = defences.build(t.defence, c.pose, cur.z, cur.rz, t.rotz)
            local d = decodeData(cur.data)
            d.defence = st
            -- a built defence stays: no despawn timer, no longer a loot spawn's item
            db.exec(
                "UPDATE items SET z = ?, rz = ?, data = ?, despawn_at = NULL, loot_spawn_id = NULL "
                    .. "WHERE id = ? AND x IS NOT NULL",
                { z, rz, encodeData(d), cur.id },
                function()
                    exports.items:resendWorldItem(cur.id)
                    util.log(
                        "building",
                        "info",
                        "built defence %d (%s, %s) at %f, %f, %f rz %f",
                        cur.id,
                        cur.type_uname,
                        st.pose,
                        cur.x,
                        cur.y,
                        z,
                        rz
                    )
                    if isElement(pl) then
                        exports.character:gainSkill(pl, "Construction")
                        toast(pl, "DEFENCE_BUILT")
                    end
                end
            )
        end)
    end, { player = player, tool = tool, pose = pose })
end

function removeDefence(player, itemId)
    itemId = tonumber(itemId)
    if not charId(player) or heldUname(player) ~= "Crowbar" or not itemId then
        return
    end
    db.one(DEFENCE_ROW, { itemId }, function(row, c)
        if not row or not isElement(c.player) then
            return
        end
        local t = exports.data:itemType(row.type_uname)
        if not (t and t.defence and defences.state(decodeData(row.data))) then
            return
        end
        local px, py, pz = getElementPosition(c.player)
        if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > 3.0 then
            return
        end
        if not defences.isBehind(t.defence, row.rz, row.x, row.y, px, py) then
            return toast(c.player, "DEFENCE_FRONT")
        end
        local ms = exports.character:skillTimeModifier(c.player, defences.REMOVE_MS, "Construction")
        holdDefenceAction(c.player, row, "Crowbar", "Removing " .. t.name, ms, function(pl, cur)
            local d = decodeData(cur.data)
            local st = defences.state(d)
            if not st then
                return
            end
            local z, rz = defences.unbuild(t.defence, st, cur.z, cur.rz, t.rotz)
            d.defence = nil
            db.exec(
                "UPDATE items SET z = ?, rz = ?, data = ? WHERE id = ? AND x IS NOT NULL",
                { z, rz, encodeData(d), cur.id },
                function()
                    exports.items:resendWorldItem(cur.id)
                    if isElement(pl) then
                        toast(pl, "DEFENCE_REMOVED")
                    end
                end
            )
            -- upstream's [CROWBAR] line, kept so a wrongly broken base can be put back
            util.log(
                "building",
                "info",
                "%s removed defence %d (%s) at %f, %f, %f",
                getPlayerName(pl),
                cur.id,
                cur.type_uname,
                cur.x,
                cur.y,
                cur.z
            )
        end)
    end, { player = player })
end

net.handler("buildingInteractRequested", function(player, itemId)
    local cid = charId(player)
    itemId = tonumber(itemId)
    if not cid or not itemId then
        return
    end
    db.one(
        "SELECT id, type_uname, data, x, y, z, rz FROM items "
            .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { itemId },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local px, py, pz = getElementPosition(c.player)
            local d = getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z)
            if d > 3.0 then
                return
            end
            handleDefenceInteract(c.player, row)
        end,
        { player = player }
    )
end, { rate = 3 })

net.handler("keypadSubmitted", function(player, defenceId, enteredCode)
    local cid = charId(player)
    defenceId = tonumber(defenceId)
    if not cid or not defenceId then
        return
    end
    db.one(
        "SELECT id, type_uname, data, x, y, z, rz FROM items "
            .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { defenceId },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local d = decodeData(row.data)
            if defences.verifyPasscode(d.passcode, c.enteredCode) then
                triggerClientEvent(c.player, "keypadClosed", c.player)
                setDoorOpenState(row, true, function()
                    exports.items:refreshPlayer(c.player)
                    toast(c.player, "ACCESS_GRANTED")
                    if isTimer(autoCloseTimers[row.id]) then
                        killTimer(autoCloseTimers[row.id])
                    end
                    autoCloseTimers[row.id] = setTimer(function(itId)
                        autoCloseTimers[itId] = nil
                        db.one("SELECT id, type_uname, data, rz FROM items WHERE id = ?", { itId }, function(itRow)
                            if itRow then
                                setDoorOpenState(itRow, false, function()
                                    for _, p in ipairs(getElementsByType("player")) do
                                        exports.items:refreshPlayer(p)
                                    end
                                end)
                            end
                        end)
                    end, 5000, 1, row.id)
                end)
            else
                toast(c.player, "WRONG_PASSCODE")
            end
        end,
        { player = player, enteredCode = enteredCode }
    )
end, { rate = 3 })

net.handler("keypadInstallRequested", function(player, defenceId, newPasscode)
    local cid = charId(player)
    defenceId = tonumber(defenceId)
    if not cid or not defenceId or not newPasscode then
        return
    end
    db.one(
        "SELECT id, type_uname, data, x, y, z, rz FROM items "
            .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { defenceId },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local d = decodeData(row.data)
            d.keypad = true
            d.passcode = string.format("%04d", tonumber(c.newPasscode) or 0)
            db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(d), row.id }, function()
                if isElement(c.player) then
                    toast(c.player, "KEYPAD_INSTALLED")
                end
            end)
        end,
        { player = player, newPasscode = newPasscode }
    )
end, { rate = 3 })

-- 6. Plot Pole Colshapes
local function refreshPlotPoles()
    db.query(
        "SELECT id, x, y, z, interior, dimension FROM items "
            .. "WHERE type_uname = 'PlotPole' AND container_id IS NULL AND holder_char_id IS NULL",
        {},
        function(rows)
            if not rows then
                return
            end
            local activeIds = {}
            for _, r in ipairs(rows) do
                activeIds[r.id] = true
                if not plotPoleColshapes[r.id] then
                    local col = createColSphere(r.x, r.y, r.z, 20.0)
                    if col then
                        setElementInterior(col, r.interior or 0)
                        setElementDimension(col, r.dimension or 0)
                        setElementData(col, "plotpole.id", r.id, false)
                        addEventHandler("onColShapeHit", col, function(elem, matchingDim)
                            if matchingDim and getElementType(elem) == "player" then
                                toast(elem, "PLOTPOLEENT")
                            end
                        end)
                        addEventHandler("onColShapeLeave", col, function(elem, matchingDim)
                            if matchingDim and getElementType(elem) == "player" then
                                toast(elem, "PLOTPOLEEXT")
                            end
                        end)
                        plotPoleColshapes[r.id] = col
                    end
                end
            end
            for id, col in pairs(plotPoleColshapes) do
                if not activeIds[id] then
                    if isElement(col) then
                        destroyElement(col)
                    end
                    plotPoleColshapes[id] = nil
                end
            end
        end
    )
end

setTimer(refreshPlotPoles, 5000, 0)
addEventHandler("onResourceStart", resourceRoot, refreshPlotPoles)

addEventHandler("onResourceStop", resourceRoot, function()
    for _, col in pairs(plotPoleColshapes) do
        if isElement(col) then
            destroyElement(col)
        end
    end
    plotPoleColshapes = {}
end)

function isInsideAnyPlotPole(x, y)
    for _, col in pairs(plotPoleColshapes) do
        if isElement(col) then
            local cx, cy = getElementPosition(col)
            if defences.isInsidePlotPole(x, y, cx, cy, 20.0) then
                return true
            end
        end
    end
    return false
end

function interactDefence(player, row)
    return handleDefenceInteract(player, row)
end

function submitPasscode(player, defenceId, enteredCode)
    defenceId = tonumber(defenceId)
    if not defenceId or not enteredCode then
        return false
    end
    db.one(
        "SELECT id, type_uname, data, x, y, z, rz FROM items "
            .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { defenceId },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local d = decodeData(row.data)
            local expected = d.passcode
            if expected and string.format("%04d", tonumber(c.enteredCode) or 0) == expected then
                setDoorOpenState(row, true, function()
                    exports.items:refreshPlayer(c.player)
                    toast(c.player, "ACCESS_GRANTED")
                    if isTimer(autoCloseTimers[row.id]) then
                        killTimer(autoCloseTimers[row.id])
                    end
                    autoCloseTimers[row.id] = setTimer(function(itId)
                        autoCloseTimers[itId] = nil
                        db.one("SELECT id, type_uname, data, rz FROM items WHERE id = ?", { itId }, function(clRow)
                            if clRow then
                                setDoorOpenState(clRow, false, function()
                                    for _, p in ipairs(getElementsByType("player")) do
                                        exports.items:refreshPlayer(p)
                                    end
                                end)
                            end
                        end)
                    end, 5000, 1, row.id)
                end)
            else
                toast(c.player, "WRONG_PASSCODE")
            end
        end,
        { player = player, enteredCode = enteredCode }
    )
    return true
end

function installKeypad(player, defenceId, newPasscode)
    defenceId = tonumber(defenceId)
    if not defenceId or not newPasscode then
        return false
    end
    db.one(
        "SELECT id, type_uname, data, x, y, z, rz FROM items "
            .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL",
        { defenceId },
        function(row, c)
            if not isElement(c.player) or not row then
                return
            end
            local d = decodeData(row.data)
            d.keypad = true
            d.passcode = string.format("%04d", tonumber(c.newPasscode) or 0)
            db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(d), row.id }, function()
                if isElement(c.player) then
                    toast(c.player, "KEYPAD_INSTALLED")
                end
            end)
        end,
        { player = player, newPasscode = newPasscode }
    )
    return true
end

util.log("building", "info", "building system initialized")
