-- The inventory's Skills list (upstream skl_ShowSkillList, #93): each skill with its level name in the level's
-- colour, Back returns to the inventory. The server sends the rows on spawn and after every change
-- (characterSkillsSynced); a skill named after an item type shows that type's name.
local rows = {}

addEventHandler("characterSkillsSynced", localPlayer, function(list)
    rows = type(list) == "table" and list or {}
end)

local function displayName(name)
    local t = exports.data:itemType(name)
    return t and t.name or name
end

function skillsOpen()
    local list = {}
    for i, r in ipairs(rows) do
        local label = string.format("%s (%s)", displayName(r.name), r.level)
        list[i] = { id = "skill:" .. r.name, label = label, colour = r.colour }
    end
    if #list == 0 then
        list[1] = { id = "skill:none", label = "No skills yet" }
    end
    return exports.ui:listOpen("skills", "Skills", list, { "Back", "Close" })
end

addEventHandler("uiListActionSelected", root, function(listId)
    if listId ~= "skills" then
        return
    end
    exports.ui:listClose()
    triggerServerEvent("inventoryOpenRequested", localPlayer)
end)
