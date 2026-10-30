-- A launched Firework Box (shared/logic/firework.lua, #150): the server says where and when (fireworkLaunched), each
-- client flies the rocket and its sparks itself. A projectile is the rocket model or a GTA effect moved along its
-- line every frame, removed where it stops and burst there into the next generation.
return function(firework)
    local flying = {} -- { p, el, start, interior, dimension }

    local function randInt(n)
        return math.random(0, n - 1)
    end

    local function spawn(p, interior, dimension)
        if #flying >= firework.MAX_PROJECTILES then
            return
        end
        local x, y, z = p.from[1], p.from[2], p.from[3]
        local el
        if type(p.look) == "number" then
            el = createObject(p.look, x, y, z, 90, 0, 0)
            if el then
                setElementCollisionsEnabled(el, false)
            end
        else
            el = createEffect(p.look, x, y, z)
        end
        if not el then
            return
        end
        setElementInterior(el, interior)
        setElementDimension(el, dimension)
        flying[#flying + 1] = { p = p, el = el, start = getTickCount(), interior = interior, dimension = dimension }
    end

    addEventHandler("fireworkLaunched", resourceRoot, function(x, y, z, interior, dimension)
        spawn(firework.launch(x, y, z, randInt), interior or 0, dimension or 0)
    end)

    addEventHandler("onClientPreRender", root, function()
        if #flying == 0 then
            return
        end
        local now = getTickCount()
        local landed = {}
        for i = #flying, 1, -1 do
            local f = flying[i]
            local t = math.min(1, (now - f.start) / f.p.ms)
            local a, b = f.p.from, f.p.to
            if isElement(f.el) then
                setElementPosition(f.el, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t)
            end
            if t >= 1 then
                if isElement(f.el) then
                    destroyElement(f.el)
                end
                table.remove(flying, i)
                landed[#landed + 1] = f
            end
        end
        for _, f in ipairs(landed) do
            for _, child in ipairs(firework.burst(f.p, randInt)) do
                spawn(child, f.interior, f.dimension)
            end
        end
    end)
end
