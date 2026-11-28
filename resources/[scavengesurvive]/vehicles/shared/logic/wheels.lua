-- Which wheel item a vehicle's wheel becomes when it comes off, and which items count as a wheel.
-- Styles are the ten stock GTA wheel meshes and five wheels of their own for the vehicles those do not suit
-- (prop_models, tools/stock_wheels.py): "Wheel" + stem for an inflated one, + "Flat" for a burst one. The generic
-- "Wheel" (20222) stays a wheel too.
-- Every car, truck and trailer model of data/generated/vehicle_types.lua has its style here, picked by the size of
-- its wheel (vehicles.ide) and the look of its rim. A model added there gets a line here too.
-- stylua: ignore
local STYLE_MODELS = {
    -- sports cars, tuners and racers
    Sport = { 402, 411, 415, 429, 451, 477, 480, 506, 533, 541, 558, 559, 560, 561, 562, 587, 602, 603 },
    -- everyday saloons, estates, taxis and police cars
    Saloon = { 401, 420, 426, 445, 458, 479, 492, 507, 516, 517, 526, 529, 540, 546, 547, 550, 566, 585, 596, 597, 598 },
    -- luxury saloons, limousines and road SUVs
    Alloy = { 400, 405, 409, 421, 551, 579, 580 },
    -- old American cars, lowriders and hot rods
    Classic = {
        412, 419, 434, 438, 439, 442, 466, 467, 474, 475, 491, 504, 518, 534, 536, 542, 545, 549, 555, 567, 575, 576,
        604,
    },
    -- compacts and hatchbacks
    Smallcar = { 404, 410, 436, 485, 496, 527, 565, 589 },
    -- vans, campers and the Ambulance
    Lightvan = { 413, 416, 418, 423, 440, 459, 482, 483, 498, 508, 582, 588, 609, 610 },
    -- pickups and light lorries
    Lighttruck = { 414, 422, 478, 489, 490, 499, 505, 525, 535, 543, 552, 554, 599, 600, 605 },
    -- 4x4s and buggies
    Offroad = { 424, 470, 495, 500, 568 },
    -- lorries, buses, heavy plant and their trailers
    Truck = {
        403, 407, 408, 427, 428, 431, 432, 433, 435, 437, 443, 450, 455, 456, 514, 515, 524, 528, 544, 573, 578, 584,
        591, 601, 611,
    },
    -- small utility vehicles: airport tugs and their carts, the Caddy, Forklift, Mower and Sweeper
    Rim = { 457, 530, 572, 574, 583, 606, 607, 608 },
    -- the Dumper and the Dozer
    Heavy = { 406, 486 },
    -- the three monster trucks
    Monster = { 444, 556, 557 },
    -- the Tractor and the Combine Harvester
    Tractor = { 531, 532 },
    Kart = { 571 },
    -- the three Hotring Racers, on slicks
    Racing = { 494, 502, 503 },
}

local STYLE_BY_MODEL = {}
local STEMS = { "Smallcar", "Offroad", "Truck", "Rim", "Alloy", "Lightvan", "Lighttruck", "Classic", "Saloon", "Sport" }
local SPECIAL_STEMS = { "Heavy", "Monster", "Tractor", "Kart", "Racing" }
for stem, list in pairs(STYLE_MODELS) do
    for _, model in ipairs(list) do
        STYLE_BY_MODEL[model] = stem
    end
end

-- item model ids, in the order tools/stock_wheels.py lays them out: the ten stock styles inflated (20237+) and flat
-- (20247+), then the five special ones inflated (20313+) and flat (20318+)
local MODEL = { Wheel = 20222 }
for i, stem in ipairs(STEMS) do
    MODEL["Wheel" .. stem] = 20236 + i
    MODEL["Wheel" .. stem .. "Flat"] = 20246 + i
end
for i, stem in ipairs(SPECIAL_STEMS) do
    MODEL["Wheel" .. stem] = 20312 + i
    MODEL["Wheel" .. stem .. "Flat"] = 20317 + i
    STEMS[#STEMS + 1] = stem
end

local IS_WHEEL, IS_FLAT = { Wheel = true }, {}
local UNAMES = { "Wheel" }
for _, stem in ipairs(STEMS) do
    for _, uname in ipairs({ "Wheel" .. stem, "Wheel" .. stem .. "Flat" }) do
        IS_WHEEL[uname] = true
        UNAMES[#UNAMES + 1] = uname
    end
    IS_FLAT["Wheel" .. stem .. "Flat"] = true
end

-- the style stem for a vehicle model; a model not listed above (bikes, aircraft) gets a saloon wheel when `isCar`,
-- else a light truck one
local function styleFor(model, isCar)
    return STYLE_BY_MODEL[tonumber(model)] or (isCar and "Saloon" or "Lighttruck")
end

local function itemFor(model, flat, isCar)
    return "Wheel" .. styleFor(model, isCar) .. (flat and "Flat" or "")
end

-- true only for the inflated or flat wheel of exactly this style; the generic "Wheel" fits no vehicle
local function fitsStyle(uname, stem)
    return uname == "Wheel" .. stem or uname == "Wheel" .. stem .. "Flat"
end

-- `'a','b'` for an SQL IN list: the inflated and the flat wheel of one style
local function sqlListFor(stem)
    return "'Wheel" .. stem .. "','Wheel" .. stem .. "Flat'"
end

local function isWheel(uname)
    return IS_WHEEL[uname] == true
end

local function isFlat(uname)
    return IS_FLAT[uname] == true
end

local function modelFor(uname)
    return MODEL[uname]
end

-- `'a','b',...` for an SQL IN list; the names are fixed constants above
local function sqlList()
    local quoted = {}
    for i, uname in ipairs(UNAMES) do
        quoted[i] = "'" .. uname .. "'"
    end
    return table.concat(quoted, ",")
end

return {
    UNAMES = UNAMES,
    styleFor = styleFor,
    itemFor = itemFor,
    fitsStyle = fitsStyle,
    sqlListFor = sqlListFor,
    isWheel = isWheel,
    isFlat = isFlat,
    modelFor = modelFor,
    sqlList = sqlList,
}
