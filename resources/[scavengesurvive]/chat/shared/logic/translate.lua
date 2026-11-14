-- Chat translation helpers (pure; the server does the Google Cloud Translation v2 calls in server/main.lua).
-- A message is translated once per reader language present in its audience; readers whose language is the one it
-- was written in get nothing extra.
local translate = {}

translate.URL = "https://translation.googleapis.com/language/translate/v2"
translate.CACHE_MAX = 300
translate.BACKOFF_MS = 60000 -- after a failed call, stop calling for this long

-- auth's language codes to Google's target codes ("pt" at Google is Brazilian; bhs is shown in Croatian, Latin script)
translate.TARGETS = {
    en = "en",
    es = "es",
    fr = "fr",
    pt = "pt-PT",
    ptbr = "pt",
    ru = "ru",
    ro = "ro",
    id = "id",
    bhs = "hr",
    cs = "cs",
}

-- Google codes that count as the same language for a reader (Bosnian, Croatian and Serbian read alike)
local FAMILY = { bs = "hr", sr = "hr", hr = "hr" }

local function family(code)
    local base = tostring(code or ""):lower():match("^(%a+)") or ""
    return FAMILY[base] or base
end

-- true when text detected as `source` needs no translation for a reader of Google target `target`
function translate.sameLanguage(source, target)
    return family(source) == family(target)
end

function translate.stripColours(s)
    return (tostring(s or ""):gsub("#%x%x%x%x%x%x", ""))
end

-- worth a call: something other than spaces, punctuation and digits (bytes >= 0x80 are letters of other scripts)
function translate.worthTranslating(text)
    return #text >= 2 and text:find("[^%s%p%d]") ~= nil
end

-- the lowercase code of Google's detected source ("es", "pt-pt")
function translate.sourceTag(source)
    return tostring(source or "?"):lower()
end

-- The translated text as it goes into the chat line (mode prefix and name as the original): a soft mint,
-- apart from the mode colours (cyan, white, orange).
function translate.line(text)
    return "#C8EBD2" .. text
end

local function urlencode(s)
    return (s:gsub("[^%w%-%._~]", function(c)
        return string.format("%%%02X", c:byte())
    end))
end

-- the form body of one v2 call (form-encoded: MTA's toJSON wraps everything in an array)
function translate.body(text, target)
    return "format=text&target=" .. urlencode(target) .. "&q=" .. urlencode(text)
end

-- What Discord gets for a global line: the English translation with the original after it, or the original as is
-- when it was English already or the translation failed.
function translate.relayText(original, res)
    if not res or translate.sameLanguage(res.source, "en") then
        return original
    end
    return string.format("%s  (%s: %s)", res.text, translate.sourceTag(res.source), original)
end

-- A tiny cache: target .. "\0" .. text -> { text = translated, source = detected }; dropped whole when full.
function translate.newCache()
    return { n = 0, map = {} }
end

function translate.cacheGet(cache, target, text)
    return cache.map[target .. "\0" .. text]
end

function translate.cachePut(cache, target, text, value)
    if cache.n >= translate.CACHE_MAX then
        cache.n, cache.map = 0, {}
    end
    local key = target .. "\0" .. text
    if not cache.map[key] then
        cache.n = cache.n + 1
    end
    cache.map[key] = value
end

-- Google returns HTML entities even for format=text in a few cases; decode the common ones.
local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }
function translate.decodeEntities(s)
    s = s:gsub("&#(%d+);", function(n)
        n = tonumber(n)
        return n and n < 128 and string.char(n) or nil
    end)
    return (s:gsub("&(%a+);", function(e)
        return ENTITIES[e]
    end))
end

return translate
