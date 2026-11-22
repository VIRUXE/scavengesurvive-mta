-- How an item comes to rest by its own shape. An item type lies in its rest rotation (rotx, roty, rotz) with its
-- lowest point on the ground (item_rest.lua); when that lowest point is a wing mirror, a handle or a brim, the rest of
-- it hangs level in the air over it. Here the mesh the clients draw (the .dff of a model pack, read by the server) is
-- put down in that rotation and tips as a rigid body would: about what it stands on, towards its centre of mass,
-- until the centre of mass is over what touches the ground. A door then lies on its mirror and its far edge.
--
-- settle.mesh(bytes) reads a .dff; settle.pose(mesh, rotx, roty, rotz) is the tipped pose of a type (false when it
-- lies well as declared, or stands on purpose); settle.lay(pose, rz, nx, ny) is that pose at a heading on a surface,
-- as the heading and ground normal an item row stores (items/client/world.lua turns the object by them).
local SUPPORT = 0.004 -- metres over the lowest point that still count as touching the ground
local INSIDE = 0.01 -- the centre of mass may sit this far outside what touches and still be held
local MIN_TILT = 2 -- degrees: a pose that tips less is left as declared
local MAX_TILT = 50 -- degrees: further than this it was not lying badly, it stands that way on purpose
local MAX_POINTS = 300 -- a bigger mesh is thinned to its outermost points along DIRECTIONS directions
local DIRECTIONS = 128
local STEPS = 100

-- binary readers (Lua 5.1 has no string.unpack); p is 1-based
local function u16(s, p)
    local a, b = s:byte(p, p + 1)
    return a + b * 256
end

