-- The pulsing box drawn around a world object a player is about to act on, or is acting on: the interaction
-- chooser's selected entry, the item a Crowbar's F reaches, the item a build or deconstruct hold works on.
-- Client-side, called from onClientRender. local outline = loadstring(exports.lib:getModule("outline"), ...)()
local outline = {}

local EDGES = {
    { 1, 2 },
    { 2, 3 },
    { 3, 4 },
    { 4, 1 },
    { 5, 6 },
    { 6, 7 },
    { 7, 8 },
    { 8, 5 },
    { 1, 5 },
    { 2, 6 },
    { 3, 7 },
    { 4, 8 },
}

-- the 12 edges of the object's bounding box, pulsing, a hair outside it so the model does not hide them
function outline.draw(obj)
    if not isElement(obj) then
        return
    end
    local x0, y0, z0, x1, y1, z1 = getElementBoundingBox(obj)
    if not x0 then
        x0, y0, z0, x1, y1, z1 = -0.25, -0.25, -0.25, 0.25, 0.25, 0.25
    end
    local pad = 0.03
    x0, y0, z0, x1, y1, z1 = x0 - pad, y0 - pad, z0 - pad, x1 + pad, y1 + pad, z1 + pad
    local m = getElementMatrix(obj)
    if not m then
        return
    end
    local function at(x, y, z)
        return x * m[1][1] + y * m[2][1] + z * m[3][1] + m[4][1],
            x * m[1][2] + y * m[2][2] + z * m[3][2] + m[4][2],
            x * m[1][3] + y * m[2][3] + z * m[3][3] + m[4][3]
    end
    local c = {}
    for i, p in ipairs({
        { x0, y0, z0 },
        { x1, y0, z0 },
        { x1, y1, z0 },
        { x0, y1, z0 },
        { x0, y0, z1 },
        { x1, y0, z1 },
        { x1, y1, z1 },
        { x0, y1, z1 },
    }) do
        c[i] = { at(p[1], p[2], p[3]) }
    end
    local alpha = 150 + 105 * math.abs(math.sin(getTickCount() / 300))
    local colour = tocolor(232, 232, 144, alpha)
    for _, e in ipairs(EDGES) do
        local a, b = c[e[1]], c[e[2]]
        dxDrawLine3D(a[1], a[2], a[3], b[1], b[2], b[3], colour, 2)
    end
end

return outline
