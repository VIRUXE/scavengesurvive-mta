-- The Generator and the Extension Cord on the client (server/generators.lua has the rules): a running Generator
-- lying in the world hums (a looped engine sound on its object) and says so over it; a cord plugged into a
-- building's mains inlet (power) runs from the Generator's socket down to the ground, along it and up the wall into
-- the inlet, a tube drawn with dxDrawMaterialPrimitive3D (depth-tested, so walls hide it) in the coil's own texture;
-- GTA's own ropes are only lines (CRope::Render) and MTA lights nothing it draws, so its faces are shaded here; an
-- Extension Cord in hand at an inlet offers to plug it in (cordPlugRequested).
-- ctx = { machines, lang } from client/main.lua.
return function(ctx)
    local machines, lang = ctx.machines, ctx.lang

    local CORD_UNAME = "ExtensionCord"
    local PLUG_REACH = 2.5 -- metres from the inlet (power shared/logic/mains.lua PLUG_REACH)
    local SOCKET = { -0.06, 0.17, 0.14 } -- the Generator's socket (tools/make_props.py build_generator), model space
    -- the Generator's footprint (0.52 x 0.32 m, the sockets on its +Y face): half its length and depth, and how far
    -- out from it the cord keeps when it goes round
    local GEN_HALF_X, GEN_HALF_Y, GEN_CLEAR = 0.26, 0.16, 0.18
    -- the tube: the coil's texture (prop_models cord_coil wears helixbarrier/yellow), its radius and sides,
    -- the yellow it falls back to without the texture; lit from above (LIGHT), AMBIENT of it on the faces turned
    -- away, all of it full by day or in a lit room and NIGHT_SHADE of it in the dark
    local CORD_TEXTURE = "yellow"
    local RADIUS, SIDES = 0.007, 6
    local CORD_RGB = { 225, 200, 20 }
    local LIGHT = { 0.3, 0.2, 0.93 }
    local AMBIENT = 0.45
    local NIGHT_SHADE = 0.35
    local STEP = 0.75 -- metres between the points that follow the ground
    local CORD_DRAW = 80 -- metres from the camera a cord is still drawn
    -- the engine: a small engine's idle loop out of GTA's vehicle banks, pitched up (pick another with /sfx)
    local ENGINE = { bank = 0, sound = 0, speed = 1.35, volume = 0.5, reach = 35 }

    local gens = {} -- generator item id -> its world entry e
    local cords = {} -- cord item id -> { e, site, gen, mesh = { key, verts } }
    local inlets = {} -- site id -> { x, y, z } of its inlet (power, fixed)

    local function first(data)
        local d = type(data) == "table" and data or {}
        return type(d[1]) == "table" and d[1] or d
    end

    local function stopEngine(e)
        if isElement(e.engine) then
            destroyElement(e.engine)
        end
        e.engine = nil
    end

    local function clear(id, e)
        stopEngine(e)
        gens[id], cords[id] = nil, nil
    end

    -- the row came (again)
    local function update(id, e, r)
        if r.uname == machines.GENERATOR_UNAME then
            gens[id] = e
            local running = machines.state(r.data).running
            if running and not isElement(e.engine) and isElement(e.obj) then
                local s = playSFX3D("genrl", ENGINE.bank, ENGINE.sound, e.x, e.y, e.z, true)
                if s then
                    setSoundSpeed(s, ENGINE.speed)
                    setSoundVolume(s, ENGINE.volume)
                    setSoundMaxDistance(s, ENGINE.reach)
                    setElementInterior(s, r.interior or 0)
                    setElementDimension(s, r.dimension or 0)
                    attachElements(s, e.obj)
                    e.engine = s
                end
            elseif not running then
                stopEngine(e)
            end
        elseif r.uname == CORD_UNAME then
            local d = first(r.data)
            local plugged = type(d.site) == "string" and tonumber(d.gen)
            cords[id] = plugged and { e = e, site = d.site, gen = tonumber(d.gen) } or nil
            -- plugged, the cord is run out (the line drawn below), not lying coiled: its coil is hidden, though the
            -- item stays where it is so a pickup at the inlet unplugs it
            if isElement(e.obj) then
                setElementAlpha(e.obj, plugged and 0 or 255)
            end
        end
    end

    -- the name over a Generator: running or not, and its fuel
    local function label(name, data)
        local st = machines.state(data)
        if st.running then
            return lang.format("%s (running, %.2f L)", name, st.fuel)
        end
        return lang.format("%s (off, %.2f L)", name, st.fuel)
    end

    local function powerRunning()
        local res = getResourceFromName("power")
        return res and getResourceState(res) == "running"
    end

    -- the chooser's entry with an Extension Cord in hand at a mains inlet
    local function heldActions(uname)
        if uname ~= CORD_UNAME or not powerRunning() then
            return {}
        end
        local site = exports.power:inletNear(PLUG_REACH)
        if not site then
            return {}
        end
        return {
            {
                id = "cord:plug:" .. site,
                label = lang.text("Plug the cord into the mains inlet"),
                event = "cordPlugRequested",
                target = site,
            },
        }
    end

    local function apply(m, v)
        return m[1][1] * v[1] + m[2][1] * v[2] + m[3][1] * v[3] + m[4][1],
            m[1][2] * v[1] + m[2][2] * v[2] + m[3][2] * v[3] + m[4][2],
            m[1][3] * v[1] + m[2][3] * v[2] + m[3][3] * v[3] + m[4][3]
    end

    local function ground(x, y, z)
        local gz = getGroundPosition(x, y, z + 0.5)
        return (gz and gz ~= 0 and math.abs(gz - z) < 3) and gz + 0.03 or z
    end

    -- GTA's day/night balance for building colours (world/client/blackout.lua nightBalance): 1 at night, 0 by day
    local function night()
        local h, m = getTime()
        local t = h * 60 + m
        if t < 360 or t >= 1260 then
            return 1
        elseif t < 420 then
            return (420 - t) / 60
        elseif t < 1200 then
            return 0
        end
        return (t - 1200) / 60
    end

    -- the coil's texture, read from a cord object's model (false until one is in: the tube is drawn untextured)
    local texture = false
    local function cordTexture(obj)
        if not texture and isElement(obj) then
            local found = engineGetModelTextures(getElementModel(obj), CORD_TEXTURE)
            texture = found and found[CORD_TEXTURE] or false
        end
        return texture or nil
    end

    -- the cord's centre line from the socket to the inlet (ix, iy, iz): out of the socket and down to the floor in
    -- front of it, round the Generator's nearer end when where it goes lies behind or beside it, along the floor
    -- through the site's floor points (path) a step at a time, following the ground, and up the wall into the inlet.
    -- m: the Generator's matrix (getElementMatrix)
    local function cordPoints(m, ix, iy, iz, path, floor)
        local sx, sy, sz = apply(m, SOCKET)
        local fx, fy = m[2][1], m[2][2] -- its front (+Y) and its length (+X) on the ground
        local lx, ly = m[1][1], m[1][2]
        local cx, cy = m[4][1], m[4][2]
        local ox, oy = sx + fx * 0.12, sy + fy * 0.12
        local px, py = sx + fx * GEN_CLEAR, sy + fy * GEN_CLEAR
        local pz = ground(px, py, sz)
        local pts = { { sx, sy, sz }, { ox, oy, sz }, { px, py, pz } }
        local targets = {}
        local aim = path[1] or { ix, iy }
        local tx, ty = aim[1] - cx, aim[2] - cy
        local ahead = tx * fx + ty * fy
        if ahead < GEN_HALF_Y + GEN_CLEAR then
            -- beside it: out to the front corner of the end nearer the way the cord goes; behind it: on round that
            -- end to the back corner too, never under it
            local side = (tx * lx + ty * ly) >= 0 and 1 or -1
            local reach = GEN_HALF_X + GEN_CLEAR
            targets[#targets + 1] = { cx + lx * side * reach + fx * GEN_CLEAR, cy + ly * side * reach + fy * GEN_CLEAR }
            if ahead < -GEN_HALF_Y then
                local back = GEN_HALF_Y + GEN_CLEAR
                targets[#targets + 1] = { cx + lx * side * reach - fx * back, cy + ly * side * reach - fy * back }
            end
        end
        for _, p in ipairs(path) do
            targets[#targets + 1] = p
        end
        targets[#targets + 1] = { ix, iy, last = true }
        for _, p in ipairs(targets) do
            local steps = math.max(1, math.floor(getDistanceBetweenPoints2D(px, py, p[1], p[2]) / STEP))
            local x0, y0 = px, py
            for i = 1, steps do
                local t = i / steps
                local x, y = x0 + (p[1] - x0) * t, y0 + (p[2] - y0) * t
                -- under the inlet the box itself would be the ground: the site's floor is
                local z = (p.last and floor) and floor + RADIUS or ground(x, y, pz)
                pts[#pts + 1] = { x, y, z }
                px, py, pz = x, y, z
            end
        end
        pts[#pts + 1] = { ix, iy, iz }
        return pts
    end

    local function norm(x, y, z)
        local l = math.sqrt(x * x + y * y + z * z)
        if l < 1e-6 then
            return 0, 0, 1
        end
        return x / l, y / l, z / l
    end

    -- the tube round pts as a triangle list: SIDES faces a segment, each face's corners coloured by how much of LIGHT
    -- it turns up to, times shade. Vertices are { x, y, z, colour, u, v } (with the texture) or { x, y, z, colour }.
    local function tube(pts, shade, textured)
        local lx, ly, lz = norm(LIGHT[1], LIGHT[2], LIGHT[3])
        local verts = {}
        local along = 0
        for i = 1, #pts - 1 do
            local a, b = pts[i], pts[i + 1]
            local dx, dy, dz = norm(b[1] - a[1], b[2] - a[2], b[3] - a[3])
            -- a frame round the segment: u across it (level where it can be), v = d x u
            local ux, uy, uz = norm(-dy, dx, 0)
            if math.abs(dz) > 0.99 then
                ux, uy, uz = 1, 0, 0
            end
            local vx, vy, vz = dy * uz - dz * uy, dz * ux - dx * uz, dx * uy - dy * ux
            local len = getDistanceBetweenPoints3D(a[1], a[2], a[3], b[1], b[2], b[3])
            local v0, v1 = along / 0.1, (along + len) / 0.1
            along = along + len
            for k = 0, SIDES - 1 do
                local a0, a1 = 2 * math.pi * k / SIDES, 2 * math.pi * (k + 1) / SIDES
                local c0, s0, c1, s1 = math.cos(a0), math.sin(a0), math.cos(a1), math.sin(a1)
                local n0x, n0y, n0z = ux * c0 + vx * s0, uy * c0 + vy * s0, uz * c0 + vz * s0
                local n1x, n1y, n1z = ux * c1 + vx * s1, uy * c1 + vy * s1, uz * c1 + vz * s1
                local mx, my, mz = norm(n0x + n1x, n0y + n1y, n0z + n1z)
                local lit = (AMBIENT + (1 - AMBIENT) * math.max(0, mx * lx + my * ly + mz * lz)) * shade
                local col = textured and tocolor(255 * lit, 255 * lit, 255 * lit, 255)
                    or tocolor(CORD_RGB[1] * lit, CORD_RGB[2] * lit, CORD_RGB[3] * lit, 255)
                local function corner(p, nx, ny, nz, u, v)
                    local x, y, z = p[1] + nx * RADIUS, p[2] + ny * RADIUS, p[3] + nz * RADIUS
                    if textured then
                        return { x, y, z, col, u, v }
                    end
                    return { x, y, z, col }
                end
                local u0, u1 = k / SIDES, (k + 1) / SIDES
                local p00 = corner(a, n0x, n0y, n0z, u0, v0)
                local p01 = corner(a, n1x, n1y, n1z, u1, v0)
                local p10 = corner(b, n0x, n0y, n0z, u0, v1)
                local p11 = corner(b, n1x, n1y, n1z, u1, v1)
                verts[#verts + 1] = p00
                verts[#verts + 1] = p10
                verts[#verts + 1] = p11
                verts[#verts + 1] = p00
                verts[#verts + 1] = p11
                verts[#verts + 1] = p01
            end
        end
        return verts
    end

    addEventHandler("onClientRender", root, function()
        if not next(cords) or not powerRunning() then
            return
        end
        local cx, cy, cz = getCameraMatrix()
        local litSites = exports.power:litSites()
        local dim, int = getElementDimension(localPlayer), getElementInterior(localPlayer)
        local dark = night()
        for _, c in pairs(cords) do
            local g = gens[c.gen]
            local r = c.e.row
            if
                g
                and isElement(g.obj)
                and (r.dimension or 0) == dim
                and (r.interior or 0) == int
                and getDistanceBetweenPoints3D(cx, cy, cz, c.e.x, c.e.y, c.e.z) < CORD_DRAW
            then
                local at = inlets[c.site]
                if not at then
                    local x, y, z, path, floor, room = exports.power:inletOf(c.site)
                    at = { x, y, z, path or {}, floor, room }
                    inlets[c.site] = at
                end
                if at[1] then
                    local tex = cordTexture(c.e.obj)
                    local shade = litSites[c.site] and 1 or 1 - (1 - NIGHT_SHADE) * dark
                    local m = getElementMatrix(g.obj)
                    local sx, sy, sz = apply(m, SOCKET)
                    -- the mesh is built again only when the Generator moves, the light changes or the texture comes
                    local key = string.format("%.2f,%.2f,%.2f,%.2f,%s", sx, sy, sz, shade, tex and "t" or "c")
                    if not c.mesh or c.mesh.key ~= key then
                        -- a Generator inside the room runs its cord straight across the floor, not round by the way in
                        local room = at[6]
                        local inside = room and sx >= room[1] and sx <= room[4] and sy >= room[2] and sy <= room[5]
                        local path = inside and {} or at[4]
                        local pts = cordPoints(m, at[1], at[2], at[3], path, at[5])
                        c.mesh = { key = key, verts = tube(pts, shade, tex ~= nil) }
                    end
                    if tex then
                        dxDrawMaterialPrimitive3D("trianglelist", tex, "prefx", unpack(c.mesh.verts))
                    else
                        dxDrawPrimitive3D("trianglelist", "prefx", unpack(c.mesh.verts))
                    end
                end
            end
        end
    end)

    local function isPlugged(id)
        return cords[id] ~= nil
    end

    -- the chooser's entries at a Generator: unplug each cord running from it (the other end is at the mains box)
    local function generatorActions(genId, obj)
        local out = {}
        for id, c in pairs(cords) do
            if c.gen == genId then
                out[#out + 1] = {
                    id = "unplug:" .. id,
                    label = lang.text("Unplug the cord"),
                    event = "cordUnplugRequested",
                    target = id,
                    element = obj,
                    item = true,
                }
            end
        end
        return out
    end

    return {
        update = update,
        clear = clear,
        label = label,
        heldActions = heldActions,
        isPlugged = isPlugged,
        generatorActions = generatorActions,
        CORD_UNAME = CORD_UNAME,
    }
end
