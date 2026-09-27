std = "lua51"
max_line_length = 120
codes = true
exclude_files = { ".lua/**", "resources/**/data/generated/**" }
files["resources/**/server/**"] = { std = "lua51+mta_shared+mta_server" }
files["resources/**/client/**"] = { std = "lua51+mta_shared+mta_client" }
files["resources/**/shared/**"] = { std = "lua51+mta_shared" }
files["resources/**/modules/**"] = { std = "lua51+mta_shared+mta_server" }
files["tests/lua/**"] = { std = "lua51+busted" }
stds.mta_shared = dofile(".luacheck/mta_shared.lua")
stds.mta_server = dofile(".luacheck/mta_server.lua")
stds.mta_client = dofile(".luacheck/mta_client.lua")
files["resources/**/lib/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getModule" } }
files["resources/**/data/**"] = { std = "lua51+mta_shared", globals = { "Data", "itemType", "itemTypes", "lootTable", "calibreBleed", "t" } }
files["resources/**/ui/**"] = { std = "lua51+mta_shared+mta_client", globals = { "UI", "toast", "progressStart", "progressCancel", "listOpen", "listUpdate", "listClose", "listIsOpen" } }
files["resources/**/auth/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "prompt", "getAccountId", "getAdminLevel", "getLanguage", "isAuthenticated" } }
files["resources/**/character/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "Character", "getCharacterId", "getPlayerByCharacterId", "getInventoryContainerId", "getStats", "modifyStat", "killCharacter", "applyWound" } }
files["resources/**/items/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "Items", "getHeld", "createStartingItems", "refreshPlayer", "destroyItem" } }
files["resources/**/items/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "Held" } }
files["resources/**/loot/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rollNear" } }
