-- The HUD as the SA-MP footage shows it (docs/ui-reference-samp.md): the stock GTA components upstream kept,
-- the hunger bar, the ammo text under the weapon icon, the key-actions column, the watch, the vehicle panel, the
-- driver's dashboard and the low-health brightness overlay. The canvas and text primitives come from the ui
-- resource's files.
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
local voiceLogic = loadFile("shared/logic/voice.lua", "=hud/voice.lua")
local dashboardLogic = loadFile("shared/logic/dashboard.lua", "=hud/dashboardlogic.lua")
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
local SUPPORTS = {
    eat = true,
    openbag = true,
    reload = true,
    unload = true,
    uncuff = true,
    radio = true,
    removebag = true,
    holster = true,
    special = true,
    wearbag = true,
    drink = true,
    give = true,
    engine = true, -- Y in the driver seat (engineToggleRequested)
    lights = true, -- N (lightsToggleRequested)
    doors = true, -- 2 (lockToggleRequested)
}

local state = {
    spawned = false,
    dead = false,
    stats = { hp = 100, food = 100, bleed = 0 },
    held = false, -- { id, uname, category }
    brightness = 0,
    combatUntil = 0, -- getTickCount() until which the watch is red (combatWindowChanged from character)
    hitch = false, -- "hitch" / "unhitch": the trailer line while driving (trailerHitchHintChanged from vehicles)
    frequency = watch.DEFAULT_FREQUENCY,
    chatMode = 0,
    keys = {},
    hidden = false, -- setHidden(true): the dev studio wants clean screenshots
    skillNotice = false, -- { text, untilTick }: "+Repair" after a skill gain (skillGained from character)
}

local voiceClient = loadFile("client/voice.lua", "=hud/voice.lua")({
    canvas = canvas,
    c = c,
    getState = function()
        return state
    end,
    voiceLogic = voiceLogic,
})
local dashboard =
    loadFile("client/dashboard.lua", "=hud/dashboard.lua")({ canvas = canvas, c = c, logic = dashboardLogic })
local SKILL_NOTICE_MS = 5000
local GREEN = tocolor(0, 255, 0, 255) -- upstream skl_PlayerNotification colour 16711935 (0x00FF00FF)
local typeCache, vehicleTypeCache = {}, {}
local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
keyactions.tr = lang.text -- the key-action lines in the player's language

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

-- ui may be restarting while we draw: a failed export call must not kill the render handler
local function uiListIsOpen()
    local ui = getResourceFromName("ui")
    if not ui or getResourceState(ui) ~= "running" then
        return false
    end
    return exports.ui:listIsOpen() == true
end

local function applyStockHud()
    for component, visible in pairs(STOCK) do
        setPlayerHudComponentVisible(component, visible)
    end
end

local function keyName(cmd, default)
    return string.upper(getKeyBoundToCommand(cmd) or default)
end

-- the display name of a control's key: the preferred key when it is bound, else the first bound one (getBoundKeys
-- is an unordered set: sub_mission is both "2" and "num_add"); keypad names read as "NUM+"
local PRETTY = { num_add = "NUM+", num_sub = "NUM-", num_mul = "NUM*", num_div = "NUM/", num_dec = "NUM." }
local function controlKey(control, preferred, default)
    local bound = getBoundKeys(control) or {}
    local key = bound[preferred] and preferred or next(bound) or default
    return PRETTY[key] or string.upper(key):gsub("^NUM_", "NUM")
end

local function refreshKeys()
    state.keys = {
        interact = keyName("interact", "f"),
        putaway = keyName("putaway", "y"),
        drop = keyName("dropitem", "n"),
        inventory = keyName("inventory", "h"),
        glovebox = keyName("glovebox", "e"),
        reload = keyName("reloadweapon", "r"),
        engine = "Y",
        lights = "N",
        doors = controlKey("sub_mission", "2", "2"),
        radio = "R",
        hitch = controlKey("vehicle_secondary_fire", "lctrl", "lctrl"),
    }
