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
local plotPoleColshapes = {} -- itemId -> colshape
local activeBreaks = {} -- player -> timer
local movingDefences = {} -- itemId -> timer
local pendingSetup = {} -- player -> defence itemId
local pendingOpen = {} -- player -> defence itemId
local passCooldown = {} -- player -> duration in ms (cooldown)
local passFails = {} -- player -> fail count
local lastPassEntry = {} -- player -> timestamp (tick count)

local DEFENCE_ROW = "SELECT id, type_uname, data, x, y, z, rz, interior, dimension FROM items "
    .. "WHERE id = ? AND container_id IS NULL AND holder_char_id IS NULL"

local function charId(player)
    return exports.character:getCharacterId(player)
end

local function heldUname(player)
    local held = exports.items:getHeld(player)
    return held and held.uname
end

-- upstream defences.pwn plays COP_AMBIENT/COPBROWSE_LOOP while a defence is built, modified or removed, and clears
-- it when the hold stops
local function cancelBreak(player)
    if activeBreaks[player] and isTimer(activeBreaks[player]) then
        killTimer(activeBreaks[player])
        if isElement(player) then
            setPedAnimation(player)
        end
    end
    activeBreaks[player] = nil
end

addEventHandler("onPlayerQuit", root, function()
    cancelBreak(source)
    pendingSetup[source] = nil
    pendingOpen[source] = nil
    passCooldown[source] = nil
    passFails[source] = nil
    lastPassEntry[source] = nil
end)

addEventHandler("characterDied", root, function()
    cancelBreak(source)
    pendingSetup[source] = nil
    pendingOpen[source] = nil
    passCooldown[source] = nil
    passFails[source] = nil
    lastPassEntry[source] = nil
end)

