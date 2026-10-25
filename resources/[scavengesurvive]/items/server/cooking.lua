-- Campfires and barbecues (#95; upstream core/item/campfire.pwn, core/item/barbecue.pwn). The interact key on one
-- with food in hand puts the food on it (campfire: cooks for 60 s; barbecue: two grill spots, cooked when lit), with
-- a Petrol Can fuels a barbecue, with a Fire Lighter lights it (30 s, one fuel). Empty hands take food off an unlit
-- barbecue, then the barbecue itself; a campfire is never picked up. A sweep every 2 s finishes cooks and burns
-- campfires out (10 min; in the rain 2 min, or out at once 60 % of the time). All state is the cookers' item data
-- (shared/logic/cooking.lua), so a restart loses nothing.
-- ctx = { db, state, type, toast, world, hands, cooking } built by server/main.lua.
return function(ctx)
    local db, state, world, hands, cooking = ctx.db, ctx.state, ctx.world, ctx.hands, ctx.cooking
    local itemType, toast = ctx.type, ctx.toast
    local SWEEP_MS, PLACE_GUARD_MS, PENDING_MS = 2000, 1000, 5000
    local busy = {} -- food id -> true while a cooker cooks it (rebuilt by every sweep)
    local pending = {} -- food id -> tick: put on a cooker since the sweep's read was sent
    local lastPlaced = {} -- player -> tick of the last food put on a barbecue (bbq_PlaceFoodTick)
    local M = {}

    local function now()
        return getRealTime().timestamp
    end

    local function raw(row)
        return (row.data and row.data ~= false) and row.data or ""
    end

    local function decode(row)
        return cooking.decode(hands.decodeData(row.data))
    end

    local function idList(ids)
        return "[" .. table.concat(ids, ",") .. "]"
    end

    -- writes a cooker's next data only if nobody changed it since the read; cb(ok)
    local function swap(row, nextData, cb)
        local sql = "UPDATE items SET data = ? WHERE id = ? AND x IS NOT NULL AND IFNULL(data, '') = ?"
        db.exec(sql, { cooking.encode(row.uname, nextData), row.id, raw(row) }, function(ok, _, affected)
            cb(ok and tonumber(affected) == 1)
        end)
    end

    local function putFood(player, cid, held, row, nextData, x, y, z, rz, code)
        local params = { cid, held.id, row.id, raw(row), cooking.encode(row.uname, nextData), x, y, z, rz }
        db.call("cooker_put_food", params, function(res, c)
            if not isElement(c.player) then
                return
            end
            if not res or not res.ok then
                return toast(c.player, res and res.code or "DB_ERROR")
            end
            if c.uname == "Campfire" then
                busy[c.foodId], pending[c.foodId] = true, getTickCount()
            else
                lastPlaced[c.player] = getTickCount()
            end
            hands.setHeld(c.player, nil)
            world.syncPlayer(c.player)
            triggerEvent("itemMoved", c.player, c.foodId, "held", "world")
            toast(c.player, c.code)
        end, { player = player, foodId = held.id, uname = row.uname, code = code })
    end

    local function campfire(player, cid, held, row)
        local t = held and itemType(held.uname)
        if not cooking.isFood(t) then
            return -- nothing else to do with a campfire, and it is never picked up
        end
        local ok, code, nextData = cooking.campfireAdd(decode(row), held.id, now())
        if not ok then
            return toast(player, code)
        end
        putFood(player, cid, held, row, nextData, row.x, row.y, row.z + cooking.FOOD_Z, math.random(0, 359), code)
    end

    -- the grill's foods still lying on it: cb(rows)
    local function grillRows(row, d, cb)
        local sql = "SELECT id, type_uname AS uname, hitpoints AS hp, data, x, y FROM items "
            .. "WHERE id IN (?, ?) AND x IS NOT NULL"
        db.query(sql, { d.grill[1], d.grill[2] }, function(rows)
            local on = {}
            for _, r in ipairs(rows or {}) do
                if math.abs(r.x - row.x) <= cooking.NEAR and math.abs(r.y - row.y) <= cooking.NEAR then
                    on[#on + 1] = r
                end
            end
            cb(on)
        end)
    end

    local function bbqFood(player, cid, held, row, d)
        grillRows(row, d, function(on)
            if not isElement(player) or state.held[player] ~= held then
                return
            end
            local onGrill = {}
            for _, r in ipairs(on) do
                onGrill[r.id] = true
            end
            local cooked = cooking.isCooked(held.data)
            local ok, code, nextData, slot = cooking.bbqAdd(d, held.id, cooked, onGrill)
            if not ok then
                return toast(player, code)
            end
            local x, y, z = cooking.grillSpot(row.x, row.y, row.z, row.rz, slot)
            putFood(player, cid, held, row, nextData, x, y, z, row.rz or 0, code)
        end)
    end

    local function bbqFuel(player, held, row, d)
        local amount = held.data and held.data.amount
        local ok, code, nextData, left = cooking.bbqFuel(d, amount == nil and 20.0 or amount)
        if not ok then
            return toast(player, code)
        end
        swap(row, nextData, function(done)
            if not isElement(player) then
                return
            end
            if not done then
                return toast(player, "BUSY")
            end
            local cur = state.held[player]
            if cur and cur.id == held.id then
                hands.syncHeldData(player, cur, { amount = left })
            end
            toast(player, code)
        end)
    end

    local function bbqLight(player, row, d)
        local ok, code, nextData = cooking.bbqLight(d, now())
        if not ok then
            return toast(player, code)
        end
        swap(row, nextData, function(done)
            if done then
                for _, id in ipairs(cooking.busyFoods(row.uname, nextData)) do
                    busy[id], pending[id] = true, getTickCount()
                end
                world.resendEverywhere(row.id) -- the burners' fire
            end
            if isElement(player) then
                toast(player, done and code or "BUSY")
            end
        end)
    end

    -- empty hands: food off the grill first, then (returning false) the barbecue itself
    local function bbqTake(player, cid, row, d)
        if d.doneAt then
            toast(player, "COOKING")
            return true
        end
        if lastPlaced[player] and getTickCount() - lastPlaced[player] < PLACE_GUARD_MS then
            return true
        end
        if d.grill[1] == 0 and d.grill[2] == 0 then
            return false
        end
        grillRows(row, d, function(on)
            if not isElement(player) or state.held[player] then
                return
            end
            if on[1] then
                return hands.pickup(player, cid, on[1])
            end
            -- the grill's foods are gone: forget them and pick the barbecue up
            local cleared = cooking.decode({ fuel = d.fuel })
            swap(row, cleared, function()
                if isElement(player) then
                    hands.pickup(player, cid, row)
                end
            end)
        end)
        return true
    end

    -- The interact key on a world item (hands.lua itemPickupRequested). true = handled here.
    function M.interact(player, cid, held, row)
        if busy[row.id] then
            toast(player, "COOKING")
            return true
        end
        if row.uname == "Campfire" then
            campfire(player, cid, held, row)
            return true
        end
        if row.uname ~= "Barbecue" then
            return false
        end
        local d = decode(row)
        if not held then
            return bbqTake(player, cid, row, d)
        end
        if held.uname == "GasCan" then
            bbqFuel(player, held, row, d)
        elseif held.uname == "FireLighter" then
            bbqLight(player, row, d)
        elseif cooking.isFood(itemType(held.uname)) then
            bbqFood(player, cid, held, row, d)
        else
            return false
        end
        return true
    end

    local function burnOut(row, logUname)
        local spots = {}
        for i, s in ipairs(cooking.logSpots(row.x, row.y, row.z, math.random)) do
            spots[i] = string.format('{"x":%.3f,"y":%.3f,"z":%.3f,"rz":%d}', s.x, s.y, s.z, s.rz)
        end
        db.call("campfire_burn_out", { row.id, logUname, idList(spots) }, function(res)
            if res and res.ok then
                world.forgetEverywhere(row.id)
                triggerEvent("itemDestroyed", resourceRoot, row.id)
            end
        end)
    end

    local function cook(row, act)
        local params = { row.id, raw(row), cooking.encode(row.uname, act.data), idList(act.foods), cooking.NEAR }
        db.call("cooker_cook", params, function(res)
            if not res or not res.ok then
                return
            end
            for _, id in ipairs(act.foods) do
                busy[id] = nil
                world.resendEverywhere(id) -- "(Cooked)" in the label
            end
            if row.uname == "Barbecue" then
                world.resendEverywhere(row.id) -- the fire goes out
            end
        end)
    end

    local SWEEP_SQL = "SELECT id, type_uname AS uname, data, x, y, z FROM items "
        .. "WHERE type_uname IN ('Campfire', 'Barbecue') AND x IS NOT NULL "
        .. "AND (type_uname = 'Campfire' OR JSON_VALUE(data, '$.doneAt') IS NOT NULL)"

    local function sweep()
        db.query(SWEEP_SQL, {}, function(rows)
            if rows == false then
                return
            end
            local t, tick = now(), getTickCount()
            local nextBusy = {}
            for id, at in pairs(pending) do
                if tick - at < PENDING_MS then
                    nextBusy[id] = true
                else
                    pending[id] = nil
                end
            end
            for _, row in ipairs(rows) do
                local d = decode(row)
                local act = cooking.step(row.uname, d, t)
                if not act then
                    for _, id in ipairs(cooking.busyFoods(row.uname, d)) do
                        nextBusy[id] = true
                    end
                elseif act.kind == "life" then
                    local life = cooking.campfireLife(exports.world:getWeather(), math.random(0, 99))
                    if life then
                        d.burnsAt = t + life
                        swap(row, d, function() end)
                    else
                        burnOut(row, "WoodLog")
                    end
                elseif act.kind == "cook" then
                    cook(row, act)
                else
                    burnOut(row, "BurntLog")
                end
            end
            busy = nextBusy
        end)
    end
    setTimer(sweep, SWEEP_MS, 0)

    addEventHandler("onPlayerQuit", root, function()
        lastPlaced[source] = nil
    end)

    return M
end
