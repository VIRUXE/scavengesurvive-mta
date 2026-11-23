-- Pure replay clock and event navigation (no MTA calls at file scope). Time `t` is milliseconds since the session's
-- start; the clock advances by real elapsed milliseconds times its speed.
local M = {}

M.SPEEDS = { 0.25, 0.5, 1, 2, 4, 8, 16, 32 }
M.SKIP_LEAD_MS = 1500 -- when skipping an idle span, land this long before its end

function M.newClock(duration)
    return { t = 0, duration = duration, playing = false, speedIndex = 3, skipIdle = false, idle = {} }
end

function M.speed(clock)
    return M.SPEEDS[clock.speedIndex]
end

function M.setSpeedIndex(clock, i)
    clock.speedIndex = math.max(1, math.min(#M.SPEEDS, i))
end

function M.faster(clock)
    M.setSpeedIndex(clock, clock.speedIndex + 1)
end

function M.slower(clock)
    M.setSpeedIndex(clock, clock.speedIndex - 1)
end

function M.seek(clock, t)
    clock.t = math.max(0, math.min(clock.duration, t))
end

-- `idle`: sorted { { from, to } } spans where nothing moves and nothing happens. With skipIdle on, playing into one
-- jumps near its end.
function M.advance(clock, dtMs)
    if not clock.playing then
        return clock.t
    end
    local t = clock.t + dtMs * M.SPEEDS[clock.speedIndex]
    if clock.skipIdle then
        for _, span in ipairs(clock.idle) do
            if t > span.from + 600 and t < span.to - M.SKIP_LEAD_MS then
                t = span.to - M.SKIP_LEAD_MS
                break
            end
        end
    end
    if t >= clock.duration then
        t = clock.duration
        clock.playing = false
    end
    clock.t = t
    return t
end

-- the spans between the first and last time where no actor moved faster than `still` metres per second, changed
-- animation, weapon or vehicle, or fired, and no event fell, at least `minMs` long. A speed, not a distance per step,
-- so 5 Hz recorder samples (a walk is ~0.3 m a step) and 2 s trail points read alike. `tracks` is a list of sample
-- lists; `events` a sorted event list.
function M.idleSpans(tracks, events, duration, minMs, still)
    minMs = minMs or 8000
    still = still or 0.25
    local marks = {}
    for _, samples in ipairs(tracks) do
        for i = 2, #samples do
            local a, b = samples[i - 1], samples[i]
            local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
            local dt = math.max((b.t - a.t) / 1000, 0.05)
            local reach = still * dt
            if
                dx * dx + dy * dy + dz * dz > reach * reach
                or b.fire
                or b.weapon ~= a.weapon
                or b.veh ~= a.veh
                or b.anim ~= a.anim
            then
                marks[#marks + 1] = b.t
            end
        end
    end
    for _, e in ipairs(events) do
        marks[#marks + 1] = e.t
    end
    table.sort(marks)
    local spans, last = {}, 0
    for _, t in ipairs(marks) do
        if t - last >= minMs then
            spans[#spans + 1] = { from = last, to = t }
        end
        last = t
    end
    if duration - last >= minMs then
        spans[#spans + 1] = { from = last, to = duration }
    end
    return spans
end

-- index of the first event with t > time (+1 beyond the end), events sorted by t
function M.nextIndex(events, t)
    local lo, hi = 1, #events
    local found = #events + 1
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        if events[mid].t > t then
            found = mid
            hi = mid - 1
        else
            lo = mid + 1
        end
    end
    return found
end

-- the time of the next event after t (with a small margin so the current one is not found again), or nil
function M.nextEventTime(events, t)
    local e = events[M.nextIndex(events, t + 50)]
    return e and e.t or nil
end

function M.prevEventTime(events, t)
    local i = M.nextIndex(events, t - 50) - 1
    return events[i] and events[i].t or nil
end

-- an item entry exists at t: t_on <= t and (no t_off or t < t_off)
function M.present(entry, t)
    return (entry.t_on or 0) <= t and (entry.t_off == nil or t < entry.t_off)
end

-- seconds since from as hh:mm:ss, or with the wall clock when `from` (unix) is given
function M.format(ms)
    local s = math.floor(ms / 1000)
    return string.format("%02d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

return M
