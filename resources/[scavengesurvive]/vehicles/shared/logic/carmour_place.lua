-- Where a defence goes when it is attached to a vehicle (carmour, shared/logic/carmour.lua): the geometry of
-- shared/data/carmour_geometry.lua (the shell's triangles, the door leaf, every defence's frame) and a ray from the
-- player's camera, all in the vehicle's frame. The client draws its ghost from this and the server places the panel
-- from the same ray, so both agree and the client cannot place anything the rules refuse.
-- A body panel lies flat on the shell at full size where the ray meets it, turned by the surface it is on: its long
-- side level (along the trailer on the roof), pushed out until no part of the shell under it pokes through. A door
-- defence goes on the door leaf only, stretched to fill it exactly. No two panels may overlap, and no body panel may
-- stand where the door swings.
-- Pure: no MTA calls.
local M = {}

M.PROUD = 0.02 -- metres between the shell's highest point under a panel and the panel's inner face
M.SUPPORT = 0.7 -- the share of a body panel's footprint that must have the shell under it, close behind it
M.SUPPORT_GAP = 0.35 -- metres behind the panel's inner face the body must be, under SUPPORT of its face (it sits on
-- the body, not floating off a curve)
M.MAX_LIFT = 0.8 -- metres a panel may stand off the shell where the ray met it (a sharp curve under a flat panel)
M.LIFT_STEP = 0.02 -- metres a panel is pushed out at a time until no triangle of the shell touches it
M.FLOOR_Z = -0.3 -- a panel holds onto the body above this height (below is the chassis under the floor)
M.GROUND_Z = -0.75 -- and no part of it reaches below the ground the wheels stand on
M.EXPOSED = 4 -- of 5 rays fanned out from where a panel holds on, this many must leave the trailer: the outer skin
M.ESCAPE = 15 -- metres a ray must travel clear to count as leaving the trailer
M.SAMPLES = 5 -- footprint samples per side
M.SMOOTH = 0.45 -- metres around the hit whose triangles' normals the panel's facing averages
M.DOOR_SWING = 1.05 -- metres in front of the door kept clear for it to swing
-- the defences that can be welded on: metal ones (a wooden or insulated panel, or a plain door, cannot be)
M.METAL = { MetPanel = true, CorPanel = true, SmallPanel = true, MetalGate = true, CrateDoor = true, ShipDoor = true }

M.REACH = 12.0 -- the camera ray's length (a third-person camera sits a few metres behind the player)
M.CELL = 0.5 -- metres per cell of the grid the triangles are bucketed in (rays only test the cells they cross)

local function sub(a, b)
    return { a[1] - b[1], a[2] - b[2], a[3] - b[3] }
end

local function add(a, b)
    return { a[1] + b[1], a[2] + b[2], a[3] + b[3] }
end

local function mul(a, s)
    return { a[1] * s, a[2] * s, a[3] * s }
end

local function dot(a, b)
    return a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
end

local function cross(a, b)
    return { a[2] * b[3] - a[3] * b[2], a[3] * b[1] - a[1] * b[3], a[1] * b[2] - a[2] * b[1] }
end

local function norm(a)
    local l = math.sqrt(dot(a, a))
    if l < 1e-9 then
        return nil
    end
    return mul(a, 1 / l)
end

M.vec = { sub = sub, add = add, mul = mul, dot = dot, cross = cross, norm = norm }

