-- Treatment, infection and drugs (#94; upstream itemtype/medical.pwn, item/pills.pwn, item/injector.pwn,
-- char/infection.pwn, char/drugs.pwn, char/drugfx.pwn). Pure: the character resource owns the state, items runs the
-- hold actions and calls treat() at the end of one.
local M = {}

M.HEAL_MS = 4000 -- HEAL_PROGRESS_MAX
M.REVIVE_MS = 6000 -- REVIVE_PROGRESS_MAX, on a knocked-out patient
M.PILL_MS = 1000
M.INJECT_MS = 1000
M.DRUG_MS = 300000 -- every DefineDrugType in init.pwn
M.DRUGS = { "Antibiotic", "Painkill", "Lsd", "Air", "Morphine", "Adrenaline", "Heroin" }
M.BAG_DRUGS = { "Antibiotic", "Painkill", "Morphine", "Adrenaline" } -- a looted Doctor's Bag's drug
M.PILLS = { "Antibiotics", "Painkiller", "LSD" } -- PILL_TYPE_* 0..2
M.INJECTIONS = { "Morphine", "Adrenaline", "Heroin" } -- INJECT_TYPE_* 1..3, "Empty" is 0
M.INJECTION_DRUG = { Empty = "Air", Morphine = "Morphine", Adrenaline = "Adrenaline", Heroin = "Heroin" }
M.HEALING = { Bandage = true, Medkit = true, DoctorBag = true, AntiSepBandage = true }

-- The hold an item starts (nil: not a treatment) and the skill that shortens it.
function M.holdFor(uname, patientKnockedOut)
    if M.HEALING[uname] then
        return patientKnockedOut and M.REVIVE_MS or M.HEAL_MS, "Medical"
    end
    if uname == "Pills" then
        return M.PILL_MS
    end
    if uname == "AutoInjec" then
        return M.INJECT_MS
    end
end

-- Pills only treat yourself; the others reach a player next to you.
function M.canTreatOthers(uname)
    return uname ~= "Pills"
end

-- Every bandage and the medkit: b -= b x (1.0091 - b)^2.1, nothing under 0.00001.
function M.reduceBleed(b)
    b = tonumber(b) or 0
    if b <= 0 then
        return 0
    end
    b = b - b * (1.0091 - b) ^ 2.1
    return b < 0.00001 and 0 or b
end

