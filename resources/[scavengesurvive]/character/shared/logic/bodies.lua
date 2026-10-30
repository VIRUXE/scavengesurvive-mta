-- The body a death leaves behind (upstream player/death.pwn CreateGravestone + item/torso.pwn, #139): a Torso item
-- whose data carries the character's name, the coroner's line for how they died and when, and whether a knife
-- can still take meat from it.
local M = {}

-- upstream death.pwn's deathreasonstring by the cause the port reports (weapons: wound.killCause; the survival
-- tick: survival.deathCause; onPlayerWasted: drowned / fall / burned)
M.REASONS = {
    beaten = "They were beaten to death.",
    knife = "They suffered small lacerations on the torso, possibly from a knife.",
    sword = "Large lacerations cover the torso and head, looks like a finely sharpened sword.",
    chainsaw = "There's bits everywhere, probably suffered a chainsaw to the torso.",
    explosion = "They suffered massive concussion due to an explosion.",
    burned = "The entire body is charred and burnt.",
    shot = "They died of blood loss caused by what looks like bullets.",
    sprayed = "They were sprayed and suffocated by a high pressure substance.",
    goggles = "Somehow, they were killed by goggles.",
    camera = "Somehow, they were killed by a camera.",
    drowned = "They drowned.",
    fall = "Most bones are broken, looks like they fell from a great height.",
    bleeding = "They bled to death.",
    starvation = "They starved to death.", -- not upstream, which had no line for it
}
M.KILLED = "They bled to death." -- upstream's default for a death at another player's hands
M.UNKNOWN = "They died for an unknown reason."

function M.reason(cause, byPlayer)
    local r = M.REASONS[string.lower(tostring(cause or ""))]
    if r then
        return r
    end
    return byPlayer and M.KILLED or M.UNKNOWN
end

-- the Torso item's data: name, reason, the death's unix time, harvest = 1 while a knife can still take meat
function M.data(name, reason, now)
    return { name = tostring(name or ""), reason = tostring(reason or M.UNKNOWN), at = now or 0, harvest = 1 }
end

return M
