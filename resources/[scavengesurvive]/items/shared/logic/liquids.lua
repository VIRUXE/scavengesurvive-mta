-- Liquid containers (upstream itemtype/liquid-container.pwn + the DefineLiquidType table in server/init.pwn):
-- a container type lists the liquids it may spawn with and their chances; the item's data holds the amount in
-- litres and the liquid name. Drinking is a 1 s hold per sip: each sip takes 0.2 L and adds the liquid's thirst and
-- food values (negative for petrol and the like; a last sip of less than 0.2 L gives its share). Pure: no MTA calls
-- at file scope. Item data arrives as { amount, liquid } or MTA's wrapped form { { amount, liquid } }; a container
-- with one possible liquid (the Petrol Can) may carry only the amount, as vehicles write it.
local M = {}

-- M.tr(text): a label word in the reader's language; the client sets it to lib lang.text, identity elsewhere
M.tr = function(s)
    return s
end
local function tr(s)
    return M.tr(s)
end

M.SIP_LITRES = 0.2
M.HOLD_MS = 1000
M.EMPTY_BELOW = 0.001 -- upstream: below this the label reads "Empty" and nothing can be drunk

-- name as shown in labels, food and thirst per 0.2 L sip. A drink quenches thirst (a 0.5 L Bottle of water gives 30,
-- a 1 L carton of juice 50 and 10 food); milk and juices feed a little, spirits and sea water dry the mouth, and
-- what is no drink keeps upstream's food penalty.
M.LIQUIDS = {
    Water = { name = "Water", food = 0.0, thirst = 12.0 },
    Milk = { name = "Milk", food = 4.0, thirst = 8.0 },
    Orange = { name = "Orange Juice", food = 2.0, thirst = 10.0 },
    Apple = { name = "Apple Juice", food = 2.0, thirst = 10.0 },
    Whiskey = { name = "Whiskey", food = 0.1, thirst = -3.0 },
    WineRed = { name = "Red Wine", food = 0.4, thirst = 4.0 },
    WineWhite = { name = "White Wine", food = 0.4, thirst = 4.0 },
    Champagne = { name = "Champagne", food = 0.2, thirst = 4.0 },
    Ethanol = { name = "Ethanol", food = -44.1, thirst = 0.0 },
    Turpentine = { name = "Turpentine", food = -101.0, thirst = 0.0 },
    HydroAcid = { name = "Hydrochloric Acid", food = -101.0, thirst = 0.0 },
    CarbonatedWater = { name = "Carbonated Water", food = 0.0, thirst = 11.0 },
    Lemon = { name = "Lemon Juice", food = 1.0, thirst = 8.0 },
    Sugar = { name = "Sugar", food = 0.8, thirst = 0.0 },
    Petrol = { name = "Petrol", food = -8.0, thirst = 0.0 },
    Diesel = { name = "Diesel", food = -8.0, thirst = 0.0 },
    Oil = { name = "Oil", food = -8.0, thirst = 0.0 },
    BakingSoda = { name = "Baking Soda", food = 0.1, thirst = 0.0 },
    ProteinPowder = { name = "Protein Powder", food = 4.5, thirst = 0.0 },
    IronPowder = { name = "Iron Powder", food = 0.0, thirst = 0.0 },
    IronOxide = { name = "Iron Oxide", food = -5.0, thirst = 0.0 },
    CopperOxide = { name = "Copper Oxide", food = -5.0, thirst = 0.0 },
    Magnesium = { name = "Magnesium", food = 0.0, thirst = 0.0 },
    StrongWhiskey = { name = "Acid Whiskey", food = -5.0, thirst = 0.0 },
    Fun = { name = "Fun", food = -7.0, thirst = 0.0 },
    Lemonade = { name = "Lemonade", food = 2.0, thirst = 10.0 },
    Orangeade = { name = "Orangeade", food = 2.5, thirst = 10.0 },
    Thermite = { name = "Thermite Mix I", food = -101.0, thirst = 0.0 },
    StrongThermite = { name = "Thermite Mix II", food = -101.0, thirst = 0.0 },
    SeaWater = { name = "Sea Water", food = 0.0, thirst = -40.0 },
}

