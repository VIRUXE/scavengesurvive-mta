-- /house: tours the SA-MP house shells the maps place, one after another, dropping the player on foot a couple of
-- metres outside an entrance, facing it, free to walk in (shared/logic/houses.lua picks the spot). The move is a
-- server-side setElementPosition, which the anticheat's movement monitor ignores. "[" and "]" step back and forth
-- once /house has been used; /house off drops those binds. Loaded by server/main.lua with
-- { logic = <shared/logic/houses.lua>, say = say, command = command, studio = studio }.
return function(ctx)
    local houses, say = ctx.logic, ctx.say
    local list, doors -- built on first use from the maps resource's files
    local at = {} -- player -> { i = house index, door = entrance number }
    local bound = {} -- player -> true while [ and ] are bound

    local function readLua(path)
        local f = fileOpen(path, true)
        if not f then
            return nil
        end
        local src = fileRead(f, fileGetSize(f))
        fileClose(f)
        return assert(loadstring(src, "=" .. path))()
    end

    local function load()
        if list then
            return
        end
        local zones = {}
        for zone in pairs(readLua(":maps/data/index.lua") or {}) do
            zones[zone] = readLua(":maps/data/" .. zone .. ".lua") or {}
        end
        list = houses.collect(zones)
        doors = readLua(":maps/shared/shell_doors.lua") or {}
    end

    local function go(p, i, nth)
        local h = list[i]
        local x, y, z, rz, n, count = houses.spot(h, doors[h.model], nth)
        at[p] = { i = i, door = n }
        local vehicle = getPedOccupiedVehicle(p)
        if vehicle then
            removePedFromVehicle(p)
        end
        setElementDimension(p, 0)
        setElementInterior(p, 0)
        setElementPosition(p, x, y, z)
        setElementRotation(p, 0, 0, rz, "default", true)
        setCameraTarget(p, p)
        local where = string.format("%.1f, %.1f, %.1f", h.x, h.y, h.z)
        say(p, "house %d/%d: %s at %s (%s, entrance %d/%d)", i, #list, h.name, where, h.zone, n, count)
    end

    local step

    local function bind(p)
        if bound[p] then
            return
        end
        bound[p] = true
        bindKey(p, "]", "down", step, "next")
        bindKey(p, "[", "down", step, "prev")
    end

    local function unbind(p)
        if not bound[p] then
            return
        end
        bound[p] = nil
        unbindKey(p, "]", "down", step)
        unbindKey(p, "[", "down", step)
    end

    function step(p, _, _, arg)
        if ctx.studio.isIn(p) then
            return say(p, "leave the studio first (/studio)")
        end
        load()
        local cur = at[p]
        if arg == "door" then
            if not cur then
                return say(p, "no house yet: /house first")
            end
            return go(p, cur.i, cur.door + 1)
        end
        local i, err = houses.pick(list, cur and cur.i or 0, arg)
        if not i then
            return say(p, "%s", err)
        end
        go(p, i, 1)
    end

    ctx.command("house", function(p, arg)
        if arg == "help" then
            say(p, "/house [next|prev|<n>|<name>|door|list|off]  next house, previous, number n, next of a type")
            return say(p, "(e.g. lshouse2), next entrance of this house, counts per type, drop the [ and ] keys")
        end
        if arg == "off" then
            unbind(p)
            return say(p, "house keys unbound")
        end
        if arg == "list" then
            load()
            return say(p, "%d houses: %s", #list, houses.summary(list))
        end
        bind(p)
        step(p, nil, nil, arg)
    end)

    addEventHandler("onPlayerQuit", root, function()
        at[source] = nil
        bound[source] = nil
    end)
end
