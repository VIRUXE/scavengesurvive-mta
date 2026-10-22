-- The HUD as the SA-MP footage shows it (docs/ui-reference-samp.md): the stock GTA components upstream kept,
-- the hunger bar, the ammo text under the weapon icon, the key-actions column, the watch, the vehicle panel and
-- the low-health brightness overlay. The canvas and text primitives come from the ui resource's files.
local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local canvas = loadFile(":ui/shared/logic/canvas.lua", "=ui/canvas.lua")
local keyactions = loadFile("shared/logic/keyactions.lua", "=hud/keyactions.lua")
local watch = loadFile("shared/logic/watch.lua", "=hud/watch.lua")
local vehiclepanel = loadFile("shared/logic/vehiclepanel.lua", "=hud/vehiclepanel.lua")
local bars = loadFile("shared/logic/bars.lua", "=hud/bars.lua")
local sw, sh = guiGetScreenSize()
local ctx = { canvas = canvas, c = canvas.new(sw, sh) }
ctx.draw = loadFile(":ui/client/draw.lua", "=ui/draw.lua")(ctx)
local draw, c = ctx.draw, ctx.c

local WHITE = tocolor(255, 255, 255, 255)
local YELLOW = tocolor(0xE8, 0xE8, 0x90, 255) -- GTA's ~y~
local BLACK = tocolor(0, 0, 0, 255)
-- Stock components upstream left visible (money is hidden here: SA-MP could not hide its eight zeros).
local STOCK = {
    health = true,
    armour = true,
    weapon = true,
    area_name = true,
    crosshair = true,
    radar = false,
    ammo = false,
    money = false,
    clock = false,
    wanted = false,
    breath = false,
    vehicle_name = false,
    radio = false,
}
-- Actions the port implements; the rest of upstream's lines wait for their features.
local SUPPORTS = { eat = true }

local state = {
    spawned = false,
    dead = false,
    stats = { hp = 100, food = 100, bleed = 0 },
    held = false, -- { id, uname, category }
    brightness = 0,
    combatLogging = false,
    frequency = watch.DEFAULT_FREQUENCY,
    keys = {},
}
local typeCache, vehicleTypeCache = {}, {}

local function itemType(uname)
    if typeCache[uname] == nil then
        typeCache[uname] = exports.data:itemType(uname) or false
    end
    return typeCache[uname] or nil
end

local function vehicleType(uname)
    if not uname then
        return nil
    end
    if vehicleTypeCache[uname] == nil then
        vehicleTypeCache[uname] = exports.data:vehicleType(uname) or false
    end
    return vehicleTypeCache[uname] or nil
end

local function applyStockHud()
    for component, visible in pairs(STOCK) do
        setPlayerHudComponentVisible(component, visible)
    end
end

local function keyName(cmd, default)
    return string.upper(getKeyBoundToCommand(cmd) or default)
end

local function refreshKeys()
    state.keys = {
        interact = keyName("interact", "f"),
        putaway = keyName("putaway", "y"),
        drop = keyName("dropitem", "n"),
        inventory = keyName("inventory", "h"),
        reload = "R",
        engine = "Y",
        lights = "N",
        doors = "2",
        radio = "R",
    }
end

addEventHandler("onClientCharacterStats", root, function(s)
    state.stats = s
    if not state.spawned then
        state.spawned, state.dead = true, false
        applyStockHud()
    end
end)

addEventHandler("onClientCharacterDeathScreen", root, function(show)
    state.dead = show
    if show then
        state.spawned = false
        setPlayerHudComponentVisible("all", false)
    end
end)

addEventHandler("onClientItemsHeld", root, function(item)
    if item then
        local t = itemType(item.uname)
        state.held = { id = item.id, uname = item.uname, category = t and t.category or "generic" }
    else
        state.held = false
    end
end)

local function drawHunger()
    local H = bars.HUNGER
    draw.progressBar(H.x, H.y, H.w, H.h, bars.fill(state.stats.food, H.max), H.r, H.g, H.b, H.a, "right")
end

local function drawAmmo()
    local weapon = getPedWeapon(localPlayer)
    if not weapon or weapon == 0 or not state.held then
        return
    end
    local clip = getPedAmmoInClip(localPlayer) or 0
    local reserve = math.max(0, (getPedTotalAmmo(localPlayer) or 0) - clip)
    draw.text({
        text = string.format("%d/%d", clip, reserve),
        x = 520.41,
        y = 62.65,
        font = 1,
        lx = 0.278,
        ly = 1.372,
        colour = WHITE,
        align = "center",
        anchor = "right",
        outline = 1,
    })
