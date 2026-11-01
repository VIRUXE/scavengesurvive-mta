-- Pure helpers of the CEGUI information windows (client/info.lua): SA-MP colour codes split into CEGUI-friendly
-- coloured paragraphs (a CEGUI label has one colour).
local M = {}

M.WHITE = { 255, 255, 255 }

-- "#RRGGBB" -> { r, g, b } or nil
function M.hex(code)
    if type(code) ~= "string" then
        return nil
    end
    local r, g, b = code:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then
        return nil
    end
    return { tonumber(r, 16), tonumber(g, 16), tonumber(b, 16) }
end

-- Text without its colour codes.
function M.plain(text)
    return (tostring(text or ""):gsub("#%x%x%x%x%x%x", ""))
end

-- A line's colour: its first colour code (a label has one colour), else the colour carried over from the line
-- before it, as SA-MP dialog text keeps the last colour until the next code.
local function lineColour(line, carry)
    local first = line:match("#(%x%x%x%x%x%x)")
    local last = carry
    for code in line:gmatch("#(%x%x%x%x%x%x)") do
        last = M.hex(code)
    end
    return first and M.hex(first) or carry, last
end

-- SA-MP dialog text -> { { text, indent, colour } } paragraphs, one per non-empty line; a blank line before a
-- paragraph is kept as gap = true (the window adds space there), leading tabs become indent levels.
function M.paragraphs(text)
    local out, carry, gap = {}, M.WHITE, false
    for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        local tabs = #(line:match("^\t*"))
        local colour, last = lineColour(line, carry)
        carry = last
        local plain = M.plain(line):gsub("^%s+", ""):gsub("%s+$", "")
        if plain == "" then
            gap = #out > 0
        else
            out[#out + 1] = { text = plain, indent = tabs, colour = colour, gap = gap }
            gap = false
        end
    end
    return out
end

return M
