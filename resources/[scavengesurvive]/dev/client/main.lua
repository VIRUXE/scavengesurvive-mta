-- rcon "key <player> <command>": runs a bound command (interact, dropitem, putaway, inventory) as if the player
-- pressed its key, so a live check can be driven from a script.
addEventHandler("onClientDevKey", root, function(command)
    executeCommandHandler(command)
end)
