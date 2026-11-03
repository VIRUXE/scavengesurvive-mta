-- Texts in a player's language: local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
-- The port's own texts are written in English (item type, ammo, calibre, liquid and seed names in the data; labels,
-- messages and format templates in the code) and translated by that English text: data's translate() looks it up in
-- generated/strings_<code>.lua, from tools/convert/lang_port/strings/<code>.json. On a client every call is for the
-- local player, whose language auth keeps in the "auth.lang" element data; on the server pass the player.
-- tools/lang_qa.py collects the English texts from the item data and from the first string argument of every
-- lang.text / lang.format / lang.formatFor / tr call, and from the string values between "-- lang:begin" and
-- "-- lang:end" lines, so a text is translatable when written in one of those forms.
-- Lookups are cached per language, so a language change needs no invalidation: only callers that keep a built label
-- have to rebuild it (lang.onChange, client only).
local lang = {}

local LANG_KEY = "auth.lang"
local IS_CLIENT = localPlayer ~= nil
local texts = {} -- code -> English text -> translation
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
    local c = cacheFor(texts, code)
    local s = c[english]
    if s == nil then
        s = exports.data:translate(code, english) or english
        c[english] = s
    end
    return s
end

-- string.format of the translated template; the English one when the translation does not take the arguments
local function format(code, fmt, ...)
    local ok, out = pcall(string.format, translate(code, fmt), ...)
    if ok then
        return out
    end
    return string.format(fmt, ...)
end

-- the language code of the local player (client) or of the given player (server); "en" until one is known
function lang.code(player)
    if IS_CLIENT then
        return getElementData(localPlayer, LANG_KEY) or "en"
    end
    return isElement(player) and exports.auth:getLanguage(player) or "en"
end

-- client: an English text in the local player's language
function lang.text(english)
    return translate(lang.code(), english)
end

-- server: an English text in a player's language
function lang.textFor(player, english)
    return translate(lang.code(player), english)
end

-- client: string.format(template, ...) with the template in the local player's language
function lang.format(fmt, ...)
    return format(lang.code(), fmt, ...)
end

-- server: string.format(template, ...) with the template in a player's language
function lang.formatFor(player, fmt, ...)
    return format(lang.code(player), fmt, ...)
end

-- a name (item, liquid, seed kind...) in the player's language; player only on the server
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
