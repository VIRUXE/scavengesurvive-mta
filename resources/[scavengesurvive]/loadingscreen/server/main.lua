-- MTA's own transfer box is off for the whole join: the client script can only hide it once this resource's files
-- have arrived, and the box is already up before that (the "Map download progress" of the join, then these files).
-- A client with "always show transfer box" ticked in its MTA settings still sees it; nothing here can change that.
addEventHandler("onResourceStart", resourceRoot, function()
    setTransferBoxVisible(false)
end)

addEventHandler("onResourceStop", resourceRoot, function()
    setTransferBoxVisible(true)
end)