local function u32(s, p)
    local a, b, c, d = s:byte(p, p + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

local function i32(s, p)
    local v = u32(s, p)
    return v >= 2147483648 and v - 4294967296 or v
end

local function f32(s, p)
    local a, b, c, d = s:byte(p, p + 3)
    local exp = (d % 128) * 2 + math.floor(c / 128)
    local mant = (c % 128) * 65536 + b * 256 + a
    local v
    if exp == 0 then
        v = math.ldexp(mant, -149)
    elseif exp == 255 then
        return 0 -- inf / nan: no such vertex
    else
        v = math.ldexp(mant + 8388608, exp - 150)
    end
    return d >= 128 and -v or v
end

-- the RenderWare chunks in s[from, to): { id, from, to } with the body's bounds
local function chunks(s, from, to)
    local out, p = {}, from
    while p + 12 <= to do
        local size = u32(s, p + 4)
        local e = math.min(p + 12 + size, to)
        out[#out + 1] = { u32(s, p), p + 12, e }
        p = e
    end
    return out
end

local function find(list, id)
    for _, c in ipairs(list) do
        if c[1] == id then
            return c
        end
    end
end

local STRUCT, EXTENSION, FRAME_LIST, GEOMETRY, CLUMP, ATOMIC, GEOMETRY_LIST = 0x01, 0x03, 0x0E, 0x0F, 0x10, 0x14, 0x1A
local FRAME_NAME = 0x0253F2FE

-- a geometry's vertices { x, y, z } and triangles { a, b, c } (1-based), nil without any (platform-native data)
local function geometry(s, c)
    local st = find(chunks(s, c[2], c[3]), STRUCT)
    if not st then
        return nil
    end
    local p = st[2]
    local flags, ntri, nvert = u32(s, p), u32(s, p + 4), u32(s, p + 8)
    if math.floor(flags / 0x01000000) % 2 == 1 then
        return nil
    end
    p = p + 16
    if math.floor(flags / 8) % 2 == 1 then
        p = p + nvert * 4 -- prelit colours
    end
    local sets = math.floor(flags / 65536) % 256
    if sets == 0 then
        sets = math.floor(flags / 128) % 2 == 1 and 2 or math.floor(flags / 4) % 2 == 1 and 1 or 0
    end
    p = p + sets * nvert * 8
    local tris = {}
    for i = 0, ntri - 1 do
        local q = p + i * 8
        local a, b, d = u16(s, q) + 1, u16(s, q + 2) + 1, u16(s, q + 6) + 1
        if a <= nvert and b <= nvert and d <= nvert then
            tris[#tris + 1] = { a, b, d }
        end
    end
    p = p + ntri * 8 + 16 -- the triangles, then the first morph target's bounding sphere
    if p + 8 + nvert * 12 > st[3] or u32(s, p) == 0 then
        return nil
    end
    p = p + 8
    local verts = {}
    for i = 0, nvert - 1 do
        local q = p + i * 12
        verts[i + 1] = { f32(s, q), f32(s, q + 4), f32(s, q + 8) }
    end
    return { verts = verts, tris = tris }
end

-- an atomic is part of what lies there unless it is a low-detail or damaged variant, a muzzle flash or an extra
local function shown(name)
    return not name:find("_vlo", 1, true)
        and not name:find("_dam", 1, true)
        and name:sub(1, 8) ~= "gunflash"
        and name:sub(1, 5) ~= "extra"
end

-- the outermost points of pts along DIRECTIONS directions spread evenly over the sphere
local function thin(pts)
    if #pts <= MAX_POINTS then
        return pts
    end
    local out, seen = {}, {}
    local golden = math.pi * (3 - math.sqrt(5))
    for k = 0, DIRECTIONS - 1 do
        local dz = 1 - 2 * (k + 0.5) / DIRECTIONS
        local r = math.sqrt(1 - dz * dz)
        local dx, dy = math.cos(golden * k) * r, math.sin(golden * k) * r
        local best, bd = 1, -math.huge
        for i = 1, #pts do
            local p = pts[i]
            local d = p[1] * dx + p[2] * dy + p[3] * dz
            if d > bd then
                best, bd = i, d
            end
        end
        if not seen[best] then
            seen[best] = true
            out[#out + 1] = pts[best]
        end
    end
    return out
end

-- The mesh of a .dff (its bytes) in the model's own frame: { pts = { { x, y, z }, ... }, com = { x, y, z } }, the
-- centre of mass that of the surface as a shell of even thickness (its triangles' centres by their areas). nil when
-- the file holds no mesh.
local function mesh(s)
    local clump = find(chunks(s, 1, #s + 1), CLUMP)
    if not clump then
        return nil
    end
    local frames, geoms, atomics = {}, {}, {}
    for _, c in ipairs(chunks(s, clump[2], clump[3])) do
        if c[1] == FRAME_LIST then
            local parts = chunks(s, c[2], c[3])
            local st = find(parts, STRUCT)
            local n = st and u32(s, st[2]) or 0
            for i = 0, n - 1 do
                local p = st[2] + 4 + i * 56
                local f = { parent = i32(s, p + 48), name = "" }
                for k = 0, 11 do
                    f[k + 1] = f32(s, p + k * 4)
                end
                frames[i + 1] = f
            end
            local i = 0
            for _, e in ipairs(parts) do
                if e[1] == EXTENSION then
                    i = i + 1
                    local nm = find(chunks(s, e[2], e[3]), FRAME_NAME)
                    if nm and frames[i] then
                        frames[i].name = s:sub(nm[2], nm[3] - 1):gsub("%z.*", ""):lower()
                    end
                end
            end
        elseif c[1] == GEOMETRY_LIST then
            for _, g in ipairs(chunks(s, c[2], c[3])) do
                if g[1] == GEOMETRY then
                    geoms[#geoms + 1] = geometry(s, g) or false
                end
            end
        elseif c[1] == ATOMIC then
            local st = find(chunks(s, c[2], c[3]), STRUCT)
            if st then
                atomics[#atomics + 1] = { u32(s, st[2]) + 1, u32(s, st[2] + 4) + 1 }
            end
        end
    end
    -- a vertex of frame f in the clump's root space (a frame's rows are its right, forward and up in its parent's)
    local function toRoot(f, x, y, z)
        for _ = 1, 64 do
            local r = frames[f]
            x, y, z =
                r[1] * x + r[4] * y + r[7] * z + r[10],
                r[2] * x + r[5] * y + r[8] * z + r[11],
                r[3] * x + r[6] * y + r[9] * z + r[12]
            if r.parent < 0 or not frames[r.parent + 1] then
                break
            end
            f = r.parent + 1
        end
        return x, y, z
    end
    for pass = 1, 2 do -- every atomic when the shown ones leave nothing (a part cut from a damaged mesh)
        local pts = {}
        local area, cx, cy, cz = 0, 0, 0, 0
        for _, a in ipairs(atomics) do
            local g = frames[a[1]] and geoms[a[2]]
            if g and (pass == 2 or shown(frames[a[1]].name)) then
                local first = #pts
                for i, v in ipairs(g.verts) do
                    pts[first + i] = { toRoot(a[1], v[1], v[2], v[3]) }
                end
                for _, t in ipairs(g.tris) do
                    local p, q, r = pts[first + t[1]], pts[first + t[2]], pts[first + t[3]]
                    local ux, uy, uz = q[1] - p[1], q[2] - p[2], q[3] - p[3]
                    local vx, vy, vz = r[1] - p[1], r[2] - p[2], r[3] - p[3]
                    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
                    local w = math.sqrt(nx * nx + ny * ny + nz * nz)
                    area = area + w
                    cx = cx + w * (p[1] + q[1] + r[1]) / 3
                    cy = cy + w * (p[2] + q[2] + r[2]) / 3
                    cz = cz + w * (p[3] + q[3] + r[3]) / 3
                end
            end
        end
        if #pts >= 3 and area > 1e-9 then
            return { pts = thin(pts), com = { cx / area, cy / area, cz / area } }
        end
    end
    return nil
end

-- rotation matrices: nine numbers, row by row

local function mul(a, b)
    local out = {}
    for r = 0, 2 do
        for c = 1, 3 do
            out[r * 3 + c] = a[r * 3 + 1] * b[c] + a[r * 3 + 2] * b[3 + c] + a[r * 3 + 3] * b[6 + c]
        end
    end
    return out
end

local function apply(m, x, y, z)
    return m[1] * x + m[2] * y + m[3] * z, m[4] * x + m[5] * y + m[6] * z, m[7] * x + m[8] * y + m[9] * z
end

-- by `angle` (radians) about the unit vector k (Rodrigues)
local function about(kx, ky, kz, angle)
    local c, s = math.cos(angle), math.sin(angle)
    local t = 1 - c
    return {
        c + kx * kx * t,
        kx * ky * t - kz * s,
        kx * kz * t + ky * s,
        ky * kx * t + kz * s,
        c + ky * ky * t,
        ky * kz * t - kx * s,
        kz * kx * t - ky * s,
        kz * ky * t + kx * s,
        c + kz * kz * t,
    }
end

-- an object's rotation from GTA Euler angles in degrees, as setElementRotation turns it (the game's quaternion,
-- conjugated: open.mp's GTAQuat); a heading added to rz turns the result about the vertical
local function eulerMatrix(rx, ry, rz)
    local hx, hy, hz = math.rad(rx) * -0.5, math.rad(ry) * -0.5, math.rad(rz) * -0.5
    local cx, cy, cz = math.cos(hx), math.cos(hy), math.cos(hz)
    local sx, sy, sz = math.sin(hx), math.sin(hy), math.sin(hz)
    local w = cx * cy * cz + sx * sy * sz
    local x = -(cx * sy * sz + sx * cy * cz)
    local y = -(cx * sy * cz - sx * cy * sz)
    local z = -(cx * cy * sz - sx * sy * cz)
    return {
        1 - 2 * (y * y + z * z),
        2 * (x * y - z * w),
        2 * (x * z + y * w),
        2 * (x * y + z * w),
        1 - 2 * (x * x + z * z),
        2 * (y * z - x * w),
        2 * (x * z - y * w),
        2 * (y * z + x * w),
        1 - 2 * (x * x + y * y),
    }
end

-- the turn that takes the vertical onto the normal (nx, ny, nz): geometry.tilt of items/client/world.lua
local function tiltMatrix(nx, ny)
    local s = math.sqrt(nx * nx + ny * ny)
    if s < 1e-6 then
        return { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
    end
    return about(-ny / s, nx / s, 0, math.asin(math.min(1, s)))
end

-- convex hull of 2D points { x, y }, counter-clockwise (monotone chain)
local function hull2d(pts)
    table.sort(pts, function(a, b)
        if a[1] ~= b[1] then
            return a[1] < b[1]
        end
        return a[2] < b[2]
    end)
    local uniq = {}
    for _, p in ipairs(pts) do
        local l = uniq[#uniq]
        if not l or math.abs(l[1] - p[1]) > 1e-6 or math.abs(l[2] - p[2]) > 1e-6 then
            uniq[#uniq + 1] = p
        end
    end
    if #uniq <= 2 then
        return uniq
    end
    local out = {}
    local function half(first, last, step)
        local start = #out
        for i = first, last, step do
            local q = uniq[i]
            while #out - start >= 2 do
                local a, b = out[#out - 1], out[#out]
                if (b[1] - a[1]) * (q[2] - a[2]) - (b[2] - a[2]) * (q[1] - a[1]) > 0 then
                    break
                end
                out[#out] = nil
            end
            out[#out + 1] = q
        end
        out[#out] = nil
    end
    half(1, #uniq, 1)
    half(#uniq, 1, -1)
    return out
end

-- the point of a hull (polygon, segment or point) nearest (cx, cy), and whether (cx, cy) is inside the polygon
local function nearest(hull, cx, cy)
    local n = #hull
    if n >= 3 then
        local inside = true
        for i = 1, n do
            local a, b = hull[i], hull[i % n + 1]
            if (b[1] - a[1]) * (cy - a[2]) - (b[2] - a[2]) * (cx - a[1]) < 0 then
                inside = false
                break
            end
        end
        if inside then
            return cx, cy, true
        end
    end
    local bx, by, bd = hull[1][1], hull[1][2], math.huge
    for i = 1, n >= 3 and n or n - 1 do
        local a, b = hull[i], hull[i % n + 1]
        local ex, ey = b[1] - a[1], b[2] - a[2]
        local len = ex * ex + ey * ey
        local t = len > 0 and math.max(0, math.min(1, ((cx - a[1]) * ex + (cy - a[2]) * ey) / len)) or 0
        local qx, qy = a[1] + ex * t, a[2] + ey * t
        local d = (cx - qx) ^ 2 + (cy - qy) ^ 2
        if d < bd then
            bx, by, bd = qx, qy, d
        end
    end
    return bx, by, false
end

-- The turn a body (points pts, centre of mass com, both already in its rest rotation) makes when it is put down on
-- level ground. Each step turns it about what it stands on (a point, or the edge nearest its centre of mass), the
-- centre of mass going down, until the next point of the mesh touches the ground.
local function tip(pts, com)
    local rot = { 1, 0, 0, 0, 1, 0, 0, 0, 1 }
    for _ = 1, STEPS do
        local at, low = {}, math.huge
        for i, p in ipairs(pts) do
            local x, y, z = apply(rot, p[1], p[2], p[3])
            at[i] = { x, y, z }
            low = math.min(low, z)
        end
        local touching, flat = {}, {}
        for i, p in ipairs(at) do
            if p[3] <= low + SUPPORT then
                touching[i] = true
                flat[#flat + 1] = { p[1], p[2] }
            end
        end
        local cx, cy = apply(rot, com[1], com[2], com[3])
        local qx, qy, inside = nearest(hull2d(flat), cx, cy)
        local dist = math.sqrt((cx - qx) ^ 2 + (cy - qy) ^ 2)
        if inside or dist <= INSIDE then
            break
        end
        local nx, ny = (cx - qx) / dist, (cy - qy) / dist
        local angle = math.huge
        for i, p in ipairs(at) do
            if not touching[i] then
                local u = (p[1] - qx) * nx + (p[2] - qy) * ny -- how far past the pivot, on the centre of mass's side
                if u > 1e-6 then
                    angle = math.min(angle, math.atan2(p[3] - low, u))
                end
            end
        end
        if angle == math.huge then
            break
        end
        rot = mul(about(-ny, nx, 0, angle), rot) -- about that axis a positive turn lowers the centre of mass's side
    end
    return rot
end

-- The tipped pose of a mesh declared to lie in (rotx, roty, rotz): { rot = the turn after the rest rotation, base =
-- how far its origin then sits over the ground, tilt = degrees }. false when it tips less than MIN_TILT (it lies well
-- as declared) or more than MAX_TILT (it stands that way on purpose: a bottle, a bumper on its edge).
local function pose(m, rotx, roty, rotz)
    local rest = eulerMatrix(rotx or 0, roty or 0, rotz or 0)
    local pts = {}
    for i, p in ipairs(m.pts) do
        pts[i] = { apply(rest, p[1], p[2], p[3]) }
    end
    local rot = tip(pts, { apply(rest, m.com[1], m.com[2], m.com[3]) })
    local tilt = math.deg(math.acos(math.max(-1, math.min(1, rot[9]))))
    if tilt < MIN_TILT or tilt > MAX_TILT then
        return false
    end
    local low = math.huge
    for _, p in ipairs(pts) do
        local _, _, z = apply(rot, p[1], p[2], p[3])
        low = math.min(low, z)
    end
    return { rot = rot, base = -low, tilt = tilt }
end

-- A tipped pose lying at heading rz (degrees) on a surface of normal (nx, ny; nil when level), as an item row stores
-- it: the heading and normal that give the same orientation when the client turns the type's rest rotation by the
-- heading and tilts it onto the normal. Returns rz, nx, ny (nx, ny nil when it ends level).
local function lay(p, rz, nx, ny)
    local a = math.rad(rz)
    local c, s = math.cos(a), math.sin(a)
    local m = mul(tiltMatrix(nx or 0, ny or 0), mul({ c, -s, 0, s, c, 0, 0, 0, 1 }, p.rot))
    local tx, ty = m[3], m[6] -- where the vertical ends up
    local back = tiltMatrix(tx, ty)
    -- the transpose of `back` times m is the turn about the vertical that is left: its first column is (cos, sin, 0)
    local hc = back[1] * m[1] + back[4] * m[4] + back[7] * m[7]
    local hs = back[2] * m[1] + back[5] * m[4] + back[8] * m[7]
    local heading = math.deg(math.atan2(hs, hc)) % 360
    if tx * tx + ty * ty < 0.0025 then
        return heading, nil, nil
    end
    return heading, tx, ty
end

return { mesh = mesh, pose = pose, lay = lay }
