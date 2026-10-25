-- Changing clothes (core/char/clothes.pwn): using a Clothes item of the character's gender starts a hold of
-- clothes.HOLD_MS; moving, dying or leaving cancels it. At the end clothes_swap puts the clothes the character wore
-- into the item and the item's skin on the character (characters.skin, persisted).
-- ctx = { db, state, clothes, skins, charId, toast, sendInventory } built by server/main.lua.
return function(ctx)
    local db, state, clothes, skins = ctx.db, ctx.state, ctx.clothes, ctx.skins
    local charId, toast = ctx.charId, ctx.toast
    local CHECK_MS, MAX_MOVE = 250, 0.8
    local changing = {} -- player -> { itemId, skin, fromHand, x, y, z, timer, left }

    local function stop(player)
        local c = changing[player]
        if not c then
            return
        end
        if isTimer(c.timer) then
            killTimer(c.timer)
        end
        changing[player] = nil
        if isElement(player) then
            triggerClientEvent(player, "clothesChangeStopped", player)
        end
    end

    local function finish(player, c)
        changing[player] = nil
        triggerClientEvent(player, "clothesChangeStopped", player)
        local openContainerId = c.openContainerId
        if openContainerId and ctx.openContainerId(player) ~= openContainerId then
            openContainerId = nil
        end
        db.call("clothes_swap", { c.itemId, charId(player), c.skin, openContainerId, n = 4 }, function(res, cc)
            if not isElement(cc.player) then
                return
            end
            if not res or not res.ok then
                return toast(cc.player, res and res.code or "DB_ERROR")
            end
            setElementModel(cc.player, cc.skin)
            local nextData = { skin = res.payload and res.payload.old_skin }
            local held = state.held[cc.player]
            if held and held.id == cc.itemId then
                held.data = nextData
                triggerClientEvent(cc.player, "heldItemChanged", cc.player, held)
            end
            if not cc.fromHand then
                ctx.sendInventory(cc.player)
            end
        end, { player = player, itemId = c.itemId, skin = c.skin, fromHand = c.fromHand })
    end

    local function tick(player)
        local c = changing[player]
        if not c or not isElement(player) then
            return
        end
        local x, y, z = getElementPosition(player)
        if isPedDead(player) or getDistanceBetweenPoints3D(x, y, z, c.x, c.y, c.z) > MAX_MOVE then
            return stop(player)
        end
        c.left = c.left - CHECK_MS
        if c.left <= 0 then
            killTimer(c.timer)
            finish(player, c)
        end
    end

    local M = {}

    -- Clothes use: data is the item's decoded data (nil when it never held a stored skin)
    function M.use(player, itemId, data, fromHand, openContainerId)
        if changing[player] then
            return
        end
        if exports.staff:isOnDuty(player) then
            return toast(player, "CLOTHES_ON_DUTY")
        end
        local skin = clothes.skinFor(itemId, data)
        local female = skins.isFemale(getElementModel(player))
        if (clothes.gender(skin) == clothes.FEMALE) ~= female then
            return toast(player, "CLOTHESWRGE")
        end
        local x, y, z = getElementPosition(player)
        local c = {
            itemId = itemId,
            skin = skin,
            fromHand = fromHand,
            openContainerId = openContainerId,
            x = x,
            y = y,
            z = z,
            left = clothes.HOLD_MS,
        }
        c.timer = setTimer(tick, CHECK_MS, 0, player)
        changing[player] = c
        triggerClientEvent(player, "clothesChangeStarted", player, clothes.HOLD_MS)
    end

    addEventHandler("onPlayerQuit", root, function()
        stop(source)
    end)

    addEventHandler("characterDied", root, function()
        stop(source)
    end)

    return M
end
