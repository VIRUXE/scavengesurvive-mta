-- Mains boxes on the server (shared/logic/mains.lua, data/sites.lua). The lever is kept here (power_sites.lever_on);
-- the feed, which Generator (if any) powers a site's inlet through an Extension Cord, comes from items
-- (server/generators.lua, setFeed). A site is lit while both hold; every client is sent the state
-- (mainsStateChanged) and lights the room. A pull of the lever is told to items (mainsLeverChanged) so the
-- Generator's load follows it.
local db = assert(loadstring(exports.lib:getModule("db"), "=lib/db.lua"))()
local net = assert(loadstring(exports.lib:getModule("net"), "=lib/net.lua"))()
local log = assert(loadstring(exports.lib:getModule("log"), "=lib/log.lua"))()

local function loadFile(path, name)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, name))()
end

local mains = loadFile("shared/logic/mains.lua", "=power/mains.lua")
local sites = loadFile("data/sites.lua", "=power/sites.lua")
local byId = mains.index(sites)
local lever = {} -- site id -> true while the lever is on
local feed = {} -- site id -> the Generator item id feeding it

local function isLit(id)
    return lever[id] == true and feed[id] ~= nil
end

local function snapshot()
    local out = {}
    for _, s in ipairs(sites) do
        out[s.id] = { lever = lever[s.id] == true, lit = isLit(s.id) }
    end
    return out
end

local function broadcast(target)
    triggerClientEvent(target or root, "mainsStateChanged", resourceRoot, snapshot())
end

-- export (items): the Generator now feeding the site's inlet, or false when none does
function setFeed(siteId, generatorId)
    local s = byId[siteId]
    if not s then
        return false
    end
    local gen = tonumber(generatorId) or nil
    if feed[siteId] == gen then
        return true
    end
    local was = isLit(siteId)
    feed[siteId] = gen
    log.event("power.feedChanged", { site_id = siteId, generator_id = gen, lit = isLit(siteId) })
    if was ~= isLit(siteId) then
        broadcast()
    end
    return true
end

-- export (staff, rcon): every site's { lever, lit, generator }
function getState()
    local out = snapshot()
    for id, st in pairs(out) do
        st.generator = feed[id] or false
    end
    return out
end

-- export (items): whether the site's lever is on, so its lights load the Generator
function isLeverOn(siteId)
    return lever[siteId] == true
end

-- export: the sites (data/sites.lua)
function getSites()
    return sites
end

-- export (items): a site's inlet, x, y, z, interior, dimension
function inletOf(siteId)
    local s = byId[siteId]
    if not s then
        return false
    end
    local x, y, z = mains.inlet(s)
    return x, y, z, s.interior or 0, s.dimension or 0
end

-- export (items): where a cord plugged into the site lies, x, y, z, rz
function cordRestOf(siteId)
    local s = byId[siteId]
    if not s then
        return false
    end
    return mains.cordRest(s)
end

local function within(player, s, reach)
    if not isElement(player) or isPedDead(player) or getPedOccupiedVehicle(player) then
        return false
    end
    if getElementInterior(player) ~= (s.interior or 0) or getElementDimension(player) ~= (s.dimension or 0) then
        return false
    end
    local x, y, z = getElementPosition(player)
    local b = s.box
    return getDistanceBetweenPoints3D(x, y, z, b[1], b[2], b[3]) <= reach
end

net.handler("mainsLeverPulled", function(player, siteId)
    local s = byId[tostring(siteId)]
    if not s or not exports.character:getCharacterId(player) or not within(player, s, mains.REACH + 1.0) then
        return
    end
    local on = not lever[s.id]
    lever[s.id] = on or nil
    db.exec(
        "INSERT INTO power_sites (id, lever_on) VALUES (?, ?) ON DUPLICATE KEY UPDATE lever_on = VALUES(lever_on)",
        { s.id, on and 1 or 0 }
    )
    local x, y, z = getElementPosition(player)
    log.event("power.leverPulled", {
        player = player,
        site_id = s.id,
        lever_on = on,
        lit = isLit(s.id),
        generator_id = feed[s.id],
        x = math.floor(x),
        y = math.floor(y),
        z = math.floor(z),
    })
    -- face the box while the hand goes to the lever
    local b = s.box
    setElementRotation(player, 0, 0, (360 - math.deg(math.atan2(b[1] - x, b[2] - y))) % 360, "default", true)
    setPedAnimation(player, "BOMBER", "BOM_Plant_In", 450, false, false, true, false)
    triggerEvent("mainsLeverChanged", resourceRoot, s.id, on)
    broadcast()
end, { rate = 3 })

net.handler("mainsStateRequested", function(player)
    broadcast(player)
end, { rate = 2 })

addEventHandler("onResourceStart", resourceRoot, function()
    if not db.connect("power") then
        return
    end
    db.query("SELECT id, lever_on FROM power_sites", {}, function(rows)
        for _, r in ipairs(rows or {}) do
            if byId[r.id] and tonumber(r.lever_on) == 1 then
                lever[r.id] = true
            end
        end
        -- items works the feeds out again (a restart of this resource forgets them)
        triggerEvent("mainsLeverChanged", resourceRoot, nil, nil)
        broadcast()
    end)
end)
