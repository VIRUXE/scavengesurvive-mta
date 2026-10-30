-- Machines (upstream core/itemtype/machine.pwn with item/scrap-machine.pwn, refine-machine.pwn and
-- water-purifier.pwn): three constructed items, each with a 12-slot container and a fuel tank filled from a Petrol
-- Can. A cook runs 90 s per item plus up to 30 s, burns 3.5 fuel per item and turns the contents into Scrap Metal
-- (by the scrap value of each item, anything else destroyed), Refined Metal (one per Scrap Metal) or Water (every
-- bottle of sea water, its amount kept). State is the machine's item data: { machine = { fuel, cooking = { at, ms } } }
-- with at the cook's unix start and ms its length. Pure: no MTA calls at file scope.
local M = {}

M.TYPES = { ScrapMachine = "scrap", RefineMachine = "refine", WaterMachine = "water" }
M.CONTAINER_SIZE = 12 -- DefineMachineType(..., 12)
M.MAX_FUEL = 100.0 -- MAX_MACHINE_FUEL
M.FUEL_PER_ITEM = 3.5 -- MACHINE_FUEL_USAGE
M.MAX_ITEMS = 12 -- MAX_MACHINE_ITEMS: the scrap machine yields at most MAX_ITEMS - 1
M.COOK_S_PER_ITEM = 90 -- machine.pwn _machine_StartCooking: (itemcount * 90) + random(30)
M.COOK_JITTER_S = 30
M.REFUEL_STEP = 1.1 -- machine.pwn OnHoldActionUpdate: 1.1 a tick from the can into the tank
M.REFUEL_TICK_MS = 100
M.REFUEL_REACH = 4.0 -- the hold ends when the player walks off (the side container's own limit)
M.RESULTS = { scrap = "ScrapMetal", refine = "RefinedMetal", water = "Bottle" }
M.ACCEPTS = { refine = "Scrap Metal", water = "Water Bottle (Sea Water)" } -- MACHITEMTYP
M.PETROL = "Petrol"
M.SMOKE_EFFECT = "smoke30lit" -- the port's stand-in for SA-MP's smoke object 18726 (to pick on screen)

-- init.pwn:905-1004 SetItemTypeScrapValue
M.SCRAP = {
    Knuckles = 1,
    GolfClub = 2,
    Knife = 1,
    Spade = 2,
    Sword = 3,
    Chainsaw = 5,
    Extinguisher = 4,
    Camera = 1,
    HardDrive = 1,
    Key = 1,
    FireLighter = 1,
    Timer = 1,
    Battery = 1,
    Fusebox = 1,
    Armour = 3,
    FishRod = 1,
    Wrench = 1,
    Crowbar = 1,
    Hammer = 1,
    Flashlight = 1,
    StunGun = 1,
    LaserPoint = 1,
    Screwdriver = 1,
    MobilePhone = 1,
    Pager = 1,
    Rake = 1,
    HandCuffs = 1,
    Bucket = 2,
    GasMask = 1,
    MotionSense = 1,
    Accelerometer = 1,
    GasCan = 2,
    Capsule = 2,
    RadioPole = 2,
    SignShot = 2,
    Mailbox = 2,
    Barbecue = 6,
    Headlight = 1,
    MetPanel = 3,
    MetalGate = 4,
    CrateDoor = 4,
    CorPanel = 9,
    ShipDoor = 12,
    SmallPanel = 4,
    Keypad = 1,
    Ammo9mm = 1,
    Ammo50 = 1,
    AmmoBuck = 1,
    Ammo556 = 1,
    Ammo357 = 1,
    AmmoRocket = 1,
    PowerSupply = 1,
    StorageUnit = 1,
    Fluctuator = 1,
    IoUnit = 1,
    FluxCap = 1,
    DataInterface = 1,
    HackDevice = 1,
    HerpDerp = 1,
    Gyroscope = 1,
    Motor = 1,
    StarterMotor = 1,
    FlareGun = 1,
    LocksmithKit = 2,
    AdvancedKeypad = 1,
    Ammo9mmFMJ = 1,
    AmmoFlechette = 1,
    AmmoHomeBuck = 1,
    Ammo556Tracer = 1,
    Ammo556HP = 1,
    Ammo357Tracer = 1,
    Ammo762 = 1,
    Ammo50BMG = 1,
    Ammo308 = 1,
    Sledgehammer = 1,
    Spanner = 1,
    OilCan = 2,
    BigSword = 1,
    Spatula = 1,
    Pan = 1,
    Knife2 = 1,
    FryingPan = 1,
    WheelLock = 1,
    RedPanel = 2,
    Fork = 1,
    Knife3 = 1,
    Padlock = 1,
    OilDrum = 8,
    Canister = 3,
    Locator = 1,
    Radio = 1,
    Locker = 12,
    GearBox = 5,
    ToolBox = 8,
    MetalFrame = 16,
    LockBreaker = 1,
    ControlBox = 2,
    Computer = 2,
    TallFrame = 8,
    RemoteControl = 1,
}

function M.kind(uname)
    return M.TYPES[uname]
end

function M.isMachine(uname)
    return M.TYPES[uname] ~= nil
end

local function unwrap(data)
    if type(data) ~= "table" then
        return {}
    end
    if type(data[1]) == "table" then
        return data[1]
    end
    return data
end

-- { fuel, cooking = { at, ms } | nil } from the item data (either JSON shape)
function M.state(data)
    local m = unwrap(data).machine
    m = type(m) == "table" and m or {}
    local st = { fuel = math.max(0, tonumber(m.fuel) or 0), cooking = nil }
    local c = type(m.cooking) == "table" and m.cooking or nil
    if c and tonumber(c.at) and tonumber(c.ms) then
        st.cooking = { at = tonumber(c.at), ms = tonumber(c.ms) }
    end
    return st
end

-- the item data with the machine state written into it (the other keys kept)
function M.encode(data, st)
    local d = unwrap(data)
    local out = {}
    for k, v in pairs(d) do
        out[k] = v
    end
    out.machine = { fuel = st.fuel }
    if st.cooking then
        out.machine.cooking = { at = st.cooking.at, ms = st.cooking.ms }
    end
    return out
end

-- OnItemAddToContainer: true, or false and the name of what the machine takes
function M.accepts(kind, t, data, liquids)
    if kind == "refine" then
        return (t and t.uname == "ScrapMetal") and true or false, M.ACCEPTS.refine
    elseif kind == "water" then
        if t and t.uname == "Bottle" then
            local amount, liquid = liquids.decode(t, data)
            if liquid == "SeaWater" and amount > 0 then
                return true
            end
        end
        return false, M.ACCEPTS.water
    end
    return true
end

-- a can of petrol in hand: the amount it holds, or nil
function M.petrolIn(t, data, liquids)
    if not liquids.isContainer(t) then
        return nil
    end
    local amount, liquid = liquids.decode(t, data)
    if liquid ~= M.PETROL or amount <= 0 then
        return nil
    end
    return amount
end

-- one refuel tick: the tank and the can after up to REFUEL_STEP moved, and whether the hold is over (tank full
-- or can empty)
function M.refuelStep(fuel, canAmount)
    local move = math.min(M.REFUEL_STEP, canAmount, M.MAX_FUEL - fuel)
    if move <= 0 then
        return fuel, canAmount, true
    end
    fuel, canAmount = fuel + move, canAmount - move
    return fuel, canAmount, fuel >= M.MAX_FUEL or canAmount <= 0
end

-- the hold's full length: upstream StartHoldAction(MAX_FUEL * 100, fuel * 100)
function M.refuelMs(fuel)
    return math.max(0, math.floor((M.MAX_FUEL - fuel) * 100 + 0.5))
end

-- starting a cook (_machine_StartCooking): true and the next state, or false and the reason
function M.start(st, itemCount, now, rnd)
    if st.cooking then
        return false, "MACHPROCESS"
    end
    if itemCount <= 0 then
        return false, "MACHNOITEMS"
    end
    if st.fuel < M.FUEL_PER_ITEM * itemCount then
        return false, "MACHNOTFUEL"
    end
    local ms = (itemCount * M.COOK_S_PER_ITEM + math.floor((rnd or math.random)() * M.COOK_JITTER_S)) * 1000
    return true, { fuel = st.fuel, cooking = { at = now, ms = ms } }
end

function M.remainingMs(st, now)
    if not st.cooking then
        return 0
    end
    return math.max(0, st.cooking.at * 1000 + st.cooking.ms - now * 1000)
end

-- MsToString(ms, "%m minutes %s seconds")
function M.timeText(ms)
    local s = math.floor(math.max(0, ms) / 1000)
    return string.format("%d minutes %d seconds", math.floor(s / 60), s % 60)
end

-- the cook done (OnMachineFinish): the next state and the rows that replace the container's items, each
-- { uname, data | nil }. items = { { uname, data }, ... } as they lie in the container. liquids and itemType serve
-- the water purifier.
function M.finish(kind, st, items, liquids, itemType)
    local nextSt = { fuel = math.max(0, st.fuel - M.FUEL_PER_ITEM * #items), cooking = nil }
    local out = {}
    if kind == "scrap" then
        local n = 0
        for _, it in ipairs(items) do
            n = n + (M.SCRAP[it.uname] or 0) -- upstream added -1 for a type without a value; the port adds nothing
        end
        for i = 1, math.min(n, M.MAX_ITEMS - 1) do
            out[i] = { uname = M.RESULTS.scrap }
        end
    elseif kind == "refine" then
        for i = 1, #items do -- one for one (upstream's loop counted every item twice)
            out[i] = { uname = M.RESULTS.refine }
        end
    else
        for i, it in ipairs(items) do
            local amount = liquids.decode(itemType(it.uname), it.data)
            out[i] = { uname = M.RESULTS.water, data = { amount = amount, liquid = "Water" } }
        end
    end
    return nextSt, out
end

-- the messages the port shows in English (upstream language lines, formatted server-side)
M.TEXT = {
    MACHPROCESS = "The machine is currently processing\n%s left",
    MACHNOITEMS = "There are no items inside.",
    MACHNOTFUEL = "There is not enough fuel. Machine requires %.1f per item.",
    MACHCOOKTIM = "Cook time: %s",
    MACHITEMTYP = "This machine only accepts %s",
    REFUELLING = "Refuelling...",
}

-- the Start dialog's body (machine.pwn _mach_HoldInteract)
function M.menuBody(kind, fuel)
    local what
    if kind == "scrap" then
        what = "convert certain types of items into scrap.\n"
            .. "Items that cannot be turned into scrap metal will be destroyed."
    elseif kind == "refine" then
        what = "refine scrap metal.\nEach piece of scrap metal becomes refined metal."
    else
        what = "purify sea water.\nEach bottle of sea water becomes a bottle of water."
    end
    return string.format("Press 'Start' to activate the machine and %s\n\nFuel amount: %.1f", what, fuel)
end

return M
