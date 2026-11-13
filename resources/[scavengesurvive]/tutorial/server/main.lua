-- The tutorial (upstream core/player/tutorial.pwn): an account that has not completed it is put in a private
-- dimension on every spawn, with a kit of tools, a damaged Bobcat and a help tip for each thing it tries. It cannot
-- leave until the Bobcat has been repaired, refuelled and driven once; dying there only revives it, and leaving the
-- game puts it back in on the next spawn. Once completed (accounts.tutorial_done) it is never entered again, and
-- /tutorial takes the player out.
--
-- The tutorial character is a real one (items and vehicles are database rows). character.realPosition keeps the
-- dimension out of its saved position, tutorial.active stops its death, and tutorial_cleanup deletes what it holds.
-- luacheck: globals isInTutorial
-- luacheck: read_globals getVehicleDoorState getVehicleDoorOpenRatio getVehicleWheelStates getVehicleEngineState
-- luacheck: read_globals getVehicleController removeElementData
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
local net = loadstring(exports.lib:getModule("net"), "=lib/net.lua")()
local util = loadstring(exports.lib:getModule("util"), "=lib/util.lua")()
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()

local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=tutorial/" .. path))()
end
local logic = loadFile("shared/logic/tutorial.lua")

-- luacheck: push ignore 631
-- lang:begin
local GOAL = "To leave the tutorial, repair the Bobcat, change its flat tyres, fill its tank and drive it."
local COMPLETE = "Tutorial complete! Type /tutorial to leave it."
local DONE = "You have already completed the tutorial."
local DASHBOARD_TIP =
    "The dashboard: BAT lights when the battery is low, CHK when the engine is damaged. The needle on the right shows the battery charge."
local EXTRAS_TIP =
    "Before you go: [F] at the back of a truck opens its trunk, [E] in the driver's seat its glovebox. Out there, a Ratchet tightens loose doors and bolts the battery in."
-- lang:end
-- luacheck: pop

-- player -> { charId, accountId, dim, vehicle, ending, real = {...}, extrasTimer, checkTimer, guide }
local sessions = {}
local completed = {} -- account id -> true once its tutorial is completed (accounts.tutorial_done)

local function tipText(player, key)
    return logic.clean(exports.data:t(exports.auth:getLanguage(player) or "en", key))
end

-- A tip the tutorial forces on the player, whatever /tooltips says
local function tip(player, key, ms)
    if isElement(player) then
        exports.ui:showTip(player, tipText(player, key), false, ms or logic.TIP_MS, true)
    end
end

local function snapshot(player, v)
    local held = exports.items:getHeld(player)
    local vx, vy, vz = getElementVelocity(v)
    return {
        bonnetOpen = getVehicleDoorState(v, 0) == 4 or getVehicleDoorOpenRatio(v, 0) > 0.5,
        health = getElementHealth(v),
        wheels = { getVehicleWheelStates(v) },
        fuel = exports.vehicles:getVehicleFuel(v),
        engineOn = getVehicleEngineState(v),
        driver = getVehicleController(v) == player,
        kmh = math.sqrt(vx * vx + vy * vy + vz * vz) * 180,
        held = held and held.uname or nil,
    }
end

local function onDuty(player)
    return getElementData(player, "staff.duty") == true
end

function isInTutorial(player)
    return sessions[player] ~= nil
end

-- a private dimension nobody (a tutorial or the dev studio) stands in
local function freeDimension()
    local used = {}
    for _, s in pairs(sessions) do
        used[s.dim] = true
    end
    for _, p in ipairs(getElementsByType("player")) do
        used[getElementDimension(p)] = true
    end
    for d = logic.DIMENSION_BASE, logic.DIMENSION_BASE + logic.DIMENSION_COUNT - 1 do
        if not used[d] then
            return d
        end
    end
end

local function createKit(player, dim)
    local pending = #logic.ITEMS
    for _, it in ipairs(logic.ITEMS) do
        local data = it.data and toJSON(it.data, true):sub(2, -2) or nil
        local rz = it.spin and math.random() * 360 or 0
        local params = { it.uname, nil, data, it.x, it.y, it.z, rz, 0, dim, nil, nil, n = 11 }
        db.call("item_create", params, function(res)
            if res and res.ok then
                triggerEvent("itemCreated", resourceRoot, res.payload.item_id)
            else
                util.log("tutorial", "warn", "no %s: %s", it.uname, res and res.code or "DB_ERROR")
            end
            pending = pending - 1
            if pending == 0 and isElement(player) then
                exports.items:refreshPlayer(player)
            end
        end)
    end
end

-- The Bobcat arrives with vehicleTransientSpawned; until it has, spawningSince keeps a second one from being asked for.
local function createVehicle(player, s)
    local v = logic.VEHICLE
    s.spawningSince = getTickCount()
    local ok, code = exports.vehicles:spawnTransientVehicle({
        uname = v.uname,
        x = v.x,
        y = v.y,
        z = v.z,
        rz = v.rz,
        dimension = s.dim,
        health = v.health,
        fuel = math.random() * v.maxStartFuel,
        damage = logic.damage(math.random),
        loot = v.loot,
        owner = player,
    })
    if not ok then
        util.log("tutorial", "warn", "vehicle refused: %s", tostring(code))
    end
