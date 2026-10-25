-- Cooking (#95; upstream core/item/campfire.pwn, core/item/barbecue.pwn, core/item/food.pwn). A cooker's state is
-- its item data, so a restart keeps it: a Campfire holds { burnsAt, food, doneAt }, a Barbecue { fuel, grill, doneAt }
-- (grill = two food item ids, 0 for a free spot). Times are unix seconds. Food cooked on either carries
-- data.cooked = 1 (upstream food_cooked). Pure: busted dofiles it; items/server/cooking.lua does the I/O.
local M = {}

M.CAMPFIRE_COOK_S = 60 -- cmp_FinishCooking[60000]
M.BBQ_COOK_S = 30 -- bbq_FinishCooking[30000]
M.CAMPFIRE_LIFE_S = 600 -- cmp_BurnOut 600000
M.CAMPFIRE_RAIN_LIFE_S = 120 -- in the rain: 120000, 40 % of the time...
M.RAIN_KEEP_PERCENT = 40 -- ...otherwise it fizzles back into three Wood Logs
M.RAIN_WEATHERS = { [8] = true, [16] = true }
M.FOOD_Z = 0.3 -- campfire: the food sits 0.3 above the fire
M.GRILL_DIST, M.GRILL_Z = 0.25, 0.818 -- barbecue: either side of the grill, 0.818 up
M.PETROL_PER_FILL, M.FUEL_PER_FILL = 0.6, 10 -- 0.6 L from a Petrol Can gives 10 cooks
M.NEAR = 1.0 -- a food still within this of its cooker (x/y) is still on it
M.LOGS = 3

local function int(v)
    v = tonumber(v)
    return v and math.floor(v) or nil
end

-- item data arrives either as an object or wrapped in MTA's toJSON array
local function unwrap(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        return data[1]
    end
    return data
end
M.unwrap = unwrap

function M.isFood(t)
    return t ~= nil and t.category == "food"
end

function M.canCook(t)
    return M.isFood(t) and t.categoryData ~= nil and t.categoryData.canCook == true
end

function M.isCooked(data)
    local c = unwrap(data).cooked
    return c ~= nil and c ~= false and c ~= 0
end

-- item/food.pwn _EatItem: food that can be cooked and was not counts as raw (70 % food, infects when canRawInfect)
function M.isRaw(t, data)
    return M.canCook(t) and not M.isCooked(data)
end

-- OnItemNameRender: "Cooked" / "Uncooked" for food that can be cooked (the port eats a whole item, no bite %)
function M.label(t, name, data)
    if not M.canCook(t) then
        return name
    end
    return string.format("%s (%s)", name, M.isCooked(data) and "Cooked" or "Uncooked")
end

-- A cooker's data, normalised: numbers or nil, grill always two ids (0 = free).
function M.decode(data)
    local d = unwrap(data)
    local grill = type(d.grill) == "table" and d.grill or {}
    return {
        burnsAt = int(d.burnsAt),
        food = int(d.food),
        doneAt = int(d.doneAt),
        fuel = int(d.fuel),
        grill = { int(grill[1]) or 0, int(grill[2]) or 0 },
    }
end

-- The JSON text written to items.data; keys in a fixed order, absent fields left out.
function M.encode(uname, d)
    local parts = {}
    local function add(key, v)
        if v ~= nil then
            parts[#parts + 1] = string.format('"%s":%d', key, v)
        end
    end
    if uname == "Barbecue" then
        add("fuel", d.fuel or 0)
        parts[#parts + 1] = string.format('"grill":[%d,%d]', d.grill[1] or 0, d.grill[2] or 0)
        add("doneAt", d.doneAt)
    else
        add("burnsAt", d.burnsAt)
        add("food", d.food)
        add("doneAt", d.doneAt)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

local function copy(d)
    return { burnsAt = d.burnsAt, food = d.food, doneAt = d.doneAt, fuel = d.fuel, grill = { d.grill[1], d.grill[2] } }
end

-- OnItemCreateInWorld: how long a new campfire burns (seconds), or nil when the rain puts it out at once.
-- roll: 0..99.
function M.campfireLife(weather, roll)
    if M.RAIN_WEATHERS[tonumber(weather) or -1] then
        if roll < M.RAIN_KEEP_PERCENT then
            return M.CAMPFIRE_RAIN_LIFE_S
        end
        return nil
    end
    return M.CAMPFIRE_LIFE_S
end

-- Where the logs fall when a campfire goes out: x/y within 0.25, any heading. rand(): 0..1.
function M.logSpots(x, y, z, rand)
    local spots = {}
    for i = 1, M.LOGS do
        spots[i] = { x = x - 0.25 + rand() * 0.5, y = y - 0.25 + rand() * 0.5, z = z, rz = math.floor(rand() * 360) }
    end
    return spots
end

-- upstream x + 0.25 * floatsin(-r +/- 90), y + 0.25 * floatcos(-r +/- 90): spot 1 on one side, 2 on the other
function M.grillSpot(x, y, z, rz, slot)
    local a = math.rad(-(rz or 0) + (slot == 1 and 90 or -90))
    return x + M.GRILL_DIST * math.sin(a), y + M.GRILL_DIST * math.cos(a), z + M.GRILL_Z
end

-- The burners' fire while a barbecue cooks (upstream _LightBBQ: 0.25 either side, 0.6 below the item).
function M.burnerSpots(x, y, z, rz)
    local spots = {}
    for i, side in ipairs({ 90, 270 }) do
        local a = math.rad(-(rz or 0) + side)
        spots[i] = { x = x + M.GRILL_DIST * math.sin(a), y = y + M.GRILL_DIST * math.cos(a), z = z - 0.6 }
    end
    return spots
end

-- Campfire + food in hand (cmp_CookItem). Returns ok, code, next data.
function M.campfireAdd(d, foodId, now)
    if d.food then
        return false, "BUSY"
    end
    local n = copy(d)
    n.food, n.doneAt = foodId, now + M.CAMPFIRE_COOK_S
    return true, "FIRELITSTAR", n
end

-- Barbecue + food in hand (_UseBbqHandler). onGrill: id -> true for the grill ids still on the grill.
-- Returns ok, code, next data, spot.
function M.bbqAdd(d, foodId, cooked, onGrill)
    if cooked then
        return false, "BBQALREADYC"
    end
    for slot = 1, 2 do
        local id = d.grill[slot]
        if id == 0 or not onGrill[id] then
            local n = copy(d)
            n.grill[slot] = foodId
            return true, "BBQFOODADDE", n, slot
        end
    end
    return false, "BBQ_FULL"
end

-- Barbecue + Petrol Can: 0.6 L (or what is left) for 10 more cooks. Returns ok, code, next data, can amount left.
function M.bbqFuel(d, canAmount)
    canAmount = tonumber(canAmount) or 0
    if canAmount <= 0 then
        return false, "PETROLEMPTY"
    end
    local n = copy(d)
    n.fuel = (d.fuel or 0) + M.FUEL_PER_FILL
    return true, "BBQADDPETRO", n, math.max(0, canAmount - math.min(canAmount, M.PETROL_PER_FILL))
end

-- Barbecue + Fire Lighter: starts the 30 s cook. Returns ok, code, next data.
function M.bbqLight(d, now)
    if d.doneAt then
        return false, "BBQ_LIT"
    end
    if (d.fuel or 0) <= 0 then
        return false, "BBQFUELEMPT"
    end
    local n = copy(d)
    n.doneAt = now + M.BBQ_COOK_S
    return true, "BBQLITSTART", n
end

-- What the sweep does to a cooker row now:
--   { kind = "life" }                       a campfire not given its burn time yet (the caller rolls the weather)
--   { kind = "cook", data = n, foods = ids } the cook finished: write n, mark the foods cooked
--   { kind = "burn" }                       the campfire burnt out
--   nil                                     nothing yet
function M.step(uname, d, now)
    if uname == "Campfire" then
        if not d.burnsAt then
            return { kind = "life" }
        end
        if d.doneAt and now >= d.doneAt then
            local n = copy(d)
            n.food, n.doneAt = nil, nil
            return { kind = "cook", data = n, foods = { d.food } }
        end
        if now >= d.burnsAt then
            return { kind = "burn" }
        end
        return nil
    end
    if uname == "Barbecue" and d.doneAt and now >= d.doneAt then
        local n = copy(d)
        n.doneAt = nil
        n.fuel = math.max(0, (d.fuel or 0) - 1)
        local foods = {}
        for _, id in ipairs(d.grill) do
            if id ~= 0 then
                foods[#foods + 1] = id
            end
        end
        return { kind = "cook", data = n, foods = foods }
    end
    return nil
end

-- The ids a cooker is cooking right now (they cannot be picked up: cmp_ItemBeingCooked). Upstream only guards the
-- campfire; a lit barbecue's grill is guarded too, so its food cannot leave half way through.
function M.busyFoods(uname, d)
    local ids = {}
    if not d.doneAt then
        return ids
    end
    if uname == "Campfire" and d.food then
        ids[1] = d.food
    elseif uname == "Barbecue" then
        for _, id in ipairs(d.grill) do
            if id ~= 0 then
                ids[#ids + 1] = id
            end
        end
    end
    return ids
end

return M
