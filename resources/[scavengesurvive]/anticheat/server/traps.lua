-- Hacker traps (upstream admin/hack-trap.pwn): loot items placed where no player can reach them; whoever picks
-- one up is banned. The spots are generated (data/traps.lua, 31 of them), the item ids live in anticheat_traps, and
-- items asks every pickup through the cancellable itemPickupAttempted event. A trap item has no despawn time and
-- no loot spot, so nothing removes it; one that is gone (staff /di, a wipe) is made again on the next start.
local log = loadstring(exports.lib:getModule("log"), "=lib/log.lua")()

-- the player's zone name, or nil when maps is not running
local function zoneOf(player)
    local ok, zone = pcall(function()
        return exports.maps:getPlayerZone(player)
    end)
    return ok and zone or nil
end

return function(ctx)
    local db = ctx.db
    local spots = ctx.loadFile("data/traps.lua")
    local bySpot, byItem = {}, {}
    local SAVE_SQL = "INSERT INTO anticheat_traps (spot, item_id) VALUES (?, ?)"
        .. " ON DUPLICATE KEY UPDATE item_id = VALUES(item_id)"
    local M = {}

    local function place(spot)
        local row = spots[spot]
        local uname, data = exports.loot:pickItem(row[4])
        if not uname then
            return log.event("anticheat.trapFailed", {
                trap_id = spot,
                reason = "noLootItem",
                loot_table = tostring(row[4]),
            }, "warn")
        end
        local args = { uname, nil, data, row[1], row[2], row[3], math.random(0, 359), 0, 0, nil, nil, n = 11 }
        db.call("item_create", args, function(res)
            local itemId = res and res.ok and res.payload and tonumber(res.payload.item_id)
            if not itemId then
                return log.event("anticheat.trapFailed", { trap_id = spot, reason = "itemCreateFailed" }, "warn")
            end
            bySpot[spot], byItem[itemId] = itemId, spot
            db.exec(SAVE_SQL, { spot, itemId })
        end)
    end

    -- every spot whose item still lies in the world keeps it; the others get a new one
    function M.sync()
        local sql =
            "SELECT t.spot, t.item_id FROM anticheat_traps t JOIN items i ON i.id = t.item_id WHERE i.x IS NOT NULL"
        db.query(sql, {}, function(rows)
            if not rows then
                return log.event("anticheat.trapFailed", { reason = "readFailed" }, "warn")
            end
            bySpot, byItem = {}, {}
            for _, r in ipairs(rows) do
                local spot, itemId = tonumber(r.spot), tonumber(r.item_id)
                if spots[spot] then
                    bySpot[spot], byItem[itemId] = itemId, spot
                end
            end
            local made = 0
            for spot = 1, #spots do
                if not bySpot[spot] then
                    made = made + 1
                    place(spot)
                end
            end
            log.event("anticheat.trapsSynced", {
                total = #spots,
                in_place = #spots - made,
                made = made,
                msg = string.format("traps: %d of %d in place, %d made again", #spots - made, #spots, made),
            })
        end)
    end

    addEventHandler("itemPickupAttempted", root, function(itemId)
        local spot = byItem[tonumber(itemId)]
        if not spot then
            return
        end
        cancelEvent()
        local x, y, z = getElementPosition(source)
        log.event("anticheat.trapTriggered", {
            player = source,
            trap_id = spot,
            item_id = tonumber(itemId),
            exempt = ctx.exempt(source) == true,
            x = x,
            y = y,
            z = z,
            int = getElementInterior(source),
            dim = getElementDimension(source),
            zone = zoneOf(source),
        }, "warn")
        if ctx.exempt(source) then
            return
        end
        ctx.report(source, "TRAP", "Picked up a hack-trap", "spot " .. spot)
        ctx.autoBan(source, "Sprung the hacker trap by picking up an unreachable item!")
    end)

    return M
end
