-- Buttons, doors, the puzzles and Area 69 on the server (shared/logic/buttons.lua, doors.lua, puzzles.lua,
-- area69.lua). The client finds the button in reach and sends buttonPressed; the server checks the player is there,
-- applies what the press does and sends every client the door and puzzle state (buttonsStateChanged), which their
-- copies of the objects follow. Codes never leave the server.
-- ctx = { db, net, util, buttons, doors, puzzles, area69 }
return function(ctx)
    local db, net, util = ctx.db, ctx.net, ctx.util
    local buttons, doors, puzzles, area69 = ctx.buttons, ctx.doors, ctx.puzzles, ctx.area69
    local M = {}

    local function rand(n)
        return math.random(0, n - 1)
    end

    local reg = buttons.new()
    doors.register(reg, buttons)
    puzzles.register(reg, buttons)
    area69.register(reg, buttons)
    local state = puzzles.newState()
    local a69 = area69.newState(rand)
    local code = 0
    local keypadAt = {} -- player -> { id = keypad id, button = button } while a keypad is open for them
    local lastCode = {} -- player -> tick of the last code entered (building's keypad throttle: one per 2 s)
    local hacks = {} -- player -> the hack timer running on their keypad
    local closeTimers = {}

    local function broadcast(target)
        triggerClientEvent(target or root, "buttonsStateChanged", resourceRoot, reg.states, state)
    end

    local function message(player, title, body)
        triggerClientEvent(player, "buttonMessageShown", player, title, body)
    end

    local function teleport(player, x, y, z, world)
        setElementDimension(player, world)
        setElementPosition(player, x, y, z)
        setElementFrozen(player, true)
        setTimer(function(p)
            if isElement(p) then
                setElementFrozen(p, false)
            end
        end, buttons.FREEZE_MS, 1, player)
        exports.items:refreshPlayer(player)
    end

    local function autoClose(id, ms)
        if isTimer(closeTimers[id]) then
            killTimer(closeTimers[id])
        end
        closeTimers[id] = setTimer(function()
            closeTimers[id] = nil
            if buttons.autoClose(reg, id) then
                broadcast()
            end
        end, ms, 1)
    end

    local function within(player, b)
        if not isElement(player) or getElementDimension(player) ~= b[4] then
            return false
        end
        local x, y, z = getElementPosition(player)
        return getDistanceBetweenPoints3D(x, y, z, b[1], b[2], b[3]) <= buttons.REACH + 1.0
    end

    local function stopHack(player)
        if isTimer(hacks[player]) then
            killTimer(hacks[player])
        end
        hacks[player] = nil
    end

    -- the ranch PC (AttachRanchHdd): the hard drive goes in after 2.5 s if it is still the one in hand
    local function installHdd(player, itemId)
        setPedAnimation(player, "BOMBER", "BOM_Plant_In", -1, false, false, false, false)
        setTimer(function()
            if not isElement(player) then
                return
            end
            setPedAnimation(player, "BOMBER", "BOM_Plant_2Idle", -1, false, false, false, false)
            local held = exports.items:getHeld(player)
            if state.pcOn or not held or held.id ~= itemId then
                return
            end
            exports.items:destroyItem(itemId, player)
            puzzles.installHdd(state)
            local say = puzzles.SAY.hddDone
            message(player, say[1], say[2])
            broadcast()
        end, puzzles.HDD_MS, 1)
    end

    local apply

    -- an Area 69 code goes in (OnPlayerKeypadEnter): typed, or put in by a hack
    local function enterA69(player, id, entered)
        local held = exports.items:getHeld(player)
        local holding = held and held.uname == area69.HACK_DEVICE
        local effects, ok = area69.enterCode(a69, reg, id, entered, holding)
        if ok then
            keypadAt[player] = nil
            stopHack(player)
        elseif not holding then
            triggerClientEvent(player, "toastShown", player, "WRONG_PASSCODE")
        end
        apply(player, effects, held or nil)
    end

    -- HackKeypad: 10 s of random digits, then 40% the code goes in, else a spark, -5 HP and a 3 s knockout; 1 s later
    -- what the display shows is entered either way. Walking off or closing the keypad's spot cancels it.
    local function startHack(player, id, b)
        if hacks[player] then
            return
        end
        setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
        triggerClientEvent(player, "keypadHackStarted", player, area69.HACK_MS, area69.HACK_TICK_MS)
        hacks[player] = setTimer(function()
            hacks[player] = nil
            if not within(player, b) or (keypadAt[player] or {}).id ~= id then
                return
            end
            setPedAnimation(player, nil)
            local value = area69.codeFor(a69, id)
            local won = area69.hackSucceeds(rand)
            util.log("world", "info", "hack: %s at %s %s", getPlayerName(player), id, won and "got in" or "failed")
            if not won then
                value = 1000 + rand(8999)
                local x, y, z = getElementPosition(player)
                triggerClientEvent(root, "puzzleSparkShown", resourceRoot, x, y, z - 1.5)
                exports.character:modifyStat(player, "hp", -area69.HACK_HP)
                exports.character:knockOutPlayer(player, area69.HACK_KO_MS)
            end
            triggerClientEvent(player, "keypadHackEnded", player, value)
            setTimer(function()
                if isElement(player) and (keypadAt[player] or {}).id == id then
                    enterA69(player, id, value)
                end
            end, area69.HACK_ENTER_MS, 1)
        end, area69.HACK_MS, 1)
    end

    apply = function(player, effects, held, b)
        local changed = false
        for _, e in ipairs(effects) do
            local kind = e[1]
            if kind == "changed" then
                changed = true
            elseif kind == "autoclose" then
                autoClose(e[2], e[3])
            elseif kind == "teleport" then
                teleport(player, e[2], e[3], e[4], e[5])
            elseif kind == "message" then
                message(player, e[2], e[3])
            elseif kind == "toast" then
                triggerClientEvent(player, "toastShown", player, e[2])
            elseif kind == "keypad" then
                keypadAt[player] = { id = e[2], button = b }
                triggerClientEvent(player, "keypadOpened", player, e[2], false)
                if e[3] then
                    startHack(player, e[2], b)
                end
            elseif kind == "close" then
                triggerClientEvent(player, "keypadClosed", player)
            elseif kind == "consume" and held then
                exports.items:destroyItem(held.id, player)
            elseif kind == "hdd" and held then
                installHdd(player, held.id)
            elseif kind == "view" then
                triggerClientEvent(player, "buttonViewToggled", player)
            elseif kind == "spark" then
                triggerClientEvent(root, "puzzleKeypadSparked", resourceRoot)
            end
        end
        if changed then
            broadcast()
        end
    end

    net.handler("buttonPressed", function(player, id)
        local b = reg.byId[tostring(id)]
        if not b or not exports.character:getCharacterId(player) or not within(player, b) then
            return
        end
        if b.owner == "puzzles" and puzzles.hidden(state, b) then
            return
        end
        local held = exports.items:getHeld(player)
        local effects
        if b.owner == "puzzles" then
            effects = puzzles.press(state, reg, buttons, b.id, held and puzzles.tagOf(held.data), held ~= false)
        elseif b.owner == "area69" then
            effects = area69.press(a69, b, held and held.uname, reg)
        else
            effects = buttons.press(reg, b.id)
        end
        apply(player, effects, held or nil, b)
    end, { rate = 3 })

    net.handler("buttonsStateRequested", function(player)
        broadcast(player)
    end, { rate = 2 })

    -- the code hunt's lockup and Area 69's keypads share building's keypad UI: building drops ids that are not
    -- numbers, this takes the ones it opened ("lockup", "a69:<keypad>")
    net.handler("keypadSubmitted", function(player, id, entered)
        local open = keypadAt[player]
        if type(id) ~= "string" or not open or open.id ~= id or not within(player, open.button) then
            return
        end
        local now = getTickCount()
        if hacks[player] or now - (lastCode[player] or -10000) < 2000 then
            return
        end
        lastCode[player] = now
        if id == "lockup" then
            if puzzles.enterCode(state, code, entered) then
                keypadAt[player] = nil
                triggerClientEvent(player, "keypadClosed", player)
                broadcast()
            else
                triggerClientEvent(player, "toastShown", player, "WRONG_PASSCODE")
            end
        else
            enterA69(player, id, entered)
        end
    end, { rate = 3 })

    addEventHandler("onPlayerQuit", root, function()
        stopHack(source)
        keypadAt[source], lastCode[source] = nil, nil
    end)

    -- codehunt.pwn: a new code and its four parts on every start; the parts of the last one still lying in the world
    -- go first (one carried off keeps its old digit, as upstream's saved inventories did)
    local function placeCodeParts()
        local parts
        code, parts = puzzles.newCode(rand)
        db.query("SELECT id, data FROM items WHERE type_uname = 'CodePart' AND x IS NOT NULL", {}, function(rows)
            for _, r in ipairs(rows or {}) do
                if puzzles.tagOf(type(r.data) == "string" and fromJSON(r.data)) == puzzles.CODE_TAG then
                    exports.items:destroyWorldItem(r.id)
                end
            end
            for _, p in ipairs(parts) do
                local data = string.format('{"puzzle":"%s","digit":%d}', puzzles.CODE_TAG, p.digit)
                local args = { "CodePart", nil, data, p.spot[1], p.spot[2], p.spot[3], 0, 0, 0, nil, nil, n = 11 }
                db.call("item_create", args, function(res)
                    if not (res and res.ok) then
                        util.log("world", "warn", "code hunt: a code part: %s", res and res.code or "DB_ERROR")
                    end
                end)
            end
            util.log("world", "info", "code hunt: lockup code set, %d parts placed", #parts)
        end)
    end

    function M.start()
        placeCodeParts()
        broadcast()
    end

    -- the item data a tagged fixture is created with
    function M.fixtureData(tag)
        return tag and string.format('{"puzzle":"%s"}', tag) or nil
    end

    return M
end
