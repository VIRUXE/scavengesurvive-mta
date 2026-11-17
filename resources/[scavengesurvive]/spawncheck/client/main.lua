-- Spawn fit review overlay (server/main.lua pushes the issues within 200 m). Vehicle points: a heading arrow on the
-- ground (red: nothing fits, orange: some types removed), within 60 m the box each removed type would take at the
-- point and a cross where its first obstacle is, and a label. Loot points: every slot as a small mark (green: all
-- item sizes fit, orange: some, red: none; the outer room ring dimmer) and a label.
local issues = {}
local COL = {
    none = { 255, 60, 60 },
    some = { 255, 170, 40 },
    ok = { 80, 255, 80 },
    block = { 255, 40, 220 },
    loot = { 120, 200, 255 },
}

addEventHandler("spawnCheckChanged", root, function(list)
    issues = type(list) == "table" and list or {}
end)

local function c(t, a)
    return tocolor(t[1], t[2], t[3], a or 230)
end

local function label(lines, x, y, z, colour)
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0.06)
    if not sx then
        return
    end
    local _, sh = guiGetScreenSize()
    local scale = sh / 1080
    local lh = 16 * scale
    for k, text in ipairs(lines) do
        local yy = sy + (k - 1) * lh
        dxDrawText(text, sx + 1, yy + 1, sx + 1, yy + 1, tocolor(0, 0, 0, 220), scale, "default-bold", "center", "top")
        dxDrawText(
            text,
            sx,
            yy,
            sx,
            yy,
            k == 1 and c(colour, 255) or tocolor(235, 235, 235, 255),
            scale,
            "default-bold",
            "center",
            "top"
        )
    end
end

-- a box on the ground at (x, y, gz) turned rz: rect in its own frame, height h
local function box(x, y, gz, rz, b, colour)
    local r = math.rad(rz)
    local cs, sn = math.cos(r), math.sin(r)
    local function at(lx, ly)
        return x + lx * cs - ly * sn, y + lx * sn + ly * cs
    end
    local corners = { { b[1], b[3] }, { b[2], b[3] }, { b[2], b[4] }, { b[1], b[4] } }
    local pts = {}
    for k, q in ipairs(corners) do
        local px, py = at(q[1], q[2])
        pts[k] = { px, py }
    end
    local top = gz + (b[5] or 1.5)
    for k = 1, 4 do
        local a, n = pts[k], pts[k % 4 + 1]
        dxDrawLine3D(a[1], a[2], gz + 0.05, n[1], n[2], gz + 0.05, colour, 2)
        dxDrawLine3D(a[1], a[2], top, n[1], n[2], top, colour, 1)
        dxDrawLine3D(a[1], a[2], gz + 0.05, a[1], a[2], top, colour, 1)
    end
    -- the nose
    local fx, fy = at((b[1] + b[2]) / 2, b[4] + 0.5)
    local mx, my = at((b[1] + b[2]) / 2, b[4])
    dxDrawLine3D(mx, my, gz + 0.1, fx, fy, gz + 0.1, colour, 3)
end

local function cross(x, y, z, size, colour)
    dxDrawLine3D(x - size, y, z, x + size, y, z, colour, 3)
    dxDrawLine3D(x, y - size, z, x, y + size, z, colour, 3)
    dxDrawLine3D(x, y, z - size, x, y, z + size, colour, 3)
end

local function drawVehicle(s, d2)
    local colour = s.state == "none" and COL.none or COL.some
    local gz = (s.removed[1] and s.removed[1].gz) or (s.z - 0.8)
    dxDrawLine3D(s.x, s.y, gz, s.x, s.y, gz + 3, c(colour), 4)
    if d2 > 60 * 60 then
        return
    end
    for k, r in ipairs(s.removed) do
        if k <= 4 and r.box then
            box(s.x, s.y, r.gz or gz, s.rz, r.box, c(colour, 160 - (k - 1) * 30))
        end
        if r.at then
            cross(r.at[1], r.at[2], r.at[3], 0.35, c(COL.block))
        end
    end
    if d2 < 40 * 40 then
        local lines = {
            string.format(
                "Vehicle point %d  %s  %s",
                s.id,
                s.group,
                s.fits == 0 and "NOTHING FITS" or (s.fits .. " types fit")
            ),
        }
        for k, r in ipairs(s.removed) do
            if k > 6 then
                lines[#lines + 1] = string.format("+%d more removed", #s.removed - 6)
                break
            end
            lines[#lines + 1] = string.format("%s: %s (%s)", r.uname, r.reason, r.blocker or "")
        end
        if s.oneway > 0 then
            lines[#lines + 1] = string.format("%d type(s) fit one way only", s.oneway)
        end
        label(lines, s.x, s.y, gz + 3.3, colour)
    end
end

local function drawLoot(s, d2)
    dxDrawLine3D(s.x, s.y, s.z, s.x, s.y, s.z + 1.5, c(COL.loot), 3)
    if d2 > 50 * 50 then
        return
    end
    for _, sl in ipairs(s.slots) do
        local fit = 0
        for k = 1, 4 do
            if (sl[4][k] or 0) > 0 then
                fit = fit + 1
            end
        end
        local colour = fit == 4 and COL.ok or (fit == 0 and COL.none or COL.some)
        cross(s.x + sl[1], s.y + sl[2], sl[3] + 0.05, 0.08, c(colour, sl[5] and 120 or 230))
    end
    if d2 < 30 * 30 then
        label({ string.format("Loot point %d  %s", s.id, s.tbl), s.summary }, s.x, s.y, s.z + 1.8, COL.loot)
    end
end

addEventHandler("onClientRender", root, function()
    if #issues == 0 then
        return
    end
    local px, py, pz = getElementPosition(localPlayer)
    for _, s in ipairs(issues) do
        local dx, dy, dz = s.x - px, s.y - py, s.z - pz
        local d2 = dx * dx + dy * dy + dz * dz
        if s.kind == "vehicle" then
            drawVehicle(s, d2)
        else
            drawLoot(s, d2)
        end
    end
end)
