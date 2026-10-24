std = "lua51"
max_line_length = 120
codes = true
exclude_files = { ".lua/**", "resources/**/data/generated/**", "resources/**/attachedit/attachedit-out.lua" }
files["resources/**/server/**"] = { std = "lua51+mta_shared+mta_server" }
files["resources/**/client/**"] = { std = "lua51+mta_shared+mta_client" }
files["resources/**/shared/**"] = { std = "lua51+mta_shared" }
files["resources/**/modules/**"] = { std = "lua51+mta_shared+mta_server" }
files["tests/lua/**"] = { std = "lua51+busted" }
stds.mta_shared = dofile(".luacheck/mta_shared.lua")
stds.mta_server = dofile(".luacheck/mta_server.lua")
stds.mta_client = dofile(".luacheck/mta_client.lua")
files["resources/**/lib/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getModule" } }
files["resources/**/data/**"] = { std = "lua51+mta_shared", globals = { "itemType", "itemTypes", "lootTable", "calibreBleed", "calibreName", "ammoTypesForCalibre", "vehicleType", "vehicleTypes", "t", "languages" } }
files["resources/**/ui/**"] = { std = "lua51+mta_shared+mta_client", globals = { "actionTextShow", "actionTextHide", "toast", "progressStart", "progressCancel", "listOpen", "listUpdate", "listClose", "listIsOpen", "dialogOpen", "dialogSetBody", "dialogSetButtons", "dialogClose", "dialogIsOpen" }, read_globals = { "guiGetInputMode" } }
-- getTime/getVehicleEngineState/getVehicleName/getVehicleOccupant postdate the generated .luacheck/mta_client.lua list
files["resources/**/hud/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "setHidden" }, read_globals = { "getTime", "getVehicleEngineState", "getVehicleName", "getVehicleOccupant" } }
files["resources/**/auth/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "prompt", "getAccountId", "getAdminLevel", "getLanguage", "isAuthenticated", "setSessionAdminLevel", "setWhitelistEnabled", "isWhitelistEnabled" } }
files["resources/**/character/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getCharacterId", "getPlayerByCharacterId", "getInventoryContainerId", "getStats", "modifyStat", "killCharacter", "applyWound", "knockOutPlayer", "wakeUpPlayer", "isKnockedOut", "setPlayerCuffed", "isPlayerCuffed" } }
files["resources/**/items/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getHeld", "setHeld", "clearHeld", "openTrunkContainer", "closeTrunk", "openWorldContainer", "openSupplyContainer", "closeContainer", "updateHeldData", "createStartingItems", "refreshPlayer", "destroyItem", "destroyWorldItem", "destroyContainerItem", "resendWorldItem", "isFemaleSkin", "rollSpawnSkin" } }
files["resources/**/models/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "resolve", "hatlessSkin" } }
-- restoreWorldModel postdates the generated .luacheck/mta_client.lua list
files["resources/**/maps/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getZoneAt", "getPlayerZone" } }
files["resources/**/maps/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "getMapStats" }, read_globals = { "restoreWorldModel" } }
files["resources/**/maps/data/**"] = { std = "lua51", max_line_length = false }
-- moveObject, createBlipAttachedTo (server) and createEffect (client) postdate the generated lists
files["resources/**/loot/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rollNear", "dropSupply", "dropWeaponCache", "supplyDropTypes", "dropStatus", "lootAllowances" }, read_globals = { "moveObject", "createBlipAttachedTo" } }
files["resources/**/loot/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "nearbyCrate", "tryOpenCrate" }, read_globals = { "createEffect" } }
files["resources/**/world/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getWeather", "setGlobalWeather" } }
files["resources/**/world/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "tryInteract", "nearbyFeature" }, read_globals = { "dxDrawLine3D", "getBoundKeys" } }
files["resources/**/world/data/**"] = { std = "lua51", max_line_length = false }
-- removePedFromVehicle, dxDrawPrimitive3D and the clock/weather getters and setters postdate the generated lists
files["resources/**/dev/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rcon" }, read_globals = { "removePedFromVehicle", "removeElementData" } }
files["resources/**/dev/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "executeCommandHandler", "dxDrawPrimitive3D", "getTime", "setTime", "getWeather", "setWeather", "getMinuteDuration", "setMinuteDuration", "createLight", "showChat", "isChatVisible" } }
-- dxDrawModel3D, engineStreamingReleaseModel, getWorldFromScreenPosition, getElementMatrix and the shader functions postdate the generated lists
files["resources/**/items/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "setAttachPreview", "getAttachConfig" }, read_globals = { "dxDrawModel3D", "engineStreamingReleaseModel", "getWorldFromScreenPosition", "getElementMatrix", "engineGetModelTextures", "dxCreateShader", "dxSetShaderValue", "engineApplyShaderToWorldTexture" } }
-- fileSetPos postdates the generated .luacheck/mta_shared.lua list
files["resources/**/attachedit/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rcon" }, read_globals = { "fileSetPos" } }
files["resources/**/vehicles/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getVehicleDbId", "countVehicles", "respawnAll", "getVehicleFuel", "setVehicleFuel", "getVehicleLockState", "setVehicleLockState", "getVehicleKeyCode", "setVehicleKeyCode", "getVehicleContainerId" }, read_globals = { "attachTrailerToVehicle", "detachTrailerFromVehicle", "getVehicleEngineState", "getVehicleController", "setVehicleDoorOpenRatio", "getVehicleOverrideLights", "setVehicleOverrideLights", "getVehicleTowedByVehicle", "getVehicleTowingVehicle" } }
files["resources/**/building/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "isInsideAnyPlotPole", "interactDefence", "submitPasscode", "installKeypad" } }
files["resources/**/building/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "playSoundFrontEnd" } }
files["resources/**/crafting/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "groundCraft", "deconstruct", "workbenchCraft" } }
-- clearChatBox postdates the generated .luacheck/mta_server.lua list
files["resources/**/staff/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getLevel", "isOnDuty", "isMuted", "logAction", "mutePlayer", "getLevelColour", "runCommand" }, read_globals = { "clearChatBox" } }
files["resources/**/chat/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getRadio", "setChatMode", "sendAs" } }
