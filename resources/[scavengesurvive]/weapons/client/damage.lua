local REPORT_MS = 50
local lastReport = 0
local PARTS = {
    [3] = "torso",
    [4] = "groin",
    [5] = "left arm",
    [6] = "right arm",
    [7] = "left leg",
    [8] = "right leg",
    [9] = "head",
}

-- GTA weapon damage stays > 0 (Appendix B) so this fires; the server decides the wound and sets health.
addEventHandler("onClientPlayerDamage", root, function(attacker, weapon, bodypart, loss)
    if source ~= localPlayer then
        return
    end
    cancelEvent()
    local now = getTickCount()
    if now - lastReport < REPORT_MS then
        return
    end
    lastReport = now
    triggerServerEvent(
        "onWeaponsRequestHit",
        localPlayer,
        isElement(attacker) and attacker or false,
        weapon or 0,
        bodypart or 3,
        loss or 0
    )
end)

addEventHandler("onClientWeaponsWound", root, function(bleedAdd, hpLoss, bodypart)
    local text = string.format("Wounded: %s  -%d hp", PARTS[bodypart] or "body", math.floor(hpLoss + 0.5))
    if bleedAdd > 0 then
        text = text .. "  (bleeding)"
    end
    exports.ui:toast(text, 220, 60, 60)
end)
