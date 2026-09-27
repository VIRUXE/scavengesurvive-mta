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

addEventHandler("onClientItemsHeld", root, function(item)
    Held = item
end)

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

addEventHandler("onClientItemsInventory", root, function(p)
    local rows = rowsFor(p.inventory, "")
    for _, r in ipairs(rowsFor(p.bag or {}, "[bag] ")) do
        rows[#rows + 1] = r
    end
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
    end
end)
