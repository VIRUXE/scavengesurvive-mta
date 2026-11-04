local lang = loadstring(exports.lib:getModule("lang"), "=lib/lang.lua")()
local REPORT_MS = 50
local lastReport = 0
-- lang:begin
local PARTS = {
    [3] = "torso",
    [4] = "groin",
    [5] = "left arm",
    [6] = "right arm",
    [7] = "left leg",
    [8] = "right leg",
    [9] = "head",
}
-- lang:end

-- GTA weapon damage stays > 0 (Appendix B) so this fires; the server decides the wound and sets health.
addEventHandler("onClientPlayerDamage", root, function(attacker, weapon, bodypart, loss)
    if source ~= localPlayer then
        return
    end
    cancelEvent()
    if getElementData(localPlayer, "auth.reauthProtection") then
        return
    end
    local now = getTickCount()
    if now - lastReport < REPORT_MS then
        return
    end
    lastReport = now
    triggerServerEvent(
        "weaponHitReported",
        localPlayer,
        isElement(attacker) and attacker or false,
        weapon or 0,
        bodypart or 3,
        loss or 0
    )
end)

addEventHandler("woundInflicted", root, function(bleedAdd, hpLoss, bodypart)
    local part = PARTS[bodypart] and lang.text(PARTS[bodypart]) or lang.text("body")
    local text = lang.format("Wounded: %s  -%d hp", part, math.floor(hpLoss + 0.5))
    if bleedAdd > 0 then
        text = text .. "  " .. lang.text("(bleeding)")
    end
    exports.ui:toast(text, 220, 60, 60)
end)