-- "x,y,z,..." / "i,j,k,..." -> a mesh { verts, tris = { {a, b, c} }, normals, centres, areas }
local function parseMesh(vs, ts)
    local nums, verts, tris = {}, {}, {}
    for n in string.gmatch(vs, "[^,]+") do
        nums[#nums + 1] = tonumber(n)
    end
    for i = 1, #nums, 3 do
        verts[#verts + 1] = { nums[i], nums[i + 1], nums[i + 2] }
    end
    local idx = {}
    for n in string.gmatch(ts, "[^,]+") do
        idx[#idx + 1] = tonumber(n)
    end
    local normals, centres, areas, grid = {}, {}, {}, {}
    local cell = M.CELL
    for i = 1, #idx, 3 do
        local a, b, c = verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]]
        local nrm = cross(sub(b, a), sub(c, a))
        local area = math.sqrt(dot(nrm, nrm)) / 2
        tris[#tris + 1] = { a, b, c }
        normals[#normals + 1] = norm(nrm) or { 0, 0, 1 }
        areas[#areas + 1] = area
        centres[#centres + 1] = mul(add(add(a, b), c), 1 / 3)
        local ti = #tris
        local lo, hi = {}, {}
        for k = 1, 3 do
            lo[k] = math.floor(math.min(a[k], b[k], c[k]) / cell)
            hi[k] = math.floor(math.max(a[k], b[k], c[k]) / cell)
        end
        for x = lo[1], hi[1] do
            for y = lo[2], hi[2] do
                for z = lo[3], hi[3] do
                    local key = ((x + 500) * 1000 + y + 500) * 1000 + z + 500
                    local list = grid[key]
                    if not list then
                        list = {}
                        grid[key] = list
                    end
                    list[#list + 1] = ti
                end
            end
        end
    end
    return { tris = tris, normals = normals, centres = centres, areas = areas, grid = grid }
end

-- the triangles in the cells a segment from o along d (unit) for len metres crosses
local function candidates(mesh, o, d, len)
    local cell, seen, out, cells = M.CELL, {}, {}, {}
    local steps = math.ceil(len / (cell / 3))
    local grid = mesh.grid
    for i = 0, steps do
        local f = len * i / steps
        local x = math.floor((o[1] + d[1] * f) / cell)
        local y = math.floor((o[2] + d[2] * f) / cell)
        local z = math.floor((o[3] + d[3] * f) / cell)
        local key = ((x + 500) * 1000 + y + 500) * 1000 + z + 500
        if not cells[key] then
            cells[key] = true
            local list = grid[key]
            if list then
                for k = 1, #list do
                    local ti = list[k]
                    if not seen[ti] then
                        seen[ti] = true
                        out[#out + 1] = ti
                    end
                end
            end
        end
    end
    return out
end

-- the parsed geometry of shared/data/carmour_geometry.lua (once per resource)
function M.load(data)
    local door = data.DOOR
    local f = door.face
    return {
        model = data.MODEL,
        shell = parseMesh(data.SHELL.verts, data.SHELL.tris),
        extra = parseMesh(data.EXTRA.verts, data.EXTRA.tris),
        leaf = parseMesh(door.verts, door.tris),
        door = door,
        panels = data.PANELS,
        -- the room the door needs to open: a box in front of its outer face
        doorZone = {
            c = { f.x - M.DOOR_SWING / 2, (f.y0 + f.y1) / 2, (f.z0 + f.z1) / 2 },
            ax = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } },
            h = { M.DOOR_SWING / 2 + 0.02, (f.y1 - f.y0) / 2, (f.z1 - f.z0) / 2 },
        },
    }
end

-- Moller-Trumbore: the distance along d (unit) from o to the nearest triangle of mesh, and its index, within maxT
local function raycast(mesh, o, d, maxT)
    local best, bestI = maxT, nil
    for _, i in ipairs(candidates(mesh, o, d, maxT)) do
        local t = mesh.tris[i]
        local e1, e2 = sub(t[2], t[1]), sub(t[3], t[1])
        local p = cross(d, e2)
        local det = dot(e1, p)
        if det > 1e-9 or det < -1e-9 then
            local inv = 1 / det
            local s = sub(o, t[1])
            local u = dot(s, p) * inv
            if u >= 0 and u <= 1 then
                local q = cross(s, e1)
                local v = dot(d, q) * inv
                if v >= 0 and u + v <= 1 then
                    local dist = dot(e2, q) * inv
                    if dist > 1e-4 and dist < best then
                        best, bestI = dist, i
                    end
                end
            end
        end
    end
    if bestI then
        return best, bestI
    end
    return nil
end

M.raycast = raycast

-- the shell's facing around point p: the hit triangle's facing (turned towards `toward`) averaged with the triangles
-- near it that face the same way within 60 degrees (a hatch's sides or an inside wall nearby do not tip it over)
local function smoothNormal(mesh, p, toward, hitIndex)
    local ref = mesh.normals[hitIndex]
    if dot(ref, toward) < 0 then
        ref = mul(ref, -1)
    end
    local sum = { 0, 0, 0 }
    local r2 = M.SMOOTH * M.SMOOTH
    for i, c in ipairs(mesh.centres) do
        local dd = sub(c, p)
        if dot(dd, dd) <= r2 then
            local n = mesh.normals[i]
            if dot(n, ref) < 0 then
                n = mul(n, -1)
            end
            if dot(n, ref) > 0.5 then
                sum = add(sum, mul(n, mesh.areas[i]))
            end
        end
    end
    return norm(sum) or ref
end

-- Separating axis test of two oriented boxes { c, ax = { u, v, n } (unit), h = { half extents } }.
function M.boxesOverlap(a, b)
    local axes = { a.ax[1], a.ax[2], a.ax[3], b.ax[1], b.ax[2], b.ax[3] }
    for i = 1, 3 do
        for j = 1, 3 do
            local c = norm(cross(a.ax[i], b.ax[j]))
            if c then
                axes[#axes + 1] = c
            end
        end
    end
    local t = sub(b.c, a.c)
    for _, l in ipairs(axes) do
        local ra = math.abs(dot(a.ax[1], l)) * a.h[1]
            + math.abs(dot(a.ax[2], l)) * a.h[2]
            + math.abs(dot(a.ax[3], l)) * a.h[3]
        local rb = math.abs(dot(b.ax[1], l)) * b.h[1]
            + math.abs(dot(b.ax[2], l)) * b.h[2]
            + math.abs(dot(b.ax[3], l)) * b.h[3]
        if math.abs(dot(t, l)) > ra + rb then
            return false
        end
    end
    return true
end

-- whether triangle t (three points) touches box b { c, ax, h } (separating axes: the box's three, the triangle's
-- normal and the nine crosses of their edges)
local function triangleTouchesBox(t, b)
    local v = {}
    for i = 1, 3 do
        local d = sub(t[i], b.c)
        v[i] = { dot(d, b.ax[1]), dot(d, b.ax[2]), dot(d, b.ax[3]) }
    end
    local h = b.h
    for k = 1, 3 do
        local lo = math.min(v[1][k], v[2][k], v[3][k])
        local hi = math.max(v[1][k], v[2][k], v[3][k])
        if lo > h[k] or hi < -h[k] then
            return false
        end
    end
    local e = { sub(v[2], v[1]), sub(v[3], v[2]), sub(v[1], v[3]) }
    local axes = { cross(e[1], e[2]) }
    local unit = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
    for i = 1, 3 do
        for j = 1, 3 do
            axes[#axes + 1] = cross(unit[i], e[j])
        end
    end
    for _, a in ipairs(axes) do
        if dot(a, a) > 1e-12 then
            local p1, p2, p3 = dot(v[1], a), dot(v[2], a), dot(v[3], a)
            local r = h[1] * math.abs(a[1]) + h[2] * math.abs(a[2]) + h[3] * math.abs(a[3])
            if math.min(p1, p2, p3) > r or math.max(p1, p2, p3) < -r then
                return false
            end
        end
    end
    return true
end

-- whether any triangle of mesh touches box b (only the triangles in the grid cells the box's bounds cover)
local function meshTouchesBox(mesh, b)
    local lo, hi = { math.huge, math.huge, math.huge }, { -math.huge, -math.huge, -math.huge }
    for _, sx in ipairs({ -1, 1 }) do
        for _, sy in ipairs({ -1, 1 }) do
            for _, sz in ipairs({ -1, 1 }) do
                local q =
                    add(add(add(b.c, mul(b.ax[1], sx * b.h[1])), mul(b.ax[2], sy * b.h[2])), mul(b.ax[3], sz * b.h[3]))
                for k = 1, 3 do
                    lo[k], hi[k] = math.min(lo[k], q[k]), math.max(hi[k], q[k])
                end
            end
        end
    end
    local cell, seen = M.CELL, {}
    for x = math.floor(lo[1] / cell), math.floor(hi[1] / cell) do
        for y = math.floor(lo[2] / cell), math.floor(hi[2] / cell) do
            for z = math.floor(lo[3] / cell), math.floor(hi[3] / cell) do
                local list = mesh.grid[((x + 500) * 1000 + y + 500) * 1000 + z + 500]
                for _, ti in ipairs(list or {}) do
                    if not seen[ti] then
                        seen[ti] = true
                        if triangleTouchesBox(mesh.tris[ti], b) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

M.meshTouchesBox = meshTouchesBox

-- whether a placed panel's box touches the body or the solid parts around it
local function touchesTrailer(geo, b)
    return meshTouchesBox(geo.shell, b) or meshTouchesBox(geo.extra, b)
end

-- whether point p, facing n, is on the trailer's outer skin: most rays fanned out from it leave the trailer (an
-- inside wall seen through a window, or the frame under the floor, is boxed in)
local function exposed(geo, p, n, u, v)
    local o = add(p, mul(n, 0.03))
    local dirs = {
        n,
        norm(add(n, mul(u, 0.6))),
        norm(add(n, mul(u, -0.6))),
        norm(add(n, mul(v, 0.6))),
        norm(add(n, mul(v, -0.6))),
    }
    local free = 0
    for _, d in ipairs(dirs) do
        if not raycast(geo.shell, o, d, M.ESCAPE) and not raycast(geo.extra, o, d, M.ESCAPE) then
            free = free + 1
        end
    end
    return free >= M.EXPOSED
end

-- the lowest point of box b
local function lowestZ(b)
    return b.c[3] - math.abs(b.ax[1][3]) * b.h[1] - math.abs(b.ax[2][3]) * b.h[2] - math.abs(b.ax[3][3]) * b.h[3]
end

-- A placed panel's box from its record { c = centre, l, s (unit, in the panel's plane: long and short side), sa, sb }
-- and its defence frame (ext along a, b, c).
function M.boxOf(rec, frame)
    local n = cross(rec.l, rec.s)
    return {
        c = rec.c,
        ax = { rec.l, rec.s, n },
        h = { frame.ext[1] * (rec.sa or 1) / 2, frame.ext[2] * (rec.sb or 1) / 2, frame.ext[3] / 2 },
    }
end

-- the defence on the door leaf: stretched to the leaf's outer face, long side up, its face outward (-X)
local function doorPlacement(geo, frame)
    local f = geo.door.face
    local w, h = f.y1 - f.y0, f.z1 - f.z0
    return {
        door = true,
        c = { f.x - M.PROUD - frame.ext[3] / 2, (f.y0 + f.y1) / 2, (f.z0 + f.z1) / 2 },
        l = { 0, 0, 1 },
        s = { 0, 1, 0 },
        sa = h / frame.ext[1],
        sb = w / frame.ext[2],
    }
end

-- A stored record as it stands now: a door defence always covers the door's opening as the geometry gives it (a
-- record keeps only that it is on the door), every other record is its stored placement.
function M.effective(geo, rec)
    local frame = geo.panels[rec.u]
    if not rec.door or not frame then
        return rec
    end
    local d = doorPlacement(geo, frame)
    d.u, d.id, d.hp, d.w = rec.u, rec.id, rec.hp, rec.w
    return d
end

-- Where the defence `uname` goes for a ray from o along d (unit; the vehicle's frame), among the vehicle's
-- `existing` records (each with .u = its uname and the placement fields). Returns the record, or nil and why:
-- "NOT_METAL" (only metal defences can be welded on), "MISS" (the ray meets no outside part of the trailer),
-- "DOOR_ONLY" (a door defence away from the door), "NOT_DOOR" (a panel aimed at the door), "UNSUPPORTED" (hangs off
-- the shell, stands too far off it, under the floor or into the ground), "BLOCKS_DOOR", "CLASH".
function M.place(geo, uname, o, d, existing)
    local frame = geo.panels[uname]
    if not frame then
        return nil, "NOT_DEFENCE"
    end
    if not M.METAL[uname] then
        return nil, "NOT_METAL"
    end
    local tShell, iShell = raycast(geo.shell, o, d, M.REACH)
    local tLeaf = raycast(geo.leaf, o, d, M.REACH)
    local rec
    if tLeaf and (not tShell or tLeaf <= tShell + 0.05) then
        if not frame.door then
            return nil, "NOT_DOOR"
        end
        rec = doorPlacement(geo, frame)
    else
        if not tShell then
            return nil, "MISS"
        end
        if frame.door then
            return nil, "DOOR_ONLY"
        end
        local p = add(o, mul(d, tShell))
        local tExtra = raycast(geo.extra, o, d, M.REACH)
        if p[3] < M.FLOOR_Z or (tExtra and tExtra < tShell) then
            return nil, "UNSUPPORTED" -- under the floor, or the step, hitch or a gas tank in the way
        end
        local n = smoothNormal(geo.shell, p, mul(d, -1), iShell)
        -- the long side level: across the facing and world up, or along the trailer on a roof
        local up = math.abs(n[3]) > 0.7 and { 0, 1, 0 } or { 0, 0, 1 }
        local u = norm(cross(up, n)) or { 0, 1, 0 }
        local v = cross(n, u)
        if not exposed(geo, p, n, u, v) then
            return nil, "MISS" -- an inside surface: aim at the outside of the trailer
        end
        local hw, hh = frame.ext[1] / 2, frame.ext[2] / 2
        local lift, hits, total = -math.huge, 0, 0
        for i = 0, M.SAMPLES - 1 do
            for j = 0, M.SAMPLES - 1 do
                local du = (i / (M.SAMPLES - 1) * 2 - 1) * hw
                local dv = (j / (M.SAMPLES - 1) * 2 - 1) * hh
                local s = add(add(p, mul(u, du)), mul(v, dv))
                local t = raycast(geo.shell, add(s, mul(n, 1.2)), mul(n, -1), 1.2 + M.SUPPORT_GAP)
                total = total + 1
                if t then
                    hits = hits + 1
                    lift = math.max(lift, 1.2 - t)
                end
            end
        end
        if hits < total * M.SUPPORT or lift > M.MAX_LIFT then
            return nil, "UNSUPPORTED"
        end
        rec = { door = false, c = add(p, mul(n, lift + M.PROUD + frame.ext[3] / 2)), l = u, s = v, sa = 1, sb = 1 }
        -- the samples only see the shell under 25 points: pushed out until no triangle of it touches the panel
        while touchesTrailer(geo, M.boxOf(rec, frame)) do
            lift = lift + M.LIFT_STEP
            if lift > M.MAX_LIFT then
                return nil, "UNSUPPORTED"
            end
            rec.c = add(p, mul(n, lift + M.PROUD + frame.ext[3] / 2))
        end
        -- where it ended up, most of its inner face is close to the body
        local face = lift + M.PROUD
        local near = 0
        for i = 0, M.SAMPLES - 1 do
            for j = 0, M.SAMPLES - 1 do
                local du = (i / (M.SAMPLES - 1) * 2 - 1) * hw
                local dv = (j / (M.SAMPLES - 1) * 2 - 1) * hh
                local s = add(add(add(p, mul(u, du)), mul(v, dv)), mul(n, face))
                if raycast(geo.shell, s, mul(n, -1), M.SUPPORT_GAP) then
                    near = near + 1
                end
            end
        end
        if near < total * M.SUPPORT then
            return nil, "UNSUPPORTED"
        end
        if lowestZ(M.boxOf(rec, frame)) < M.GROUND_Z then
            return nil, "UNSUPPORTED"
        end
        if M.boxesOverlap(M.boxOf(rec, frame), geo.doorZone) then
            return nil, "BLOCKS_DOOR"
        end
    end
    local box = M.boxOf(rec, frame)
    for _, other in ipairs(existing or {}) do
        local of = geo.panels[other.u]
        if of and M.boxesOverlap(box, M.boxOf(M.effective(geo, other), of)) then
            return nil, "CLASH"
        end
    end
    return rec
end

-- GTA's ZXY rotation (R = Rz * Rx * Ry, attachElements' rx, ry, rz in degrees) of a 3x3 row-major matrix
local function toZXY(m)
    local sa = math.max(-1, math.min(1, m[3][2]))
    if math.abs(sa) > 1 - 1e-9 then
        return math.deg(math.asin(sa)), 0, math.deg(math.atan2(m[2][1], m[1][1]))
    end
    return math.deg(math.asin(sa)), math.deg(math.atan2(-m[3][1], m[3][3])), math.deg(math.atan2(-m[1][2], m[2][2]))
end

-- How the defence's object is attached for a record: offset x, y, z, rotation rx, ry, rz and the object's scale
-- along its own x, y, z (a door defence is stretched along its frame's a and b; the frames are axis aligned).
function M.attachOf(rec, frame)
    local n = cross(rec.l, rec.s)
    local cols = { rec.l, rec.s, n } -- where the frame's a, b, c go
    local rows = { frame.a, frame.b, frame.c }
    local m = {}
    for i = 1, 3 do
        m[i] = {}
        for j = 1, 3 do
            m[i][j] = cols[1][i] * rows[1][j] + cols[2][i] * rows[2][j] + cols[3][i] * rows[3][j]
        end
    end
    -- only a door defence is stretched: each of its frame's axes scales the model axis it runs along
    local sFrame = { rec.sa or 1, rec.sb or 1, 1 }
    local scale = { 1, 1, 1 }
    for k = 1, 3 do
        local best = 1
        for axis = 2, 3 do
            if math.abs(rows[k][axis]) > math.abs(rows[k][best]) then
                best = axis
            end
        end
        scale[best] = sFrame[k]
    end
    local cm = { frame.centre[1] * scale[1], frame.centre[2] * scale[2], frame.centre[3] * scale[3] }
    local rc = {
        m[1][1] * cm[1] + m[1][2] * cm[2] + m[1][3] * cm[3],
        m[2][1] * cm[1] + m[2][2] * cm[2] + m[2][3] * cm[3],
        m[3][1] * cm[1] + m[3][2] * cm[2] + m[3][3] * cm[3],
    }
    local rx, ry, rz = toZXY(m)
    local pos = sub(rec.c, rc)
    local out = { x = pos[1], y = pos[2], z = pos[3], rx = rx, ry = ry, rz = rz }
    out.sx, out.sy, out.sz = scale[1], scale[2], scale[3]
    return out
end

-- the distance from point p to a record's box (0 inside it)
function M.distanceTo(rec, frame, p)
    local b = M.boxOf(rec, frame)
    local t = sub(p, b.c)
    local s = 0
    for i = 1, 3 do
        local d = math.abs(dot(t, b.ax[i])) - b.h[i]
        if d > 0 then
            s = s + d * d
        end
    end
    return math.sqrt(s)
end

return M
