-- Live model previews in the six gear tiles (upstream core/char/inventory.pwn:CreatePlayerTile, SA-MP font-5
-- previews). The client draws each slot's model with dxDrawModel3D in world space DEPTH metres in front of the
-- camera, at the world point under the tile centre; this module holds the framing maths so busted can check it.
local M = {}

M.ROTATION = { x = -45, y = 0, z = -45 } -- upstream preview rotation, zoom 1
M.DEPTH = 0.6 -- metres from the camera: past the 0.3 near clip, closer than any wall the ped can stand against
M.FILL = 1.0 -- the enclosing sphere diameter as a fraction of the shorter side (the sphere overshoots the silhouette)
M.LIGHTING = 1 -- dxDrawModel3D lighting (0..1); SA-MP previews are fully lit
M.PROBE = 10 -- pixels between the two probe points used to measure metres per pixel at DEPTH
M.SLACK = 1.1 -- margin on the largest half-extent so a model seen across its diagonal stays inside the tile

-- The part of a tile the model fills: everything under the title bar.
function M.area(tx, ty, tw, th, titleH)
    return { x = tx, y = ty + titleH, w = tw, h = th - titleH, cx = tx + tw / 2, cy = ty + titleH + (th - titleH) / 2 }
end

-- World metres per screen pixel at DEPTH, from two world points PROBE pixels apart on the same column.
function M.metresPerPixel(ax, ay, az, bx, by, bz)
    local dx, dy, dz = bx - ax, by - ay, bz - az
    return math.sqrt(dx * dx + dy * dy + dz * dz) / M.PROBE
end

-- Framing for a model from its model-space bounding box (getElementBoundingBox) and the 4x4 row-major matrix
-- of an object standing at ROTATION (getElementMatrix): the world offset from the drawn origin to the box
-- centre, and a radius for the silhouette around that centre: the largest half-extent plus SLACK. The
-- half-diagonal would never overflow, but it left items filling under half a tile (live check 2026-10-23).
function M.frame(minX, minY, minZ, maxX, maxY, maxZ, matrix)
    local cx, cy, cz = (minX + maxX) / 2, (minY + maxY) / 2, (minZ + maxZ) / 2
    local ex, ey, ez = maxX - minX, maxY - minY, maxZ - minZ
    local m = matrix
    local ox = cx * m[1][1] + cy * m[2][1] + cz * m[3][1]
    local oy = cx * m[1][2] + cy * m[2][2] + cz * m[3][2]
    local oz = cx * m[1][3] + cy * m[2][3] + cz * m[3][3]
    return { ox = ox, oy = oy, oz = oz, radius = math.max(ex, ey, ez) / 2 * M.SLACK }
end

-- Scale so the enclosing sphere's diameter spans FILL of the shorter side of the area.
function M.scale(radius, area, metresPerPixel)
    if not radius or radius <= 0 or not metresPerPixel or metresPerPixel <= 0 then
        return 1
    end
    local wanted = math.min(area.w, area.h) * M.FILL * metresPerPixel
    return wanted / (radius * 2)
end

-- Where to draw so the box centre lands on the world point (px, py, pz) under the tile centre.
function M.origin(px, py, pz, frame, scale)
    return px - frame.ox * scale, py - frame.oy * scale, pz - frame.oz * scale
end

return M
