-- The flight recorder: every authenticated, living character is sampled at 5 Hz and the samples are written as
-- delta-encoded chunks (shared/logic/codec.lua), one replay_chunk row per character per ~10 s, in one procedure call
-- per flush. Idle characters cost a heartbeat every 5 s. What the server cannot read (the animation, the aim point,
-- walk/run/crouch state) comes from the client half (client/pose.lua) as replayPoseReported and is only ever used
-- to annotate samples: it moves nothing and is clamped here.
return function(ctx)
    local db, net, codec = ctx.db, ctx.net, ctx.codec
    local M = {}

    local TICK_MS = 200
    local CHUNK_MS = 10000
    local FLUSH_MS = 10000
    local HEARTBEAT_MS = 5000
    local POSE_TTL_MS = 1500
    local MAX_PENDING_CHUNKS = 400
    local MOVES = {
        stand = true,
        crouch = true,
        walk = true,
        run = true,
        sprint = true,
        jump = true,
        fall = true,
        swim = true,
        climb = true,
        vehicle = true,
    }

    local rec = {} -- player -> { char, prev, buf, n, firstTick, lastTick, lastSeen }
    local chars = {} -- player -> character id, refreshed once a second
    local pose = {} -- player -> { mv, an, aim, tick } as the client reported it
    local fired = {} -- player -> { x, y, z } of the shot that was fired since the last sample
    local pending = {} -- closed chunks waiting for the next flush
    local timers = {}
    local enabled = true

    local function round(n)
        return math.floor(n + 0.5)
    end

    local function cm(v)
        return round(v * 100)
    end

    function M.enabled()
        return enabled
    end

    local function closeChunk(p)
        local r = rec[p]
        if not r or #r.buf == 0 then
            return
        end
        if #pending < MAX_PENDING_CHUNKS then
            pending[#pending + 1] = { char = r.char, tick = r.firstTick, n = r.n, data = codec.encodeChunk(r.buf) }
        end
        r.buf, r.n, r.prev, r.firstTick = {}, 0, nil, nil
    end

    local function flush()
        if #pending == 0 or not ctx.ready then
            return
        end
        local now = getTickCount()
        local rows = {}
        for i, c in ipairs(pending) do
            rows[i] = { id = c.char, ago = now - c.tick, n = c.n, data = c.data }
        end
        pending = {}
        -- toJSON wraps its argument in an outer array; the procedure reads '$[0][*]'
        db.call("replay_chunk_save", { toJSON(rows, true) }, function(res)
            if not res or not res.ok then
                outputServerLog("[replay] replay_chunk_save failed: " .. tostring(res and res.code or "db"))
            end
        end)
    end

    -- where the character really is: a dev tool holding the ped elsewhere (the studio) leaves the real spot in element
    -- data, as character/tick.lua and dashboard do
    local function placeOf(p)
        local real = getElementData(p, "character.realPosition")
        if type(real) == "table" then
            return real[1], real[2], real[3], real[4], real[5]
        end
        local x, y, z = getElementPosition(p)
        return x, y, z, getElementInterior(p), getElementDimension(p)
    end

    -- walk/run/sprint from the ground speed when the client reported nothing recent
    local function deriveMove(p, vehicle)
        if vehicle then
            return "vehicle"
        end
        if isElementInWater(p) then
            return "swim"
        end
        local vx, vy, vz = getElementVelocity(p)
        if not isPedOnGround(p) then
            return (vz or 0) > 0.02 and "jump" or "fall"
        end
        if isPedDucked(p) then
            return "crouch"
        end
        local speed = math.sqrt(vx * vx + vy * vy) * 50
        if speed < 0.3 then
            return "stand"
        elseif speed < 2.5 then
            return "walk"
        elseif speed < 5.5 then
            return "run"
        end
        return "sprint"
    end

    local function read(p, now)
        local x, y, z, int, dim = placeOf(p)
        local _, _, rz = getElementRotation(p)
        local vehicle = getPedOccupiedVehicle(p)
        local s = {
            x = cm(x),
            y = cm(y),
            z = cm(z),
            r = round(rz) % 360,
            i = int or 0,
            m = dim or 0,
            h = round(getElementHealth(p)),
            w = getPedWeapon(p) or 0,
            du = getElementData(p, "staff.duty") == true and 1 or 0,
        }
        local reported = pose[p]
        local fresh = reported and now - reported.tick <= POSE_TTL_MS
        s.mv = fresh and reported.mv or deriveMove(p, vehicle)
        if fresh and reported.an then
            s.an = reported.an
        end
        local shot = fired[p]
        if shot then
            s.f = 1
            s.a = { cm(shot[1]), cm(shot[2]), cm(shot[3]) }
            fired[p] = nil
        elseif fresh and reported.aim then
            s.a = { cm(reported.aim[1]), cm(reported.aim[2]), cm(reported.aim[3]) }
        end
        if vehicle then
            local id = tonumber(getElementData(vehicle, "vehicles.id"))
            local model = getElementModel(vehicle)
            s.vk = id or -model
            s.st = getPedOccupiedVehicleSeat(p)
            if s.st == 0 then
                local vx, vy, vz = getElementPosition(vehicle)
                local rx, ry, vrz = getElementRotation(vehicle)
                s.vh = {
                    cm(vx),
                    cm(vy),
                    cm(vz),
                    round(rx) % 360,
                    round(ry) % 360,
                    round(vrz) % 360,
                    round(getElementHealth(vehicle)),
                    model,
                }
            end
        end
        return s
    end

    local function sample()
        local now = getTickCount()
        for p, char in pairs(chars) do
            if isElement(p) and not isPedDead(p) then
                local r = rec[p]
                if r and r.char ~= char then
                    closeChunk(p)
                    r = nil
                end
                if not r then
                    r = { char = char, buf = {}, n = 0, lastSeen = now }
                    rec[p] = r
                end
                local cur = read(p, now)
                local text
                if not r.prev then
                    r.firstTick = now
                    text = codec.encodeSample(cur, nil, 0, true)
                else
                    text = codec.encodeSample(cur, r.prev, now - r.lastTick, false)
                    if text and r.lastSeen - r.lastTick > TICK_MS * 1.5 then
                        -- the character stood still: pin its old state at the last quiet tick so the replay does not
                        -- glide from there to this sample across the quiet stretch
                        local hold = string.format('{"d":%d}', r.lastSeen - r.lastTick)
                        r.buf[#r.buf + 1] = hold
                        r.n = r.n + 1
                        r.lastTick = r.lastSeen
                        text = codec.encodeSample(cur, r.prev, now - r.lastTick, true)
                    elseif not text and now - r.lastTick >= HEARTBEAT_MS then
                        text = string.format('{"d":%d}', now - r.lastTick)
                    end
                end
                if text then
                    r.buf[#r.buf + 1] = text
                    r.n = r.n + 1
                    r.prev = cur
                    r.lastTick = now
                end
                r.lastSeen = now
                if r.firstTick and now - r.firstTick >= CHUNK_MS then
                    closeChunk(p)
                end
            end
        end
    end

    local function refreshChars()
        enabled = tonumber(ctx.setting("record", 1)) ~= 0
        if not enabled then
            return
        end
        for _, p in ipairs(getElementsByType("player")) do
            local id = exports.character:getCharacterId(p)
            if id and not isPedDead(p) then
                chars[p] = id
            elseif chars[p] then
                chars[p] = nil
                closeChunk(p)
            end
        end
    end

    local function forget(p)
        closeChunk(p)
        rec[p], chars[p], pose[p], fired[p] = nil, nil, nil, nil
    end

    function M.start()
        timers[#timers + 1] = setTimer(refreshChars, 1000, 0)
        timers[#timers + 1] = setTimer(function()
            if enabled then
                sample()
            end
        end, TICK_MS, 0)
        timers[#timers + 1] = setTimer(flush, FLUSH_MS, 0)
        refreshChars()
    end

    function M.stop()
        for _, t in ipairs(timers) do
            if isTimer(t) then
                killTimer(t)
            end
        end
        timers = {}
        for p in pairs(rec) do
            closeChunk(p)
        end
        flush()
    end

    addEventHandler("onPlayerQuit", root, function()
        forget(source)
    end)

    addEventHandler("playerLoggedOut", root, function()
        forget(source)
    end)

    addEventHandler("characterDied", root, function()
        forget(source)
    end)

    addEventHandler("onPlayerWeaponFire", root, function(_, endX, endY, endZ)
        if chars[source] then
            fired[source] = { endX, endY, endZ }
        end
    end)

    -- hits: who hurt whom with what; the log has no such event. At most 20 a second.
    local hitWindow, hitCount = 0, 0
    addEventHandler("onPlayerDamage", root, function(attacker, weapon, bodypart, loss)
        local victim = chars[source]
        if not victim then
            return
        end
        local now = getTickCount()
        if now - hitWindow >= 1000 then
            hitWindow, hitCount = now, 0
        end
        hitCount = hitCount + 1
        if hitCount > 20 then
            return
        end
        local x, y, z = getElementPosition(source)
        local attackerChar = isElement(attacker) and getElementType(attacker) == "player" and chars[attacker] or nil
        ctx.events.push({
            kind = "replay.hit",
            char = victim,
            other = attackerChar,
            account = exports.auth:getAccountId(source) or nil,
            x = x,
            y = y,
            z = z,
            int = getElementInterior(source),
            dim = getElementDimension(source),
            data = {
                weapon = weapon,
                loss = round(tonumber(loss) or 0),
                bodypart = bodypart,
                attacker = attackerChar and getPlayerName(attacker) or nil,
                victim = getPlayerName(source),
            },
        })
    end)

    net.handler("replayPoseReported", function(player, mv, an, ax, ay, az)
        if not chars[player] then
            return
        end
        local p = { tick = getTickCount() }
        if type(mv) == "string" and MOVES[mv] then
            p.mv = mv
        end
        if type(an) == "string" and #an <= 64 then
            p.an = an
        end
        if type(ax) == "number" and type(ay) == "number" and type(az) == "number" then
            p.aim = { ax, ay, az }
        end
        pose[player] = p
    end, { rate = 8 })

    return M
end