net.handler("holdActionCancelRequested", function(player)
    cancelBreak(player)
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

-- nudging a built defence or a constructed item (server/tweak.lua, #133)
local tweak = loadModule("server/tweak.lua")({
    db = db,
    net = net,
    util = util,
    defences = defences,
    tweak = loadModule("shared/logic/tweak.lua"),
    decodeData = decodeData,
    toast = toast,
    DEFENCE_ROW = DEFENCE_ROW,
})

local function isPasscodeUnset(passcode)
    if not passcode or passcode == "" then
        return true
    end
    local n = tonumber(passcode)
    return n == nil or n == 0
end

local function isPlayerNearDefence(player, row, maxDist)
    if not isElement(player) or not row then
        return false
    end
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > (maxDist or 3.0) then
        return false
    end
    if getElementInterior(player) ~= (row.interior or 0) then
        return false
    end
    if getElementDimension(player) ~= (row.dimension or 0) then
        return false
    end
    return true
end

local function holdDefenceAction(player, row, tool, label, ms, finish)
    cancelBreak(player)
    triggerClientEvent(player, "vehicleHoldStarted", player, label, ms)
    setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
    activeBreaks[player] = setTimer(function(pl, itemId, x, y, z)
        activeBreaks[pl] = nil
        if not isElement(pl) then
            return
        end
        setPedAnimation(pl)
        if heldUname(pl) ~= tool then
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

local function moveDefence(itemId, player)
    itemId = tonumber(itemId)
    if not itemId then
        return
    end
    if isTimer(movingDefences[itemId]) then
        return
    end
    movingDefences[itemId] = setTimer(function(id, pl)
        movingDefences[id] = nil
        db.one(DEFENCE_ROW, { id }, function(row, c)
            if not row then
                return
            end
            local d = decodeData(row.data)
            local st = defences.state(d)
            local t = exports.data:itemType(row.type_uname)
            if not st or not (t and t.defence) then
                return
            end

            -- Upstream MoveDefence: after 1500 ms, if any player is within 4.0 of the item retry 1500 ms later
            local itemInt = row.interior or 0
            local itemDim = row.dimension or 0
            for _, p in ipairs(getElementsByType("player")) do
                if getElementInterior(p) == itemInt and getElementDimension(p) == itemDim then
                    local px, py, pz = getElementPosition(p)
                    if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) < 4.0 then
                        moveDefence(id, c.player)
                        return
                    end
                end
            end

            -- otherwise toggle pose vertical<->horizontal
            local newZ, newRz, newSt = defences.toggle(t.defence, st, row.z, row.rz)
            d.defence = newSt
            db.exec(
                "UPDATE items SET z = ?, rz = ?, data = ? WHERE id = ? AND x IS NOT NULL",
                { newZ, newRz, encodeData(d), row.id },
                function()
                    exports.items:resendWorldItem(row.id)
                    local poseLabel = (newSt.pose == "vertical") and "CLOSED" or "OPEN"
                    local pName = isElement(c.player) and getPlayerName(c.player) or "unknown"
                    util.log(
                        "building",
                        "info",
                        "[DEFMOVE] Player %s moved defence %d (%s) into %s position at %.1f, %.1f, %.1f",
                        pName,
                        row.id,
                        row.type_uname,
                        poseLabel,
                        row.x,
                        row.y,
                        newZ
                    )
                end
            )
        end, { player = pl })
    end, 1500, 1, itemId, player)
end

-- upstream largeframe.pwn: the covering goes on or comes off; it is part of the built state, so it stays across a
-- restart (upstream's OnDefenceLoad) and goes with the defence when a Crowbar takes it down
local function toggleCovering(itemId)
    db.one(DEFENCE_ROW, { itemId }, function(row)
        local d = row and decodeData(row.data)
        local st = d and defences.state(d)
        if not st then
            return
        end
        d.defence = defences.toggleCovering(st)
        db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(d), row.id }, function()
            exports.items:resendWorldItem(row.id)
        end)
    end)
end

local function handleDefenceInteract(player, row)
    local cid = charId(player)
    if not cid then
        return
    end
    local d = decodeData(row.data)
    local st = defences.state(d)
    if not st then
        return
    end
    local t = exports.data:itemType(row.type_uname or row.uname)
    if not (t and t.defence) then
        return
    end

    local held = exports.items:getHeld(player)
    local tool = held and held.uname

    local px, py = getElementPosition(player)
    local isBehind = defences.isBehind(t.defence, row.rz, row.x, row.y, px, py, st.pose)

    -- 1. Installing a Motor: works only from the back side
    if tool == "Motor" and isBehind then
        if not t.defence.movable then
            return toast(player, "DEFNOTMOVAB")
        end
        local ms = exports.character:skillTimeModifier(player, 6000, "Construction")
        holdDefenceAction(player, row, "Motor", "Modifying " .. t.name, ms, function(pl, cur)
            local curData = decodeData(cur.data)
            local curSt = defences.state(curData)
            if not curSt then
                return
            end
            local curHeld = exports.items:getHeld(pl)
            if not curHeld or curHeld.uname ~= "Motor" then
                return
            end
            curSt.motor = true
            curData.defence = curSt
            exports.items:destroyItem(curHeld.id, pl)
            db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(curData), cur.id }, function()
                exports.items:resendWorldItem(cur.id)
                if isElement(pl) then
                    exports.character:gainSkill(pl, "Construction")
                    toast(pl, "DEFINSTMOTO")
                end
            end)
        end)
        return
    end

    -- 2. Installing a Keypad or AdvancedKeypad: works only from the back side
    if (tool == "Keypad" or tool == "AdvancedKeypad") and isBehind then
        if not st.motor then
            return toast(player, "DEFNEEDMOTO")
        end
        local keypadType = (tool == "AdvancedKeypad") and 2 or 1
        local toastCode = (tool == "AdvancedKeypad") and "DEFINSTADKP" or "DEFINSTKEYP"
        local ms = exports.character:skillTimeModifier(player, 6000, "Construction")
        holdDefenceAction(player, row, tool, "Modifying " .. t.name, ms, function(pl, cur)
            local curData = decodeData(cur.data)
            local curSt = defences.state(curData)
            if not curSt then
                return
            end
            local curHeld = exports.items:getHeld(pl)
            if not curHeld or curHeld.uname ~= tool then
                return
            end
            curSt.keypad = keypadType
            curData.defence = curSt
            exports.items:destroyItem(curHeld.id, pl)
            db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(curData), cur.id }, function()
                exports.items:resendWorldItem(cur.id)
                if isElement(pl) then
                    exports.character:gainSkill(pl, "Construction")
                    toast(pl, toastCode)
                    pendingSetup[pl] = cur.id
                    triggerClientEvent(pl, "keypadOpened", pl, cur.id, true)
                end
            end)
        end)
        return
    end

    -- 3. Interacting (empty hand / any other item, or Motor/Keypad from front)
    if defences.isCoverable(row.type_uname or row.uname) then
        toggleCovering(row.id)
    end
    if not st.motor then
        -- Without a motor, interacting does nothing beyond upstream (no swing)
        return
    end

    if st.keypad then
        if isPasscodeUnset(st.passcode) then
            -- keypad installed and no passcode set (nil, "", "0000", or 0) -> setup UI
            pendingSetup[player] = row.id
            triggerClientEvent(player, "keypadOpened", player, row.id, true)
        else
            -- keypad + passcode -> enter-passcode UI
            pendingOpen[player] = row.id
            triggerClientEvent(player, "keypadOpened", player, row.id, false)
        end
    else
        -- No keypad -> toast DEFMOVINGIT and move
        toast(player, "DEFMOVINGIT")
        moveDefence(row.id, player)
    end
