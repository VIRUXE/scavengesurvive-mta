-- The tutorial (upstream core/player/tutorial.pwn): a fresh character may play in a private dimension with a kit
-- of tools, a damaged Bobcat and a help tip for each thing it tries; /tutorial ends it, as does dying or leaving, and
-- the player gets a new character (character:restartCharacter).
--
-- The tutorial character is a real one (items and vehicles are database rows). character.realPosition keeps the
-- dimension out of its saved position, tutorial.active stops its death, and tutorial_cleanup deletes what it holds.
local db = loadstring(exports.lib:getModule("db"), "=lib/db.lua")()
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

-- lang:begin
local REFUSED = {
    NOT_FRESH = "The tutorial is only offered to a new character before it has picked anything up.",
    IN_VEHICLE = "Get out of the vehicle first.",
    NO_CHARACTER = "You cannot start the tutorial now.",
    FULL = "No tutorial room is free right now.",
}
local DRIVE_TIP = "Tap Y to turn the key to ACC, hold Y to crank the engine. Press E for the glovebox."
-- lang:end

local sessions = {} -- player -> { charId, dim, vehicle, ending, real = { x, y, z, int, dim }, driveTimer }
local fresh = {} -- player -> expiry timer: a new character that may still start the tutorial

local function tipText(player, key)
    return logic.clean(exports.data:t(exports.auth:getLanguage(player) or "en", key))
end

-- A tip the tutorial forces on the player, whatever /tooltips says
local function tip(player, key, ms)
    if isElement(player) then
        exports.ui:showTip(player, tipText(player, key), false, ms or logic.TIP_MS, true)
    end
end

local function onDuty(player)
    return getElementData(player, "staff.duty") == true
end

function isInTutorial(player)
    return sessions[player] ~= nil
end

local function withdrawOffer(player)
    local timer = fresh[player]
    if timer == nil then
        return
    end
    if isTimer(timer) then
        killTimer(timer)
    end
    fresh[player] = nil
    if isElement(player) then
        triggerClientEvent(player, "tutorialOffered", player, false)
    end
end

local function offer(player)
    withdrawOffer(player)
    fresh[player] = setTimer(withdrawOffer, logic.OFFER_MS, 1, player)
    triggerClientEvent(player, "tutorialOffered", player, true)
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

local function createVehicle(player, s)
    local v = logic.VEHICLE
    local spec = {
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
    }
    local ok, code = exports.vehicles:spawnTransientVehicle(spec, function(vehicle)
        if not vehicle then
            return util.log("tutorial", "warn", "no vehicle for %s", getPlayerName(player))
        end
        if sessions[player] ~= s or s.ending then
            return exports.vehicles:destroyTransientVehicle(vehicle) -- the tutorial ended while it was inserted
        end
        s.vehicle = vehicle
    end)
    if not ok then
        util.log("tutorial", "warn", "vehicle refused: %s", tostring(code))
    end
end

local function start(player)
    if sessions[player] or not isElement(player) then
        return false, "ALREADY"
    end
    local charId = exports.character:getCharacterId(player)
    if not charId or onDuty(player) then
        return false, "NO_CHARACTER"
    end
    if not fresh[player] then
        return false, "NOT_FRESH"
    end
    if getPedOccupiedVehicle(player) then
        return false, "IN_VEHICLE"
    end
    local dim = freeDimension()
    if not dim then
        return false, "FULL"
    end
    local x, y, z = getElementPosition(player)
    local s =
        { charId = charId, dim = dim, real = { x, y, z, getElementInterior(player), getElementDimension(player) } }
    sessions[player] = s
    withdrawOffer(player)
    setElementData(player, "character.realPosition", s.real, "local")
    setElementData(player, "tutorial.active", true, "local")
    setElementInterior(player, 0)
    setElementDimension(player, dim)
    setElementPosition(player, logic.SPAWN.x, logic.SPAWN.y, logic.SPAWN.z)
    setElementRotation(player, 0, 0, logic.SPAWN.rz)
    local stats = exports.character:getStats(player)
    if stats and stats.hp < 100 then
        exports.character:modifyStat(player, "hp", 100 - stats.hp)
    end
    createKit(player, dim)
    createVehicle(player, s)
    triggerClientEvent(player, "tutorialStarted", player)
    exports.ui:showTip(player, tipText(player, "TUTORINTROD"), false, logic.INTRO_MS, true)
    log.event("tutorial.started", { player = player, character_id = charId, dim = dim })
    return true
end

-- reason: "left", "died", "quit", "logout" or "stop". The player is made a new character unless they are gone.
local function finish(player, reason)
    local s = sessions[player]
    if not s or s.ending then
        return false
    end
    s.ending = true
    if isTimer(s.driveTimer) then
        killTimer(s.driveTimer)
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
    log.event(
        "tutorial.ended",
        { player = isElement(player) and player or nil, character_id = s.charId, reason = reason }
    )
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

addCommandHandler("tutorial", function(player)
    if sessions[player] then
        return finish(player, "left")
    end
    local ok, code = start(player)
    if not ok then
        outputChatBox(lang.textFor(player, REFUSED[code] or REFUSED.NO_CHARACTER), player, 255, 220, 0)
    end
end)

addEventHandler("tutorialCharacterDied", root, function()
    finish(source, "died")
end)

addEventHandler("characterSpawned", root, function(_, isNew)
    -- a new character, or a restart after the tutorial: offer it again
    if isNew and not sessions[source] then
        offer(source)
    elseif not isNew then
        withdrawOffer(source)
    end
end)

-- The tips an item move earns. Moving anything ends the offer: the character now has something to lose.
addEventHandler("itemMoved", root, function(_, from, to, containerId)
    local player = source
    local s = sessions[player]
    if not s then
        return withdrawOffer(player)
    end
    if s.ending then
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

-- The first time the player drives the Bobcat, once its repair tip has been read: the key and the glovebox.
addEventHandler("onVehicleEnter", root, function(player, seat)
    local s = sessions[player]
    if not s or seat ~= 0 or source ~= s.vehicle or s.drove then
        return
    end
    s.drove = true
    s.driveTimer = setTimer(function()
        if sessions[player] == s and not s.ending and getPedOccupiedVehicle(player) == s.vehicle then
            exports.ui:showTip(player, lang.textFor(player, DRIVE_TIP), false, logic.TIP_MS, true)
        end
    end, logic.DRIVE_TIP_DELAY_MS, 1)
end)

addEventHandler("onPlayerQuit", root, function()
    withdrawOffer(source)
    finish(source, "quit")
end)

addEventHandler("playerLoggedOut", root, function()
    withdrawOffer(source)
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
end)
