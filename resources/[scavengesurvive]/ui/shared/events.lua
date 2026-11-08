-- server to client
addEvent("helpTipShown", true)
addEvent("helpTipHidden", true)
addEvent("infoShown", true)

-- client-local
addEvent("uiListActionSelected", false)
addEvent("uiListActionsOpened", false) -- a row's actions dialog opened (listId, rowId)
addEvent("uiListClosed", false)
addEvent("uiDialogResponded", false)
