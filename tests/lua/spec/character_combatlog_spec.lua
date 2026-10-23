local combatlog = dofile("resources/[scavengesurvive]/character/shared/logic/combatlog.lua")
local online = {}
local function isOnline(p)
    return online[p] == true
end

describe("anti-combat-log", function()
    local st
    before_each(function()
        st = combatlog.new()
        online = { A = true, B = true }
    end)
    it("names the last attacker while the window is open and the attacker is online", function()
        combatlog.damaged(st, "B", "A", 1000)
        assert.equals("A", combatlog.attackerOf(st, "B", 1000 + 29999, 30, isOnline))
        assert.is_nil(combatlog.attackerOf(st, "B", 1000 + 30000, 30, isOnline))
        assert.is_nil(combatlog.attackerOf(st, "A", 1000, 30, isOnline)) -- the attacker was never hit
    end)
    it("uses the default 30 s window when the setting is missing", function()
        combatlog.damaged(st, "B", "A", 0)
        assert.equals("A", combatlog.attackerOf(st, "B", 29999, nil, isOnline))
        assert.is_nil(combatlog.attackerOf(st, "B", 30000, nil, isOnline))
    end)
    it("is not a combat log once the attacker left", function()
        combatlog.damaged(st, "B", "A", 0)
        online.A = nil
        assert.is_nil(combatlog.attackerOf(st, "B", 1000, 30, isOnline))
    end)
    it("keeps the attacker but extends the window on environmental damage", function()
        combatlog.damaged(st, "B", "A", 0)
        combatlog.damaged(st, "B", nil, 25000) -- a fall
        assert.equals("A", combatlog.attackerOf(st, "B", 50000, 30, isOnline))
    end)
    it("ignores self-inflicted damage as an attacker", function()
        combatlog.damaged(st, "B", "B", 0)
        assert.is_nil(combatlog.attackerOf(st, "B", 1000, 30, isOnline))
    end)
    it("starts a new character clean", function()
        combatlog.damaged(st, "B", "A", 0)
        combatlog.reset(st, "B")
        assert.is_nil(combatlog.attackerOf(st, "B", 1000, 30, isOnline))
    end)
    it("releases the victim when the attacker disconnects", function()
        combatlog.damaged(st, "B", "A", 0)
        assert.equals("B", combatlog.forget(st, "A")) -- the caller tells B's watch to turn white again
        assert.is_nil(st.lastAttacker.B)
        assert.is_nil(st.lastAttacked.A)
        assert.is_nil(combatlog.forget(st, "B")) -- nobody to release
        -- a later attacker is not released by the first one's departure
        combatlog.damaged(st, "B", "A", 0)
        combatlog.damaged(st, "B", "C", 10)
        assert.is_nil(combatlog.forget(st, "A"))
        assert.equals("C", st.lastAttacker.B)
    end)
    it("counts quits, timeouts and unknown reasons, never kicks or bans", function()
        assert.is_true(combatlog.countsAsLogout("Quit"))
        assert.is_true(combatlog.countsAsLogout("Timed out"))
        assert.is_true(combatlog.countsAsLogout("Bad Connection"))
        assert.is_true(combatlog.countsAsLogout(nil))
        assert.is_false(combatlog.countsAsLogout("Kicked"))
        assert.is_false(combatlog.countsAsLogout("Banned"))
    end)
end)