end

addEventHandler("vehicleTransientSpawned", root, function(owner)
    local s = isElement(owner) and sessions[owner]
    if not s then
        return -- another resource's, or its tutorial ended while it was inserted (cleaned up below)
    end
    if s.ending or isElement(s.vehicle) then
        return exports.vehicles:destroyTransientVehicle(source)
    end
    s.vehicle, s.spawningSince = source, nil
end)

local function accountOf(player)
    return exports.auth:getAccountId(player)
end

local function revive(player, s)
    local stats = exports.character:getStats(player)
    if stats then
        -- hp first: modifyStat kills at 0
        exports.character:modifyStat(player, "hp", 100 - stats.hp)
        exports.character:modifyStat(player, "food", math.max(0, 80 - stats.food))
        exports.character:modifyStat(player, "bleed", -stats.bleed)
    end
    if isPedDead(player) then
        spawnPlayer(
            player,
            logic.SPAWN.x,
            logic.SPAWN.y,
            logic.SPAWN.z,
            logic.SPAWN.rz,
            getElementModel(player),
            0,
            s.dim
        )
        setCameraTarget(player, player)
        fadeCamera(player, true)
    end
end

-- The Bobcat repaired, refuelled and running with its driver at a walking pace: the tutorial is complete.
local function checkCompleted(player, s)
    local v = s.vehicle
    if not s.ending and not isElement(v) then
        -- no Bobcat (vehicles restarted, or it blew up): the tutorial cannot be left without one
        if not s.spawningSince or getTickCount() - s.spawningSince > logic.VEHICLE_RETRY_MS then
            createVehicle(player, s)
        end
        return
    end
    if s.ending or s.completed or not isElement(v) then
        return
    end
    -- a locked Bobcat cannot be opened again (nothing in the kit breaks a lock), so it never stays locked
    if exports.vehicles:getVehicleLockState(v) > 0 then
        exports.vehicles:setVehicleLockState(v, 0)
    end
    local snap = snapshot(player, v)
    local step, hint, tool = logic.guide(snap)
    local key = step .. "|" .. hint .. "|" .. (tool or "")
    if s.guide ~= key then
        s.guide = key
        triggerClientEvent(player, "tutorialStepChanged", player, step, hint, tool)
    end
    if not snap.driver or not logic.completed(snap.health, snap.fuel, snap.engineOn, snap.kmh, snap.wheels) then
        return
    end
    s.completed = true
    completed[s.accountId] = true
    db.exec("UPDATE accounts SET tutorial_done = 1 WHERE id = ?", { s.accountId })
    triggerClientEvent(player, "tutorialCompleted", player)
    exports.ui:showTip(player, lang.textFor(player, COMPLETE), false, logic.COMPLETE_MS, true)
    s.extrasTimer = setTimer(function()
        if sessions[player] == s and not s.ending then
            exports.ui:showTip(player, lang.textFor(player, EXTRAS_TIP), false, logic.INTRO_MS, true)
        end
    end, logic.COMPLETE_MS, 1)
    log.event("tutorial.completed", { player = player, character_id = s.charId, account_id = s.accountId })
end

local function start(player, accountId)
    if sessions[player] or not isElement(player) then
        return false, "ALREADY"
    end
    local charId = exports.character:getCharacterId(player)
    if not charId or onDuty(player) or getPedOccupiedVehicle(player) then
        return false, "NO_CHARACTER"
    end
    local dim = freeDimension()
    if not dim then
        return false, "FULL"
    end
    local x, y, z = getElementPosition(player)
    local s = {
        charId = charId,
        accountId = accountId,
        dim = dim,
        real = { x, y, z, getElementInterior(player), getElementDimension(player) },
    }
    sessions[player] = s
    setElementData(player, "character.realPosition", s.real, "local")
    setElementData(player, "tutorial.active", true, "local")
    setElementInterior(player, 0)
    setElementDimension(player, dim)
    setElementPosition(player, logic.SPAWN.x, logic.SPAWN.y, logic.SPAWN.z)
    setElementRotation(player, 0, 0, logic.SPAWN.rz)
    revive(player, s)
    createKit(player, dim)
    createVehicle(player, s)
    -- a closure, not timer arguments: MTA copies a table passed to setTimer, and the copy never sees s.vehicle
    s.checkTimer = setTimer(function()
        checkCompleted(player, s)
    end, logic.CHECK_MS, 0)
    triggerClientEvent(player, "tutorialStarted", player)
    exports.ui:showTip(player, tipText(player, "TUTORINTROD"), false, logic.INTRO_MS, true)
    log.event("tutorial.started", { player = player, character_id = charId, account_id = accountId, dim = dim })
    return true
end

