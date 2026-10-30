-- The Note and Sign dialogs (upstream item/note.pwn, item/sign.pwn, #136): the server opens them (noteOpened,
-- signEditOpened) and the answer goes back with the item id it was opened for. A blank note takes a message
-- (Done / Cancel); a written note shows it (Close / Tear); a sign takes its text (Accept / Close).
return function()
    local NOTE_ID, SIGN_ID = "items:note", "items:sign"
    local SIGN_BODY = "Enter the text to display below\nTyping '\\' will start a new line."
    local open = nil -- { kind = "note" | "sign", itemId, written }

    addEventHandler("noteOpened", localPlayer, function(itemId, text)
        open = { kind = "note", itemId = itemId, written = text ~= "" }
        if text == "" then
            exports.ui:dialogOpen(NOTE_ID, "input", "Note", "Write a message onto the note:", "Done", "Cancel")
        else
            exports.ui:dialogOpen(NOTE_ID, "msgbox", "Note", text, "Close", "Tear")
        end
    end)

    addEventHandler("signEditOpened", localPlayer, function(itemId)
        open = { kind = "sign", itemId = itemId }
        exports.ui:dialogOpen(SIGN_ID, "input", "Sign", SIGN_BODY, "Accept", "Close")
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
        end
    end)
end
