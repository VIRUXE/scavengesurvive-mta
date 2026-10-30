local spawn = dofile("resources/[scavengesurvive]/vehicles/shared/logic/spawn.lua")
local function rng(values)
    local i = 0
    return function()
        i = i + 1
        return values[((i - 1) % #values) + 1]
    end
end
local TYPES = spawn.index({
    { uname = "Bobcat", model = 422, group = "Civilian", category = "truck", size = "medium", spawnChance = 76.0, maxFuel = 60.0 },
    { uname = "Sabre", model = 475, group = "Civilian", category = "car", size = "medium", spawnChance = 17.0, maxFuel = 60.0 },
    { uname = "MountBike", model = 510, group = "Civilian", category = "pushbike", size = "small", spawnChance = 8.0, maxFuel = 0.0 },
    { uname = "Rhino", model = 432, group = "Military", category = "truck", size = "large", spawnChance = 0.01, maxFuel = 1900.0 },
})
local function row(o)
    local r = { rz = 90, group_name = "Civilian", type_name = false, categories = "CT", sizes = "SM" }
    for k, v in pairs(o) do
        r[k] = v
    end
    return r
end

describe("vehicle spawn roll", function()
    it("spawns a point only when the per-point chance hits (4 % default)", function()
        -- first roll: rng*100 < 96 skips
        assert.is_nil(spawn.roll(row({}), TYPES, nil, rng({ 0.5 })))
        local r = spawn.roll(row({}), TYPES, 4.0, rng({ 0.97, 0.9, 0.1, 0.1, 0.1, 0.1 }))
        assert.is_not_nil(r)
        assert.is_nil(spawn.roll(row({}), TYPES, 100.0, rng({ 0.999, 0.9, 0.99 }))) -- 100 % never skips, candidates fail
    end)
    it("flips the heading by 180 half of the time and wraps", function()
        -- rolls: point 0.97 (hit), flip 0.4 (+180), candidate rolls 0.1, pick 0
        assert.equals(270, spawn.roll(row({ rz = 90 }), TYPES, nil, rng({ 0.97, 0.4, 0.1, 0.1, 0.1, 0 })).rz)
        assert.equals(90, spawn.roll(row({ rz = 90 }), TYPES, nil, rng({ 0.97, 0.6, 0.1, 0.1, 0.1, 0 })).rz)
        local wrapped = spawn.roll(row({ rz = 412.055419 }), TYPES, nil, rng({ 0.97, 0.6, 0.1, 0.1, 0.1, 0 })).rz
        assert.is_true(math.abs(wrapped - 52.055419) < 1e-6)
    end)
    it("filters group candidates by group, category letters, size letters and their own chance", function()
        local all = spawn.candidates(row({}), TYPES, rng({ 0 }))
        assert.same({ "Bobcat", "Sabre" }, { all[1].uname, all[2].uname }) -- MountBike is a pushbike, Rhino is Military
        assert.same({}, spawn.candidates(row({ categories = "H" }), TYPES, rng({ 0 })))
        assert.same({}, spawn.candidates(row({ sizes = "L" }), TYPES, rng({ 0 })))
        assert.equals(1, #spawn.candidates(row({ categories = "CTMB" }), TYPES, rng({ 0.5 }))) -- only Bobcat (76 %) beats 50
        assert.equals("Rhino", spawn.candidates(row({ group_name = "Military", categories = "T", sizes = "L" }), TYPES, rng({ 0 }))[1].uname)
    end)
    it("leaves the point empty when no candidate passes (upstream would spawn a Bobcat)", function()
        assert.is_nil(spawn.roll(row({ group_name = "Military", categories = "T", sizes = "L" }), TYPES, 100.0, rng({ 0.5 })))
    end)
    it("spawns an explicit type only through its own chance", function()
        local r = spawn.roll(row({ type_name = "Rhino" }), TYPES, 100.0, rng({ 0.5, 0.6, 0.00005 }))
        assert.equals("Rhino", r.type.uname)
        assert.is_nil(spawn.roll(row({ type_name = "Rhino" }), TYPES, 100.0, rng({ 0.5, 0.6, 0.5 })))
        assert.is_nil(spawn.roll(row({ type_name = "Coach" }), TYPES, 100.0, rng({ 0.5 })))
    end)
    it("hands out upstream's battered health and near-empty tanks", function()
        assert.equals(600, spawn.health(rng({ 0.005, 0.5 })))
        assert.equals(500, spawn.health(rng({ 0.03, 0.5 })))
        assert.equals(400, spawn.health(rng({ 0.5, 0.5 })))
        assert.equals(45, spawn.fuel(60, rng({ 0.005, 0.5 })))
        assert.equals(25, spawn.fuel(60, rng({ 0.03, 0.5 })))
        assert.equals(15, spawn.fuel(60, rng({ 0.08, 0.5 })))
        assert.equals(0.5, spawn.fuel(60, rng({ 0.5, 0.5 })))
    end)
    it("damages cars and trucks only, and locks a damaged-door vehicle on a coin flip", function()
        assert.is_nil(spawn.damage("boat", rng({ 0 })))
        assert.is_nil(spawn.damage("motorbike", rng({ 0 })))
        local d = spawn.damage("car", rng({ 0.99 }))
        assert.same({ 3, 3, 3, 3, 3, 3, 3 }, d.panels)
        assert.same({ 4, 4, 4, 4 }, d.doors)
        assert.same({ 1, 1, 1, 1 }, d.lights)
        assert.same({ 1, 1, 1, 1 }, d.tires)
        assert.is_true(spawn.locked(TYPES.byUname.Sabre, d, rng({ 0.2 })))
        assert.is_false(spawn.locked(TYPES.byUname.Sabre, d, rng({ 0.7 })))
        assert.is_false(spawn.locked(TYPES.byUname.Sabre, spawn.damage("car", rng({ 0 })), rng({ 0.2 }))) -- no door damage
        assert.is_false(spawn.locked(TYPES.byUname.MountBike, d, rng({ 0.2 }))) -- no tank: never locked
        assert.is_false(spawn.locked(TYPES.byUname.Sabre, nil, rng({ 0.2 })))
    end)
end)

describe("Area 69 aircraft spawns", function()
    local data = dofile("resources/[scavengesurvive]/data/generated/vehicle_types.lua")
    local list = {}
    for _, uname in ipairs(data.order) do
        list[#list + 1] = data.byUname[uname]
    end
    local real = spawn.index(list)

    it("rolls the Hunter and the Hydra from explicit spawn rows", function()
        local hunterRow = row({ type_name = "Hunter", group_name = false })
        local hydraRow = row({ type_name = "Hydra", group_name = false })
        local hunter = spawn.roll(hunterRow, real, 100.0, rng({ 0.5, 0.6, 0.005 }))
        local hydra = spawn.roll(hydraRow, real, 100.0, rng({ 0.5, 0.6, 0.005 }))
        assert.equals(425, hunter.type.model)
        assert.equals("helicopter", hunter.type.category)
        assert.equals(520, hydra.type.model)
        assert.equals("plane", hydra.type.category)
    end)
end)
