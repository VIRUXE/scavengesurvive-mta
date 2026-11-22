-- Mains boxes (data/sites.lua): where a box's parts are in the world and what a powered one does. Pure logic, no MTA
-- calls. A site is lit while its lever is on and a running Generator with fuel feeds its inlet through an Extension
-- Cord (items: server/generators.lua decides the feed, server/main.lua here keeps the lever).

-- points on the box model (tools/make_props.py MAINS_LEVER_PIVOT / MAINS_INLET), its front +Y, origin at the back
local LEVER_PIVOT = { -0.085, 0.209, -0.015 }
local INLET = { 0.11, 0.247, -0.14 }
local LEVER_ON_ROTATION = 90 -- degrees about the box's Y (out of the wall): the lever down (OFF, +Z) to the side
local LEVER_MS = 350
local REACH = 2.0 -- metres from the box a player works the lever from
local PLUG_REACH = 2.5 -- metres from the inlet a player plugs a cord in from
local CORD_LENGTH = 15.0 -- an Extension Cord: metres from the inlet to the Generator it feeds from
local BOX_MODEL, LEVER_MODEL = 20307, 20308

-- a point in a box's model space turned into the world (the box only turns about Z)
local function toWorld(box, v)
    local r = math.rad(box[4] or 0)
    local c, s = math.cos(r), math.sin(r)
    return box[1] + v[1] * c - v[2] * s, box[2] + v[1] * s + v[2] * c, box[3] + v[3]
end

local function inlet(site)
    return toWorld(site.box, INLET)
end

local function pivot(site)
    return toWorld(site.box, LEVER_PIVOT)
end

-- where a plugged cord lies: on the floor under the inlet, a little out from the wall, turned along the wall
local function cordRest(site)
    local x, y = toWorld(site.box, { INLET[1], INLET[2] + 0.25, 0 })
    return x, y, site.floor, (site.box[4] or 0) % 360
end

-- the sites by id
local function index(sites)
    local byId = {}
    for _, s in ipairs(sites) do
        byId[s.id] = s
    end
    return byId
end

-- the site whose box is within `reach` of x, y, z in that interior and dimension, or nil
local function siteAt(sites, x, y, z, int, dim, reach)
    local best, bestD = nil, reach
    for _, s in ipairs(sites) do
        if (s.interior or 0) == (int or 0) and (s.dimension or 0) == (dim or 0) then
            local b = s.box
            local d = math.sqrt((b[1] - x) ^ 2 + (b[2] - y) ^ 2 + (b[3] - z) ^ 2)
            if d <= bestD then
                best, bestD = s, d
            end
        end
    end
    return best
end

local function within(site, x, y, z)
    local r = site.room
    return x >= r[1] and x <= r[4] and y >= r[2] and y <= r[5] and z >= r[3] and z <= r[6]
end

return {
    LEVER_PIVOT = LEVER_PIVOT,
    INLET = INLET,
    LEVER_ON_ROTATION = LEVER_ON_ROTATION,
    LEVER_MS = LEVER_MS,
    REACH = REACH,
    PLUG_REACH = PLUG_REACH,
    CORD_LENGTH = CORD_LENGTH,
    BOX_MODEL = BOX_MODEL,
    LEVER_MODEL = LEVER_MODEL,
    toWorld = toWorld,
    inlet = inlet,
    pivot = pivot,
    cordRest = cordRest,
    index = index,
    siteAt = siteAt,
    within = within,
}
