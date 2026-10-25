-- Infection, drugs and the end of a treatment (#94, shared/logic/medical.lua). items runs the hold actions and calls
-- treat(); the drugs count down here once a second and wear off with upstream's "%s has worn off" line.
-- ctx = { medical, state, sendStats, wake, isKnockedOut } built by server/main.lua.
return function(ctx)
    local medical, state = ctx.medical, ctx.state
    local M = {}

    local function notice(player, text, ms)
        triggerClientEvent(player, "characterNoticeShown", player, text, ms or 3000)
    end

    -- LSD and Heroin paint the sky on the client; when the last of them wears off it goes back to the server's
    local function restoreSky(player)
        local hour, minute = getTime()
        triggerClientEvent(player, "drugSkyEnded", player, exports.world:getWeather(), hour, minute)
    end

    function M.applyDrug(player, st, name, ms)
        if not medical.applyDrug(st.drugs, name, ms) then
            return false
        end
        st.dirty = true
        notice(player, string.format("Taken %s", name))
        ctx.sendStats(player, true)
        return true
    end

    function M.setInfection(player, st, kind, on)
        if kind ~= "food" and kind ~= "wound" then
            return false
        end
        st.infection[kind] = on == true
        st.dirty = true
        ctx.sendStats(player, true)
        return true
    end

    -- Called by the survival tick each second for every live character.
    function M.tick(player, st, dtMs)
        local hadSky = medical.drugSky(st.drugs) ~= nil
        local off = medical.tickDrugs(st.drugs, dtMs)
        if #off == 0 then
            return
        end
        for _, name in ipairs(off) do
            notice(player, string.format("%s has worn off", name))
        end
        if hadSky and not medical.drugSky(st.drugs) then
            restoreSky(player)
        end
        st.dirty = true
        ctx.sendStats(player, true)
    end

    -- The end of a hold: applies the outcome to the patient and returns { used, consume, data } for items.
    function M.treat(healer, patient, uname, data)
        local st = state.byPlayer[patient]
        if not st or st.dead then
            return { used = false }
        end
        local view = { bleed = st.bleed, wounds = st.wounds, infection = st.infection }
        view.knockedOut = ctx.isKnockedOut(patient)
        local r = medical.treat(uname, data, view, healer == patient, math.random, math.random)
        if not r.used then
            return { used = false }
        end
        if r.bleed then
            st.bleed = r.bleed
        end
        if r.removeWounds then
            st.wounds = math.max(0, st.wounds - r.removeWounds)
        end
        for kind, on in pairs(r.infect) do
            st.infection[kind] = on
        end
        if r.hp then
            st.hp = math.min(100, st.hp + r.hp)
            setElementHealth(patient, math.max(1, st.hp))
        end
        st.dirty = true
        if r.drug then
            M.applyDrug(patient, st, r.drug)
        end
        if r.wake then
            ctx.wake(patient)
        end
        for _, text in ipairs(r.messages) do
            if text:find("^Reduced bleedrate") then
                outputChatBox(text, healer, 255, 255, 0)
            elseif text:find("infected") then
                notice(patient, text, 5000)
            else
                notice(healer, text, 5000)
            end
        end
        ctx.sendStats(patient, true)
        return { used = true, consume = r.consume, data = r.data }
    end

    return M
end
