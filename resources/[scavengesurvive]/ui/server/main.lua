-- Server side of the help tip (client/tip.lua): resources call exports.ui:showTip(player, text, footer, ms) and
-- it reaches only players with /tooltips on (auth, accounts.tooltips), as upstream's ShowHelpTip does.
function showTip(player, text, footer, ms)
    if not isElement(player) or not exports.auth:tooltipsOn(player) then
        return false
    end
    triggerClientEvent(player, "helpTipShown", player, tostring(text), footer or false, tonumber(ms) or 0)
    return true
end

function hideTip(player)
    if not isElement(player) then
        return false
    end
    triggerClientEvent(player, "helpTipHidden", player)
    return true
end
