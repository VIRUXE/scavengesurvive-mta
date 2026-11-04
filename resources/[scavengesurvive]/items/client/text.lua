-- The Note and Sign dialogs (upstream item/note.pwn, item/sign.pwn, #136): the server opens them (noteOpened,
-- signEditOpened) and the answer goes back with the item id it was opened for. A blank note takes a message
-- (Done / Cancel); a written note shows it (Close / Tear); a sign takes its text (Accept / Close). A body's
-- name and reason (bodyInspected, #139) is a plain message box.
return function(machines)
    local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
    local L = lang.text
    local NOTE_ID, SIGN_ID, MACHINE_ID = "items:note", "items:sign", "items:machine"
    local open = nil -- { kind = "note" | "sign" | "machine", itemId, written }
    -- lang:begin
    local SIGN_BODY = "Enter the text to display below\nTyping '\\' will start a new line."
    local TITLES = { scrap = "Scrap Machine", refine = "Refining Machine", water = "Water Purifier" }
    local MACHINE = "Machine"
    -- lang:end

    addEventHandler("noteOpened", localPlayer, function(itemId, text)
        open = { kind = "note", itemId = itemId, written = text ~= "" }
        if text == "" then
            local prompt = L("Write a message onto the note:")
            exports.ui:dialogOpen(NOTE_ID, "input", L("Note"), prompt, L("Done"), L("Cancel"))
        else
            exports.ui:dialogOpen(NOTE_ID, "msgbox", L("Note"), text, L("Close"), L("Tear"))
        end
    end)

    addEventHandler("signEditOpened", localPlayer, function(itemId)
        open = { kind = "sign", itemId = itemId }
        exports.ui:dialogOpen(SIGN_ID, "input", L("Sign"), L(SIGN_BODY), L("Accept"), L("Close"))
    end)

    addEventHandler("bodyInspected", localPlayer, function(name, reason)
        exports.ui:dialogOpen("items:body", "msgbox", name, L(reason), L("Close"), "")
    end)

    addEventHandler("potInspected", localPlayer, function(status)
        exports.ui:dialogOpen("items:pot", "msgbox", L("Plant Pot"), status, L("Close"), "")
    end)

    -- a machine's menu (#145, upstream machine.pwn _mach_HoldInteract): Start cooks what is inside
    addEventHandler("machineMenuShown", localPlayer, function(itemId, kind, fuel)
        open = { kind = "machine", itemId = itemId }
        local body = machines.menuBody(kind, tonumber(fuel) or 0)
        exports.ui:dialogOpen(MACHINE_ID, "msgbox", L(TITLES[kind] or MACHINE), body, L("Start"), L("Cancel"))
    end)

    addEventHandler("uiDialogResponded", root, function(id, accepted, text)
        local o = open
        if not o then
            return
        end
        if id == NOTE_ID and o.kind == "note" then
            open = nil
            if o.written then
                if not accepted then
                    triggerServerEvent("noteTearRequested", localPlayer, o.itemId)
                end
            elseif accepted and tostring(text or "") ~= "" then
                triggerServerEvent("noteWritten", localPlayer, o.itemId, tostring(text))
            end
        elseif id == SIGN_ID and o.kind == "sign" then
            open = nil
            if accepted and tostring(text or "") ~= "" then
                triggerServerEvent("signTextSubmitted", localPlayer, o.itemId, tostring(text))
            end
        elseif id == MACHINE_ID and o.kind == "machine" then
            open = nil
            if accepted then
                triggerServerEvent("machineStartRequested", localPlayer, o.itemId)
            end
        end
    end)
end
