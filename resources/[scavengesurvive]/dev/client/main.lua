-- rcon "key <player> <command>": runs a bound command (interact, dropitem, putaway, inventory) or dispatches a
-- client key press (arrow_u, arrow_d, enter, escape) so a live check can be driven from a script.
addEventHandler("onClientDevKey", root, function(command)
    if not executeCommandHandler(command) then
        triggerEvent("onClientKey", root, command, true)
    end
end)
