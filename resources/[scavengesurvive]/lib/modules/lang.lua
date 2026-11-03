-- Display names in a player's language: local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
-- Item types, ammo kinds, calibres, liquids and seed kinds are named in English in the data; data's name() looks the
-- English text up in generated/names_<code>.lua (tools/convert/lang_port/names/<code>.json). On a client every call
-- is for the local player, whose language auth keeps in the "auth.lang" element data; on the server pass the player.
-- Lookups are cached per language, so a language change needs no invalidation: only callers that keep a formatted
-- label have to rebuild it (lang.onChange, client only).
local lang = {}

local LANG_KEY = "auth.lang"
local IS_CLIENT = localPlayer ~= nil
local names = {} -- code -> English name -> translation
local types = {} -- code -> uname -> localised copy of the item type, false for an unknown uname

local function cacheFor(cache, code)
    local c = cache[code]
    if not c then
        c = {}
        cache[code] = c
    end
    return c
end

local function translate(code, english)
    if type(english) ~= "string" or english == "" or code == "en" then
        return english
    end
    local c = cacheFor(names, code)
    local s = c[english]
    if s == nil then
        s = exports.data:name(code, english) or english
        c[english] = s
    end
    return s
end

-- the language code of the local player (client) or of the given player (server); "en" until one is known
function lang.code(player)
    if IS_CLIENT then
        return getElementData(localPlayer, LANG_KEY) or "en"
    end
    return isElement(player) and exports.auth:getLanguage(player) or "en"
end

function lang.name(english, player)
    return translate(lang.code(player), english)
end

-- exports.data:itemType(uname) as a copy whose name (and an ammo type's kind name) are in the player's language, so
-- every label built from it reads translated; nil for an unknown uname
function lang.itemType(uname, player)
    local code = lang.code(player)
    local c = cacheFor(types, code)
    local t = c[uname]
    if t == nil then
        local def = exports.data:itemType(uname)
        t = false
        if type(def) == "table" then
            t = {}
            for k, v in pairs(def) do
                t[k] = v
            end
            t.name = translate(code, def.name)
            if type(def.categoryData) == "table" and def.categoryData.name then
                local cd = {}
                for k, v in pairs(def.categoryData) do
                    cd[k] = v
                end
                cd.name = translate(code, cd.name)
                t.categoryData = cd
            end
        end
        c[uname] = t
    end
    return t or nil
end

-- an item type's name in the player's language, the uname itself for an unknown type
function lang.itemName(uname, player)
    local t = lang.itemType(uname, player)
    return t and t.name or tostring(uname)
end

function lang.calibreName(calibre, player)
    return translate(lang.code(player), exports.data:calibreName(calibre)) or calibre
end

-- client: fn(code) after the local player's language changed (/lang)
function lang.onChange(fn)
    addEventHandler("onClientElementDataChange", localPlayer, function(key, _, value)
        if key == LANG_KEY then
            fn(value or "en")
        end
    end, false)
end

return lang
