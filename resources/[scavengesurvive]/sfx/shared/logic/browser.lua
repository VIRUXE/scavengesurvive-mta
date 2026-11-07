-- Where the sound browser stands in the catalog (data/catalog.lua, tools/sfx_catalog.py) and how it moves: a
-- container, a bank in it and a sound in that bank, numbered from 0 as playSFX takes them. Pure: no MTA calls.
local M = {}

-- Playlists /sfx <name> walks instead of the whole catalog: { container, bank, sound } in order.
-- glass: the shortest, brightest, noisiest one-shots of genrl with a sharp attack, the candidates for the snack
-- machine's pane breaking (bank 32 holds most of them: the collision sounds)
M.LISTS = {
    glass = {
        { "genrl", 32, 5 },
        { "genrl", 32, 6 },
        { "genrl", 32, 7 },
        { "genrl", 32, 8 },
        { "genrl", 32, 9 },
        { "genrl", 32, 10 },
        { "genrl", 32, 11 },
        { "genrl", 32, 15 },
        { "genrl", 32, 16 },
        { "genrl", 32, 17 },
        { "genrl", 32, 18 },
        { "genrl", 32, 53 },
        { "genrl", 32, 56 },
        { "genrl", 32, 68 },
        { "genrl", 32, 69 },
        { "genrl", 32, 70 },
        { "genrl", 32, 71 },
        { "genrl", 20, 0 },
        { "genrl", 20, 13 },
    },
}

-- the position of entry i (wrapping) of a playlist
function M.fromList(catalog, list, i)
    local e = list[(i - 1) % #list + 1]
    return M.start(catalog, e[1], e[2], e[3])
end

-- pos = { c = container index (1-based into catalog.order), bank = 0.., sound = 0.. }
function M.start(catalog, container, bank, sound)
    local c = 1
    for i, name in ipairs(catalog.order) do
        if name == container then
            c = i
        end
    end
    return M.clamp(catalog, { c = c, bank = tonumber(bank) or 0, sound = tonumber(sound) or 0 })
end

local function banks(catalog, pos)
    return catalog[catalog.order[pos.c]]
end

function M.clamp(catalog, pos)
    local n = #catalog.order
    pos.c = (pos.c - 1) % n + 1
    local list = banks(catalog, pos)
    pos.bank = math.max(0, math.min(#list - 1, pos.bank))
    local sounds = list[pos.bank + 1] or {}
    pos.sound = math.max(0, math.min(math.max(#sounds - 1, 0), pos.sound))
    return pos
end

-- the next sound (step 1) or the one before (-1), running on into the next or previous bank
function M.stepSound(catalog, pos, step)
    local list = banks(catalog, pos)
    local sounds = list[pos.bank + 1] or {}
    local s = pos.sound + step
    if s >= #sounds then
        if pos.bank + 1 < #list then
            pos.bank, pos.sound = pos.bank + 1, 0
        end
    elseif s < 0 then
        if pos.bank > 0 then
            pos.bank = pos.bank - 1
            pos.sound = math.max(#(list[pos.bank + 1] or {}) - 1, 0)
        end
    else
        pos.sound = s
    end
    return pos
end

function M.stepBank(catalog, pos, step)
    pos.bank, pos.sound = pos.bank + step, 0
    return M.clamp(catalog, pos)
end

function M.stepContainer(catalog, pos, step)
    pos.c, pos.bank, pos.sound = pos.c + step, 0, 0
    return M.clamp(catalog, pos)
end

-- container name, bank, sound, length in seconds, loops, sounds in the bank, banks in the container
function M.describe(catalog, pos)
    local list = banks(catalog, pos)
    local sounds = list[pos.bank + 1] or {}
    local len = sounds[pos.sound + 1] or 0
    return catalog.order[pos.c], pos.bank, pos.sound, math.abs(len), len < 0, #sounds, #list
end

return M