end

addEventHandler("characterStatsSynced", root, function(s)
    state.stats = s
    if not state.spawned then
        state.spawned, state.dead = true, false
        applyStockHud()
    end
end)

addEventHandler("combatWindowChanged", root, function(ms)
    ms = tonumber(ms) or 0
    state.combatUntil = ms > 0 and getTickCount() + ms or 0
end)

addEventHandler("trailerHitchHintChanged", localPlayer, function(hint)
    state.hitch = hint or false
end)

addEventHandler("chatRadioChanged", root, function(freq, mode)
    state.frequency = tonumber(freq) or state.frequency
    state.chatMode = tonumber(mode) or state.chatMode or 0
end)

addEventHandler("deathScreenShown", root, function(show)
    state.dead = show
    if show then
        state.spawned = false
        setPlayerHudComponentVisible("all", false)
    end
end)

-- upstream skills.pwn: "+<skill>" at 320,430 for five seconds; a skill named after an item type shows its name
addEventHandler("skillGained", root, function(name)
    local t = lang.itemType(name)
    state.skillNotice = { text = "+" .. (t and t.name or tostring(name)), untilTick = getTickCount() + SKILL_NOTICE_MS }
end)

-- y: 430, or above the dashboard while it shows
local function drawSkillNotice(y)
    local n = state.skillNotice
    if not n then
        return
    end
    if getTickCount() > n.untilTick then
        state.skillNotice = false
        return
    end
    draw.text({
        text = n.text,
        x = 320,
        y = y or 430,
        font = 1,
        lx = 0.4,
        ly = 1.4,
        colour = GREEN,
        align = "center",
        outline = 1,
    })
end

addEventHandler("heldItemChanged", root, function(item)
    if item then
        local t = itemType(item.uname)
        local cd = t and t.categoryData or nil
        state.held = {
            id = item.id,
            uname = item.uname,
            category = t and t.category or "generic",
            data = item.data,
            calibre = cd and cd.calibre or nil,
            liquid = cd and cd.liquid or false,
        }
    else
        state.held = false
    end
end)

local function drawHunger()
    local H = bars.HUNGER
    draw.progressBar(H.x, H.y, H.w, H.h, bars.fill(state.stats.food, H.max), H.r, H.g, H.b, H.a, "right")
end

local function drawAmmo()
    local held = state.held
    if not held or held.category ~= "weapon" or not held.calibre or held.liquid then
        return
    end
    local clip = tonumber(held.data and held.data.mag) or 0
    local reserve = tonumber(held.data and held.data.reserve) or 0
    draw.text({
        text = string.format("%d/%d", clip, reserve),
        x = bars.AMMO.x,
        y = bars.AMMO.y,
        font = 1,
        lx = 0.278,
        ly = 1.372,
        colour = WHITE,
        align = "center",
        anchor = "right",
        outline = 1,
    })
end

-- another player within the server's hand-over reach (items/server/hands.lua GIVE_REACH): the drop key gives instead
local GIVE_REACH = 1.5
local function hasPlayerNearby()
    local px, py, pz = getElementPosition(localPlayer)
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if p ~= localPlayer and getElementInterior(p) == int and getElementDimension(p) == dim then
            local tx, ty, tz = getElementPosition(p)
            if getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz) <= GIVE_REACH then
                return true
            end
        end
    end
    return false
end

local function hasCuffedPlayerNearby()
    local px, py, pz = getElementPosition(localPlayer)
    local int, dim = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for _, p in ipairs(getElementsByType("player", root, true)) do
        if
            p ~= localPlayer
            and getElementData(p, "character.cuffed") == true
            and getElementInterior(p) == int
            and getElementDimension(p) == dim
        then
            local tx, ty, tz = getElementPosition(p)
            if getDistanceBetweenPoints3D(px, py, pz, tx, ty, tz) <= 2.0 then
                return true
            end
        end
    end
    return false