function M.isContainer(t)
    return type(t) == "table" and t.category == "liquid"
end

local function unwrap(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        return data[1]
    end
    return data
end

-- The only liquid a container type can hold, when it lists exactly one (nil otherwise).
local function soleLiquid(t)
    local list = t and t.categoryData and t.categoryData.liquids
    if type(list) == "table" and #list == 1 and type(list[1]) == "table" then
        return list[1][1]
    end
    return nil
end

-- amount (litres, 0 when unknown), liquid key (nil when the container is empty or unknown)
function M.decode(t, data)
    local d = unwrap(data)
    local amount = tonumber(d.amount or d[1]) or 0
    local liquid = type(d.liquid) == "string" and d.liquid or (type(d[2]) == "string" and d[2] or soleLiquid(t))
    if amount < M.EMPTY_BELOW or not liquid then
        return 0, nil -- an amount of an unknown liquid is nothing drinkable
    end
    return amount, liquid
end

-- Containers something fills again once empty: the Petrol Can at a fuel pump (vehicles/server/main.lua
-- fuelPumpInteractRequested). Nothing else refills a container (the upstream `reusable` flag in the type data is
-- read by no code), so every other emptied drink is rubbish.
M.REFILLABLE = { GasCan = true }

-- An empty container that is only rubbish now: a liquid type that can hold something, that nothing refills, with
-- nothing drinkable left. Types with no liquids at all (Ketchup, Mustard) are never empty "after use" and stay.
function M.isLitter(t, data)
    if not M.isContainer(t) or M.REFILLABLE[t.uname] then
        return false
    end
    local list = t.categoryData and t.categoryData.liquids
    if type(list) ~= "table" or #list == 0 then
        return false
    end
    local _, liquid = M.decode(t, data)
    return liquid == nil
end

function M.capacity(t)
    return tonumber(t and t.categoryData and t.categoryData.capacity) or 0
end

function M.liquidName(key)
    local l = key and M.LIQUIDS[key]
    return l and l.name or tostring(key or "?")
end

-- OnItemNameRender: "Bottle (Water 0.4/0.50)" or "Bottle (Empty)"
function M.label(t, name, data)
    local amount, liquid = M.decode(t, data)
    if not liquid then
        return name .. " (" .. tr("Empty") .. ")"
    end
    return string.format("%s (%s %.1f/%.2f)", name, tr(M.liquidName(liquid)), amount, M.capacity(t))
end

-- One sip: ok, next data, food delta, thirst delta; or false, "EMPTY".
function M.sip(t, data)
    local amount, liquid = M.decode(t, data)
    if not liquid then
        return false, "EMPTY"
    end
    local l = M.LIQUIDS[liquid]
    local drunk = math.min(amount, M.SIP_LITRES)
    local share = drunk / M.SIP_LITRES
    local next_ = { amount = math.max(0, amount - drunk), liquid = liquid }
    return true, next_, (l and l.food or 0) * share, (l and l.thirst or 0) * share
end

-- From FULL up a need counts as met: nothing is eaten or drunk for it.
M.FULL = 99

-- Whether a sip of the container would do the character any good, or is no drink at all (petrol, acid: always
-- allowed). False when it only gives what the character is already full of.
function M.wanted(t, data, food, thirst)
    local _, liquid = M.decode(t, data)
    local l = liquid and M.LIQUIDS[liquid]
    if not l or l.food < 0 or l.thirst < 0 or (l.food <= 0 and l.thirst <= 0) then
        return true
    end
    return (l.thirst > 0 and (tonumber(thirst) or 0) < M.FULL) or (l.food > 0 and (tonumber(food) or 0) < M.FULL)
end

return M
