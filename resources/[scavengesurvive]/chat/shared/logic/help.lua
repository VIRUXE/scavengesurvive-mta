-- The /help window's content (client/help.lua draws it): short topics in plain words for a player who has never
-- played a survival game. Upstream's /help was only the GENCOMDHELP command list (core/player/commands.pwn) and
-- its crafting help sat behind /recipes (core/player/recipes.pwn Dialog_ShowCraftHelp); the port gathers the basics
-- in one place. {interact}, {putaway}, {dropitem}, {inventory}, {reloadweapon} and {chat} stand for the key the
-- player has bound to that command, so the text names the key they really press.
local help = {}

-- lang:begin
local T = {
    title = "Help",
    hint = "Type /help any time to open this window again.",
    back = "< Back",
    next = "Next >",
    close = "Close",
    key = "Key",
    action = "What it does",
    command = "Command",
    hold = "Hold %s",
    tipLabel = "TIP",
    warnLabel = "CAREFUL",

    startTitle = "Start here",
    startSteps = {
        "This is a survival game. You have one life.",
        "If you die, you lose everything you carry and start again with nothing.",
        "Find what you need to stay alive: food, a bag, tools and weapons.",
        "Search houses, yards, shops and cars. Items on the ground show a yellow name.",
        "Walk up to an item and press {interact} to pick it up.",
        "Top right of the screen: the red bar is your health, the green bar is your hunger.",
        "Other players can help you or kill you. Be careful who you trust.",
    },
    startTip = "Click the buttons on the left, or press Next, to read the rest. It only takes a minute.",

    keysTitle = "Keys",
    keyInteract = "Pick up, use, eat, open",
    keyInteractHold = "Pick up a bag or a box (a tap opens it)",
    keyPutaway = "Put away what you hold, wear a bag",
    keyDropitem = "Drop what you hold, or give it to the player next to you",
    keyInventory = "Open and close your inventory",
    keyReload = "Reload your gun",
    keyChat = "Talk in the chat",
    keyCarEngine = "In a car: hold it to start the engine",
    keyCarLights = "In a car: lights on and off",
    keyCarRadio = "In a car: radio",
    keysTip = "Not sure what a key does? Look at the yellow keys at the top right of the screen."
        .. " They show what each key does right now.",

    aliveTitle = "Stay alive",
    aliveSteps = {
        "When the green bar gets low, eat. Hold the food and press {interact}.",
        "If hunger drops below 20, you start to lose health.",
        "Raw meat and raw fish make you sick. Cook them on a campfire first.",
        "Hit by a gun or a knife? You are bleeding and lose health every second.",
        "To stop bleeding: hold a bandage and hold {interact} for 4 seconds.",
        "Press {inventory} to open your inventory. On the left it shows your wounds, bleeding and sickness.",
    },
    aliveWarn = "Bandage straight away. A small bleed is easy to stop. A big one kills you.",

    itemsTitle = "Items and bags",
    itemsSteps = {
        "You hold one item in your hands at a time.",
        "Press {putaway} to put it in your pockets. Your pockets have 6 slots.",
        "Big items take more slots. Very big items can only be carried in your hands.",
        "Find a bag! Hold it and press {putaway} to wear it. A bag carries a lot more.",
        "Press {inventory} to see everything you carry and wear.",
        "In the inventory, choose an item to see what you can do with it.",
        "Boxes and bags on the ground: tap {interact} to look inside, hold {interact} to pick them up.",
    },
    itemsTip = "Your first bag is the best thing you can find. Look for one first.",

    weaponsTitle = "Weapons",
    weaponsSteps = {
        "Each gun takes one kind of ammo.",
        "To load a gun: hold it, stand over its ammo on the ground and press {interact}.",
        "Press {reloadweapon} to reload. Hold {dropitem} to take the ammo out.",
        "Press {putaway} to put a gun in your holster. Press it again with empty hands to take it out.",
        "Knives, bats and other hand weapons need no ammo.",
    },
    weaponsWarn = "Shooting is loud. Other players hear it and come to look.",

    carsTitle = "Cars",
    carsSteps = {
        "Most cars you find are broken, low on fuel or locked.",
        "Get in with {interact}. Then hold {putaway} to start the engine.",
        "The engine needs fuel and a battery.",
        "No fuel? Fill a Petrol Can at a petrol station pump, then pour it in at the side of the car.",
        "Battery or engine: stand at the front with empty hands and press {interact} to open the bonnet.",
        "To repair: open the bonnet, hold a tool at the front and press {interact}."
            .. " Very broken cars need a Spanner first.",
        "At the back of a car, press {interact} to open the trunk. You can store items in it.",
        "Lock the doors from inside with /lock before you leave the car.",
    },
    carsWarn = "A car nobody uses for 3 days disappears, with everything in its trunk.",

    craftTitle = "Crafting",
    craftSteps = {
        "You can make new items out of items you have.",
        "Type /recipes to see every recipe.",
        "Combine: hold one item, open the inventory, choose the other item and pick Combine.",
        "Build on the ground: drop the parts, hold the tool and hold {interact} next to them.",
        "Workbench: put the parts inside the workbench, hold the tool and hold {interact} at it.",
    },
    craftTip = "Each recipe in /recipes says which tool you need.",

    deathTitle = "Death",
    deathSteps = {
        "At 0 health your character is dead for good.",
        "Everything you carried falls next to your body. Anyone can take it, even your killer.",
        "You start again on a beach with almost nothing.",
        "Leaving the game in the middle of a fight also kills you.",
    },
    deathTip = "Hide your best things in a tent or a locked car before you take risks.",

    talkTitle = "Chat and help",
    talkSteps = {
        "Press {chat} to talk.",
        "/l talks to players near you, /g to everyone, /r to your radio.",
        "Need a person to help you? /admins shows the staff.",
        "Someone cheating or breaking the rules? /report <name> tells the staff.",
        "Found a bug? /bug tells the developers.",
        "/rules shows the rules. Read them: breaking them gets you banned.",
    },
    talkTip = "Be nice to new players. Everyone was new once.",

    commandsTitle = "Commands",
    cmdRecipes = "every crafting recipe",
    cmdChatModes = "talk nearby, to everyone, or on the radio",
    cmdReport = "report a player to the staff",
    cmdBug = "report a bug",
    cmdLang = "change your language",
    cmdLock = "lock or unlock the car you sit in",
    cmdRadio = "open the radio",
}
-- lang:end

