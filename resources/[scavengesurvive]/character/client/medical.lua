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

local stats = { hp = 100, infection = {}, drugs = {} }
local drunk, lastShake = 0, 0

local function setDrunk(level)
    drunk = level
    setCameraDrunkLevel(math.min(255, math.floor(level / 200)))
end

addEventHandler("characterStatsSynced", localPlayer, function(s)
    stats.hp = tonumber(s.hp) or stats.hp
    stats.infection = type(s.infection) == "table" and s.infection or {}
    stats.drugs = type(s.drugs) == "table" and s.drugs or {}
end)

addEventHandler("characterNoticeShown", localPlayer, function(text, ms)
    exports.ui:actionTextShow(tostring(text), tonumber(ms) or 3000)
end)

addEventHandler("drugSkyEnded", localPlayer, function(weather, hour, minute)
    setWeather(tonumber(weather) or 0)
    setTime(tonumber(hour) or 12, tonumber(minute) or 0)
end)

local function update()
    if isPedDead(localPlayer) then
        if drunk ~= 0 then
            setDrunk(0)
        end
        return
    end
    local held = medical.drugDrunk(stats.drugs)
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
        if nextLevel then
            lastShake = now
            setDrunk(nextLevel)
        elseif drunk ~= 0 and (stats.drugs.Adrenaline or not (stats.infection.food or stats.infection.wound)) then
            setDrunk(0)
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
