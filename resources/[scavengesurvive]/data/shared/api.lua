-- Static gamemode data: item types, loot tables, vehicle types and translations from data/generated.
-- Everything lives in this local table; the exports at the bottom are the only globals, and the file
-- returns the table.
local Data = {}

local function readSource(path)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return src
end

local function loadGenerated(name)
    local path = "generated/" .. name .. ".lua"
    if not fileExists(path) then
        return nil
    end
    return assert(loadstring(readSource(path), "=data/" .. path))()
end

local function loadModelMap()
    return assert(loadstring(readSource("model_map.lua"), "=data/model_map.lua"))()
end

local LANGUAGES = assert(loadstring(readSource("shared/lang.lua"), "=data/shared/lang.lua"))()
local modelMap = loadModelMap()
local items = assert(loadGenerated("item_types"), "data: generated/item_types.lua missing")
local loot = assert(loadGenerated("loot_tables"), "data: generated/loot_tables.lua missing")
local vehicles = assert(loadGenerated("vehicle_types"), "data: generated/vehicle_types.lua missing")
local langs = {}
local names = {} -- code -> English display name -> translation (generated/names_<code>.lua)
for _, code in ipairs(LANGUAGES) do
    langs[code] = loadGenerated("lang_" .. code) or {}
    names[code] = code ~= "en" and loadGenerated("names_" .. code) or {}
end

for _, def in pairs(items.byUname) do
    def.mtaModel, def.sampOnly = modelMap.resolve(def.model)
end

local ammoByCalibre = {}
for _, uname in ipairs(items.order) do
    local def = items.byUname[uname]
    if def and def.category == "ammo" and def.categoryData and def.categoryData.calibre then
        local cal = def.categoryData.calibre
        ammoByCalibre[cal] = ammoByCalibre[cal] or {}
        ammoByCalibre[cal][#ammoByCalibre[cal] + 1] = uname
    end
end

function Data.itemType(uname)
    return items.byUname[uname]
end

function Data.itemTypes()
    return items.order
end

function Data.lootTable(name)
    return loot[name]
end

function Data.calibreBleed(name)
    return items.calibres[name]
end

function Data.calibreName(name)
    return items.calibreNames[name]
end

function Data.ammoTypesForCalibre(name)
    return ammoByCalibre[name] or {}
end

-- vehicle types by uname (Bobcat, Police1, BfInject, ...); display names repeat, so unameByName resolves them
function Data.vehicleType(uname)
    return vehicles.byUname[uname] or vehicles.byUname[vehicles.unameByName[string.lower(tostring(uname))] or false]
end

function Data.vehicleTypes()
    return vehicles.order
end

-- the vehicle type for a model id (first type listed wins when several share one), nil when unknown
local byModel
function Data.vehicleTypeByModel(model)
    if not byModel then
        byModel = {}
        for _, uname in ipairs(vehicles.order) do
            local vt = vehicles.byUname[uname]
            if vt and vt.model and not byModel[vt.model] then
                byModel[vt.model] = vt
            end
        end
    end
    return byModel[tonumber(model) or false]
end

function Data.languages()
    return LANGUAGES
end

-- Upstream's language files carry "(REQUIRES TRANSLATION:'…')" where a line was never translated; the player
-- gets the English line instead of the marker (docs/languages-qa.md counts them as untranslated).
local UNTRANSLATED = "(REQUIRES TRANSLATION"

function Data.t(lang, key, ...)
    local s = (langs[lang] or {})[key]
    if type(s) ~= "string" or s:sub(1, #UNTRANSLATED) == UNTRANSLATED then
        s = langs.en[key] or key
    end
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then
            return out
        end
    end
    return s
end

-- A display name (item type, ammo kind, calibre, liquid, seed kind) in a language: names are English in the data
-- and translated by their English text, which comes back unchanged when a language has no entry for it.
function Data.name(lang, english)
    local s = (names[lang] or {})[english]
    return type(s) == "string" and s or english
end

-- An item type's name in a language; the uname itself for an unknown type.
function Data.itemName(lang, uname)
    local def = items.byUname[uname]
    return def and Data.name(lang, def.name) or tostring(uname)
end

-- Export wrappers: other resources call exports.data:itemType(uname) etc. (exports must be global functions).
function itemType(uname)
    return Data.itemType(uname)
end

function itemTypes()
    return Data.itemTypes()
end

function lootTable(name)
    return Data.lootTable(name)
end

function calibreBleed(name)
    return Data.calibreBleed(name)
end

function calibreName(name)
    return Data.calibreName(name)
end

function ammoTypesForCalibre(name)
    return Data.ammoTypesForCalibre(name)
end

function vehicleType(uname)
    return Data.vehicleType(uname)
end

function vehicleTypes()
    return Data.vehicleTypes()
end

function vehicleTypeByModel(model)
    return Data.vehicleTypeByModel(model)
end

function t(lang, key, ...)
    return Data.t(lang, key, ...)
end

function name(lang, english)
    return Data.name(lang, english)
end

function itemName(lang, uname)
    return Data.itemName(lang, uname)
end

function languages()
    return Data.languages()
end

return Data
