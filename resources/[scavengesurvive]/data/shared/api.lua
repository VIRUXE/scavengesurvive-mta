Data = Data or {}
Data._raw = Data._raw or {}

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
    local mod = assert(loadstring(readSource(path), "=data/" .. path))()
    Data._raw[name] = mod
    return mod
end

local function loadModelMap()
    return assert(loadstring(readSource("model_map.lua"), "=data/model_map.lua"))()
end

local modelMap = loadModelMap()
local items = assert(loadGenerated("item_types"), "data: generated/item_types.lua missing")
local loot = assert(loadGenerated("loot_tables"), "data: generated/loot_tables.lua missing")
local langs = {}
for _, code in ipairs(Data.LANGUAGES) do
    langs[code] = loadGenerated("lang_" .. code) or {}
end

for _, def in pairs(items.byUname) do
    def.mtaModel, def.sampOnly = modelMap.resolve(def.model)
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

function Data.languages()
    return Data.LANGUAGES
end

function Data.t(lang, key, ...)
    local s = (langs[lang] or {})[key] or langs.en[key] or key
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, s, ...)
        if ok then
            return out
        end
    end
    return s
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

function t(lang, key, ...)
    return Data.t(lang, key, ...)
end
