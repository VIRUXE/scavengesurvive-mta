-- onPlayerNetworkStatus: every interruption of a player's packets is logged (anticheat.networkInterrupted), and a
-- run of them (netstatus.THRESHOLD inside the hour, timeouts included) goes to staff in game and to Discord #staff.
return function(ctx, logic, log)
    local tracker = logic.new()
    local open = {} -- player -> { tick, at, x, y, z, held, vehicle }

    local function heldName(player)
        local ok, item = pcall(function()
            return exports.items:getHeld(player)
        end)
        return ok and type(item) == "table" and item.uname or nil
    end

    local function vehicleName(player)
        local veh = getPedOccupiedVehicle(player)
        return veh and getVehicleName(veh) or nil
    end

    local function finish(player, ms, timedOut)
        local start = open[player]
        open[player] = nil
        if not start then
            return
        end
        local x, y, z = getElementPosition(player)
        local entry = {
            at = start.at,
            ms = ms,
            timedOut = timedOut,
            moved = getDistanceBetweenPoints3D(start.x, start.y, start.z, x, y, z),
            held = start.held or heldName(player),
            vehicle = start.vehicle,
        }
        local alert = tracker.record(getPlayerSerial(player), entry, getRealTime().timestamp)
        log.event("anticheat.networkInterrupted", {
            player = player,
            ms = ms and math.floor(ms) or nil,
            timed_out = timedOut,
            moved_m = math.floor(entry.moved + 0.5),
            held = entry.held,
            vehicle = entry.vehicle,
            in_hour = #tracker.recent(getPlayerSerial(player), getRealTime().timestamp),
            alerted = alert and true or false,
        }, "warn")
        if alert and not ctx.exempt(player) then
            local text = logic.alertText((getPlayerName(player):gsub("#%x%x%x%x%x%x", "")), alert)
            exports.staff:notifyStaff(
                1,
                string.format(
                    " >  %s lost connection %d× in the last hour (possible lag switch)",
                    getPlayerName(player),
                    #alert
                )
            )
            if getResourceFromName("discordchat") then
                pcall(function()
                    exports.discordchat:sendStaffLog(text)
                end)
            end
        end
    end

    addEventHandler("onPlayerNetworkStatus", root, function(status, ticks)
        if status == 0 then
            local x, y, z = getElementPosition(source)
            open[source] = {
                tick = getTickCount() - (tonumber(ticks) or 0),
                at = getRealTime().timestamp - math.floor((tonumber(ticks) or 0) / 1000),
                x = x,
                y = y,
                z = z,
                held = heldName(source),
                vehicle = vehicleName(source),
            }
        elseif status == 1 then
            finish(source, tonumber(ticks) or 0, false)
        end
    end)

    -- A timeout is an interruption that never resumed. One without a status-0 event first (MTA did not report it)
    -- still counts, starting where the player was last seen.
    addEventHandler("onPlayerQuit", root, function(quitType)
        if quitType == "Timed out" then
            if not open[source] then
                local x, y, z = getElementPosition(source)
                open[source] = { at = getRealTime().timestamp, x = x, y = y, z = z } -- no tick: duration unknown
            end
            local tick = open[source].tick
            finish(source, tick and (getTickCount() - tick) or nil, true)
        end
        open[source] = nil
    end)
end