end

-- Makes a lying item a built defence (upstream ConvertItemToDefenceItem): the pose's rotation and height, no despawn
-- timer, no longer a loot spawn's item; done(z, rz, data) once the row is written
local function activateDefence(row, t, pose, done)
    local z, rz, st = defences.build(t.defence, pose, row.z, row.rz, t.rotz)
    local d = decodeData(row.data)
    d.defence = st
    local sql = "UPDATE items SET z = ?, rz = ?, data = ?, despawn_at = NULL, loot_spawn_id = NULL "
        .. "WHERE id = ? AND x IS NOT NULL"
    db.exec(sql, { z, rz, encodeData(d), row.id }, function()
        exports.items:resendWorldItem(row.id)
        local where = string.format("%f, %f, %f rz %f", row.x, row.y, z, rz)
        util.log("building", "info", "built defence %d (%s, %s) at %s", row.id, row.type_uname, st.pose, where)
        done(z, rz, d)
    end)
end

-- Building and taking down defences (upstream StartBuildingDefence and the crowbar in _InteractDefenceWithItem).
-- Reached from items' interact key with a Hammer, Screwdriver or Crowbar in hand next to a defence item. Both re-check
-- the tool, the distance and the row when the hold ends, so walking off or swapping tools cancels.
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
            activateDefence(cur, t, c.pose, function(z, rz, d)
                if isElement(pl) then
                    exports.character:gainSkill(pl, "Construction")
                    toast(pl, "DEFENCE_BUILT")
                    -- upstream: the builder then nudges it into place, the arrow showing its front
                    cur.z, cur.rz, cur.data = z, rz, d
                    tweak.start(pl, cur, true)
                end
            end)
        end)
    end, { player = player, tool = tool, pose = pose })
end

-- crafting's ground construction (upstream SetCraftSetConstructible tweak = true): the finished item is tweaked
-- where it was built; a built defence also gets the arrow. With a pose (a set marked .defence = true) the item is
-- made a defence in that pose first.
function tweakItem(player, itemId, pose)
    itemId = tonumber(itemId)
    if not charId(player) or not itemId then
        return false
    end
    db.one(DEFENCE_ROW, { itemId }, function(row, c)
        if not row or not isElement(c.player) then
            return
        end
        local t = exports.data:itemType(row.type_uname)
        local built = t and t.defence and defences.state(decodeData(row.data)) ~= nil
        if c.pose and t and t.defence and not built then
            return activateDefence(row, t, c.pose, function(z, rz, d)
                if isElement(c.player) then
                    row.z, row.rz, row.data = z, rz, d
                    tweak.start(c.player, row, true)
                end
            end)
        end
        tweak.start(c.player, row, built == true)
    end, { player = player, pose = pose })
    return true
end