end

local function drawKeyActions(driver)
    local held = state.held
    local t = held and itemType(held.uname)
    local lines = keyactions.lines({
        spawned = true,
        uiOpen = exports.ui:listIsOpen(),
        knockedOut = false,
        driver = driver,
        held = held and { uname = held.uname, category = held.category, isWeapon = t and t.category == "weapon" },
        nearPlayer = false,
        supports = SUPPORTS,
    }, state.keys)
    local scale = canvas.textScale(c, 1.5, 1)
    local font = canvas.font(1)
    local y = 120
    for _, line in ipairs(lines) do
        local verbWidth = dxGetTextWidth(" " .. line.text, scale, font)
        draw.text({ text = line.text, x = 618, y = y, ly = 1.5, colour = WHITE, align = "right", outline = 1 })
        draw.text({
            text = line.key,
            x = 618,
            y = y,
            ly = 1.5,
            colour = YELLOW,
            align = "right",
            outline = 1,
            dx = -verbWidth,
        })
        y = y + 14.7
    end
end

local function drawWatch(vehicle)
    local _, _, angle = getElementRotation(vehicle or localPlayer)
    local hour, minute = getTime()
    local G = watch.GEOMETRY
    local r, g, b = watch.colour(state.combatLogging)
    local colour = tocolor(r, g, b, 255)
    dxDrawCircle(canvas.x(c, G.cx), canvas.y(c, G.cy), canvas.len(c, G.ry), 0, 360, BLACK, BLACK, 64, G.rx / G.ry)
    draw.text({
        text = watch.bearing(angle),
        x = G.cx,
        y = G.bearingY,
        font = 2,
        ly = 1.5,
        colour = colour,
        align = "center",
        anchor = "left",
        outline = 1,
    })
    draw.text({
        text = watch.clock(hour, minute),
        x = G.cx,
        y = G.timeY,
        font = 2,
        ly = 2.0,
        colour = colour,
        align = "center",
        anchor = "left",
        outline = 1,
    })
    draw.text({
        text = watch.frequency(state.frequency),
        x = G.cx,
        y = G.freqY,
        font = 2,
        ly = 1.5,
        colour = colour,
        align = "center",
        anchor = "left",
        outline = 1,
    })
end

local function drawVehiclePanel(vehicle)
    local R = vehiclepanel.ROWS
    local vt = vehicleType(getElementData(vehicle, "vehicles.type"))
    local fuel = tonumber(getElementData(vehicle, "vehicles.fuel")) or 0
    local vx, vy, vz = getElementVelocity(vehicle)
    local function row(text, y, rgb, ly)
        draw.text({
            text = text,
            x = 620,
            y = y,
            font = 2,
            ly = ly or 1.6,
            colour = tocolor(rgb[1], rgb[2], rgb[3], 255),
            align = "right",
            outline = 1,
        })
    end
    row("DOR", R.doors, vehiclepanel.stateColour(not isVehicleLocked(vehicle)))
    row("ENG", R.engine, vehiclepanel.stateColour(getVehicleEngineState(vehicle)))
    row("DMG", R.damage, vehiclepanel.damageColour(getElementHealth(vehicle) or 0))
    row(vehiclepanel.fuelText(fuel, vt and vt.maxFuel or 0), R.fuel, { 255, 255, 255 })
    row(vehiclepanel.speedText(vx, vy, vz), R.speed, { 255, 255, 255 })
    draw.text({
        text = vt and vt.name or getVehicleName(vehicle),
        x = 621,
        y = R.name,
        font = 2,
        ly = 1.8,
        colour = WHITE,
        align = "right",
        outline = 1,
    })
end

addEventHandler("onClientRender", root, function()
    if not state.spawned or state.dead then
        return
    end
    if state.brightness > 0 then
        dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, state.brightness))
    end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local driver = vehicle and getVehicleOccupant(vehicle, 0) == localPlayer or false
    drawHunger()
    drawAmmo()
    drawKeyActions(driver)
    drawWatch(vehicle)
    if driver then
        drawVehiclePanel(vehicle)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    setPlayerHudComponentVisible("all", false)
    refreshKeys()
    setTimer(refreshKeys, 1000, 0)
    setTimer(function()
        state.brightness = bars.brightnessStep(state.brightness, bars.brightness(state.stats.hp))
    end, 100, 0)
end)

loadFile("client/keys.lua", "=hud/keys.lua")({
    getHeld = function()
        return state.held
    end,
})
