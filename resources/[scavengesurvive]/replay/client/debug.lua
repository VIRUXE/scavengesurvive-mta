-- A synthetic Appendix A payload for checking the viewer without the server half: a subject who walks, runs, sprints,
-- crouches, drives a car and shoots around the given point, another character following, a few events and a small
-- base whose pieces come and go. Returns info (replaySessionStarted) and part (one replayChunkReceived part).
return function(cx, cy, cz, from)
    local DURATION = 90 -- seconds
    local actors, vehicles, events = {}, {}, {}
    local subject = { name = "DemoSubject", skin = 0, role = "subject", samples = {} }
    local other = { name = "DemoOther", skin = 7, role = "other", samples = {} }
    local car = { id = 1, model = 411, colors = { 0, 1, 0, 1 }, samples = {} }
    actors[900001], actors[900002], vehicles.v1 = subject, other, car

    local function ring(r, a)
        local rad = math.rad(a)
        return cx + r * math.cos(rad), cy + r * math.sin(rad)
    end

    for step = 0, DURATION * 5 do
        local t = step * 200
        local s = t / 1000
        -- phases: 0-10 walk, 10-20 run, 20-30 sprint, 30-36 crouch, 36-40 stand and aim, 40-60 drive, 60-90 on foot
        local angle = (s * 14) % 360
        local x, y = ring(16, angle)
        local sample = {
            t = t,
            x = x,
            y = y,
            z = cz,
            rz = angle % 360,
            int = 0,
            dim = 0,
            hp = 100 - math.floor(s / 6),
            weapon = 0,
        }
        if s < 10 then
            sample.move = "walk"
            sample.x, sample.y = ring(16, s * 9)
            sample.rz = (s * 9) % 360
        elseif s < 20 then
            sample.move = "run"
            sample.x, sample.y = ring(16, 90 + (s - 10) * 22)
            sample.rz = (90 + (s - 10) * 22) % 360
        elseif s < 30 then
            sample.move = "sprint"
            sample.x, sample.y = ring(16, 310 + (s - 20) * 34)
            sample.rz = (310 + (s - 20) * 34) % 360
        elseif s < 36 then
            sample.move = "crouch"
            sample.x, sample.y = ring(16, 650 + (s - 30) * 5)
            sample.rz = (650 + (s - 30) * 5) % 360
        elseif s < 40 then
            sample.move = "stand"
            sample.x, sample.y = ring(16, 680)
            sample.rz = 180
            sample.weapon = 30
            local ax, ay = ring(60, 0)
            sample.aim = { ax, ay, cz }
            sample.fire = (step % 3 == 0) or nil
        elseif s < 60 then
            local ca = 40 + (s - 40) * 18
            local vx, vy = ring(24, ca)
            sample.x, sample.y, sample.z = vx, vy, cz
            sample.rz = (ca + 90) % 360
            sample.veh, sample.seat, sample.move = "v1", 0, "vehicle"
            car.samples[#car.samples + 1] =
                { t = t, x = vx, y = vy, z = cz, rx = 0, ry = 0, rz = (ca + 90) % 360 - 0, hp = 1000 - (s - 40) * 10 }
        else
            sample.move = (s % 8 < 4) and "walk" or "run"
            sample.x, sample.y = ring(10 + (s - 60) * 0.3, 200 + (s - 60) * 12)
            sample.rz = (200 + (s - 60) * 12) % 360
        end
        subject.samples[#subject.samples + 1] = sample
        -- the other character stays 4 s behind the subject, sparse (2 s samples) like character_track
        if step % 10 == 0 and t >= 4000 then
            local back = subject.samples[math.max(1, #subject.samples - 20)]
            other.samples[#other.samples + 1] =
                { t = t, x = back.x + 2, y = back.y + 2, z = cz, int = 0, dim = 0, sparse = true }
        end
    end
    local function ev(t, kind, label, x, y, z, extra)
        local e = { t = t * 1000, kind = kind, label = label, x = x, y = y, z = z, char_id = 900001 }
        for k, v in pairs(extra or {}) do
            e[k] = v
        end
        events[#events + 1] = e
    end
    local px, py = ring(16, 0)
    ev(5, "item.taken", "took Crowbar", px, py, cz)
    ev(25, "building.removed", "removed WoodPanel", cx + 6, cy, cz, { item_id = 801 })
    ev(30, "building.placed", "placed WoodPanel", cx - 6, cy, cz, { item_id = 802 })
    ev(38, "weapon.fired", "fired AK-47", cx, cy - 16, cz)
    ev(40, "vehicle.entered", "entered Infernus", ring(24, 40))
    ev(60, "vehicle.exited", "left Infernus", ring(24, 400))
    ev(75, "chat.messageSent", "says: hello", cx, cy, cz)
    ev(88, "death.died", "died", cx, cy, cz)

    local function panel(id, x, y, rz, tOn, tOff)
        return {
            id = id,
            uname = "WoodPanel",
            x = x,
            y = y,
            z = cz + 0.2,
            rz = rz,
            int = 0,
            dim = 0,
            sdata = { defence = { active = true, rx = 0, ry = 0, pose = "vertical" } },
            t_on = tOn,
            t_off = tOff,
        }
    end
    local items = {}
    for i = 0, 3 do
        local it = panel(800 + i, cx + 6, cy - 3 + i * 2.2, 90, -1)
        if i == 1 then
            it.t_off = 25000
        end
        items[#items + 1] = it
    end
    items[#items + 1] = panel(802, cx - 6, cy, 0, 30000)
    items[#items + 1] =
        { id = 810, uname = "Crowbar", x = px, y = py, z = cz - 0.8, rz = 0, int = 0, dim = 0, t_on = -1, t_off = 5000 }
    items[#items + 1] =
        { id = 811, uname = "CanDrink", x = cx + 2, y = cy + 2, z = cz - 0.8, rz = 20, int = 0, dim = 0, t_on = 12000 }

    local info = {
        id = 1,
        from = from,
        to = from + DURATION,
        tz = 0,
        subject = { char_id = 900001, name = "DemoSubject", skin = 0 },
        origin = { x = cx, y = cy, z = cz, int = 0, dim = 0 },
        kinds = {},
    }
    local part = { actors = actors, vehicles = vehicles, events = events, world = { items = items } }
    return info, part
end