-- reason: "left", "quit", "logout" or "stop". The player is made a new character unless they are gone.
local function finish(player, reason)
    local s = sessions[player]
    if not s or s.ending then
        return false
    end
    s.ending = true
    for _, timer in ipairs({ s.extrasTimer, s.checkTimer }) do
        if isTimer(timer) then
            killTimer(timer)
        end
    end
    local gone = reason == "quit" or reason == "logout"
    if isElement(player) then
        removeElementData(player, "character.realPosition")
        removeElementData(player, "tutorial.active")
        if not gone then
            triggerClientEvent(player, "tutorialEnded", player)
        end
    end
    if isElement(s.vehicle) then
        exports.vehicles:destroyTransientVehicle(s.vehicle)
    end
    local function restart()
        sessions[player] = nil
        if not gone and isElement(player) then
            -- items clears its hands and gear on this event (character's /dropall raises it too)
            triggerEvent("characterItemsDropped", player, s.charId)
            exports.character:restartCharacter(player)
        end
    end
    log.event("tutorial.ended", {
        player = isElement(player) and player or nil,
        character_id = s.charId,
        reason = reason,
        completed = s.completed == true,
    })
    if reason == "stop" then
        db.call("tutorial_cleanup", { s.charId, s.dim })
        restart()
    else
        db.call("tutorial_cleanup", { s.charId, s.dim }, function(res)
            if not res or not res.ok then
                util.log("tutorial", "error", "tutorial_cleanup failed: %s", res and res.code or "db")
            end
            restart()
        end)
    end
    return true
end

-- The only way out, and only once the account has completed the tutorial.
addCommandHandler("tutorial", function(player)
    local s = sessions[player]
    if not s then
        return outputChatBox(lang.textFor(player, DONE), player, 255, 220, 0)
    end
    if not completed[s.accountId] then
        return outputChatBox(lang.textFor(player, GOAL), player, 255, 220, 0)
    end
    finish(player, "left")
end)

-- Dying in the tutorial only revives the player there.
addEventHandler("tutorialCharacterDied", root, function()
    local s = sessions[source]
    if s and not s.ending then
        revive(source, s)
    end
end)

-- Every spawn of an account that has not completed the tutorial starts it (the character was just made, or came
-- back from a crash mid-tutorial: either way what it holds is deleted at the end).
local function startIfDue(player)
    local accountId = accountOf(player)
    if not accountId or sessions[player] or completed[accountId] then
        return
    end
    db.one("SELECT tutorial_done FROM accounts WHERE id = ?", { accountId }, function(row)
        if not row or not isElement(player) then
            return
        end
        if tonumber(row.tutorial_done) == 1 then
            completed[accountId] = true
            return
        end
        local ok, code = start(player, accountId)
        if not ok and code ~= "ALREADY" then
            util.log("tutorial", "warn", "not started for %s: %s", getPlayerName(player), tostring(code))
        end
    end)
end

addEventHandler("characterSpawned", root, function()
    startIfDue(source)
end)

-- The tips an item move earns.
addEventHandler("itemMoved", root, function(_, from, to, containerId)
    local player = source
    local s = sessions[player]
    if not s or s.ending then
        return
    end
    if to ~= "container" then
        local key = logic.moveTipKey(from, to)
        return key and tip(player, key)
    end
    if containerId and containerId == exports.character:getInventoryContainerId(player) then
        return tip(player, logic.moveTipKey(from, to, "inventory"))
    end
    db.one("SELECT kind FROM containers WHERE id = ?", { containerId }, function(row)
        if sessions[player] == s then
            tip(player, logic.moveTipKey(from, to, row and row.kind or nil))
        end
    end)
end)

addEventHandler("itemHolstered", root, function()
    if sessions[source] then
        tip(source, "TUTORITMHOL")
    end
end)

-- The first time the player sits at the wheel of the Bobcat: what the dashboard in front of them says.
addEventHandler("onVehicleEnter", root, function(player, seat)
    local s = sessions[player]
    if not s or seat ~= 0 or source ~= s.vehicle or s.dashboardShown then
        return
    end
    s.dashboardShown = true
    exports.ui:showTip(player, lang.textFor(player, DASHBOARD_TIP), false, logic.TIP_MS, true)
end)

-- A client whose script (re)started after the tutorial began missed tutorialStarted: send the state again.
net.handler("tutorialStateRequested", function(player)
    local s = sessions[player]
    if s and not s.ending then
        s.guide = nil -- the next tick sends the step again
        triggerClientEvent(player, "tutorialStarted", player)
        if s.completed then
            triggerClientEvent(player, "tutorialCompleted", player)
        end
    end
end, { rate = 1 })

addEventHandler("onPlayerQuit", root, function()
    finish(source, "quit")
end)

addEventHandler("playerLoggedOut", root, function()
    finish(source, "logout")
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do
        finish(player, "stop")
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("tutorial") then
        return
    end
    -- a tutorial a crash cut short leaves items lying in its dimension
    db.exec(
        "DELETE FROM items WHERE dimension BETWEEN ? AND ? AND x IS NOT NULL",
        { logic.DIMENSION_BASE, logic.DIMENSION_BASE + logic.DIMENSION_COUNT - 1 }
    )
    -- characters already in the game when the resource (re)starts go in too
    for _, p in ipairs(getElementsByType("player")) do
        if exports.character:getCharacterId(p) then
            startIfDue(p)
        end
    end
end)
