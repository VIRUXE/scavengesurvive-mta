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
files["resources/**/data/**"] = { std = "lua51+mta_shared", globals = { "itemType", "itemTypes", "lootTable", "calibreBleed", "calibreName", "ammoTypesForCalibre", "vehicleType", "vehicleTypes", "t" } }
files["resources/**/ui/**"] = { std = "lua51+mta_shared+mta_client", globals = { "actionTextShow", "actionTextHide", "toast", "progressStart", "progressCancel", "listOpen", "listUpdate", "listClose", "listIsOpen" } }
-- getTime/getVehicleEngineState/getVehicleName/getVehicleOccupant postdate the generated .luacheck/mta_client.lua list
files["resources/**/hud/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "getTime", "getVehicleEngineState", "getVehicleName", "getVehicleOccupant" } }
files["resources/**/auth/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "prompt", "getAccountId", "getAdminLevel", "getLanguage", "isAuthenticated" } }
files["resources/**/character/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getCharacterId", "getPlayerByCharacterId", "getInventoryContainerId", "getStats", "modifyStat", "killCharacter", "applyWound", "knockOutPlayer", "wakeUpPlayer", "isKnockedOut", "setPlayerCuffed", "isPlayerCuffed" } }
files["resources/**/items/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getHeld", "setHeld", "clearHeld", "openTrunkContainer", "closeTrunk", "openWorldContainer", "closeContainer", "updateHeldData", "createStartingItems", "refreshPlayer", "destroyItem", "destroyWorldItem", "destroyContainerItem" } }
files["resources/**/models/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "resolve" } }
-- restoreWorldModel postdates the generated .luacheck/mta_client.lua list
files["resources/**/maps/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getZoneAt", "getPlayerZone" } }
files["resources/**/maps/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "getMapStats" }, read_globals = { "restoreWorldModel" } }
files["resources/**/maps/data/**"] = { std = "lua51", max_line_length = false }
files["resources/**/loot/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rollNear" } }
files["resources/**/world/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getWeather", "setGlobalWeather" } }
files["resources/**/dev/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rcon" } }
files["resources/**/dev/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "executeCommandHandler" } }
files["resources/**/vehicles/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getVehicleDbId", "countVehicles", "respawnAll", "getVehicleFuel", "setVehicleFuel", "getVehicleLockState", "setVehicleLockState", "getVehicleKeyCode", "setVehicleKeyCode", "getVehicleContainerId" }, read_globals = { "attachTrailerToVehicle", "detachTrailerFromVehicle", "getVehicleEngineState", "getVehicleController", "setVehicleDoorOpenRatio", "getVehicleOverrideLights", "setVehicleOverrideLights", "getVehicleTowedByVehicle", "getVehicleTowingVehicle" } }
files["resources/**/building/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "isInsideAnyPlotPole", "interactDefence", "submitPasscode", "installKeypad" } }
files["resources/**/building/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "playSoundFrontEnd" } }
files["resources/**/crafting/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "groundCraft", "deconstruct", "workbenchCraft" } }
