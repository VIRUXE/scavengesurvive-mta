-- The toxic cloud on a client: the cloud seen from outside (a mass of big puffs standing on the ground where the
-- server's plan puts it, drawn against the world's depth so hills and buildings hide it) and the gas seen from
-- inside (the fog closes in, the sky takes the gas's colour, the screen is tinted).
-- The game's own fog and clouds only exist around the camera, so a front seen from kilometres away has to be
-- drawn here. The far clip plane is nearer than that: a puff beyond it is drawn nearer along the line of sight and
-- smaller by the same ratio, which looks the same from where the camera stands.
-- luacheck: read globals setFogDistance resetFogDistance getFogDistance getFarClipDistance setFarClipDistance
-- luacheck: read globals resetFarClipDistance setSkyGradient resetSkyGradient getSkyGradient dxDrawMaterialLine3D
-- luacheck: read globals dxCreateShader dxSetShaderValue getVehicleType getVehiclePanelState getVehicleDoorState
-- luacheck: read globals getVehicleDoorOpenRatio
-- luacheck: globals protection
local function loadFile(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=toxic/" .. path))()
end
local cloudLogic = loadFile("shared/logic/cloud.lua")
local enclosure = loadFile("shared/logic/enclosure.lua")

local GAS = { 168, 186, 58 } -- the gas in daylight
local FAR_PULL = 0.9 -- of the far clip distance: where a puff beyond it is drawn
local SWAY = 18 -- metres a puff drifts around its place
local EASE = 0.6 -- of the gap closed each second, as the gas around the camera thickens or thins
local FOG_IN = 6 -- metres: where the fog starts in the thick of it
local FAR_IN = 140 -- metres: how far one sees in the thick of it
local TINT_ALPHA = 70 -- the screen tint in the thick of it
local HAZE_EASE = 1.5 -- of the gap closed each second, as the haze on the screen follows the gas around the player

local active = nil -- { cloud, puffs, tick (getTickCount at age 0) }
local texture = nil -- the puff, and what the lines are drawn with: the shader that keeps the fog off it, or it
local material = nil
local inside = 0 -- eased gas strength around the camera in the open, 0..1
local served = 0 -- the gas strength around the player as the server has it (it knows what seeped indoors)
local haze = 0 -- eased strength of the tint on the screen
local drawWisps -- the gas seeping in, defined with the openings further down
local normal = nil -- { fog, far, sky = { 6 numbers } }: the world's own values, read while the gas is not on them
local screenW, screenH = guiGetScreenSize()

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function clamp01(v)
    return math.max(0, math.min(1, v))
end

-- How lit the gas is, 1 in full day .. 0.2 in the dead of night: it has no light of its own, so it takes the
-- brightness of the sky's horizon (the clock would be wrong under a weather or a time only this client sees).
local function daylight()
    local sky = normal and normal.sky or { getSkyGradient() }
    local horizon = ((sky[4] or 0) * 0.3 + (sky[5] or 0) * 0.59 + (sky[6] or 0) * 0.11) / 150
    return 0.2 + 0.8 * clamp01(horizon)
end

local function age()
    return (getTickCount() - active.tick) / 1000
end

-- Outside view -----------------------------------------------------------------------------------------------

local function drawCloud(t)
    local cloud = active.cloud
    local cx, cy = cloudLogic.centre(cloud, t)
    local camX, camY, camZ = getCameraMatrix()
    local limit = getFarClipDistance() * FAR_PULL
    local life = cloudLogic.life(cloud, t)
    local light = daylight()
    local now = getTickCount() / 1000
    for _, p in ipairs(active.puffs) do
        local swing = now * 0.05 + p.phase * 6.283
        local x = cx + p.ox + math.sin(swing) * SWAY
        local y = cy + p.oy + math.cos(swing * 0.8) * SWAY
        local foot, top = p.base, p.base + p.height * (0.92 + 0.08 * math.sin(swing * 1.7))
        local dx, dy, dz = x - camX, y - camY, (foot + top) / 2 - camZ
        local d = math.sqrt(dx * dx + dy * dy + dz * dz)
        -- a puff the camera stands in would be a sheet across the screen: it thins out as the camera nears it
        local near = clamp01((d - p.width * 0.35) / (p.width * 0.6))
        local alpha = 235 * life * near * lerp(1, 0.6, clamp01(d / 4000))
        if alpha >= 2 then
            local width = p.width
            if d > limit then
                local k = limit / d
                x, y = camX + dx * k, camY + dy * k
                foot, top = camZ + (foot - camZ) * k, camZ + (top - camZ) * k
                width = width * k
            end
            local shade = light * (0.78 + 0.22 * p.shade)
            local colour = tocolor(GAS[1] * shade, GAS[2] * shade, GAS[3] * shade, alpha)
            dxDrawMaterialLine3D(x, y, top, x, y, foot, material, width, colour, "postfx")
        end
    end
end

-- Inside view ------------------------------------------------------------------------------------------------

local function readNormal()
    normal = { fog = getFogDistance(), far = getFarClipDistance(), sky = { getSkyGradient() } }
end

local function restoreWorld()
    if normal then
        resetFogDistance()
        resetFarClipDistance()
        resetSkyGradient()
        normal = nil
    end
end

local function applyInside()
    -- under a roof the world resource holds the fog off (world/client/weather.lua): the outdoor look stays outside
    if inside < 0.01 or exports.world:isSheltered() then
        restoreWorld()
        return
    end
    if not normal then
        readNormal()
    end
    local thick = math.sqrt(inside)
    local light = daylight()
    local sky = normal.sky
    local r, g, b = GAS[1] * light * 0.85, GAS[2] * light * 0.85, GAS[3] * light * 0.85
    setFogDistance(lerp(normal.fog, FOG_IN, thick))
    setFarClipDistance(lerp(normal.far, FAR_IN, thick))
    setSkyGradient(
        lerp(sky[1], r, thick),
        lerp(sky[2], g, thick),
        lerp(sky[3], b, thick),
        lerp(sky[4], r, thick),
        lerp(sky[5], g, thick),
        lerp(sky[6], b, thick)
    )
end

addEventHandler("onClientPreRender", root, function(dt)
    local target = 0
    if active then
        local t = age()
        if t > active.cloud.duration then
            active = nil
        else
            drawCloud(t)
            local x, y, z = getCameraMatrix()
            target = cloudLogic.concentration(active.cloud, t, x, y, z)
        end
    end
    inside = inside + (target - inside) * math.min(1, EASE * dt / 1000)
    if inside < 0.002 and target == 0 then
        inside = 0
    end
    applyInside()
    -- the haze on the screen: the cloud around the camera in the open, what has seeped in under a roof
    local around = exports.world:isSheltered() and served or math.max(inside, served)
    drawWisps(dt)
    haze = haze + (around - haze) * math.min(1, HAZE_EASE * dt / 1000)
    if haze < 0.002 and around == 0 then
        haze = 0
    end
end)

-- under the HUD and every window: drawn before GTA's HUD and the onClientRender overlays
addEventHandler("onClientHUDRender", root, function()
    if haze > 0.01 then
        local light = daylight()
        local colour = tocolor(GAS[1] * light, GAS[2] * light, GAS[3] * light, TINT_ALPHA * haze)
        dxDrawRectangle(0, 0, screenW, screenH, colour)
    end
end)

addEventHandler("toxicExposureSynced", localPlayer, function(strength)
    served = tonumber(strength) or 0
end)

-- How sheltered the player is, for the gauge ---------------------------------------------------------------
-- The same reading the server takes for the poison (shared/logic/enclosure.lua), on this client's own collision,
-- which also has the doors and what players built. It is only shown: the server's reading decides the dose.

local SHELTER_MS = 2000
local HEAD = 0.6 -- metres over the ped's position: where it breathes
local ROOFLESS_TYPE = { Bike = true, BMX = true, Quad = true, Boat = true }
local openness = 1 -- of where the player is, 0 sealed .. 1 the open air
local openings = {} -- where the outside air comes into the place the player is in (enclosure.openings)
local resistance = 0 -- the character's Poison Resistance skill, 0..1
local MAX_OPENINGS = 6
local REPORT_STEP, REPORT_MS = 0.03, 8000 -- the server is told the openness when it changes, and now and then
local reportedOpenness, reportedTick = nil, 0

local function clientRay(x1, y1, z1, x2, y2, z2)
    local hit, hx, hy, hz = processLineOfSight(x1, y1, z1, x2, y2, z2, true, false, false, true, true, false, false)
    if hit then
        return hx, hy, hz
    end
    return nil
end

local function cabinOf(vehicle)
    local c = { doors = {}, ratios = {} }
    c.roofless = ROOFLESS_TYPE[getVehicleType(vehicle)] or false
    c.windscreen = getVehiclePanelState(vehicle, 4) < 3
    for door = 2, 5 do
        c.doors[#c.doors + 1] = getVehicleDoorState(vehicle, door)
        c.ratios[#c.ratios + 1] = getVehicleDoorOpenRatio(vehicle, door)
    end
    return enclosure.cabin(c)
end

local function wornMask()
    local items = getResourceFromName("items")
    return items and getResourceState(items) == "running" and exports.items:maskProtection() or false
end

setTimer(function()
    if not active and served <= 0 and not wornMask() then
        openness = 1
        return
    end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    openings = {}
    if vehicle then
        openness = cabinOf(vehicle)
    elseif getElementInterior(localPlayer) ~= 0 then
        openness = 0
    else
        local x, y, z = getElementPosition(localPlayer)
        local found
        openness, found = enclosure.measure(clientRay, x, y, z + HEAD)
        -- the doorways and gaps are only looked for while there is gas outside to come through them
        if found.roof and active and cloudLogic.concentration(active.cloud, age(), x, y, z) > 0 then
            openings = enclosure.openings(clientRay, found.away, MAX_OPENINGS)
        end
    end
    -- the server cannot see the doors and what players built: while there is gas about it is told what this
    -- client measures (server/exposure.lua decides where to believe it)
    local now = getTickCount()
    if active or served > 0 then
        local changed = not reportedOpenness or math.abs(openness - reportedOpenness) >= REPORT_STEP
        if changed or now - reportedTick >= REPORT_MS then
            reportedOpenness, reportedTick = openness, now
            triggerServerEvent("toxicShelterReported", localPlayer, openness)
        end
    end
end, SHELTER_MS, 0)

-- Gas seeping in ------------------------------------------------------------------------------------------
-- While the player is under a roof and the cloud is over the place, wisps of gas come in through every opening the
-- fan found: small puffs born at the opening that drift inwards, sink a little, swell and fade. How many depends on
-- the cloud's strength outside. A sealed room has no openings and gets none.

local WISP_LIFE = 4.5 -- seconds
local WISP_RATE = 5 -- puffs a second through one opening at full strength
local WISP_SPEED = 0.9 -- metres a second inwards
local WISP_MAX = 160
local wisps = {} -- { x, y, z, vx, vy, vz, born (ms), size, turn }
local wispDue = 0

function drawWisps(dt)
    local now = getTickCount()
    if #openings > 0 and active then
        local x, y, z = getElementPosition(localPlayer)
        local strength = cloudLogic.concentration(active.cloud, age(), x, y, z)
        wispDue = wispDue + dt / 1000 * WISP_RATE * strength * #openings
        while wispDue >= 1 and #wisps < WISP_MAX do
            wispDue = wispDue - 1
            local o = openings[math.random(#openings)]
            local sx, sy = (math.random() - 0.5) * 0.9, (math.random() - 0.5) * 0.9
            wisps[#wisps + 1] = {
                x = o.x + sx,
                y = o.y + sy,
                z = o.z - 0.3 + math.random() * 0.8,
                vx = o.ix * WISP_SPEED * (0.6 + math.random() * 0.8) + sx * 0.2,
                vy = o.iy * WISP_SPEED * (0.6 + math.random() * 0.8) + sy * 0.2,
                vz = -0.12 - math.random() * 0.1,
                born = now,
                size = 0.7 + math.random() * 0.6,
            }
        end
        wispDue = math.min(wispDue, 2)
    end
    if #wisps == 0 then
        return
    end
    local light = daylight()
    local step = dt / 1000
    for i = #wisps, 1, -1 do
        local w = wisps[i]
        local t = (now - w.born) / 1000 / WISP_LIFE
        if t >= 1 then
            table.remove(wisps, i)
        else
            w.x, w.y, w.z = w.x + w.vx * step, w.y + w.vy * step, w.z + w.vz * step
            local size = w.size * (1 + 2.6 * t)
            local alpha = 150 * math.min(1, t * 5) * (1 - t)
            local colour = tocolor(GAS[1] * light, GAS[2] * light, GAS[3] * light, alpha)
            dxDrawMaterialLine3D(w.x, w.y, w.z + size / 2, w.x, w.y, w.z - size / 2, material, size, colour, "postfx")
        end
    end
end

addEventHandler("characterSkillsSynced", localPlayer, function(list)
    resistance = 0
    for _, row in ipairs(type(list) == "table" and list or {}) do
        if row.name == "PoisonResistance" then
            resistance = tonumber(row.amount) or 0
        end
    end
end)

-- Exported (hud): how protected from the gas the player is right now, or false when there is nothing to show (no
-- mask on and no cloud in the air). { total, mask, shelter (each 0..1), left (% of the mask's filter or life, or
-- false), breathing (the gas strength around the player, 0..1) }.
function protection()
    local mask = wornMask()
    if not mask and not active and served <= 0 then
        return false
    end
    local maskShare = mask and mask.protection or 0
    local shelterShare = 1 - math.min(1, openness)
    local taken = (1 - maskShare) * (1 - shelterShare) * (1 - 0.25 * resistance)
    return {
        total = 1 - taken,
        mask = maskShare,
        shelter = shelterShare,
        left = mask and mask.left or false,
        breathing = math.max(served, exports.world:isSheltered() and 0 or inside),
    }
end

-- The cloud in the air ---------------------------------------------------------------------------------------

addEventHandler("toxicCloudStarted", root, function(cloud, t)
    if type(cloud) ~= "table" then
        return
    end
    active = { cloud = cloud, puffs = cloudLogic.puffs(cloud), tick = getTickCount() - (tonumber(t) or 0) * 1000 }
end)

addEventHandler("toxicCloudEnded", root, function()
    active = nil
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    texture = dxCreateTexture("files/puff.png", "argb", true, "clamp")
    material = dxCreateShader("client/cloud.fx")
    if material then
        dxSetShaderValue(material, "Puff", texture)
    else
        material = texture -- no shader on this card: the puffs take the fog's colour far away
    end
    triggerServerEvent("toxicCloudRequested", localPlayer)
end)

addEventHandler("onClientResourceStop", resourceRoot, restoreWorld)
