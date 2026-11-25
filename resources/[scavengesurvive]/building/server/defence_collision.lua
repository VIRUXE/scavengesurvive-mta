-- Test the GTA standing ped collider (three 0.35 m spheres) against the model's COL primitives.
-- https://github.com/gta-reversed/gta-reversed/blob/master/source/game_sa/Collision/TempColModels.cpp
local PED_SPHERE_HEIGHTS = { -0.20, 0.20, 0.60 }
local RADIUS_SQUARED = 0.35 ^ 2

local function boxDistanceSquared(box, x, y, z)
    local dx = math.max(box[1] - x, x - box[4], 0)
    local dy = math.max(box[2] - y, y - box[5], 0)
    local dz = math.max(box[3] - z, z - box[6], 0)
    return dx * dx + dy * dy + dz * dz
end

local function edgeDistanceSquared(x, y, z, a, b)
    local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local px, py, pz = x - a[1], y - a[2], z - a[3]
    local lengthSquared = dx * dx + dy * dy + dz * dz
    local t = lengthSquared > 0 and math.max(0, math.min(1, (px * dx + py * dy + pz * dz) / lengthSquared)) or 0
    local qx, qy, qz = px - t * dx, py - t * dy, pz - t * dz
    return qx * qx + qy * qy + qz * qz
end

local function triangleTouches(x, y, z, a, b, c)
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local px, py, pz = x - a[1], y - a[2], z - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local areaSquared = nx * nx + ny * ny + nz * nz
    if areaSquared > 0 then
        local height = px * nx + py * ny + pz * nz
        if height * height > RADIUS_SQUARED * areaSquared then
            return false
        end
        -- The projected point's two barycentric coordinates, scaled by areaSquared.
        local u = (py * vz - pz * vy) * nx + (pz * vx - px * vz) * ny + (px * vy - py * vx) * nz
        local v = (uy * pz - uz * py) * nx + (uz * px - ux * pz) * ny + (ux * py - uy * px) * nz
        if u >= 0 and v >= 0 and u + v <= areaSquared then
            return true
        end
    end
    return edgeDistanceSquared(x, y, z, a, b) <= RADIUS_SQUARED
        or edgeDistanceSquared(x, y, z, b, c) <= RADIUS_SQUARED
        or edgeDistanceSquared(x, y, z, c, a) <= RADIUS_SQUARED
end

local function sphereTouches(shape, x, y, z)
    if boxDistanceSquared(shape.bounds, x, y, z) > RADIUS_SQUARED then
        return false
    end
    if shape.boxes then
        for _, box in ipairs(shape.boxes) do
            if boxDistanceSquared(box, x, y, z) <= RADIUS_SQUARED then
                return true
            end
        end
    end
    if shape.faces then
        local vertices = shape.vertices
        for _, face in ipairs(shape.faces) do
            if triangleTouches(x, y, z, vertices[face[1]], vertices[face[2]], vertices[face[3]]) then
                return true
            end
        end
    end
    return false
end

-- Move the ped spheres into model space. Invert the ground tilt (items/shared/logic/geometry.lua),
-- then invert the object's ZXY rotation, which is also used by defences.pivotOffset.
local function collider(shape, x, y, z, rx, ry, rz, nx, ny)
    local ax, ay, az = math.rad(rx), math.rad(ry), math.rad(rz)
    local sx, cx, sy, cy, sz, cz = math.sin(ax), math.cos(ax), math.sin(ay), math.cos(ay), math.sin(az), math.cos(az)
    local tilt = math.sqrt(nx * nx + ny * ny)
    local cosTilt = math.sqrt(math.max(0, 1 - tilt * tilt))
    local kx, ky = 0, 0
    if tilt >= 1e-6 then
        kx, ky = -ny / tilt, nx / tilt
    end
    return function(px, py, pz)
        for _, height in ipairs(PED_SPHERE_HEIGHTS) do
            local dx, dy, dz = px - x, py - y, pz + height - z
            if tilt >= 1e-6 then
                local dot = (kx * dx + ky * dy) * (1 - cosTilt)
                dx, dy, dz =
                    dx * cosTilt - nx * dz + kx * dot,
                    dy * cosTilt - ny * dz + ky * dot,
                    dz * cosTilt + nx * dx + ny * dy
            end
            local x1, y1 = dx * cz + dy * sz, -dx * sz + dy * cz
            local y2, z2 = y1 * cx + dz * sx, -y1 * sx + dz * cx
            if sphereTouches(shape, x1 * cy - z2 * sy, y2, x1 * sy + z2 * cy) then
                return true
            end
        end
        return false
    end
end

return function(models)
    return function(row, model, st, x, y, z, rz)
        local shape = models[model]
        if not shape then
            return function()
                return false
            end
        end
        local nx, ny = 0, 0
        if st.pose == "horizontal" and row.type_uname ~= "LargeFrame" then
            nx, ny = st.gnx or 0, st.gny or 0
            -- The row's loose-item normal survives when only the rotation or data changes.
            if not st.gnx and x == row.x and y == row.y and z == row.z then
                nx, ny = tonumber(row.ground_nx) or 0, tonumber(row.ground_ny) or 0
            end
        end
        local touches = collider(shape, x, y, z, st.rx or 0, st.ry or 0, rz, nx, ny)
        if row.type_uname == "LargeFrame" and st.covered == true then
            local touchesRoof = collider(models[19908], x, y, z + 2.6, 0, 90, rz, 0, 0)
            return function(px, py, pz)
                return touches(px, py, pz) or touchesRoof(px, py, pz)
            end
        end
        return touches
    end
end
