-- Masks against the toxic cloud (no MTA calls). A worn mask cuts the gas its wearer breathes by its protection,
-- wears out as it does, and makes breathing harder the better it protects: sprints get shorter and need a rest.
--   cloth (the bandanas): a little protection, never wears out;
--   disposable (Dust Mask): data.wear = % of its life left; breathed gas uses it up and a spent one is thrown away;
--   filtered (Half Respirator, Gas Mask): data.filter = % of the filter left and data.seal = % of the mask's own
--     seals. A live filter gives the full protection, a spent one little more than cloth and a clogged, harder
--     breath; a Filter item fits a fresh one. The seals outlast some ten filters and leak from SEAL_SOUND down.
-- A mask found without data is rolled partly used the first time it is worn (ensure).
-- tr(text): a line in the reader's language; the client passes lib lang.text.
local FILTER_UNAME = "Filter"
local SEAL_SOUND = 50 -- % of seal from which the mask leaks
local CLOGGED = 0.2 -- more restriction on a spent filter
-- protection and restriction are 0..1; lifeS, filterS and sealS are seconds of full-strength gas
local MASKS = {
    BandanaBl = { kind = "cloth", protection = 0.15, restriction = 0.05, sound = "cloth" },
    BandanaGr = { kind = "cloth", protection = 0.15, restriction = 0.05, sound = "cloth" },
    BandanaWh = { kind = "cloth", protection = 0.15, restriction = 0.05, sound = "cloth" },
    BandanaPat = { kind = "cloth", protection = 0.15, restriction = 0.05, sound = "cloth" },
    DustMask = { kind = "disposable", protection = 0.5, restriction = 0.15, lifeS = 300, sound = "dust" },
    HalfRespirator = {
        kind = "filtered",
        protection = 0.85,
        bare = 0.1,
        restriction = 0.35,
        filterS = 900,
        sealS = 9000,
        sound = "respirator",
    },
    GasMask = {
        kind = "filtered",
        protection = 0.97,
        bare = 0.1,
        restriction = 0.55,
        filterS = 1200,
        sealS = 12000,
        sound = "gasmask",
    },
}

local function clamp(v, lo, hi)
    return math.max(lo, math.min(hi, v))
end

local function percent(v, default)
    return clamp(tonumber(v) or default, 0, 100)
end

local function spec(uname)
    return MASKS[uname]
end

-- Gives a mask its condition when it has none; true when it rolled and the data needs saving. rnd() -> 0..1.
local function ensure(item, rnd)
    local m = MASKS[item.uname]
    if not m or m.kind == "cloth" then
        return false
    end
    if type(item.data) ~= "table" then
        item.data = {}
    end
    local d, rolled = item.data, false
    if m.kind == "disposable" and tonumber(d.wear) == nil then
        d.wear, rolled = 60 + math.floor(rnd() * 41), true
    elseif m.kind == "filtered" then
        if tonumber(d.filter) == nil then
            d.filter, rolled = 20 + math.floor(rnd() * 81), true
        end
        if tonumber(d.seal) == nil then
            d.seal, rolled = 60 + math.floor(rnd() * 41), true
        end
    end
    return rolled
end

-- The share of the gas the mask keeps out, 0..1 (0 for no mask or an item that is none).
local function protection(uname, data)
    local m = MASKS[uname]
    if not m then
        return 0
    end
    data = type(data) == "table" and data or {}
    if m.kind == "cloth" then
        return m.protection
    end
    if m.kind == "disposable" then
        return percent(data.wear, 100) > 0 and m.protection or 0
    end
    local live = percent(data.filter, 100) > 0 and m.protection or m.bare
    local seal = clamp(percent(data.seal, 100) / SEAL_SOUND, 0, 1)
    return m.bare + (live - m.bare) * seal
end

-- How hard the mask is to breathe through, 0..1.
local function restriction(uname, data)
    local m = MASKS[uname]
    if not m then
        return 0
    end
    data = type(data) == "table" and data or {}
    if m.kind == "filtered" and percent(data.filter, 100) <= 0 then
        return m.restriction + CLOGGED
    end
    return m.restriction
end

-- dt seconds of gas at this strength pass through the worn mask. Returns "spent" when a disposable mask is used
-- up (the caller throws it away), "filter" when a filter just ran out, true when the data changed, false if not.
local function breathe(item, concentration, dt)
    local m = MASKS[item.uname]
    if not m or m.kind == "cloth" or concentration <= 0 then
        return false
    end
    local d = item.data
    local dose = concentration * dt * 100
    if m.kind == "disposable" then
        d.wear = math.max(0, percent(d.wear, 100) - dose / m.lifeS)
        return d.wear <= 0 and "spent" or true
    end
    local before = percent(d.filter, 100)
    d.filter = math.max(0, before - dose / m.filterS)
    d.seal = math.max(0, percent(d.seal, 100) - dose / m.sealS)
    return before > 0 and d.filter <= 0 and "filter" or true
end

-- What every client is told of a worn mask (element data "items.maskState"): { % of life or filter left, % of seal
-- left }, whole numbers so it only changes now and then; false for cloth, for no mask and before the first wear.
local function worn(uname, data)
    local m = MASKS[uname]
    if not m or m.kind == "cloth" or type(data) ~= "table" then
        return false
    end
    local left = m.kind == "disposable" and data.wear or data.filter
    if not tonumber(left) then
        return false
    end
    return { math.ceil(percent(left, 100)), math.ceil(percent(data.seal, 100)) }
end

-- The item data a client rebuilds from that state, for protection, restriction and legs.
local function dataOf(uname, state)
    local m = MASKS[uname]
    if not m or type(state) ~= "table" then
        return {}
    end
    if m.kind == "disposable" then
        return { wear = state[1] }
    end
    return { filter = state[1], seal = state[2] }
end

-- A fresh filter goes into a filtered mask; false for any other.
local function fitFilter(item)
    local m = MASKS[item.uname]
    if not m or m.kind ~= "filtered" then
        return false
    end
    if type(item.data) ~= "table" then
        item.data = {}
    end
    item.data.filter = 100
    item.data.seal = percent(item.data.seal, 100)
    return true
end

-- What the legs still do with the mask on (the shape of character hunger.legs): a sprint lasts maxMs and then needs
-- cooldownMs off. A Gas Mask: 12 s of sprint, 8 s to recover. nil for no mask.
local function legs(uname, data)
    local r = restriction(uname, data)
    if r <= 0 then
        return nil
    end
    return { sprint = true, jump = true, maxMs = 6600 / r, cooldownMs = 4000 + 7300 * r }
end

-- "Gas Mask (filter 63%)", "Dust Mask (40%)"; the name alone for cloth and for a mask not worn yet.
local function label(name, uname, data, tr)
    local m = MASKS[uname]
    data = type(data) == "table" and data or {}
    if not m or m.kind == "cloth" then
        return name
    end
    if m.kind == "disposable" then
        return tonumber(data.wear) and string.format("%s (%d%%)", name, math.ceil(percent(data.wear, 100))) or name
    end
    if not tonumber(data.filter) then
        return name
    end
    local left = math.ceil(percent(data.filter, 100))
    if left <= 0 then
        return string.format("%s (%s)", name, tr("filter spent"))
    end
    return string.format("%s (%s %d%%)", name, tr("filter"), left)
end

return {
    FILTER_UNAME = FILTER_UNAME,
    spec = spec,
    ensure = ensure,
    protection = protection,
    restriction = restriction,
    breathe = breathe,
    worn = worn,
    dataOf = dataOf,
    fitFilter = fitFilter,
    legs = legs,
    label = label,
}
