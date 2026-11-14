-- Which wheel item a vehicle's wheel becomes when it comes off, and which items count as a wheel.
-- Styles are the ten stock GTA wheel meshes (prop_models, tools/stock_wheels.py): "Wheel" + stem for an
-- inflated one, + "Flat" for a burst one. The generic "Wheel" (20222) stays a wheel too.
local M = {}

local STYLE_MODELS = {
    Sport = { 480, 560 },
    Saloon = { 596, 597, 598, 479 },
    Alloy = { 405, 579 },
    Classic = { 475, 549, 542, 504 },
    Smallcar = { 496, 485 },
    Lightvan = { 440, 418, 498, 416, 508 },
    Lighttruck = { 422, 478, 543, 554, 489, 599 },
    Offroad = { 470, 500, 495, 568, 424, 573 },
    Truck = { 433, 578, 455, 456, 403, 591, 407, 427, 528, 515, 611 },
    Rim = { 583 },
}

local STYLE_BY_MODEL = {}
local STEMS = { "Smallcar", "Offroad", "Truck", "Rim", "Alloy", "Lightvan", "Lighttruck", "Classic", "Saloon", "Sport" }
for stem, list in pairs(STYLE_MODELS) do
    for _, model in ipairs(list) do
        STYLE_BY_MODEL[model] = stem
    end
end

-- item model ids, in the order tools/stock_wheels.py lays them out: ten inflated (20237+), then ten flat
local MODEL = { Wheel = 20222 }
for i, stem in ipairs(STEMS) do
    MODEL["Wheel" .. stem] = 20236 + i
    MODEL["Wheel" .. stem .. "Flat"] = 20246 + i
end

local IS_WHEEL, IS_FLAT = { Wheel = true }, {}
M.UNAMES = { "Wheel" }
for _, stem in ipairs(STEMS) do
    for _, uname in ipairs({ "Wheel" .. stem, "Wheel" .. stem .. "Flat" }) do
        IS_WHEEL[uname] = true
        M.UNAMES[#M.UNAMES + 1] = uname
    end
    IS_FLAT["Wheel" .. stem .. "Flat"] = true
end

-- the style stem for a vehicle model; unlisted models get a saloon wheel when `isCar`, else a light truck one
function M.styleFor(model, isCar)
    return STYLE_BY_MODEL[tonumber(model)] or (isCar and "Saloon" or "Lighttruck")
end

function M.itemFor(model, flat, isCar)
    return "Wheel" .. M.styleFor(model, isCar) .. (flat and "Flat" or "")
end

function M.isWheel(uname)
    return IS_WHEEL[uname] == true
end

function M.isFlat(uname)
    return IS_FLAT[uname] == true
end

function M.modelFor(uname)
    return MODEL[uname]
end

-- `'a','b',...` for an SQL IN list; the names are fixed constants above
function M.sqlList()
    local quoted = {}
    for i, uname in ipairs(M.UNAMES) do
        quoted[i] = "'" .. uname .. "'"
    end
    return table.concat(quoted, ",")
end

return M
