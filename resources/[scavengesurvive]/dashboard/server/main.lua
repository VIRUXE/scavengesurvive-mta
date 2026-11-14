-- Live positions for the staff map (ops/dashboard): once a second the resource writes every spawned character's
-- place and the last few minutes of its trail to live.json in its own folder, which the dashboard API reads. A file
-- instead of an HTTP export because dev's rcon (same HTTP server) trusts every account allowed to call exports, so
-- a second account would be one more way to run `lua`. No DB, no network, nothing a player can reach.
local FILE = "live.json"
local SAMPLE_MS = 1000
local MIN_MOVE = 1.5 -- metres between two trail points
local KEEP = 300 -- trail points per player (5 min at a point a second)

local trails = {} -- player -> { { x, y, z, int, dim, veh, t, seat }, ... } oldest first; seat -1 when on foot

local function round(n, places)
    local m = 10 ^ (places or 0)
    return math.floor(n * m + 0.5) / m
end

local function snapshot()
    local now = getRealTime().timestamp
    local players = {}
    for _, p in ipairs(getElementsByType("player")) do
        local char = exports.character:getCharacterId(p)
        if char then
            -- a dev tool holding the ped somewhere else (the studio) records the real spot, as character/tick.lua does
            local real = getElementData(p, "character.realPosition")
            local x, y, z, int, dim
            if type(real) == "table" then
                x, y, z, int, dim = real[1], real[2], real[3], real[4], real[5]
            else
                x, y, z = getElementPosition(p)
                int, dim = getElementInterior(p), getElementDimension(p)
            end
            local _, _, rz = getElementRotation(p)
            local vehicle = getPedOccupiedVehicle(p)
            local veh = vehicle and getElementModel(vehicle) or nil
            local seat = vehicle and getPedOccupiedVehicleSeat(p) or -1

            local trail = trails[p]
            if not trail then
                trail = {}
                trails[p] = trail
            end
            local last = trail[#trail]
            if
                not last
                or last[4] ~= int
                or last[5] ~= dim
                or last[6] ~= (veh or 0)
                or last[8] ~= seat
                or (x - last[1]) ^ 2 + (y - last[2]) ^ 2 + (z - last[3]) ^ 2 >= MIN_MOVE * MIN_MOVE
            then
                trail[#trail + 1] = { round(x, 1), round(y, 1), round(z, 1), int, dim, veh or 0, now, seat }
                if #trail > KEEP then
                    table.remove(trail, 1)
                end
            end

            players[#players + 1] = {
                name = getPlayerName(p),
                char = char,
                x = round(x, 1),
                y = round(y, 1),
                z = round(z, 1),
                rz = round(rz, 0),
                int = int,
                dim = dim,
                veh = veh,
                seat = seat,
                hp = round(getElementHealth(p), 0),
                zone = exports.maps:getPlayerZone(p) or false,
                duty = getElementData(p, "staff.duty") == true,
                ping = getPlayerPing(p),
                trail = trail,
            }
        end
    end
    return { at = now, players = players }
end

local function write()
    -- toJSON wraps its argument in an outer array; the reader unwraps it
    local f = fileCreate(FILE)
    if not f then
        return
    end
    fileWrite(f, toJSON(snapshot(), true))
    fileClose(f)
end

addEventHandler("onPlayerQuit", root, function()
    trails[source] = nil
end)

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(write, SAMPLE_MS, 0)
    write()
end)
