-- Gas Bottles on a trailer's A-frame (the towable Airstream's two propane mounts, GAS_MOUNTS in
-- shared/logic/vehicle.lua): a Gas Bottle in hand goes onto a free mount, empty hands take the bottle off a mount
-- into them. Each mount keeps the gas and hitpoints of its bottle in vehicles.gas_bottles
-- ({"l": {"gas": kg, "hp": n}, "r": ...}, a key per occupied mount); the procedures gas_bottle_mount and
-- gas_bottle_unmount move the item and the mount in one transaction. A trailer whose column is NULL has never been
-- filled: its mounts are rolled once when it loads, each with an even chance of a bottle holding a random amount of
-- gas (none, one or both). Clients hide the tank of an empty mount from the element data "vehicles.gasBottles"
-- (airstream_trailer/client/gasbottles.lua); a stove or heater reads the gas with exports.vehicles:getGasBottles.
-- ctx = { db, info, toast, activeActions, cancelHoldAction, vlogic, toLocal } built by server/main.lua.
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
return function(ctx)
    local db, info, toast, activeActions = ctx.db, ctx.info, ctx.toast, ctx.activeActions
    local vlogic, cancelHoldAction, toLocal = ctx.vlogic, ctx.cancelHoldAction, ctx.toLocal
    local M = {}

    local SLOTS = { "l", "r" }
    local FILL_CHANCE = 0.5
    local HOLD_MS = 2500
    local SAVE = "UPDATE vehicles SET gas_bottles = ? WHERE id = ?"

    local function mountable(vehicle)
        local inf = info[vehicle]
        local vt = inf and exports.data:vehicleType(inf.uname)
        return vt ~= nil and vt.trailer == true and vt.door == true
    end

    local function encode(state)
        local parts = {}
        for _, slot in ipairs(SLOTS) do
            local b = state[slot]
            if b then
                parts[#parts + 1] = string.format('"%s":{"gas":%.1f,"hp":%d}', slot, b.gas, b.hp)
            end
        end
        return "{" .. table.concat(parts, ",") .. "}"
    end

    local function occupancy(state)
        local out = ""
        for _, slot in ipairs(SLOTS) do
            out = out .. (state[slot] and slot or "")
        end
        return out
    end

    -- state changed or loaded: the occupancy string for the clients, "" with both mounts empty
    function M.apply(vehicle)
        local inf = info[vehicle]
        if not inf or not isElement(vehicle) or not inf.gasBottles then
            return
        end
        setElementData(vehicle, "vehicles.gasBottles", occupancy(inf.gasBottles), "broadcast", "deny")
    end

    local function decode(text)
        local d = fromJSON(text)
        local state = {}
        for _, slot in ipairs(SLOTS) do
            local b = type(d) == "table" and d[slot]
            if type(b) == "table" then
                state[slot] = { gas = tonumber(b.gas) or 0, hp = math.floor(tonumber(b.hp) or 3) }
            end
        end
        return state
    end

    -- vehicles.create: the stored mounts of a row (NULL: roll them once and keep the result)
    function M.load(vehicle, text)
        local inf = info[vehicle]
        if not inf or not mountable(vehicle) then
            return
        end
        if type(text) == "string" and text ~= "" then
            inf.gasBottles = decode(text)
        else
            local state = {}
            for _, slot in ipairs(SLOTS) do
                if math.random() < FILL_CHANCE then
                    state[slot] = exports.items:rollGasBottle()
                end
            end
            inf.gasBottles = state
            db.exec(SAVE, { encode(state), inf.id })
        end
        M.apply(vehicle)
    end

    -- the gas on each mount: { l = { gas = kg, hp = n }, r = ... }, a key per occupied mount; false without mounts
    function M.get(vehicle)
        local inf = isElement(vehicle) and info[vehicle]
        if not inf or not inf.gasBottles then
            return false
        end
        local copy = {}
        for slot, b in pairs(inf.gasBottles) do
            copy[slot] = { gas = b.gas, hp = b.hp }
        end
        return copy
    end

    local function stillThere(player, vehicle)
        if not isElement(player) or not isElement(vehicle) or not info[vehicle] or isPedDead(player) then
            return false
        end
        local px, py, pz = getElementPosition(player)
        local lx, ly = toLocal(getElementMatrix(vehicle), px, py, pz)
        return vlogic.nearGasMount(lx, ly) ~= nil and info[vehicle].gasBottles ~= nil
    end

    local MOUNT_FAIL = { SLOT_FULL = "GASB_SLOTFULL" }
    local UNMOUNT_FAIL = { SLOT_EMPTY = "GASB_NONE", HANDS_FULL = "HANDS_FULL" }

    -- {gas, hp} of a procedure payload
    local function bottleOf(payload)
        local gas = tonumber(payload.gas) or 0
        local hp = math.floor(tonumber(payload.hp) or 3)
        return { gas = gas, hp = hp }
    end

    local function mount(player, vehicle, slot, held)
        local inf = info[vehicle]
        local cid = exports.character:getCharacterId(player)
        local args = { inf.id, held.id, slot, cid }
        db.call("gas_bottle_mount", args, function(res)
            if not res or not res.ok then
                return toast(player, MOUNT_FAIL[res and res.code] or "DB_ERROR")
            end
            local bottle = bottleOf(res.payload)
            inf.gasBottles[slot] = bottle
            M.apply(vehicle)
            if isElement(player) then
                exports.items:clearHeld(player)
                exports.items:refreshPlayer(player)
                toast(player, "GASB_MOUNTED")
            end
            local line = "[GAS] %s mounted a gas bottle (%.1f kg) on vehicle %d slot %s"
            local who = getPlayerName(player)
            outputServerLog(string.format(line, who, bottle.gas, inf.id, slot))
        end)
    end

    local function unmount(player, vehicle, slot)
        local inf = info[vehicle]
        local cid = exports.character:getCharacterId(player)
        local args = { inf.id, slot, cid }
        db.call("gas_bottle_unmount", args, function(res)
            if not res or not res.ok then
                return toast(player, UNMOUNT_FAIL[res and res.code] or "DB_ERROR")
            end
            local bottle = bottleOf(res.payload)
            inf.gasBottles[slot] = nil
            M.apply(vehicle)
            if isElement(player) then
                local item = {
                    id = tonumber(res.payload.item_id),
                    uname = "GasBottle",
                    hp = bottle.hp,
                    data = { gas = bottle.gas },
                }
                exports.items:setHeld(player, item)
                toast(player, "GASB_REMOVED")
            end
            local line = "[GAS] %s took the gas bottle off vehicle %d slot %s"
            outputServerLog(string.format(line, getPlayerName(player), inf.id, slot))
        end)
    end

    -- vehicleInteractRequested within reach of a mount: with a Gas Bottle in hand (held) it goes onto the mount, with
    -- empty hands (held nil) the mount's bottle comes off
    function M.interact(player, vehicle, slot, held)
        local inf = info[vehicle]
        if not inf or not inf.gasBottles or activeActions[player] then
            return
        end
        local taking = held == nil
        if taking and not inf.gasBottles[slot] then
            return toast(player, "GASB_NONE")
        end
        if not taking and inf.gasBottles[slot] then
            return toast(player, "GASB_SLOTFULL")
        end
        cancelHoldAction(player)
        setPedAnimation(player, "COP_AMBIENT", "COPBROWSE_LOOP", -1, true, false, false, false)
        local label = taking and lang.textFor(player, "Taking the bottle off")
            or lang.textFor(player, "Mounting gas bottle")
        triggerClientEvent(player, "vehicleHoldStarted", player, label, HOLD_MS)
        local timer = setTimer(function(p, veh, which, heldId)
            activeActions[p] = nil
            if not isElement(p) then
                return
            end
            setPedAnimation(p, nil)
            triggerClientEvent(p, "vehicleHoldStopped", p)
            if not stillThere(p, veh) then
                return
            end
            if heldId then
                local cur = exports.items:getHeld(p)
                if not cur or cur.id ~= heldId then
                    return
                end
                mount(p, veh, which, cur)
            else
                unmount(p, veh, which)
            end
        end, HOLD_MS, 1, player, vehicle, slot, held and held.id or nil)
        activeActions[player] = { actionType = "gasbottle", vehicle = vehicle, timer = timer }
    end

    return M
end
