-- The character's skills for the HUD's skill bars (hud/client/main.lua, bottom right): the server sends the rows
-- ({ name, amount, level, colour } in learned order, shared/logic/skills.lua M.rows) on spawn and after every change
-- (characterSkillsSynced); the hud reads them through skillRows when it (re)starts.
local rows = {}

addEventHandler("characterSkillsSynced", localPlayer, function(list)
    rows = type(list) == "table" and list or {}
end)

function skillRows()
    return rows
end

-- the spawn's rows are lost when the server side started before this script (a character restart)
addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("characterSkillsRequested", localPlayer)
end)
