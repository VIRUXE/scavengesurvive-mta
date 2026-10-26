-- Liquid containers (upstream itemtype/liquid-container.pwn + the DefineLiquidType table in server/init.pwn):
-- a container type lists the liquids it may spawn with and their chances; the item's data holds the amount in
-- litres and the liquid name. Drinking is a 1 s hold per sip: each sip takes 0.2 L and adds the liquid's food value
-- (negative for petrol and the like). Pure: no MTA calls at file scope. Item data arrives as { amount, liquid } or
-- MTA's wrapped form { { amount, liquid } }; a container with one possible liquid (the Petrol Can) may carry only
-- the amount, as vehicles write it.
local M = {}

M.SIP_LITRES = 0.2
M.HOLD_MS = 1000
M.EMPTY_BELOW = 0.001 -- upstream: below this the label reads "Empty" and nothing can be drunk

-- name as shown in labels, food per sip
M.LIQUIDS = {
    Water = { name = "Water", food = 0.5 },
    Milk = { name = "Milk", food = 2.1 },
    Orange = { name = "Orange Juice", food = 1.0 },
    Apple = { name = "Apple Juice", food = 1.0 },
    Whiskey = { name = "Whiskey", food = 0.1 },
    WineRed = { name = "Red Wine", food = 0.4 },
    WineWhite = { name = "White Wine", food = 0.4 },
    Champagne = { name = "Champagne", food = 0.2 },
    Ethanol = { name = "Ethanol", food = -44.1 },
    Turpentine = { name = "Turpentine", food = -101.0 },
    HydroAcid = { name = "Hydrochloric Acid", food = -101.0 },
    CarbonatedWater = { name = "Carbonated Water", food = 0.1 },
    Lemon = { name = "Lemon Juice", food = 2.1 },
    Sugar = { name = "Sugar", food = 0.8 },
    Petrol = { name = "Petrol", food = -8.0 },
    Diesel = { name = "Diesel", food = -8.0 },
    Oil = { name = "Oil", food = -8.0 },
    BakingSoda = { name = "Baking Soda", food = 0.1 },
    ProteinPowder = { name = "Protein Powder", food = 4.5 },
    IronPowder = { name = "Iron Powder", food = 0.0 },
    IronOxide = { name = "Iron Oxide", food = -5.0 },
    CopperOxide = { name = "Copper Oxide", food = -5.0 },
    Magnesium = { name = "Magnesium", food = 0.0 },
    StrongWhiskey = { name = "Acid Whiskey", food = -5.0 },
    Fun = { name = "Fun", food = -7.0 },
    Lemonade = { name = "Lemonade", food = 2.1 },
    Orangeade = { name = "Orangeade", food = 2.5 },
    Thermite = { name = "Thermite Mix I", food = -101.0 },
    StrongThermite = { name = "Thermite Mix II", food = -101.0 },
    SeaWater = { name = "Sea Water", food = -50.0 },
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
    local amount = tonumber(d.amount) or 0
    local liquid = type(d.liquid) == "string" and d.liquid or soleLiquid(t)
    if amount < M.EMPTY_BELOW or not liquid then
        return 0, nil -- an amount of an unknown liquid is nothing drinkable
    end
    return amount, liquid
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
        return name .. " (Empty)"
    end
    return string.format("%s (%s %.1f/%.2f)", name, M.liquidName(liquid), amount, M.capacity(t))
end

-- One sip: ok, next data, food delta; or false, "EMPTY".
function M.sip(t, data)
    local amount, liquid = M.decode(t, data)
    if not liquid then
        return false, "EMPTY"
    end
    local l = M.LIQUIDS[liquid]
    local next_ = { amount = math.max(0, amount - M.SIP_LITRES), liquid = liquid }
    return true, next_, l and l.food or 0
end

return M
