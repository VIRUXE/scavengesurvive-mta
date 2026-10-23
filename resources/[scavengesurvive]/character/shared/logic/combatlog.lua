-- Anti-combat-log (upstream weapon/anti-combat-log.pwn + accounts.pwn): a player who disconnects within the
-- combat-log window of their last damage, while the player who last hurt them is still online, counts as dead.
-- Pure logic: the caller supplies the clock and the "is this attacker still online" test.
local combatlog = {}
combatlog.DEFAULT_WINDOW_S = 30

function combatlog.new()
    return { lastDamage = {}, lastAttacker = {}, lastAttacked = {} }
end

-- Any damage refreshes the victim's clock (upstream GetPlayerTookDamageTick); only a player attacker is remembered,
-- so an environmental hit keeps the previous attacker but extends the window.
function combatlog.damaged(state, victim, attacker, now)
    state.lastDamage[victim] = now
    if attacker ~= nil and attacker ~= victim then
        state.lastAttacker[victim] = attacker
        state.lastAttacked[attacker] = victim
    end
end

-- A fresh character starts clean (upstream OnPlayerSpawn).
function combatlog.reset(state, player)
    state.lastDamage[player] = nil
    state.lastAttacker[player] = nil
end

-- The attacker that makes `player` a combat logger at `now` (ms), or nil.
function combatlog.attackerOf(state, player, now, windowS, isOnline)
    local hit, attacker = state.lastDamage[player], state.lastAttacker[player]
    if not hit or not attacker then
        return nil
    end
    if now - hit >= (windowS or combatlog.DEFAULT_WINDOW_S) * 1000 then
        return nil
    end
    if not isOnline(attacker) then
        return nil
    end
    return attacker
end

-- Only a disconnect the player chose (or lost) is a combat log; a kick or ban is the staff's decision and the
-- character is saved as on any logout. A nil reason (no information) counts as the player's choice.
function combatlog.countsAsLogout(reason)
    return reason ~= "Kicked" and reason ~= "Banned"
end

-- On disconnect: drop the player's own record and release the victim they last hit (upstream OnPlayerDisconnect),
-- so a quitting attacker never leaves a dangling reference. Returns the victim released, if any.
function combatlog.forget(state, player)
    local victim = state.lastAttacked[player]
    local released = nil
    if victim and state.lastAttacker[victim] == player then
        state.lastAttacker[victim] = nil
        released = victim
    end
    state.lastAttacked[player] = nil
    state.lastDamage[player] = nil
    state.lastAttacker[player] = nil
    return released
end

return combatlog
