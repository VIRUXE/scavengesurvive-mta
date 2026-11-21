-- Infection and drug effects on the local player (#94, shared/logic/medical.lua): upstream's drunk levels become
-- MTA's camera drunk level (drunk / 200: infection's 5000 is 25, Air's 100000 the 255 maximum), LSD and Heroin
-- hold their sky, and the server's notices ("Taken Morphine", "Healed 2 wounds") show as action text.
local function loadModule(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, "=character/" .. path))()
end
local medical = loadModule("shared/logic/medical.lua")
medical.tr = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")().text -- labels in the player's language
local hunger = loadModule("shared/logic/hunger.lua") -- the thirst sway shares the drunk level (client/hunger.lua)
local wounds = loadModule("shared/logic/wounds.lua") -- arm wounds sway the aim

local stats = { hp = 100, food = 100, thirst = 100, infection = {}, drugs = {}, woundParts = {} }
local drunk, lastShake = 0, 0
local aimFloor = 0 -- hunger, thirst and arm wounds sway the aim: the level the camera keeps at least while aiming

local function applyCamera()
    setCameraDrunkLevel(math.min(255, math.floor(math.max(drunk, aimFloor) / 200)))
end

local function setDrunk(level)
    drunk = level
    applyCamera()
end

addEventHandler("characterStatsSynced", localPlayer, function(s)
    stats.hp = tonumber(s.hp) or stats.hp
    stats.food = tonumber(s.food) or stats.food
    stats.thirst = tonumber(s.thirst) or stats.thirst
    stats.infection = type(s.infection) == "table" and s.infection or {}
    stats.drugs = type(s.drugs) == "table" and s.drugs or {}
    stats.woundParts = type(s.woundParts) == "table" and s.woundParts or stats.woundParts
end)

addEventHandler("characterNoticeShown", localPlayer, function(text, ms)
    exports.ui:actionTextShow(tostring(text), tonumber(ms) or 3000)
end)

addEventHandler("drugSkyEnded", localPlayer, function(weather, hour, minute)
    setWeather(tonumber(weather) or 0)
    setTime(tonumber(hour) or 12, tonumber(minute) or 0)
end)

local function update()
    if isPedDead(localPlayer) or getElementData(localPlayer, "staff.duty") == true then
        aimFloor = 0
        if drunk ~= 0 then
            setDrunk(0)
        end
        return
    end
    local held = medical.drugDrunk(stats.drugs)
    local aiming = not held and not getPedOccupiedVehicle(localPlayer) and getPedControlState(localPlayer, "aim_weapon")
    local nextAim = aiming
            and math.max(
                hunger.aimDrunk(stats.food, stats.thirst, stats.drugs),
                wounds.aimDrunk(stats.woundParts, stats.drugs)
            )
        or 0
    if nextAim ~= aimFloor then
        aimFloor = nextAim
        applyCamera()
    end
    if held then
        if drunk ~= held then
            setDrunk(held)
        end
    else
        if drunk == 2200 or drunk == 100000 then
            setDrunk(0) -- the drug that held it wore off
        end
        local now = getTickCount()
        local nextLevel = medical.infectionShake(stats.infection, stats.drugs, stats.hp, drunk, now - lastShake)
        local infected = (stats.infection.food or stats.infection.wound) and not stats.drugs.Adrenaline
        if nextLevel then
            lastShake = now
            setDrunk(nextLevel)
        elseif not infected then
            -- no infection holding the camera: thirst sways it now and then (shared/logic/hunger.lua)
            local thirsty = hunger.thirstDrunk(stats.thirst, stats.drugs, drunk, now - lastShake)
            if thirsty then
                lastShake = now
                setDrunk(thirsty)
            end
        end
    end
    -- the world resource's clock sync and weather rolls are global: the drug sky is put back every tick
    local sky = medical.drugSky(stats.drugs)
    if sky then
        setTime(sky[1], sky[2])
        setWeather(sky[3])
    end
end

-- items' inventory rows: "Pills (LSD)", "Doctor's Bag (2/3, Morphine)"
function medicalLabel(uname, name, data)
    return medical.label(uname, name, data)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(update, 500, 0)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    setCameraDrunkLevel(0)
end)
