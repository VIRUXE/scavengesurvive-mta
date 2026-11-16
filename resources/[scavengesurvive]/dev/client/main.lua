local function loadFile(path, chunkName)
    local f = fileOpen(path, true)
    local src = fileRead(f, fileGetSize(f))
    fileClose(f)
    return assert(loadstring(src, chunkName))()
end
local logic = loadFile("shared/logic/studio.lua", "=dev/studio_logic.lua")
local heldUntil = {} -- lower-case command or key -> tick until which it counts as held

local function pressCommand(command)
    if not executeCommandHandler(command) then
        triggerEvent("onClientKey", root, command, true)
    end
end

-- rcon "key <player> <command>" and "hold <player> <command> <ms>": runs a bound command (interact, dropitem,
-- putaway, inventory) or dispatches a client key press (arrow_u, arrow_d, enter, escape) so a live check can be
-- driven from a script. With ms > 0 the command and its bound key also report as held through isHeld() for ms
-- milliseconds; ms = 0 releases an active hold early (#98).
addEventHandler("devKeyPressed", root, function(command, ms)
    if ms ~= nil then
        if logic.holdSet(heldUntil, command, getKeyBoundToCommand(command), getTickCount(), ms) then
            pressCommand(command)
        end
        return
    end
    pressCommand(command)
end)

function isHeld(name)
    return logic.holdActive(heldUntil, name, getTickCount())
end

-- rcon "clua <player> <code>": runs a chunk on this client and prints its return values (or the error) to chat,
-- where "rcon chat <player>" reads them. Dev-only, like the server-side lua verb.
addEventHandler("devClientLuaRequested", root, function(code)
    local chunk, err = loadstring(code, "=rcon-client")
    if not chunk then
        return outputChatBox("[clua] compile error: " .. tostring(err))
    end
    local r = { pcall(chunk) }
    if not table.remove(r, 1) then
        return outputChatBox("[clua] runtime error: " .. tostring(r[1]))
    end
    if #r == 0 then
        return outputChatBox("[clua] ok (no return values)")
    end
    for i = 1, #r do
        local v = r[i]
        if type(v) == "table" then
            local parts = {}
            for k, x in pairs(v) do
                parts[#parts + 1] = tostring(k) .. "=" .. tostring(x)
            end
            table.sort(parts)
            v = "{ " .. table.concat(parts, ", ") .. " }"
        end
        outputChatBox(string.format("[clua] [%d] %s", i, tostring(v)))
    end
end)

-- rcon "chat <player>": every chat line this client receives is echoed to the server, which keeps the last
-- hundred per player. Screenshots never include the chat box, so a scripted live check reads replies this way.
addEventHandler("onClientChatMessage", root, function(text)
    triggerServerEvent("devChatLineReceived", localPlayer, text)
end)