help.T = T

-- the topics in reading order; kind "steps" is a numbered list, "keys" and "commands" are tables
help.TOPICS = {
    { id = "start", title = T.startTitle, steps = T.startSteps, tip = T.startTip },
    { id = "keys", title = T.keysTitle, kind = "keys", tip = T.keysTip },
    { id = "alive", title = T.aliveTitle, steps = T.aliveSteps, warn = T.aliveWarn },
    { id = "items", title = T.itemsTitle, steps = T.itemsSteps, tip = T.itemsTip },
    { id = "weapons", title = T.weaponsTitle, steps = T.weaponsSteps, warn = T.weaponsWarn },
    { id = "cars", title = T.carsTitle, steps = T.carsSteps, warn = T.carsWarn },
    { id = "craft", title = T.craftTitle, steps = T.craftSteps, tip = T.craftTip },
    { id = "death", title = T.deathTitle, steps = T.deathSteps, tip = T.deathTip },
    { id = "talk", title = T.talkTitle, steps = T.talkSteps, tip = T.talkTip },
    { id = "commands", title = T.commandsTitle, kind = "commands" },
}

-- { command, text, hold } rows of the Keys table; hold = the row is "Hold <key>"
help.KEY_ROWS = {
    { "interact", T.keyInteract },
    { "interact", T.keyInteractHold, hold = true },
    { "putaway", T.keyPutaway },
    { "dropitem", T.keyDropitem },
    { "inventory", T.keyInventory },
    { "reloadweapon", T.keyReload },
    { "chat", T.keyChat },
    { "putaway", T.keyCarEngine, hold = true },
    { "dropitem", T.keyCarLights },
    { "radio", T.keyCarRadio },
}

-- the port's commands upstream's GENCOMDHELP list does not name
help.EXTRA_COMMANDS = {
    { "/recipes", T.cmdRecipes },
    { "/l  /g  /r", T.cmdChatModes },
    { "/report <name>", T.cmdReport },
    { "/bug", T.cmdBug },
    { "/lang <code>", T.cmdLang },
    { "/lock", T.cmdLock },
    { "/radio", T.cmdRadio },
}

local function identity(s)
    return s
end

-- "[F]" for a command's key; keyOf(command) gives the bound key name or nil
local function keyLabel(command, keyOf)
    local key = keyOf(command)
    return "[" .. string.upper(tostring(key or "?")) .. "]"
end

-- a text with its {command} tokens replaced by the keys bound to them
function help.fill(text, keyOf)
    return (tostring(text):gsub("{(%w+)}", function(command)
        return keyLabel(command, keyOf)
    end))
end

-- the Keys table: { { "[F]", "Pick up, use, eat, open" }, ... } with texts through tr
function help.keyRows(keyOf, tr)
    tr = tr or identity
    local rows = {}
    for _, row in ipairs(help.KEY_ROWS) do
        local key = keyLabel(row[1], keyOf)
        if row.hold then
            key = string.format(tr(T.hold), key)
        end
        rows[#rows + 1] = { key, help.fill(tr(row[2]), keyOf) }
    end
    return rows
end

-- the Commands table: upstream's GENCOMDHELP rows (chat.helpWindow) and then the port's own, all in one colour
-- per row; rows = { { "/cmd", "description", colour = "#RRGGBB" } }
function help.commandRows(upstreamRows, tr)
    tr = tr or identity
    local rows = {}
    for _, row in ipairs(upstreamRows or {}) do
        rows[#rows + 1] = row
    end
    for _, row in ipairs(help.EXTRA_COMMANDS) do
        rows[#rows + 1] = { row[1], tr(row[2]), colour = "#FFFFFF" }
    end
    return rows
end

return help