function finishTweak(player)
    return tweak.commit(player)
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
        local d = decodeData(row.data)
        local st = defences.state(d)
        if not (t and t.defence and st) then
            return
        end
        local px, py, pz = getElementPosition(c.player)
        if getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z) > 3.0 then
            return
        end
        if not defences.isBehind(t.defence, row.rz, row.x, row.y, px, py, st.pose) then
            return toast(c.player, "DEFENCE_FRONT")
        end
        local ms = exports.character:skillTimeModifier(c.player, defences.REMOVE_MS, "Construction")
        holdDefenceAction(c.player, row, "Crowbar", "Removing " .. t.name, ms, function(pl, cur)
            local curData = decodeData(cur.data)
            local curSt = defences.state(curData)
            if not curSt then
                return
            end
            if movingDefences[cur.id] and isTimer(movingDefences[cur.id]) then
                killTimer(movingDefences[cur.id])
                movingDefences[cur.id] = nil
            end
            local z, rz = defences.unbuild(t.defence, curSt, cur.z, cur.rz, t.rotz)
            curData.defence = nil
            curData.keypad = nil
            curData.passcode = nil
            db.exec(
                "UPDATE items SET z = ?, rz = ?, data = ? WHERE id = ? AND x IS NOT NULL",
                { z, rz, encodeData(curData), cur.id },
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
    db.one(DEFENCE_ROW, { itemId }, function(row, c)
        if not isElement(c.player) or not row then
            return
        end
        local px, py, pz = getElementPosition(c.player)
        local d = getDistanceBetweenPoints3D(px, py, pz, row.x, row.y, row.z)
        if d > 3.0 then
            return
        end
        handleDefenceInteract(c.player, row)
    end, { player = player })
end, { rate = 3 })

net.handler("keypadSubmitted", function(player, defenceId, enteredCode)
    local cid = charId(player)
    defenceId = tonumber(defenceId)
    if not cid or not defenceId then
        return
    end

    if pendingOpen[player] ~= defenceId then
        return
    end

    -- Throttle check: upstream def_LastPassEntry / def_Cooldown
    local now = getTickCount()
    local cooldown = passCooldown[player] or 2000
    local lastEntry = lastPassEntry[player] or 0
    if now - lastEntry < cooldown then
        return
    end

    db.one(DEFENCE_ROW, { defenceId }, function(row, c)
        if not isElement(c.player) or not row then
            return
        end
        -- Distance, interior, dimension check: must be near the defence
        if not isPlayerNearDefence(c.player, row, 3.0) then
            return
        end

        local d = decodeData(row.data)
        local st = defences.state(d)
        if not st or not st.motor or not st.keypad then
            return
        end

        if defences.verifyPasscode(st.passcode, c.enteredCode) then
            -- Reset cooldown and fails on correct code
            passCooldown[c.player] = nil
            passFails[c.player] = nil
            lastPassEntry[c.player] = nil
            pendingOpen[c.player] = nil

            triggerClientEvent(c.player, "keypadClosed", c.player)
            toast(c.player, "DEFMOVINGIT")
            moveDefence(row.id, c.player)
        else
            -- Upstream wrong-code throttle: after 5 fails, cooldown grows by 4000 ms
            local fails = (passFails[c.player] or 0) + 1
            if fails >= 5 then
                passCooldown[c.player] = cooldown + 4000
                passFails[c.player] = 0
            else
                passFails[c.player] = fails
                passCooldown[c.player] = 2000
            end
            lastPassEntry[c.player] = getTickCount()

            toast(c.player, "WRONG_PASSCODE")
            util.log(
                "building",
                "info",
                "[DEFFAIL] Player %s failed defence %d (%s) keypad code %s",
                getPlayerName(c.player),
                row.id,
                row.type_uname,
                tostring(c.enteredCode)
            )
        end
    end, { player = player, enteredCode = enteredCode })
end, { rate = 3 })

net.handler("keypadInstallRequested", function(player, defenceId, newPasscode)
    local cid = charId(player)
    defenceId = tonumber(defenceId)
    if not cid or not defenceId or not newPasscode then
        return
    end
    -- Must have a pending setup for this defence id
    if pendingSetup[player] ~= defenceId then
        return
    end
    pendingSetup[player] = nil

    db.one(DEFENCE_ROW, { defenceId }, function(row, c)
        if not isElement(c.player) or not row then
            return
        end
        -- Distance, interior, dimension check: must be near the defence
        if not isPlayerNearDefence(c.player, row, 3.0) then
            return
        end
        local d = decodeData(row.data)
        local st = defences.state(d)
        -- Defence must be built with a keypad
        if not st or not st.keypad then
            return
        end
        -- Passcode must be unset or "0000" / 0
        if not isPasscodeUnset(st.passcode) then
            return
        end

        local codeNum = tonumber(c.newPasscode) or 0
        st.passcode = string.format("%04d", codeNum)
        d.defence = st
        db.exec("UPDATE items SET data = ? WHERE id = ?", { encodeData(d), row.id }, function()
            exports.items:resendWorldItem(row.id)
            if isElement(c.player) then
                toast(c.player, "KEYPAD_INSTALLED")
                if codeNum == 0 then
                    toast(c.player, "DEFCODEZERO")
                end
            end
        end)
    end, { player = player, newPasscode = newPasscode })
end, { rate = 3 })

-- Plot Pole Colshapes
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
    for _, timer in pairs(movingDefences) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    movingDefences = {}
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

util.log("building", "info", "building system initialized")