-- Loot data for the three items that carry one (upstream OnItemCreate when GetItemLootIndex != -1); rng(a, b) is
-- math.random. Returns the JSON text or nil.
function M.lootData(uname, rng)
    if uname == "DoctorBag" then
        return string.format('{"charges":%d,"drug":"%s"}', rng(1, 3), M.BAG_DRUGS[rng(1, #M.BAG_DRUGS)])
    end
    if uname == "Pills" then
        return string.format('{"pill":"%s"}', M.PILLS[rng(1, #M.PILLS)])
    end
    if uname == "AutoInjec" then
        return string.format('{"inject":"%s"}', M.INJECTIONS[rng(1, #M.INJECTIONS)])
    end
end

-- What an item without loot data holds (crafted, staff-given): upstream's zeroed array data.
function M.pill(data)
    local p = type(data) == "table" and data.pill
    return (p == "Painkiller" or p == "LSD") and p or "Antibiotics"
end

function M.injection(data)
    local i = type(data) == "table" and data.inject
    return M.INJECTION_DRUG[i] and i or "Empty"
end

-- The name extra upstream's OnItemNameRender shows: "Pills (LSD)", "Doctor's Bag (2/3, Morphine)".
function M.label(uname, name, data)
    if uname == "Pills" then
        return string.format("%s (%s)", name, M.pill(data))
    end
    if uname == "AutoInjec" then
        return string.format("%s (%s)", name, M.injection(data))
    end
    if uname == "DoctorBag" and type(data) == "table" and (tonumber(data.charges) or 0) > 0 then
        return string.format("%s (%d/3, %s)", name, tonumber(data.charges), tostring(data.drug or "?"))
    end
    return name
end

-- The end of a treatment hold. patient = { bleed, wounds, infection = { food, wound }, knockedOut };
-- self = the healer treats themselves; rng() in [0,1) and rngInt(a, b) like math.random.
-- Returns { used, consume, data, bleed, removeWounds, infect = { food, wound } (booleans to set), drug, hp, wake,
-- messages } where used = false means nothing happened (the item stays as it is).
function M.treat(uname, data, patient, self, rng, rngInt)
    local r = { used = false, consume = false, infect = {}, messages = {} }
    local bleed = tonumber(patient.bleed) or 0

    local function cutBleed()
        if bleed > 0 then
            r.bleed = M.reduceBleed(bleed)
            r.messages[#r.messages + 1] = string.format("Reduced bleedrate from %f to %f", bleed, r.bleed)
            return true
        end
        return false
    end

    local function healWounds(n)
        r.removeWounds = n
        r.messages[#r.messages + 1] = string.format("Healed %d wounds", n)
    end

    if uname == "Bandage" then
        if cutBleed() then
            r.used, r.consume = true, true
            -- upstream infected the healer (SetPlayerInfectionIntensity(playerid, ...)): the port infects the patient
            if rng() < 0.33 then
                r.infect.wound = true
                r.messages[#r.messages + 1] = "Your wound has become infected!"
            end
        end
    elseif uname == "AntiSepBandage" then
        local cut = cutBleed()
        local cured = patient.infection and patient.infection.wound
        -- upstream cured the healer's wound infection and kept the bandage when nobody bled: the port cures the
        -- patient and spends the bandage on either effect
        if cured then
            r.infect.wound = false
        end
        r.used = cut or cured or false
        r.consume = r.used
    elseif uname == "Medkit" then
        cutBleed()
        healWounds(self and rngInt(1, 2) or rngInt(2, 3))
        r.used, r.consume = true, true
    elseif uname == "DoctorBag" then
        healWounds(self and rngInt(1, 2) or rngInt(3, 5))
        r.bleed = 0
        r.infect.wound = false
        local charges = type(data) == "table" and tonumber(data.charges) or 0
        local drug = type(data) == "table" and data.drug or nil
        r.drug = M.isDrug(drug) and drug or nil
        r.used = true
        if charges > 1 then
            r.data = { charges = charges - 1, drug = drug }
        else
            r.consume = true
        end
    elseif uname == "Pills" then
        local pill = M.pill(data)
        r.used, r.consume = true, true
        if pill == "Antibiotics" then
            r.infect.food = false
            if rng() < 0.5 then
                r.infect.wound = false
            end
            r.drug = "Antibiotic"
        elseif pill == "Painkiller" then
            r.hp = 10
            r.drug = "Painkill"
        else
            r.drug = "Lsd"
        end
    elseif uname == "AutoInjec" then
        local kind = M.injection(data)
        r.used = true
        r.drug = M.INJECTION_DRUG[kind]
        r.data = { inject = "Empty" }
        -- injector.pwn: adrenaline wakes a knocked-out player, but not yourself
        r.wake = kind == "Adrenaline" and not self and patient.knockedOut == true
    end
    return r
end

-- Drugs: { [name] = ms left }. Taking a drug again adds its duration (upstream wore it off after the base duration
-- from the first dose, ADR 0007); a loaded character keeps what was left.
function M.isDrug(name)
    for _, d in ipairs(M.DRUGS) do
        if d == name then
            return true
        end
    end
    return false
end

function M.applyDrug(drugs, name, ms)
    if not M.isDrug(name) then
        return false
    end
    drugs[name] = (drugs[name] or 0) + (tonumber(ms) or M.DRUG_MS)
    return true
end

-- Counts every active drug down by dtMs; returns the names that wore off, in M.DRUGS order.
function M.tickDrugs(drugs, dtMs)
    local off = {}
    for _, name in ipairs(M.DRUGS) do
        local left = drugs[name]
        if left then
            left = left - dtMs
            if left <= 0 then
                drugs[name] = nil
                off[#off + 1] = name
            else
                drugs[name] = left
            end
        end
    end
    return off
end

-- characters.drugs: [["Morphine",245000],...]; names are [%a] only.
function M.encodeDrugs(drugs)
    local parts = {}
    for _, name in ipairs(M.DRUGS) do
        if drugs[name] then
            parts[#parts + 1] = string.format('["%s",%d]', name, math.floor(drugs[name]))
        end
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

function M.decodeDrugs(list)
    local drugs = {}
    if type(list) ~= "table" then
        return drugs
    end
    for _, pair in ipairs(list) do
        local name, ms = type(pair) == "table" and pair[1], type(pair) == "table" and tonumber(pair[2])
        if M.isDrug(name) and ms and ms > 0 then
            drugs[name] = math.min(ms, M.DRUG_MS * 12)
        end
    end
    return drugs
end

-- characters.infection: bit 0 food, bit 1 wound.
function M.encodeInfection(inf)
    return (inf.food and 1 or 0) + (inf.wound and 2 or 0)
end

function M.decodeInfection(v)
    v = math.floor(tonumber(v) or 0)
    return { food = v % 2 == 1, wound = math.floor(v / 2) % 2 == 1 }
end

-- The camera shake infection.pwn drives through the drunk level: 5000 for a while, then off; it shakes again
-- after 500 x hp ms and settles after 100 x (120 - hp) ms. Morphine, Adrenaline and Air hold it off.
-- Returns the drunk level to set, or nil to leave it, given the current one and the ms since the last change.
function M.infectionShake(infection, drugs, hp, drunk, sinceMs)
    if not (infection.food or infection.wound) then
        return nil
    end
    if drugs.Morphine or drugs.Adrenaline or drugs.Air then
        return nil
    end
    if drunk == 0 then
        return sinceMs > 500 * hp and 5000 or nil
    end
    return sinceMs > 100 * (120 - hp) and 0 or nil
end

-- The drunk level drugs hold (drugfx.pwn, bleed.pwn), or nil when none does.
function M.drugDrunk(drugs)
    if drugs.Air then
        return 100000
    end
    if drugs.Morphine then
        return 2200
    end
end

-- The sky LSD and Heroin force (drugfx.pwn): { hour, minute, weather } or nil.
function M.drugSky(drugs)
    if drugs.Lsd then
        return { 22, 3, 33 }
    end
    if drugs.Heroin then
        return { 22, 30, 33 }
    end
end

-- brightness.pwn: Painkill and Adrenaline hide the low-HP darkness.
function M.hidesDarkness(drugs)
    return drugs.Painkill ~= nil or drugs.Adrenaline ~= nil
end

return M
