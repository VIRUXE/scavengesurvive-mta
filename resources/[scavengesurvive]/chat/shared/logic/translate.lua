-- Chat translation helpers (pure). server/main.lua sends each line to the local translator service
-- (ops/translator: Claude Haiku with the recent conversation as context) with the reader languages present in its
-- audience; it answers once with every translation, leaving out the languages the line is already in.
local translate = {}

translate.URL = "http://127.0.0.1:8130/translate"
translate.BACKOFF_MS = 15000 -- after a failed call, stop calling for this long

function translate.stripColours(s)
    return (tostring(s or ""):gsub("#%x%x%x%x%x%x", ""))
end

-- worth a call: something other than spaces, punctuation and digits (bytes >= 0x80 are letters of other scripts)
function translate.worthTranslating(text)
    return #text >= 2 and text:find("[^%s%p%d]") ~= nil
end

-- The translated text as it goes into the chat line (mode prefix and name as the original): a soft mint,
-- apart from the mode colours (cyan, white, orange).
function translate.line(text)
    return "#C8EBD2" .. text
end

-- What Discord gets for a global line: the English translation with the original after it, or the original as is
-- when it was English already or there is no translation.
function translate.relayText(original, source, english)
    if type(english) ~= "string" or english == "" then
        return original
    end
    return string.format("%s  (%s: %s)", english, tostring(source or "?"):lower(), original)
end

return translate
