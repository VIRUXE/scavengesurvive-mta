-- Treatment holds (#94; upstream itemtype/medical.pwn, item/pills.pwn, item/injector.pwn): holding the interact key
-- with a Bandage, Antiseptic Bandage, Medkit, Doctor's Bag, Pills or Injector in hand starts a hold on the player
-- next to you (pills: always yourself), else on yourself; letting go, moving, the patient walking off, a new item in
-- hand, dying or leaving cancels it. The rules (hold time, outcome) live in character's shared/logic/medical.lua.
-- ctx = { db, net, state, destroy, sendInventory } built by server/main.lua.
return function(ctx)
    local db, net, state = ctx.db, ctx.net, ctx.state
    local CHECK_MS, MAX_MOVE, NEXT_TO, MAX_REACH = 250, 0.8, 1.5, 2.5
    local active = {} -- healer -> { itemId, uname, patient, x, y, z, left, timer }
    local M = {}

    local TREATMENTS = { Bandage = true, AntiSepBandage = true, Medkit = true, DoctorBag = true, Pills = true }
    TREATMENTS.AutoInjec = true

    local function setAnim(player, uname, patient, knockedOut)
        if uname == "Pills" then
            return setPedAnimation(player, "BAR", "dnk_stndM_loop", -1, true, false, false, false)
        end
        if patient == player then
            if uname == "AutoInjec" then
                return setPedAnimation(player, "PED", "IDLE_CSAW", -1, true, false, false, false)
            end
            return setPedAnimation(player, "SWEET", "Sweet_injuredloop", -1, true, false, false, false)
        end
        if knockedOut then
            return setPedAnimation(player, "MEDIC", "CPR", -1, true, false, false, false)
        end
        setPedAnimation(player, "COP_AMBIENT", "Copbrowse_loop", -1, true, false, false, false)
    end

    -- upstream IsPlayerNextToPlayer; the last player found wins in medical.pwn, the nearest one here
    local function patientFor(player)
        local x, y, z = getElementPosition(player)
        local best, bestDist = player, NEXT_TO
        for _, p in ipairs(getElementsWithinRange(x, y, z, NEXT_TO, "player")) do
            if p ~= player and not isPedDead(p) and not getPedOccupiedVehicle(p) then
                local px, py, pz = getElementPosition(p)
                local d = getDistanceBetweenPoints3D(x, y, z, px, py, pz)
                if d < bestDist and exports.character:getCharacterId(p) then
                    best, bestDist = p, d
                end
            end
        end
        return best
    end

    local function stop(player)
        local a = active[player]
        if not a then
            return
        end
        if isTimer(a.timer) then
            killTimer(a.timer)
        end
        active[player] = nil
        if isElement(player) then
            setPedAnimation(player)
            triggerClientEvent(player, "treatmentStopped", player)
        end
        if a.patient ~= player and isElement(a.patient) then
            triggerClientEvent(a.patient, "treatmentStopped", a.patient)
        end
    end

    local function writeData(player, itemId, data)
        db.exec("UPDATE items SET data = ? WHERE id = ?", { toJSON(data):sub(2, -2), itemId })
        local held = state.held[player]
        if held and held.id == itemId then
            held.data = data
            triggerClientEvent(player, "heldItemChanged", player, held)
        end
    end

    local function finish(player, a)
        stop(player)
        local held = state.held[player]
        if not held or held.id ~= a.itemId or not isElement(a.patient) then
            return
        end
        local res = exports.character:treatPlayer(player, a.patient, a.uname, held.data)
        if not res or not res.used then
            return
        end
        -- upstream gave Medical experience on every finished heal, used or not; the port only when it did something
        if a.uname ~= "Pills" and a.uname ~= "AutoInjec" then
            exports.character:gainSkill(player, "Medical")
        end
        if res.consume then
            return ctx.destroy(a.itemId, player)
        end
        if type(res.data) == "table" then
            writeData(player, a.itemId, res.data)
        end
    end

    local function tick(player)
        local a = active[player]
        if not a or not isElement(player) then
            return
        end
        local x, y, z = getElementPosition(player)
        local held = state.held[player]
        if isPedDead(player) or getDistanceBetweenPoints3D(x, y, z, a.x, a.y, a.z) > MAX_MOVE then
            return stop(player)
        end
        if not held or held.id ~= a.itemId then
            return stop(player)
        end
        if a.patient ~= player then
            if not isElement(a.patient) or isPedDead(a.patient) then
                return stop(player)
            end
            local px, py, pz = getElementPosition(a.patient)
            if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > MAX_REACH then
                return stop(player)
            end
        end
        a.left = a.left - CHECK_MS
        if a.left <= 0 then
            finish(player, a)
        end
    end

    -- From the hand only, like upstream (OnPlayerKeyStateChange / OnPlayerUseItem read GetPlayerItem).
    function M.start(player, held)
        if active[player] or exports.character:isKnockedOut(player) or getPedOccupiedVehicle(player) then
            return
        end
        local patient = held.uname == "Pills" and player or patientFor(player)
        local ms = exports.character:treatmentHold(player, held.uname, patient)
        if not ms then
            return
        end
        local x, y, z = getElementPosition(player)
        local a = { itemId = held.id, uname = held.uname, patient = patient, x = x, y = y, z = z, left = ms }
        a.timer = setTimer(tick, CHECK_MS, 0, player)
        active[player] = a
        setAnim(player, held.uname, patient, exports.character:isKnockedOut(patient))
        triggerClientEvent(player, "treatmentStarted", player, ms, true)
        if patient ~= player then
            triggerClientEvent(patient, "treatmentStarted", patient, ms, false)
        end
    end

    function M.isTreatment(uname)
        return TREATMENTS[uname] == true
    end

    net.handler("treatmentCancelRequested", function(player)
        stop(player)
    end)

    addEventHandler("onPlayerQuit", root, function()
        stop(source)
        for healer, a in pairs(active) do
            if a.patient == source then
                stop(healer)
            end
        end
    end)

    addEventHandler("characterDied", root, function()
        stop(source)
    end)

    return M
end