end

-- "ladder" / "zipline" / "ladder_on" / "zipline_on" from the world resource, nil when nothing is near
local function nearFeature()
    return exports.world:nearbyFeature() or nil
end

-- "open" / "closed" / "locked": a walk-in vehicle door in reach (vehicles, the towable Airstream's), nil when none is
local function walkInDoor()
    local v, open, locked = exports.vehicles:nearbyTrailerDoor()
    if not v then
        return nil
    end
    return open and "open" or (locked and "locked" or "closed")
end

-- uncooked food that can be cooked, with a campfire or barbecue in reach: F puts it on (items/server/use.lua)
local function nearCooker(held)
    if not held or held.category ~= "food" then
        return false
    end
    local t = itemType(held.uname)
    local data = type(held.data) == "table" and held.data or {}
    local cooked = data.cooked or (type(data[1]) == "table" and data[1].cooked)
    if not (t and t.categoryData and t.categoryData.canCook) or (cooked and cooked ~= 0) then
        return false
    end
    return exports.items:nearbyCooker() ~= false
end

-- carmour (vehicles): "attach" while placing a defence, "weld" with the Welder's torch at a trailer, "torch" with it
-- anywhere else, "defence" with a defence in hand at a trailer, "grind" with an Angle Grinder in hand at one,
-- "welder" with empty hands at a Welder lying near, "gas" / "gasoff" with empty hands at a Gas Cylinder or Gas Bottle
-- lying by a Welder (not hooked up / hooked up)
local function carmourHint(held)
    if exports.vehicles:attachModeActive() then
        return "attach"
    end
    local veh = exports.vehicles:nearbyWeldTarget()
    if exports.vehicles:hasTorch() then
        return veh and "weld" or "torch"
    end
    if veh and held and exports.vehicles:isAttachable(held.uname) then
        return "defence"
    end
    if veh and held and held.uname == "Grinder" then
        return "grind"
    end
    if not held then
        local welderId, welderDist = exports.vehicles:nearbyWelder()
        local gasId, gasDist, hooked = exports.vehicles:nearbyGas()
        if gasId and (not welderId or gasDist < welderDist) then
            return hooked and "gasoff" or "gas"
        end
        if welderId then
            return "welder"
        end
    end
    return nil
end

-- Vehicle actions follow the vehicle under the camera crosshair, matching the interact key's intended target.
local function lookedAtVehicle(maxDistance)
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    if not cx or not tx then
        return nil
    end
    local dx, dy, dz = tx - cx, ty - cy, tz - cz
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length == 0 then
        return nil
    end
    local scale = maxDistance / length
    local hit, _, _, _, element = processLineOfSight(
        cx,
        cy,
        cz,
        cx + dx * scale,
        cy + dy * scale,
        cz + dz * scale,
        true,
        true,
        true,
        true,
        true,
        false,
        false,
        localPlayer
    )
    if hit and isElement(element) and getElementType(element) == "vehicle" then
        return element
    end
    return nil
end

-- a Ratchet in hand next to a vehicle body part that is still on: what F held does ("Tighten Left Door" for a part
-- fitted loose, "Remove Left Door" for a secured one), else nil
-- the vehicles resource's body part slot names (bodyparts.lua) as the hint shows them
-- lang:begin
local BODY_PART_NAMES = {
    Hood = "Hood",
    Tailgate = "Tailgate",
    LeftDoor = "Left Door",
    RightDoor = "Right Door",
    FrontBumper = "Front Bumper",
    RearBumper = "Rear Bumper",
}
-- lang:end

-- the open bonnet the local player is standing at, if any (same front cone as the interact key)
local function openBonnetVehicle()
    if getPedOccupiedVehicle(localPlayer) then
        return nil
    end
    local px, py, pz = getElementPosition(localPlayer)
    local best, bestDist = nil, 5.5
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        if getPedContactElement(localPlayer) ~= veh and exports.vehicles:hasBatteryBay(veh) then
            local vx, vy, vz = getElementPosition(veh)
            local dist = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
            if dist < bestDist then
                best, bestDist = veh, dist
            end
        end
    end
    if not best then
        return nil
    end
    local vx, vy = getElementPosition(best)
    local _, _, vrz = getElementRotation(best)
    local rad = math.rad(vrz or 0)
    local dx, dy = px - vx, py - vy
    local localX = dx * math.cos(rad) + dy * math.sin(rad)
    local localY = -dx * math.sin(rad) + dy * math.cos(rad)
    local angle = (math.deg(math.atan2(localX, localY)) + 360) % 360
    if angle >= 25 and angle <= 335 then
        return nil
    end
    local open = getVehicleDoorState(best, 0) == 4 or getVehicleDoorOpenRatio(best, 0) > 0.5
    return open and best or nil
end

local function bodyPartHint(held)
    if not held or held.uname ~= "Ratchet" then
        return nil
    end
    -- the front of the car is the bay menu; body-part holds stay on the sides
    if openBonnetVehicle() then
        return nil
    end
    local veh = lookedAtVehicle(5.5)
    if veh then
        local name, condition, loose = exports.vehicles:bodyPartSlot(veh)
        if name and condition ~= "missing" then
            local part = lang.text(BODY_PART_NAMES[name] or (name:gsub("(%l)(%u)", "%1 %2")))
            return loose and lang.format("(Hold) Tighten %s", part) or lang.format("(Hold) Remove %s", part)
        end
    end
    return nil
end

-- a Ratchet at the open bonnet: hold F opens the bay menu
local function bayMenuHint(held)
    if (held and held.uname ~= "Ratchet") or not openBonnetVehicle() then
        return nil
    end
    -- a lone entry is named (the hold runs it once confirmed); several are just the menu
    local labels = exports.vehicles:bayMenuLabels(openBonnetVehicle(), not held)
    if labels and #labels == 1 then
        return lang.format("(Hold) %s", lang.text(labels[1]))
    end
    return lang.text("(Hold) Engine menu")
end

-- a Battery or a Starter Motor in hand at the open bonnet: F fits it into its empty slot
local function fitPartHint(held)
    if not held or (held.uname ~= "Battery" and held.uname ~= "StarterMotor") then
        return nil
    end
    local veh = openBonnetVehicle()
    if not veh then
        return nil
    end
    local battery, starter = exports.vehicles:bayStates(veh)
    if not battery then
        return nil
    end
    if held.uname == "Battery" and battery == 0 then
        return lang.text("Fit battery")
    end
    if held.uname == "StarterMotor" and starter == 0 then
        return lang.text("Fit starter motor")
    end
    return nil
end

local function installPartHint(held)
    if not held or not exports.vehicles:isBodyPart(held.uname) then
        return false
    end
    local veh = lookedAtVehicle(5.5)
    return veh and exports.vehicles:canInstallBodyPart(veh, held.uname) or false
end

-- Match the vehicle and front-angle check used by the interact key before advertising the bonnet action.
local function nearBonnetHint(held)
    if held then
        return nil
    end
    local px, py, pz = getElementPosition(localPlayer)
    local nearVeh, nearDist = nil, 5.5
    for _, veh in ipairs(getElementsByType("vehicle", root, true)) do
        local vx, vy, vz = getElementPosition(veh)
        local dist = getDistanceBetweenPoints3D(px, py, pz, vx, vy, vz)
        if dist < nearDist then
            nearVeh, nearDist = veh, dist
        end
    end
    if not nearVeh or not exports.vehicles:hasBatteryBay(nearVeh) then
        return nil
    end
    -- the bonnet was taken off (door state 4): nothing left to open or close
    if getVehicleDoorState(nearVeh, 0) == 4 then
        return nil
    end
    local vx, vy = getElementPosition(nearVeh)
    local _, _, vrz = getElementRotation(nearVeh)
    local rad = math.rad(vrz or 0)
    local dx, dy = px - vx, py - vy
    local angle = (
        math.deg(math.atan2(dx * math.cos(rad) + dy * math.sin(rad), -dx * math.sin(rad) + dy * math.cos(rad))) + 360
    ) % 360
    if angle >= 25 and angle <= 335 then
        return nil
    end
    if getVehicleDoorOpenRatio(nearVeh, 0) <= 0.5 then
        return "closed"
    end
    -- empty hands at the open bonnet lift a loose battery or a loose starter motor
    local battery, starter = exports.vehicles:bayStates(nearVeh)
    if battery == 1 then
        return "pickup_battery"
    end
    if starter == 1 then
        return "pickup_starter"
    end
    return "open"
end

-- a bag or box in reach: true, or "fixed" for one that is never picked up (the snack machine), else false
local function nearContainerHint()
    local id, category = exports.items:nearbyContainerItem()
    if not id then
        return false
    end
    return category == "fixed" and "fixed" or true
end

-- seated in a front seat of a vehicle with a glovebox in its dash
local function vehicleHasFrontGlovebox()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    return vehicle ~= false
        and getPedOccupiedVehicleSeat(localPlayer) <= 1
        and exports.vehicles:hasGlovebox(vehicle) == true
end

local interactionActions = loadFile("client/interactions.lua", "=hud/interactions.lua")

local function drawKeyActions(driver)
    local held = state.held
    local isCalibreWep = held and held.category == "weapon" and held.calibre ~= nil and not held.liquid or false
    local itemDist = not held and exports.items:nearestItemDistance() or false
    local nearItem = itemDist and itemDist <= 2.0
    local _, inspectUname = exports.items:nearbyInspectable()
    local choices = interactionActions(held)
    local lines = keyactions.lines({
        spawned = true,
        uiOpen = uiListIsOpen(),
        knockedOut = getElementData(localPlayer, "character.knockedOut") == true,
        driver = driver,
        hitch = driver and state.hitch or false,
        glovebox = vehicleHasFrontGlovebox(),
        held = held and { uname = held.uname, category = held.category, isWeapon = isCalibreWep },
        nearPlayer = held and hasPlayerNearby() or false,
        nearFeature = nearFeature(),
        nearCrate = exports.loot:nearbyCrate() or exports.dumpsters:nearbyDumpster() or nil,
        nearDoor = walkInDoor(),
        nearBonnet = nearBonnetHint(held),
        nearItem = nearItem,
        nearInspectable = not held and inspectUname or false,
        nearCooker = nearCooker(held),
        nearMachine = exports.items:nearbyMachine() ~= false,
        nearContainer = nearContainerHint(),
        carmour = carmourHint(held),
        bodyPart = bodyPartHint(held),
        bayMenu = bayMenuHint(held),
        fitPart = fitPartHint(held),
        installPart = installPartHint(held),
        cuffedNearby = not held and hasCuffedPlayerNearby() or false,
        hasHolster = getElementData(localPlayer, "items.holster") ~= false,
        supports = SUPPORTS,
    }, state.keys)
    if (#choices > 1 or (#choices == 1 and not choices[1].item)) and #lines > 0 then
        local interactKey = state.keys.interact or "F"
        for i = #lines, 1, -1 do
            if lines[i].key == interactKey then
                table.remove(lines, i)
            end
        end
        table.insert(
            lines,
            1,
            { key = interactKey, text = #choices > 1 and lang.text("Choose action") or choices[1].label }
        )
    end
    local scale = canvas.textScale(c, 1.5, 1)
    local font = canvas.font(1)
    local y = 120
    for _, line in ipairs(lines) do
        local verbWidth = dxGetTextWidth(" " .. line.text, scale * canvas.xScale(1, 0.3, 1.5), font)
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
    local r, g, b = watch.colour(state.combatUntil > getTickCount())
    local colour = tocolor(r, g, b, 255)
    dxDrawCircle(canvas.x(c, G.cx), canvas.y(c, G.cy), canvas.len(c, G.ry), 0, 360, BLACK, BLACK, 64, G.rx / G.ry)
    draw.text({
        text = watch.bearing(angle),
        x = G.cx,
        y = G.bearingY,
        font = 2,
        lx = 0.3,
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
        lx = 0.5,
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
        lx = 0.3,
        ly = 1.5,
        colour = colour,
        align = "center",
        anchor = "left",
        outline = 1,
    })
end

local function drawVehiclePanel(vehicle)
    local vt = vehicleType(getElementData(vehicle, "vehicles.type"))
    local N = vehiclepanel.NAME
    draw.text({
        text = vt and vt.name or getVehicleName(vehicle),
        x = N.x,
        y = N.y,
        font = 2,
        lx = N.lx,
        ly = N.ly,
        colour = WHITE,
        align = "right",
        outline = 1,
    })
end

addEventHandler("onClientRender", root, function()
    if not state.spawned or state.dead or state.hidden then
        return
    end
    if state.brightness > 0 then
        dxDrawRectangle(0, 0, sw, sh, tocolor(0, 0, 0, state.brightness))
    end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local driver = vehicle and getVehicleOccupant(vehicle, 0) == localPlayer or false
    -- duty staff have frozen stats, so no hunger bar, and no watch (bearing, clock, radio frequency)
    local onDuty = getElementData(localPlayer, "staff.duty") == true
    if not onDuty then
        drawHunger()
    end
    drawAmmo()
    drawKeyActions(driver)
    if not onDuty then
        drawWatch(vehicle)
    end
    local vt = driver and vehicleType(getElementData(vehicle, "vehicles.type")) or nil
    local dash = vt and not vt.noEngine and (vt.maxFuel or 0) > 0
    drawSkillNotice(dash and dashboard.TOP - 16 or nil)
    if driver then
        drawVehiclePanel(vehicle)
        if dash then
            dashboard.draw(vehicle, vt)
        end
    end
    voiceClient.render()
end)

-- export: a reloadable firearm is in hand (chat holds R to open the radio then, a tap reloads)
function holdingReloadable()
    local held = state.held
    return held and held.category == "weapon" and held.calibre ~= nil and not held.liquid and true or false
end

-- export: dev preview of the driver's dashboard (client/dashboard.lua), e.g. over rcon
-- `clua <player> exports.hud:dashboardPreview({ battery = 18 })` (a low battery's slow flash) or
-- `exports.hud:dashboardPreview(nil, "crank", "DAMAGED")` (the starter grinding); false clears the overrides
function dashboardPreview(overrides, kind, code)
    return dashboard.preview(overrides, kind, code)
end

-- export: hide everything this resource draws, stock components included; false brings the usual set back
function setHidden(hidden)
    state.hidden = hidden == true
    if state.hidden then
        setPlayerHudComponentVisible("all", false)
    elseif state.spawned and not state.dead then
        applyStockHud()
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setPlayerHudComponentVisible("all", false)
    triggerServerEvent("hudStateRequested", localPlayer) -- a restarted hud asks for the stats and the hand
    refreshKeys()
    setTimer(refreshKeys, 1000, 0)
    setTimer(function()
        -- brightness.pwn: Painkill and Adrenaline hide the darkness (character sends the drugs with the stats, #94)
        local drugs = type(state.stats.drugs) == "table" and state.stats.drugs or {}
        local target = (drugs.Painkill or drugs.Adrenaline) and 0 or bars.brightness(state.stats.hp)
        state.brightness = bars.brightnessStep(state.brightness, target)
    end, 100, 0)
end)

loadFile("client/keys.lua", "=hud/keys.lua")({
    interactionActions = interactionActions,
    getHeld = function()
        return state.held
    end,
    hasPlayerNearby = hasPlayerNearby,
    canvas = canvas,
    c = c,
    draw = draw,
})
