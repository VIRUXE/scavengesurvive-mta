-- The rotating chat tips (upstream server/info-message.pwn sent infomessage/messages every infomessage/interval
-- minutes): server/main.lua sends the next one every chat.tip_minutes (MINUTES when unset), client/help.lua shows it.
-- Plain words like the /help window (shared/logic/help.lua), one chat line each (under about 110 characters), true to
-- the wiki; {interact}, {putaway} and {dropitem} stand for the player's own keys (help.fill).
-- lang:begin
local TIPS = {
    "New here? Type /help: it explains the basics in a few minutes.",
    "You have one life. When you die, what you carry stays by your body and you start again with nothing.",
    "Wounds never heal on their own. A Medkit or a Doctor's Bag removes them.",
    "While you bleed, your health does not come back. Your inventory shows how fast you bleed.",
    "Dirty Bandages can infect a wound. Antiseptic Bandages never do.",
    "Antibiotic Pills cure a food infection. An Antiseptic Bandage or a Doctor's Bag cures an infected wound.",
    "Raw meat and raw fish make you sick. Cook them on a Campfire (60 s) or a Barbecue (30 s).",
    "Salty snacks make you thirsty, and sea water makes you thirstier. Never drink it.",
    "Make a Campfire from 3 Wood Logs and light it with a Lighter. It burns 10 minutes, 2 in the rain.",
    "Hold {interact} on a bag or a box to pick it up with everything inside. A tap opens it.",
    "Next to a player, press {dropitem} to give them what you hold.",
    "With empty hands, press {putaway} to take your gun out of the holster.",
    "Your pockets have 6 slots. A bag adds 7 (Small Bag) to 19 (Travel Rucksack). Find one first!",
    "Crates, wheels and panels need both hands. They never fit in a bag.",
    "Type /recipes to see every recipe and the tool each one needs.",
    "Build defences with a Hammer. Only a Crowbar takes them down, and only from the inside.",
    "Fit a Motor to a defence, then a Keypad. Do not keep the code 0000!",
    "A car starts only with fuel, a battery at 10% or more and over 300 health.",
    "In a car, hold {putaway} to start the engine. A tap only turns the key.",
    "Turn the lights off ({dropitem}) when you park: with the engine off they drain the battery 12% an hour.",
    "Fill a Petrol Can (20 L) at a pump. Each pour puts up to 10 L in the car.",
    "A car moved from where it was found and unused for 3 days disappears, trunk and all. Use it to keep it.",
    "/lock does not stop a parked car from disappearing. A custom lock does: a Locksmith Kit or a Lock and Chain.",
    "Loot never appears within 150 m of a player. A searched spot fills again after 3 to 9 hours.",
    "Supply drops are announced in chat, with where they land. Get there first!",
    "Leaving the game within 30 seconds of being hurt by a player kills your character.",
    "Sprint + crouch raises your hands. /dropall drops everything you carry and gives up.",
    "/l talks to players near you, /g to everyone, /r to your radio. /quiet hides global chat.",
    "Tune your radio with /freq (87.5 to 108.0). Players on the same frequency hear you on /r.",
    "Change your language any time with /lang. Other players' chat is translated for you too.",
    "Someone breaking the rules? /report <name> tells the staff. Found a bug? Type /bug.",
    "Don't want these tips? /tooltips turns them off, and on again.",
}
-- lang:end

return { MINUTES = 5, TIPS = TIPS }
