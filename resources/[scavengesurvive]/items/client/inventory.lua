Held = false
local TOASTS = {
    HANDS_FULL = "Your hands are full",
    NOT_IN_WORLD = "It is gone",
    CONTAINER_FULL = "No space",
    PUT_AWAY = "Put away",
    BAG_WORN = "You put on the bag",
    BAG_SLOT_USED = "You already wear a bag",
    NOT_HELD = "Nothing in hand",
    ATE = "You ate it",
    DB_ERROR = "Server error",
    NOT_OWNER = "Not yours",
    NOT_OWNED = "Not yours",
    NOT_IN_CONTAINER = "It is not there any more",
    SELF_CONTAINMENT = "It does not fit inside itself",
}

addEventHandler("onClientItemsToast", root, function(code)
    exports.ui:toast(TOASTS[code] or tostring(code))
end)

local function itemName(uname)
    local t = exports.data:itemType(uname)
    return t and t.name or uname
end

local function rowsFor(list, prefix)
    local rows = {}
    for _, it in ipairs(list or {}) do
        local actions = { { id = "take", label = "Take" } }
        if it.category == "food" then
            actions[#actions + 1] = { id = "use", label = "Eat" }
        end
        rows[#rows + 1] =
            { id = it.id, label = prefix .. itemName(it.uname), sub = tostring(it.hp) .. " hp", actions = actions }
    end
    return rows
end

local lastInventory

-- the held item is the first row (Eat for food, Drop); inventory and bag rows follow
local function buildRows(p)
    local rows = {}
    if Held then
        local t = exports.data:itemType(Held.uname)
        local actions = {}
        if t and t.category == "food" then
            actions[#actions + 1] = { id = "use", label = "Eat" }
        end
        actions[#actions + 1] = { id = "drop", label = "Drop" }
        rows[1] = {
            id = Held.id,
            label = "[hand] " .. itemName(Held.uname),
            sub = tostring(Held.hp) .. " hp",
            actions = actions,
        }
    end
    for _, r in ipairs(rowsFor(p.inventory, "")) do
        rows[#rows + 1] = r
    end
    for _, r in ipairs(rowsFor(p.bag or {}, "[bag] ")) do
        rows[#rows + 1] = r
    end
    return rows
end

addEventHandler("onClientItemsHeld", root, function(item)
    Held = item
    if lastInventory then
        exports.ui:listUpdate("inventory", buildRows(lastInventory))
    end
end)

addEventHandler("onClientItemsInventory", root, function(p)
    lastInventory = p
    local rows = buildRows(p)
    local title = string.format("Inventory %d/%d", p.capacity.inv.used, p.capacity.inv.size)
    if p.capacity.bag then
        title = title .. string.format("  Bag %d/%d", p.capacity.bag.used, p.capacity.bag.size)
    end
    -- reopen (not listUpdate) so the capacity title stays current
    exports.ui:listOpen("inventory", title, rows)
end)

addEventHandler("onClientUiListAction", root, function(listId, rowId, actionId)
    if listId ~= "inventory" then
        return
    end
    if actionId == "take" then
        triggerServerEvent("onItemsRequestTake", localPlayer, rowId)
    elseif actionId == "use" then
        triggerServerEvent("onItemsRequestUse", localPlayer, rowId)
    elseif actionId == "drop" then
        triggerServerEvent("onItemsRequestDrop", localPlayer)
    end
end)
