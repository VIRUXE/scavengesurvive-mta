-- What /additem and the item picker can put inside an item they create: per item type the fields to ask for
-- (`fields`) and the data JSON those fields make (`encode`). Pure: no MTA calls at file scope. The shapes are the ones
-- the game reads: liquids = items/shared/logic/liquids.lua (decode), Gas Bottle = loot roll.gasBottleData and
-- items/shared/logic/gas.lua, calibre weapons and ammo tins = items/shared/logic/ammo.lua, liquid weapons likewise
-- (data.mag counts 100 units a litre), medical items = character/shared/logic/medical.lua (lootData).
--
-- ctx = { ammoTypes = { unames } for the weapon's calibre, medical = { drugs, pills, injections } }.
-- A field is { key, kind = "choice" | "number", label, choices = { value, ... }, min, max, full }; `full` is the
-- value a freshly opened panel holds (the "Full" button). A type with no fields carries no data and spawns straight.
local logic = {}

logic.GAS_BOTTLE = "GasBottle"
logic.GAS_BOTTLE_CAPACITY = 11.0 -- loot/shared/logic/roll.lua GAS_BOTTLE_CAPACITY
logic.FUEL_UNITS_PER_LITRE = 100 -- items/shared/logic/ammo.lua
logic.EMPTY_INJECTION = "Empty"

local function cd(def)
    return type(def) == "table" and type(def.categoryData) == "table" and def.categoryData or {}
end

local function int(n)
    return math.floor(tonumber(n) or 0)
end

local function liquidChoices(def)
    local out = {}
    for _, entry in ipairs(cd(def).liquids or {}) do
        out[#out + 1] = entry[1]
    end
    return out
end

local function isLiquidContainer(def)
    return def.category == "liquid" and #liquidChoices(def) > 0
end

local function isCalibreWeapon(def)
    return def.category == "weapon" and cd(def).calibre ~= nil and cd(def).liquid == nil
end

local function isLiquidWeapon(def)
    return def.category == "weapon" and cd(def).liquid ~= nil
end

local function isAmmoTin(def)
    return def.category == "ammo" and cd(def).calibre ~= nil
end

local function fuelCapacity(def)
    local c = cd(def)
    return math.max(0, int(c.magSize)) * (1 + math.max(0, int(c.maxReserveMags)))
end

local function medicalLists(ctx)
    local m = type(ctx) == "table" and ctx.medical or {}
    return m.drugs or {}, m.pills or {}, m.injections or {}
end

local function contains(list, value)
    for _, v in ipairs(list) do
        if v == value then
            return true
        end
    end
    return false
end

-- The panel's fields for an item type; an empty list for one with no contents.
function logic.fields(def, ctx)
    if type(def) ~= "table" then
        return {}
    end
    local c = cd(def)
    if isLiquidContainer(def) then
        local choices = liquidChoices(def)
        return {
            { key = "liquid", kind = "choice", label = "Liquid", choices = choices, full = choices[1] },
            {
                key = "amount",
                kind = "number",
                label = "Litres",
                min = 0,
                max = tonumber(c.capacity) or 0,
                full = tonumber(c.capacity) or 0,
            },
        }
    end
    if def.uname == logic.GAS_BOTTLE then
        return {
            {
                key = "gas",
                kind = "number",
                label = "Gas (kg)",
                min = 0,
                max = logic.GAS_BOTTLE_CAPACITY,
                full = logic.GAS_BOTTLE_CAPACITY,
            },
        }
    end
    if isCalibreWeapon(def) then
        local magSize = math.max(0, int(c.magSize))
        local reserve = magSize * math.max(0, int(c.maxReserveMags))
        local ammo = type(ctx) == "table" and ctx.ammoTypes or {}
        return {
            { key = "ammoItem", kind = "choice", label = "Ammo", choices = ammo, full = ammo[1] },
            { key = "mag", kind = "number", label = "Magazine", min = 0, max = magSize, full = magSize },
            { key = "reserve", kind = "number", label = "Reserve", min = 0, max = reserve, full = 0 },
        }
    end
    if isAmmoTin(def) then
        local rounds = math.max(1, int(c.rounds))
        return { { key = "rounds", kind = "number", label = "Rounds", min = 1, max = rounds, full = rounds } }
    end
    if isLiquidWeapon(def) then
        local litres = fuelCapacity(def) / logic.FUEL_UNITS_PER_LITRE
        return { { key = "fuel", kind = "number", label = "Fuel (L)", min = 0, max = litres, full = litres } }
    end
    local drugs, pills, injections = medicalLists(ctx)
    if def.uname == "DoctorBag" then
        return {
            { key = "drug", kind = "choice", label = "Drug", choices = drugs, full = drugs[1] },
            { key = "charges", kind = "number", label = "Charges", min = 1, max = 3, full = 3 },
        }
    end
    if def.uname == "Pills" then
        return { { key = "pill", kind = "choice", label = "Pill", choices = pills, full = pills[1] } }
    end
    if def.uname == "AutoInjec" then
        local choices = { logic.EMPTY_INJECTION }
        for _, i in ipairs(injections) do
            choices[#choices + 1] = i
        end
        return { { key = "inject", kind = "choice", label = "Injection", choices = choices, full = injections[1] } }
    end
    return {}
end

-- A number within the field's limits, or the reason it is not one.
local function number(field, value)
    local n = tonumber(value)
    if not n or n ~= n then
        return nil, string.format("%s is not a number", field.label)
    end
    return math.max(field.min, math.min(field.max, n))
end

local function choice(field, value)
    if type(value) ~= "string" or not contains(field.choices, value) then
        return nil, string.format("%s: unknown choice", field.label)
    end
    return value
end

-- Reads every field out of `values` (key -> text or number): { key = checked value } or nil, reason.
local function read(fields, values)
    local out = {}
    for _, f in ipairs(fields) do
        local v, err
        if f.kind == "choice" then
            v, err = choice(f, type(values) == "table" and values[f.key])
        else
            v, err = number(f, type(values) == "table" and values[f.key])
        end
        if v == nil then
            return nil, err
        end
        out[f.key] = v
    end
    return out
end

-- The data JSON text for `values` (nil: spawn without data, an empty container), or nil, reason when a value is
-- invalid. Numbers are clamped to the field's limits; choices must be one of the listed ones.
function logic.encode(def, values, ctx)
    local fields = logic.fields(def, ctx)
    if #fields == 0 then
        return nil
    end
    local v, err = read(fields, values)
    if not v then
        return nil, err
    end
    if isLiquidContainer(def) then
        if v.amount <= 0 then
            return nil
        end
        return string.format('{"amount":%.3f,"liquid":"%s"}', v.amount, v.liquid)
    end
    if def.uname == logic.GAS_BOTTLE then
        return string.format('{"gas":%.1f}', v.gas)
    end
    if isCalibreWeapon(def) then
        local mag, reserve = int(v.mag), int(v.reserve)
        if mag > 0 or reserve > 0 then
            return string.format('{"mag":%d,"reserve":%d,"ammoItem":"%s"}', mag, reserve, v.ammoItem)
        end
        return '{"mag":0,"reserve":0}'
    end
    if isAmmoTin(def) then
        return string.format('{"rounds":%d}', int(v.rounds))
    end
    if isLiquidWeapon(def) then
        return string.format('{"mag":%d,"reserve":0}', math.floor(v.fuel * logic.FUEL_UNITS_PER_LITRE + 0.5))
    end
    if def.uname == "DoctorBag" then
        return string.format('{"charges":%d,"drug":"%s"}', int(v.charges), v.drug)
    end
    if def.uname == "Pills" then
        return string.format('{"pill":"%s"}', v.pill)
    end
    if def.uname == "AutoInjec" then
        return string.format('{"inject":"%s"}', v.inject)
    end
    return nil
end

-- The values of the "Full" and "Empty" buttons: key -> value for every field.
function logic.preset(fields, which)
    local out = {}
    for _, f in ipairs(fields) do
        if which == "empty" and f.kind == "number" then
            out[f.key] = f.min
        else
            out[f.key] = f.full
        end
    end
    return out
end

return logic
