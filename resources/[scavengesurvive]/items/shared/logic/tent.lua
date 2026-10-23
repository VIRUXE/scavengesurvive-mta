-- The pitched tent (upstream core/item/tent.pwn CreateTentFromItem): six objects placed around the TentPack row,
-- four camo panels leaning together over the pack and a pole at each end. Pure geometry: the client creates the
-- objects and applies the materials (client/world.lua).
local M = {}

M.PANEL = 19477 -- SA-MP Plane003, a flat sheet
M.POLE = 19087 -- SA-MP Rope1
-- upstream SetDynamicObjectMaterial: the stock model whose TXD carries the texture, and the texture name
M.MATERIALS = {
    net = { model = 2068, texture = "CJ_cammonet" }, -- outer sheets: camouflage netting
    camo = { model = 3095, texture = "sam_camo" }, -- inner sheets: camouflage fabric
    pole = { model = 1270, texture = "lamppost" },
}

-- upstream: x + d * floatsin(angle, degrees), y + d * floatcos(angle, degrees)
local function offset(x, y, dist, deg)
    local a = math.rad(deg)
    return x + dist * math.sin(a), y + dist * math.cos(a)
end

-- x, y, z, rz: the pack's position and heading (degrees). Each part: { model, x, y, z, rx, ry, rz, material }.
function M.parts(x, y, z, rz)
    z = z + 0.4
    rz = (rz or 0) + 90
    local parts = {}
    local function panel(dist, side, ry, material)
        local px, py = offset(x, y, dist, -rz + side)
        parts[#parts + 1] = { model = M.PANEL, x = px, y = py, z = z, rx = 0, ry = ry, rz = rz, material = material }
    end
    panel(0.49, 270, 45, "net")
    panel(0.48, 270, 45, "camo")
    panel(0.49, 90, -45, "net")
    panel(0.48, 90, -45, "camo")
    local function pole(dist)
        local px, py = offset(x, y, dist, -rz)
        parts[#parts + 1] = { model = M.POLE, x = px, y = py, z = z + 0.48, rx = 0, ry = 0, rz = rz, material = "pole" }
    end
    pole(1.3)
    pole(-1.3)
    return parts
end

return M
