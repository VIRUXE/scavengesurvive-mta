-- Weapon overheat (#151, upstream char/overheat.pwn; rules in shared/logic/overheat.lua). The driver of a Rhino,
-- Hunter or Hydra has the main weapon control bound while seated; a 100 ms timer cools or heats and sends the heat
-- to the driver's bar (overheatChanged) whenever it changes; over the maximum the vehicle's spot blows up.
local overheat
do
    local f = fileOpen("shared/logic/overheat.lua", true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    overheat = assert(loadstring(src, "=vehicles/overheat.lua"))()
end

local drivers = {} -- player -> { vehicle, heat, sent, gun, timer }

local function send(player, d)
    if d.sent ~= d.heat then
        d.sent = d.heat
        triggerClientEvent(player, "overheatChanged", player, d.heat, overheat.MAX)
    end
end

local function onShot(player)
    local d = drivers[player]
    if d and isElement(d.vehicle) then
        d.heat = overheat.shot(d.heat, getVehicleEngineState(d.vehicle))
        send(player, d)
    end
end

local function onGun(player, _, keyState)
    local d = drivers[player]
    if d then
        d.gun = keyState == "down"
    end
end

local function stop(player)
    local d = drivers[player]
    if not d then
        return
    end
    drivers[player] = nil
    if isTimer(d.timer) then
        killTimer(d.timer)
    end
    if isElement(player) then
        unbindKey(player, "vehicle_fire", "down", onShot)
        unbindKey(player, "vehicle_secondary_fire", "both", onGun)
        triggerClientEvent(player, "overheatEnded", player)
    end
end

local function tick(player)
    local d = drivers[player]
    local v = d and d.vehicle
    if not isElement(player) or not isElement(v) or getPedOccupiedVehicle(player) ~= v then
        return stop(player)
    end
    d.heat = overheat.tick(d.heat, getElementModel(v), d.gun, getVehicleEngineState(v))
    if overheat.isOver(d.heat) then
        local x, y, z = getElementPosition(v)
        createExplosion(x, y, z, overheat.EXPLOSION_TYPE, player)
        d.heat = 0.0
    end
    send(player, d)
end

addEventHandler("onVehicleEnter", root, function(player, seat)
    if seat ~= 0 or not overheat.isArmed(getElementModel(source)) then
        return
    end
    stop(player)
    local d = { vehicle = source, heat = 0.0, gun = false }
    d.timer = setTimer(tick, overheat.TICK_MS, 0, player)
    drivers[player] = d
    bindKey(player, "vehicle_fire", "down", onShot)
    bindKey(player, "vehicle_secondary_fire", "both", onGun)
    send(player, d)
end)

addEventHandler("onVehicleExit", root, function(player)
    stop(player)
end)

addEventHandler("onPlayerWasted", root, function()
    stop(source)
end)

addEventHandler("onPlayerQuit", root, function()
    stop(source)
end)
