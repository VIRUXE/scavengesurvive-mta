-- The world as it was: the item and defence rows of Appendix A (`world.items`, each with t_on / t_off) drawn with the
-- same builder the live world uses (items resource exports buildWorldRow / destroyWorldRow), created and destroyed
-- exactly when the clock crosses their t_on / t_off, within RADIUS of the point the viewer looks at. The live items
-- are hidden for this client by items:setWorldHidden for the whole session.
return function(ctx)
    local timeline = ctx.timeline
    local M = {}

    local RADIUS = 260 -- metres around the focus that get drawn
    local MAX_BUILD_PER_TICK = 60 -- so a seek into a dense base spreads over a few ticks

    local entries = {} -- key -> { row entry, handle, element }
    local list = {} -- the entries as an array, for the sweep
    local built = 0

    local function keyOf(e)
        return tostring(e.id) .. ":" .. tostring(e.t_on or 0)
    end

    function M.clear()
        for _, ent in pairs(entries) do
            if ent.handle then
                exports.items:destroyWorldRow(ent.handle)
            end
        end
        entries, list, built = {}, {}, 0
    end

    -- merge entries from a chunk (later copies of the same key replace the earlier one)
    function M.add(items)
        for _, e in pairs(items or {}) do
            if not e.holder then
                local k = keyOf(e)
                local ent = entries[k]
                if ent then
                    if ent.handle then
                        exports.items:destroyWorldRow(ent.handle)
                        ent.handle, ent.element = nil, nil
                    end
                    ent.e = e
                else
                    ent = { e = e }
                    entries[k] = ent
                    list[#list + 1] = ent
                end
            end
        end
    end

    local function row(e)
        return {
            id = e.id,
            uname = e.uname,
            x = e.x,
            y = e.y,
            z = e.z,
            rz = e.rz or 0,
            interior = e.int or 0,
            dimension = e.dim or 0,
            data = e.sdata,
            ground_nx = e.nx,
            ground_ny = e.ny,
        }
    end

    -- syncs what is built with time t around (fx, fy): destroys what left, builds what arrived
    function M.update(t, fx, fy)
        local budget = MAX_BUILD_PER_TICK
        local r2 = RADIUS * RADIUS
        for _, ent in ipairs(list) do
            local e = ent.e
            local near = fx == nil or ((e.x - fx) ^ 2 + (e.y - fy) ^ 2) <= r2
            local want = near and timeline.present(e, t)
            if want and not ent.handle and budget > 0 then
                local handle, element = exports.items:buildWorldRow(row(e))
                if handle then
                    ent.handle, ent.element = handle, element
                    built = built + 1
                    budget = budget - 1
                end
            elseif not want and ent.handle then
                exports.items:destroyWorldRow(ent.handle)
                ent.handle, ent.element = nil, nil
                built = built - 1
            end
        end
    end

    -- the items resource restarted: its handles are gone with it
    function M.forgetHandles()
        for _, ent in pairs(entries) do
            ent.handle, ent.element = nil, nil
        end
        built = 0
    end

    function M.counts()
        return #list, built
    end

    -- labels of the entries near the camera, so "which item is that" has an answer
    function M.drawLabels(t)
        local cx, cy, cz = getCameraMatrix()
        local shown = 0
        for _, ent in ipairs(list) do
            local e = ent.e
            if ent.handle and isElement(ent.element) and timeline.present(e, t) then
                local dx, dy, dz = e.x - cx, e.y - cy, e.z - cz
                if dx * dx + dy * dy + dz * dz < 144 then
                    local sx, sy = getScreenFromWorldPosition(e.x, e.y, e.z + 0.5, 0.1, false)
                    if sx then
                        dxDrawText(
                            e.uname,
                            sx + 1,
                            sy + 1,
                            sx + 1,
                            sy + 1,
                            tocolor(0, 0, 0, 200),
                            0.8,
                            "default",
                            "center",
                            "bottom"
                        )
                        dxDrawText(
                            e.uname,
                            sx,
                            sy,
                            sx,
                            sy,
                            tocolor(225, 225, 225, 230),
                            0.8,
                            "default",
                            "center",
                            "bottom"
                        )
                        shown = shown + 1
                        if shown >= 12 then
                            return
                        end
                    end
                end
            end
        end
    end

    return M
end
