-- Staff replay sessions: /replay (staff/server/replay.lua) asks for a subject and a time range; this module reads the
-- flight recorder (replay_chunk), the 2 s trail (character_track), the events (replay_event), the system-versioned
-- items and the vehicle table, assembles the payloads of docs/superpowers/specs/2026-11-23-replay-design.md
-- Appendix A and streams them to that one staff member's client, which draws everything. Nothing here changes game
-- state: the viewer keeps their own character where it is and is only put back if it was moved.
return function(ctx)
    local db, net, codec, kinds, log = ctx.db, ctx.net, ctx.codec, ctx.kinds, ctx.log
    local M = {}

    local MIN_LEVEL = 2
    local SAMPLES_PER_PART = 1500
    local EVENTS_PER_PART = 400
    local ITEMS_PER_PART = 500
    local SEND_GAP_MS = 60
    local MAX_NEARBY = 8
    local MAX_EVENTS = 4000
    local MAX_WORLD_ROWS = 15000
    local GAP_MS = 8000 -- recorder silence longer than this is filled from the 2 s trail
    -- dials: a Combination Padlock shut without turning them still shows its code
    local SECRET = {
        passcode = true,
        password = true,
        token = true,
        code = true,
        combo = true,
        dials = true,
        serial = true,
        ip = true,
    }

    local sessions = {} -- staff -> session
    local nextId = 0

    local function say(p, fmt, ...)
        if isElement(p) then
            outputChatBox(string.format(fmt, ...), p, 255, 255, 0, true)
        end
    end

    local function q(sql, params, cb)
        db.query(sql, params, cb)
    end

    -- run `n` callbacks-in-flight and call done() once all returned
    local function gate(n, done)
        local left = n
        return function()
            left = left - 1
            if left == 0 then
                done()
            end
        end
    end

    -- ------------------------------------------------------------------------------------------------------------
    -- time and text helpers

    local function fill(template, fields)
        return (
            template:gsub("{([%w_]+)}", function(key)
                local v = fields[key]
                if v == nil or v == false then
                    return "?"
                end
                return tostring(v)
            end)
        )
    end

    -- the data of an event or an item, with everything secret dropped; a keypad's presence stays, its number does not
    local function sanitize(v)
        if type(v) ~= "table" then
            return v
        end
        local out = {}
        for k, x in pairs(v) do
            if k == "keypad" then
                out[k] = true
            elseif not (type(k) == "string" and SECRET[k:lower()]) then
                out[k] = sanitize(x)
            end
        end
        return out
    end

    local function parseJson(text)
        if type(text) ~= "string" or text == "" then
            return nil
        end
        local ok, value = pcall(fromJSON, text)
        if ok and type(value) == "table" then
            return value
        end
        return nil
    end

    -- ------------------------------------------------------------------------------------------------------------
    -- the subject's samples: recorder chunks first, the 2 s trail in the spans the recorder did not cover

    local function moveFromSpeed(speed, vehicle)
        if vehicle then
            return "vehicle"
        elseif speed < 0.3 then
            return "stand"
        elseif speed < 2.5 then
            return "walk"
        elseif speed < 5.5 then
            return "run"
        end
        return "sprint"
    end

    -- heading in GTA's convention (0 faces +y, 90 faces -x) from a displacement
    local function heading(dx, dy)
        return (math.deg(math.atan2(-dx, dy)) + 360) % 360
    end

    local function sparseFromTrack(points, lo, hi, fromMs)
        -- points: rows of replay_track, ascending; lo/hi: the uncovered span, absolute ms
        local out = {}
        for i, p in ipairs(points) do
            local t = tonumber(p.t_ms)
            if t >= lo and t <= hi then
                local prev, nxt = points[i - 1], points[i + 1]
                local ref = nxt or p
                local base = nxt and p or prev or p
                local dx, dy = ref.x - base.x, ref.y - base.y
                local dt = math.max(1, math.abs(tonumber(ref.t_ms) - tonumber(base.t_ms))) / 1000
                local speed = math.sqrt(dx * dx + dy * dy) / dt
                local rz
                if dx * dx + dy * dy > 0.04 then
                    rz = heading(dx, dy)
                end
                local model = tonumber(p.vehicle)
                out[#out + 1] = {
                    t = t - fromMs,
                    x = p.x,
                    y = p.y,
                    z = p.z,
                    rz = rz,
                    int = tonumber(p.interior) or 0,
                    dim = tonumber(p.dimension) or 0,
                    move = moveFromSpeed(speed, model),
                    vkey = model and ("m" .. model) or nil,
                    seat = model and tonumber(p.vehicle_seat) or nil,
                    sparse = true,
                    vmodel = model,
                }
            end
        end
        return out
    end

    -- chunks (ascending rows of replay_chunks) + trail -> sorted list of samples with t in ms from the session start
    local function buildSamples(chunks, track, fromMs, toMs)
        local samples, spans = {}, {}
        local lastEnd
        for _, row in ipairs(chunks) do
            local decoded = parseJson(row.data)
            local list = decoded and codec.decodeChunk(decoded) or {}
            local t0 = tonumber(row.t0_ms)
            local first, last
            for _, s in ipairs(list) do
                local abs = t0 + s.t
                first = first or abs
                last = abs
                if abs >= fromMs - GAP_MS and abs <= toMs then
                    s.t = abs - fromMs
                    samples[#samples + 1] = s
                end
            end
            if first then
                if lastEnd and first - lastEnd > GAP_MS then
                    spans[#spans + 1] = { lastEnd, first }
                end
                if not lastEnd then
                    spans[#spans + 1] = { fromMs - 1, first }
                end
                lastEnd = last
            end
        end
        if lastEnd then
            spans[#spans + 1] = { lastEnd, toMs + 1 }
        else
            spans[#spans + 1] = { fromMs - 1, toMs + 1 }
        end
        for _, span in ipairs(spans) do
            for _, s in ipairs(sparseFromTrack(track, span[1] + 1, span[2] - 1, fromMs)) do
                samples[#samples + 1] = s
            end
        end
        table.sort(samples, function(a, b)
            return a.t < b.t
        end)
        return samples
    end

    local function sameSample(a, b)
        return a.x == b.x
            and a.y == b.y
            and a.z == b.z
            and a.rz == b.rz
            and a.hp == b.hp
            and a.move == b.move
            and a.anim == b.anim
            and a.weapon == b.weapon
            and a.vkey == b.vkey
            and a.seat == b.seat
            and not a.fire
            and not b.fire
            and a.aim == nil
            and b.aim == nil
            and a.int == b.int
            and a.dim == b.dim
            and not a.vehicle
            and not b.vehicle
    end

    -- A run of identical samples (a character standing still) keeps its first and last one: the client interpolates
    -- between neighbours, so the ends of the run are enough and the middle only costs bytes.
    local function thin(samples)
        local out = {}
        for i, s in ipairs(samples) do
            local prev, nxt = samples[i - 1], samples[i + 1]
            if not (prev and nxt and sameSample(prev, s) and sameSample(s, nxt)) then
                out[#out + 1] = s
            end
        end
        return out
    end

    local function addVehicleSample(vehicles, s)
        local key = s.vkey and tostring(s.vkey)
        if not key then
            return
        end
        local v = vehicles[key]
        if not v then
            v = { id = type(s.vkey) == "number" and s.vkey > 0 and s.vkey or nil, samples = {} }
            vehicles[key] = v
        end
        local d = s.vehicle
        if d then
            v.model = v.model or d.model
            v.samples[#v.samples + 1] =
                { t = s.t, x = d.x, y = d.y, z = d.z, rx = d.rx, ry = d.ry, rz = d.rz, hp = d.hp }
        elseif s.sparse then
            -- a trail point: the vehicle is wherever its occupant is
            v.model = v.model or s.vmodel
            v.samples[#v.samples + 1] = { t = s.t, x = s.x, y = s.y, z = s.z, rx = 0, ry = 0, rz = s.rz or 0 }
        elseif s.seat ~= 0 then
            -- a recorded passenger: only used when no driver of that vehicle was recorded (assemble)
            v.ride = v.ride or {}
            v.ride[#v.ride + 1] = { t = s.t, x = s.x, y = s.y, z = s.z, rx = 0, ry = 0, rz = s.rz or 0 }
        end
    end

    -- ------------------------------------------------------------------------------------------------------------
    -- gathering

    local function fail(sess, msg)
        say(sess.staff, " >  Replay: %s", msg)
        if sess.dry then
            M.lastDry = { error = msg }
        end
        M.stop(sess.staff, "failed")
    end

    local function level(p)
        return tonumber(exports.auth:getAdminLevel(p)) or 0
    end

    local function resolveSubject(sess, target, cb)
        local from, to = sess.from, sess.to
        local pick = "SELECT c.id, c.skin, a.id AS account_id, a.name, a.admin_level,"
            .. " (SELECT COUNT(*) FROM character_track t WHERE t.char_id = c.id"
            .. " AND t.at BETWEEN FROM_UNIXTIME(?) AND FROM_UNIXTIME(?))"
            .. " + (SELECT COUNT(*) FROM replay_chunk r WHERE r.char_id = c.id"
            .. " AND r.t0 BETWEEN FROM_UNIXTIME(?) AND FROM_UNIXTIME(?)) AS pts"
            .. " FROM characters c JOIN accounts a ON a.id = c.account_id WHERE "
        local order = " ORDER BY pts DESC, c.id DESC LIMIT 1"
        local function lookupAccount(accountId)
            local params = { from, to, from, to, accountId, to, from, n = 7 }
            q(
                pick
                    .. "c.account_id = ? AND COALESCE(c.spawned_at, '2000-01-01') <= FROM_UNIXTIME(?)"
                    .. " AND (c.died_at IS NULL OR c.died_at >= FROM_UNIXTIME(?))"
                    .. order,
                params,
                function(rows)
                    if rows and rows[1] then
                        return cb(rows[1])
                    end
                    -- the account had no living character in the range: its busiest one overall
                    q(pick .. "c.account_id = ?" .. order, { from, to, from, to, accountId, n = 5 }, function(any)
                        cb(any and any[1] or nil)
                    end)
                end
            )
        end
        local charId = target:match("^#(%d+)$") or target:match("^[cC](%d+)$")
        if charId then
            q(pick .. "c.id = ?" .. order, { from, to, from, to, tonumber(charId), n = 5 }, function(rows)
                cb(rows and rows[1] or nil)
            end)
            return
        end
        local online = getPlayerFromName(target)
        if not online then
            local lower = target:lower()
            for _, p in ipairs(getElementsByType("player")) do
                if getPlayerName(p):lower():find(lower, 1, true) then
                    online = p
                    break
                end
            end
        end
        local accountId = online and exports.auth:getAccountId(online)
        if accountId then
            return lookupAccount(accountId)
        end
        q("SELECT id FROM accounts WHERE name = ? LIMIT 1", { target }, function(rows)
            if rows and rows[1] then
                return lookupAccount(tonumber(rows[1].id))
            end
            q("SELECT id FROM accounts WHERE name LIKE ? LIMIT 1", { target .. "%" }, function(like)
                if like and like[1] then
                    return lookupAccount(tonumber(like[1].id))
                end
                cb(nil)
            end)
        end)
    end

    -- chunks and trail of one character over the range -> samples; cb(samples)
    local function loadActor(sess, charId, cb)
        local from, to = sess.from, sess.to
        local chunks, track
        local done = gate(2, function()
            cb(thin(buildSamples(chunks or {}, track or {}, sess.fromMs, sess.toMs)))
        end)
        q("CALL replay_chunks(?, FROM_UNIXTIME(?), FROM_UNIXTIME(?))", { charId, from, to }, function(rows)
            chunks = rows or {}
            done()
        end)
        q("CALL replay_track(?, FROM_UNIXTIME(?), FROM_UNIXTIME(?))", { charId, from, to }, function(rows)
            track = rows or {}
            done()
        end)
    end

    local function buildEvents(sess, rows, hidden)
        local out = {}
        for _, r in ipairs(rows) do
            local account = tonumber(r.account_id)
            if not (account and hidden[account]) then
                local data = parseJson(r.data) or {}
                local def = kinds[r.kind]
                local fields = {}
                for k, v in pairs(data) do
                    fields[k] = v
                end
                fields.vehicle_id = fields.vehicle_id or tonumber(r.vehicle_id)
                local ev = {
                    t = tonumber(r.t_ms) - sess.fromMs,
                    kind = r.kind,
                    char_id = tonumber(r.char_id),
                    other_char_id = tonumber(r.other_char_id),
                    item_id = tonumber(r.item_id),
                    vehicle_id = tonumber(r.vehicle_id),
                    x = tonumber(r.x),
                    y = tonumber(r.y),
                    z = tonumber(r.z),
                    int = tonumber(r.interior) or 0,
                    dim = tonumber(r.dimension) or 0,
                    label = def and fill(def.label, fields) or r.kind,
                    data = sanitize(data),
                }
                out[#out + 1] = ev
            end
        end
        return out
    end

    -- one entry per version of a positioned item; consecutive versions that look the same are merged
    local function buildWorld(sess, rows)
        local items = {}
        local lastById = {}
        for _, r in ipairs(rows) do
            local id = tonumber(r.id)
            local tOn = tonumber(r.t_on_ms) - sess.fromMs
            local tOff = r.t_off_ms and (tonumber(r.t_off_ms) - sess.fromMs) or nil
            local last = lastById[id]
            if
                last
                and last.t_off
                and last.t_off >= tOn - 50
                and last.uname == r.type_uname
                and last._x == r.x
                and last._y == r.y
                and last._z == r.z
                and last.rz == r.rz
                and last._data == r.data
            then
                last.t_off = tOff
            else
                local entry = {
                    id = id,
                    uname = r.type_uname,
                    x = r.x,
                    y = r.y,
                    z = r.z,
                    rz = r.rz,
                    int = tonumber(r.interior) or 0,
                    dim = tonumber(r.dimension) or 0,
                    sdata = sanitize(parseJson(r.data)),
                    container = tonumber(r.container_id),
                    t_on = tOn,
                    t_off = tOff,
                    _x = r.x,
                    _y = r.y,
                    _z = r.z,
                    _data = r.data,
                }
                lastById[id] = entry
                items[#items + 1] = entry
            end
        end
        local out = {}
        for i, e in ipairs(items) do
            e._x, e._y, e._z, e._data = nil, nil, nil, nil
            out[string.format("%d:%d", e.id, i)] = e
        end
        return out, #items
    end

    -- ------------------------------------------------------------------------------------------------------------
    -- sending

    local function queueParts(sess, parts)
        local total = #parts
        local i = 0
        local function nextPart()
            if sessions[sess.staff] ~= sess or not isElement(sess.staff) then
                return
            end
            i = i + 1
            triggerClientEvent(sess.staff, "replayChunkReceived", sess.staff, sess.id, i, total, parts[i])
            if i < total then
                sess.timer = setTimer(nextPart, SEND_GAP_MS, 1)
            else
                sess.timer = nil
                sess.sent = true
            end
        end
        nextPart()
        return total
    end

    local function slices(list, size)
        local out = {}
        for i = 1, #list, size do
            out[#out + 1] = { unpack(list, i, math.min(i + size - 1, #list)) }
        end
        if #out == 0 then
            out[1] = {}
        end
        return out
    end

    local function sendSession(sess, actors, vehicles, events, world)
        local info = {
            id = sess.id,
            from = sess.from,
            to = sess.to,
            subject = { char_id = sess.subject.id, name = sess.subject.name, skin = sess.subject.skin },
            origin = sess.origin,
            kinds = {},
        }
        for kind, def in pairs(kinds) do
            info.kinds[kind] = { label = def.label, color = def.color, group = def.group }
        end
        sess.started = true
        if not sess.dry then
            triggerClientEvent(sess.staff, "replaySessionStarted", sess.staff, info)
        end

        local parts = {}
        for charId, a in pairs(actors) do
            for n, slice in ipairs(slices(a.samples, SAMPLES_PER_PART)) do
                parts[#parts + 1] = {
                    actors = {
                        [charId] = {
                            name = n == 1 and a.name or nil,
                            skin = n == 1 and a.skin or nil,
                            role = n == 1 and a.role or nil,
                            samples = slice,
                        },
                    },
                }
            end
        end
        for key, v in pairs(vehicles) do
            for n, slice in ipairs(slices(v.samples, SAMPLES_PER_PART)) do
                parts[#parts + 1] = {
                    vehicles = {
                        [key] = {
                            id = n == 1 and v.id or nil,
                            model = n == 1 and v.model or nil,
                            colors = n == 1 and v.colors or nil,
                            samples = slice,
                        },
                    },
                }
            end
        end
        for _, slice in ipairs(slices(events, EVENTS_PER_PART)) do
            parts[#parts + 1] = { events = slice }
        end
        local keys = {}
        for k in pairs(world) do
            keys[#keys + 1] = k
        end
        table.sort(keys)
        for i = 1, #keys, ITEMS_PER_PART do
            local chunk = {}
            for j = i, math.min(i + ITEMS_PER_PART - 1, #keys) do
                chunk[keys[j]] = world[keys[j]]
            end
            parts[#parts + 1] = { world = { items = chunk } }
        end
        if sess.dry then
            sess.parts, sess.info = parts, info
            return #parts
        end
        return queueParts(sess, parts)
    end

    -- ------------------------------------------------------------------------------------------------------------
    -- the whole build, after the subject is known

    -- A trail point only knows the model of the vehicle its character sat in; the log's vehicle.entered events know
    -- which one it was (vehicle_id). Re-key such samples to the vehicle's database id.
    local function rekeyVehicles(sess, samples, eventRows)
        local enters = {}
        for _, r in ipairs(eventRows) do
            if r.kind == "vehicle.entered" and tonumber(r.char_id) == sess.subject.id and r.vehicle_id then
                local data = parseJson(r.data) or {}
                enters[#enters + 1] =
                    { t = tonumber(r.t_ms), model = tonumber(data.model), id = tonumber(r.vehicle_id) }
            end
        end
        for _, s in ipairs(samples) do
            if s.sparse and s.vmodel then
                local abs = s.t + sess.fromMs
                for i = #enters, 1, -1 do
                    local e = enters[i]
                    if e.t <= abs + 1500 and e.model == s.vmodel then
                        s.vkey = e.id
                        break
                    end
                end
            end
        end
    end

    local function gather(sess)
        local subject = sess.subject
        local radius = tonumber(ctx.setting("radius", 120)) or 120
        local from, to = sess.from, sess.to
        local actors, vehicles = {}, {}
        local eventRows, nearby, worldRows, hiddenRows = {}, {}, {}, {}

        local function assemble(vehicleRows)
            if sessions[sess.staff] ~= sess then
                return
            end
            local hidden = {}
            for _, r in ipairs(hiddenRows) do
                hidden[tonumber(r.id)] = true
            end
            local events = buildEvents(sess, eventRows, hidden)
            local world, worldCount = buildWorld(sess, worldRows)
            -- vehicles keep what the table knows about them (model, colours)
            for _, r in ipairs(vehicleRows) do
                local v = vehicles[tostring(tonumber(r.id))]
                if v then
                    v.model = tonumber(r.model) or v.model
                    -- "39,47,75,..." in the table; the client takes a list of numbers
                    local colors = {}
                    for n in tostring(r.colors or ""):gmatch("%-?%d+") do
                        colors[#colors + 1] = tonumber(n)
                    end
                    v.colors = #colors > 0 and colors or nil
                end
            end
            for _, v in pairs(vehicles) do
                if #v.samples == 0 and v.ride then
                    v.samples = v.ride
                end
                v.ride = nil
                table.sort(v.samples, function(a, b)
                    return a.t < b.t
                end)
            end
            local count = 0
            for _, a in pairs(actors) do
                count = count + #a.samples
            end
            sess.stats = { samples = count, events = #events, items = worldCount, actors = 0, vehicles = 0 }
            for _ in pairs(actors) do
                sess.stats.actors = sess.stats.actors + 1
            end
            for _ in pairs(vehicles) do
                sess.stats.vehicles = sess.stats.vehicles + 1
            end
            local parts = sendSession(sess, actors, vehicles, events, world)
            sess.stats.parts = parts
            say(
                sess.staff,
                " >  Replay of %s: %d samples, %d events, %d item versions, %d other players, %d vehicles (%d parts).",
                subject.name,
                count,
                #events,
                worldCount,
                sess.stats.actors - 1,
                sess.stats.vehicles,
                parts
            )
            sess.ready = true
            if sess.dry then
                M.lastDry = M.summarize(sess, actors, vehicles, events, world)
                M.stop(sess.staff, "dry run")
            end
        end

        -- all actors are loaded: the vehicles they used, then the vehicle table's rows for those with a database id
        local function finish()
            if sessions[sess.staff] ~= sess then
                return
            end
            rekeyVehicles(sess, actors[subject.id].samples, eventRows)
            local ids = {}
            for _, a in pairs(actors) do
                for _, s in ipairs(a.samples) do
                    addVehicleSample(vehicles, s)
                    if s.vkey then
                        s.veh = tostring(s.vkey)
                    end
                    s.vkey, s.vehicle, s.vmodel = nil, nil, nil
                end
            end
            for key in pairs(vehicles) do
                local id = tonumber(key)
                if id and id > 0 then
                    ids[#ids + 1] = id
                end
            end
            if #ids == 0 then
                return assemble({})
            end
            q(
                "SELECT id, model, colors FROM vehicles WHERE id IN (" .. table.concat(ids, ",") .. ")",
                {},
                function(rows)
                    assemble(rows or {})
                end
            )
        end

        local function loadNearby()
            if sessions[sess.staff] ~= sess then
                return
            end
            local picked = {}
            for _, r in ipairs(nearby) do
                if #picked < MAX_NEARBY and tonumber(r.admin_level) <= sess.level then
                    picked[#picked + 1] = r
                end
            end
            if #picked == 0 then
                return finish()
            end
            local left = gate(#picked, finish)
            for _, r in ipairs(picked) do
                loadActor(sess, tonumber(r.id), function(samples)
                    actors[tonumber(r.id)] =
                        { name = r.name, skin = tonumber(r.skin), role = "other", samples = samples }
                    left()
                end)
            end
        end

        local function afterSubject()
            local steps = gate(4, loadNearby)
            q(
                "CALL replay_events(?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, ?)",
                { subject.id, from, to, radius, MAX_EVENTS, n = 5 },
                function(rows)
                    eventRows = rows or {}
                    steps()
                end
            )
            q(
                "CALL replay_nearby(?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?)",
                { subject.id, from, to, radius, n = 4 },
                function(rows)
                    nearby = rows or {}
                    steps()
                end
            )
            q(
                "CALL replay_world(?, FROM_UNIXTIME(?), FROM_UNIXTIME(?), ?, ?)",
                { subject.id, from, to, radius, MAX_WORLD_ROWS, n = 5 },
                function(rows)
                    worldRows = rows or {}
                    steps()
                end
            )
            q("SELECT id FROM accounts WHERE admin_level > ?", { sess.level }, function(rows)
                hiddenRows = rows or {}
                steps()
            end)
        end

        loadActor(sess, subject.id, function(samples)
            if sessions[sess.staff] ~= sess then
                return
            end
            if #samples == 0 then
                return fail(sess, "nothing was recorded for " .. subject.name .. " in that range.")
            end
            actors[subject.id] = { name = subject.name, skin = subject.skin, role = "subject", samples = samples }
            afterSubject()
        end)
    end

    -- diagnostics for dryRun: sizes and a look at the first of everything, JSON for the rcon to print
    function M.summarize(sess, actors, vehicles, events, world)
        local bytes = 0
        for _, part in ipairs(sess.parts) do
            bytes = bytes + #toJSON(part, true)
        end
        local out = { stats = sess.stats, bytes = bytes, subject = sess.subject, actors = {}, events = {}, world = {} }
        for id, a in pairs(actors) do
            local first, last = a.samples[1], a.samples[#a.samples]
            local sparse = 0
            for _, s in ipairs(a.samples) do
                sparse = sparse + (s.sparse and 1 or 0)
            end
            out.actors[#out.actors + 1] = {
                id = id,
                name = a.name,
                role = a.role,
                n = #a.samples,
                sparse = sparse,
                t0 = first and first.t,
                t1 = last and last.t,
            }
        end
        for i = 1, math.min(#events, 400) do
            local e = events[i]
            out.events[#out.events + 1] =
                { t = e.t, kind = e.kind, label = e.label, x = e.x, y = e.y, char = e.char_id }
        end
        local n = 0
        for key, e in pairs(world) do
            n = n + 1
            if n <= 12 then
                out.world[#out.world + 1] =
                    { key = key, uname = e.uname, t_on = e.t_on, t_off = e.t_off, x = e.x, y = e.y }
            end
        end
        out.vehicles = {}
        for key, v in pairs(vehicles) do
            out.vehicles[#out.vehicles + 1] = { key = key, model = v.model, id = v.id, n = #v.samples }
        end
        return out
    end

    -- ------------------------------------------------------------------------------------------------------------
    -- lifecycle

    function M.isActive(staff)
        return sessions[staff] ~= nil
    end

    -- spec = { target = "name | #charId", from = unix seconds, to = unix seconds }; staff is false for a dry run
    local function begin(staff, spec, dry)
        local lvl = 5
        if not dry then
            if not isElement(staff) or getElementType(staff) ~= "player" then
                return false, "players only"
            end
            lvl = level(staff)
            if lvl < MIN_LEVEL then
                return false, "moderator level needed"
            end
            if getElementData(staff, "staff.duty") ~= true then
                return false, "go on duty first (/duty)"
            end
        end
        if sessions[staff] then
            return false, "already replaying: /replay stop first"
        end
        if type(spec) ~= "table" or type(spec.target) ~= "string" or not spec.from or not spec.to then
            return false, "bad request"
        end
        local maxRange = tonumber(ctx.setting("max_range_s", 10800)) or 10800
        if spec.to - spec.from > maxRange then
            return false, string.format("longest range is %d minutes", math.floor(maxRange / 60))
        end
        if not ctx.ready then
            return false, "database unavailable"
        end
        nextId = nextId + 1
        local x, y, z = 0, 0, 0
        local int, dim = 0, 0
        if not dry then
            x, y, z = getElementPosition(staff)
            int, dim = getElementInterior(staff), getElementDimension(staff)
        end
        local sess = {
            id = nextId,
            staff = staff,
            level = lvl,
            dry = dry or nil,
            from = math.floor(spec.from),
            to = math.floor(spec.to),
            origin = { x = x, y = y, z = z, int = int, dim = dim },
        }
        sess.fromMs, sess.toMs = sess.from * 1000, sess.to * 1000
        sessions[staff] = sess
        resolveSubject(sess, spec.target, function(row)
            if sessions[staff] ~= sess then
                return
            end
            if not row then
                return fail(sess, "no such player or character: " .. spec.target)
            end
            local accountId = tonumber(row.account_id)
            if tonumber(row.admin_level) > lvl and accountId ~= (staff and exports.auth:getAccountId(staff)) then
                return fail(sess, "that account is staff of a higher level")
            end
            if tonumber(row.pts) == 0 then
                return fail(sess, row.name .. " has nothing recorded in that range.")
            end
            sess.subject = { id = tonumber(row.id), skin = tonumber(row.skin), name = row.name, account = accountId }
            exports.staff:logAction(
                dry and "dry run" or getPlayerName(staff),
                "replay",
                row.name,
                string.format(
                    "character %d, %s to %s",
                    sess.subject.id,
                    os.date("%Y-%m-%d %H:%M", sess.from),
                    os.date("%Y-%m-%d %H:%M", sess.to)
                )
            )
            log.event("replay.started", {
                actor = staff or nil,
                target_account_id = accountId,
                target_character_id = sess.subject.id,
                from = sess.from,
                to = sess.to,
            })
            say(staff, " >  Replay: loading %s (character %d)...", row.name, sess.subject.id)
            gather(sess)
        end)
        return true
    end

    function M.start(staff, spec)
        return begin(staff, spec, false)
    end

    -- a session that builds everything and sends nothing: M.lastDry gets the summary (dev checks over rcon)
    function M.dryRun(spec)
        M.lastDry = nil
        return begin(false, spec, true)
    end

    function M.stop(staff, reason)
        local sess = sessions[staff]
        if not sess then
            return false
        end
        sessions[staff] = nil
        if sess.timer and isTimer(sess.timer) then
            killTimer(sess.timer)
        end
        if isElement(staff) then
            if sess.started and not sess.dry then
                triggerClientEvent(staff, "replaySessionEnded", staff, sess.id, reason or "stopped")
            end
            local o = sess.origin
            local x, y, z = getElementPosition(staff)
            if (x - o.x) ^ 2 + (y - o.y) ^ 2 + (z - o.z) ^ 2 > 25 then
                setElementInterior(staff, o.int)
                setElementDimension(staff, o.dim)
                setElementPosition(staff, o.x, o.y, o.z)
            end
        end
        if sess.subject then
            log.event("replay.stopped", {
                actor = isElement(staff) and staff or nil,
                target_character_id = sess.subject.id,
                reason = reason or "stopped",
                samples = sess.stats and sess.stats.samples,
                events = sess.stats and sess.stats.events,
            })
        end
        return true
    end

    function M.stopAll(reason)
        for staff in pairs(sessions) do
            M.stop(staff, reason)
        end
    end

    addEventHandler("onPlayerQuit", root, function()
        local sess = sessions[source]
        if sess then
            sessions[source] = nil
            if sess.timer and isTimer(sess.timer) then
                killTimer(sess.timer)
            end
        end
    end)

    net.handler("replayStopRequested", function(player, id)
        local sess = sessions[player]
        if sess and sess.id == tonumber(id) then
            M.stop(player, "stopped")
        end
    end, { rate = 3 })

    -- everything is sent up front (the range is capped), so a seek needs nothing more from the server
    net.handler("replaySeekRequested", function() end, { rate = 20 })

    net.handler("replaySubjectSwitchRequested", function(player, id, charId)
        local sess = sessions[player]
        if not sess or sess.id ~= tonumber(id) or not sess.ready then
            return
        end
        local spec = { target = "#" .. tostring(tonumber(charId) or 0), from = sess.from, to = sess.to }
        M.stop(player, "switching")
        M.start(player, spec)
    end, { rate = 2 })

    return M
end
