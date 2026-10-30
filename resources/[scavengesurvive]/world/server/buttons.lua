-- Buttons, doors and the puzzles on the server (shared/logic/buttons.lua, doors.lua, puzzles.lua). The client finds
-- the button in reach and sends buttonPressed; the server checks the player is there, applies what the press does and
-- sends every client the door and puzzle state (buttonsStateChanged), which their copies of the objects follow.
-- ctx = { db, net, util, buttons, doors, puzzles }
return function(ctx)
    local db, net, util = ctx.db, ctx.net, ctx.util
    local buttons, doors, puzzles = ctx.buttons, ctx.doors, ctx.puzzles
    local M = {}

    local reg = buttons.new()
    doors.register(reg, buttons)
    puzzles.register(reg, buttons)
    local state = puzzles.newState()
    local code = 0
    local keypadAt = {} -- player -> true while the lockup keypad is open for them
    local lastCode = {} -- player -> tick of the last code entered (building's keypad throttle: one per 2 s)
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

    local function apply(player, effects, held)
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
                keypadAt[player] = true
                triggerClientEvent(player, "keypadOpened", player, e[2], false)
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

    local function within(player, b)
        if getElementDimension(player) ~= b[4] then
            return false
        end
        local x, y, z = getElementPosition(player)
        return getDistanceBetweenPoints3D(x, y, z, b[1], b[2], b[3]) <= buttons.REACH + 1.0
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
        else
            effects = buttons.press(reg, b.id)
        end
        apply(player, effects, held or nil)
    end, { rate = 3 })

    net.handler("buttonsStateRequested", function(player)
        broadcast(player)
    end, { rate = 2 })

    -- the lockup keypad shares building's keypad UI: building drops ids that are not numbers, this takes "lockup"
    net.handler("keypadSubmitted", function(player, id, entered)
        if id ~= "lockup" or not keypadAt[player] or not within(player, reg.byId.lockupKeypad) then
            return
        end
        local now = getTickCount()
        if now - (lastCode[player] or -10000) < 2000 then
            return
        end
        lastCode[player] = now
        if puzzles.enterCode(state, code, entered) then
            keypadAt[player] = nil
            triggerClientEvent(player, "keypadClosed", player)
            broadcast()
        else
            triggerClientEvent(player, "toastShown", player, "WRONG_PASSCODE")
        end
    end, { rate = 3 })

    addEventHandler("onPlayerQuit", root, function()
        keypadAt[source], lastCode[source] = nil, nil
    end)

    -- codehunt.pwn: a new code and its four parts on every start; the parts of the last one still lying in the world
    -- go first (one carried off keeps its old digit, as upstream's saved inventories did)
    local function placeCodeParts()
        local parts
        code, parts = puzzles.newCode(function(n)
            return math.random(0, n - 1)
        end)
        db.query("SELECT id, data FROM items WHERE type_uname = 'CodePart' AND x IS NOT NULL", {}, function(rows)
            for _, r in ipairs(rows or {}) do
                if puzzles.tagOf(type(r.data) == "string" and fromJSON(r.data)) == puzzles.CODE_TAG then
                    exports.items:destroyWorldItem(r.id)
                end
            end
            for _, p in ipairs(parts) do
                local data = string.format('{"puzzle":"%s","digit":%d}', puzzles.CODE_TAG, p.digit)
                local args = { "CodePart", 5, data, p.spot[1], p.spot[2], p.spot[3], 0, 0, 0, nil, nil, n = 11 }
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
