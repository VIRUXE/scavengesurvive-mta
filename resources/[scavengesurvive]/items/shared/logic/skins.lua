-- Every human ped model (GTA:SA ids 0-312; 74, 149 and 208 are not peds) by gender and build, so a skin upstream
-- never tuned a worn item for borrows the rows of a similar skin instead of a generic default (#72).
-- Gender comes from the model name (<region><ethnicity><m|f><y|o>…, story characters by hand); the build classes
-- were sorted by eye on the dev studio contact sheets (docs/reviews/2026-10-23-apparel-all-skins.md).
local M = {}

local FEMALE = {}
local FEMALE_IDS = "6 9 10 11 12 13 31 38 39 40 41 42 53 54 55 56 63 64 69 75 76 85 86 87 88 89 90 91 92 93 129 130"
    .. " 131 138 139 140 141 145 148 150 151 152 157 169 172 178 190 191 192 193 194 195 196 197 198 199 201 205"
    .. " 207 211 214 215 216 218 219 224 225 226 231 232 233 237 238 243 244 245 246 251 256 257 263 290 298 304"
for id in FEMALE_IDS:gmatch("%d+") do
    FEMALE[tonumber(id)] = true
end

local INVALID = { [74] = true, [149] = true, [208] = true }

-- Ordered donors per build class: the first one with a tuned row wins. Hats, masks and armour have upstream rows
-- for 17 skins (apparel.lua), bags for 54, so a chain lists its closest spawn skin first and the wider set after.
local CHAINS = {
    m = { 60, 170, 188, 250, 206, 101, 44, 156, 254, 50, 287, 285, 294, 289 },
    f = { 93, 192, 233, 193, 191, 131, 90, 190, 195, 41, 157, 201, 298, 141 },
    -- heavy men (the mechanic 50 and biker 254 carry upstream's widest armour and bag rows)
    mh = { 50, 254, 44, 206, 60, 170, 188, 250, 101, 156, 287, 25, 289 },
    -- slight men (206 is upstream's narrowest armour row)
    ms = { 206, 188, 60, 170, 250, 101, 44, 156, 254, 50, 287 },
    -- heavy women (131 and the country women carry the widest female bag rows)
    fh = { 131, 191, 93, 192, 233, 193, 90, 157, 201, 298, 141 },
}

-- Build class per model where it is not the gender's average; sorted by eye on the contact sheets: the heavy men
-- (Big Bear 5, 15, the bodyguards 24 and 25, 57, 95, 168, 253, Big Smoke 269, 308) take the mechanic's wider rows.
local BUILD = {}
for id in ("5 15 24 25 57 95 168 253 269 308"):gmatch("%d+") do
    BUILD[tonumber(id)] = "mh"
end

function M.isValid(id)
    return type(id) == "number" and id >= 0 and id <= 312 and id % 1 == 0 and not INVALID[id]
end

function M.isFemale(id)
    return FEMALE[id] == true
end

--- Build class name: "m", "f", "mh" (heavy man), "ms" (slight man) or "fh" (heavy woman).
function M.build(id)
    return BUILD[id] or (FEMALE[id] and "f" or "m")
end

--- Ordered candidate skins for a wearer: the skin itself, its build chain, then its gender's chain.
function M.candidates(id)
    local out, seen = { id }, { [id] = true }
    local function add(list)
        for _, s in ipairs(list or {}) do
            if not seen[s] then
                seen[s] = true
                out[#out + 1] = s
            end
        end
    end
    add(CHAINS[M.build(id)])
    add(CHAINS[FEMALE[id] and "f" or "m"])
    return out
end

--- First candidate skin for which has(skin) is true, or nil.
---@param id number ped model of the wearer
---@param has function skin -> boolean
function M.fallback(id, has)
    for _, s in ipairs(M.candidates(id)) do
        if has(s) then
            return s
        end
    end
    return nil
end

--- Every valid human ped model id, ascending.
function M.all()
    local out = {}
    for id = 0, 312 do
        if not INVALID[id] then
            out[#out + 1] = id
        end
    end
    return out
end

return M
