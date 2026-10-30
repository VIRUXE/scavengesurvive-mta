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
files["resources/**/lib/shared/**"] = { std = "lua51+mta_shared", globals = { "getModule" } }
files["resources/**/lib/modules/surface.lua"] = { std = "lua51+mta_shared+mta_client" }
files["resources/**/data/**"] = { std = "lua51+mta_shared", globals = { "itemType", "itemTypes", "lootTable", "calibreBleed", "calibreName", "ammoTypesForCalibre", "vehicleType", "vehicleTypes", "t", "languages" } }
files["resources/**/ui/**"] = { std = "lua51+mta_shared+mta_client", globals = { "actionTextShow", "actionTextHide", "toast", "progressStart", "progressCancel", "listOpen", "listUpdate", "listClose", "listIsOpen", "dialogOpen", "dialogSetBody", "dialogSetButtons", "dialogClose", "dialogIsOpen", "tipShow", "tipHide" }, read_globals = { "guiGetInputMode" } }
files["resources/**/ui/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "showTip", "hideTip" } }
-- getTime/getVehicleEngineState/getVehicleName/getVehicleOccupant postdate the generated .luacheck/mta_client.lua list
files["resources/**/hud/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "setHidden" }, read_globals = { "getTime", "getVehicleEngineState", "getVehicleName", "getVehicleOccupant" } }
files["resources/**/auth/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "prompt", "getAccountId", "getAccountName", "getAdminLevel", "getLanguage", "tooltipsOn", "isAuthenticated", "setSessionAdminLevel", "setWhitelistEnabled", "isWhitelistEnabled", "setWhitelistAuto", "isWhitelistAuto", "whitelistNameChanged" } }
files["resources/**/character/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getCharacterId", "getPlayerByCharacterId", "getInventoryContainerId", "getStats", "modifyStat", "killCharacter", "applyWound", "knockOutPlayer", "wakeUpPlayer", "isKnockedOut", "setPlayerCuffed", "isPlayerCuffed", "gainSkill", "setSkill", "getSkill", "skillTimeModifier", "treatPlayer", "treatmentHold", "medicalLootData", "setInfection", "applyDrug", "hasDrug" }, read_globals = { "getTime", "isElementInWater", "isPedDucked", "isPedOnGround" } }
files["resources/**/character/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "skillsOpen", "medicalLabel" }, read_globals = { "setCameraDrunkLevel", "setTime", "setWeather", "getPedMoveState", "fxAddBlood" } }
files["resources/**/items/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getHeld", "setHeld", "clearHeld", "openTrunkContainer", "closeTrunk", "openWorldContainer", "openSupplyContainer", "closeContainer", "updateHeldData", "createStartingItems", "refreshPlayer", "destroyItem", "destroyWorldItem", "destroyContainerItem", "forgetWorldItem", "dropHeld", "resendWorldItem", "sendInventory", "isFemaleSkin", "rollSpawnSkin", "meleeHit", "popHeadgear" }, read_globals = { "getWaterLevel" } }
files["resources/**/explosives/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "detonateItem", "checkTripMine", "linkPhoneBomb" }, read_globals = { "blowVehicle", "createExplosion" } }
files["resources/**/models/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "resolve", "hatlessSkin", "bareSkin" } }
-- restoreWorldModel postdates the generated .luacheck/mta_client.lua list
files["resources/**/maps/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getZoneAt", "getPlayerZone" } }
files["resources/**/maps/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "getMapStats" }, read_globals = { "restoreWorldModel" } }
files["resources/**/maps/data/**"] = { std = "lua51", max_line_length = false }
-- moveObject, createBlipAttachedTo (server) and createEffect (client) postdate the generated lists
files["resources/**/loot/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rollNear", "dropSupply", "dropWeaponCache", "supplyDropTypes", "dropStatus", "lootAllowances" }, read_globals = { "moveObject", "createBlipAttachedTo" } }
files["resources/**/loot/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "nearbyCrate", "tryOpenCrate" }, read_globals = { "createEffect" } }
-- isPedDucked and getVehicleController postdate the generated .luacheck/mta_server.lua list
files["resources/**/weapons/server/**"] = { std = "lua51+mta_shared+mta_server", read_globals = { "isPedDucked", "getVehicleController" } }
files["resources/**/world/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getWeather", "setGlobalWeather" } }
files["resources/**/world/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "tryInteract", "nearbyFeature" }, read_globals = { "dxDrawLine3D", "getBoundKeys" } }
files["resources/**/world/data/**"] = { std = "lua51", max_line_length = false }
-- removePedFromVehicle, dxDrawPrimitive3D and the clock/weather getters and setters postdate the generated lists
files["resources/**/dev/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rcon", "isItemSpawnAllowed" }, read_globals = { "removePedFromVehicle", "removeElementData" } }
files["resources/**/discordchat/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "logItemSpawn", "sendStaffLog" } }
files["resources/**/dev/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "isHeld" }, read_globals = { "executeCommandHandler", "dxDrawPrimitive3D", "getTime", "setTime", "getWeather", "setWeather", "getMinuteDuration", "setMinuteDuration", "createLight", "showChat", "isChatVisible" } }
-- dxDrawModel3D, engineStreamingReleaseModel, getWorldFromScreenPosition, getElementMatrix and the shader functions postdate the generated lists
files["resources/**/items/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "setAttachPreview", "getAttachConfig", "nearbyCooker", "nearbyBag", "nearbyInspectable", "nearbyMachine" }, read_globals = { "dxDrawModel3D", "engineStreamingReleaseModel", "getWorldFromScreenPosition", "getElementMatrix", "engineGetModelTextures", "dxCreateShader", "dxSetShaderValue", "engineApplyShaderToWorldTexture", "createEffect" } }
-- fileSetPos postdates the generated .luacheck/mta_shared.lua list
files["resources/**/attachedit/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "rcon" }, read_globals = { "fileSetPos" } }
-- getVehicleWheelStates and getVehicleLightState postdate the generated .luacheck/mta_server.lua list
files["resources/**/vehicles/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getVehicleDbId", "countVehicles", "respawnAll", "getVehicleFuel", "setVehicleFuel", "getVehicleLockState", "setVehicleLockState", "getVehicleKeyCode", "setVehicleKeyCode", "getVehicleContainerId" }, read_globals = { "attachTrailerToVehicle", "detachTrailerFromVehicle", "getVehicleEngineState", "getVehicleController", "setVehicleDoorOpenRatio", "getVehicleOverrideLights", "setVehicleOverrideLights", "getVehicleTowedByVehicle", "getVehicleTowingVehicle", "getVehicleWheelStates", "getVehicleLightState" } }
files["resources/**/building/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "isInsideAnyPlotPole", "interactDefence", "buildDefence", "removeDefence", "submitPasscode", "installKeypad", "tweakItem", "finishTweak" } }
files["resources/**/building/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "tweakIsOpen", "tweakFinish" }, read_globals = { "playSoundFrontEnd" } }
files["resources/**/crafting/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "groundCraft", "deconstruct", "workbenchCraft", "isConstructionTool" } }
-- clearChatBox postdates the generated .luacheck/mta_server.lua list
files["resources/**/staff/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getLevel", "getMotd", "isOnDuty", "isMuted", "logAction", "mutePlayer", "getLevelColour", "runCommand" }, read_globals = { "clearChatBox" } }
-- the CEGUI grid list, combo box, memo and label functions postdate the generated .luacheck/mta_client.lua list
files["resources/**/staff/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "guiCreateGridList", "guiGridListAddColumn", "guiGridListAddRow", "guiGridListClear", "guiGridListGetSelectedItem", "guiGridListSetItemColor", "guiGridListSetItemText", "guiGridListSetSortingEnabled", "guiCreateComboBox", "guiComboBoxAddItem", "guiComboBoxGetSelected", "guiComboBoxGetItemText", "guiCreateMemo", "guiMemoSetReadOnly", "guiMemoSetCaretIndex", "guiLabelSetColor", "guiLabelSetHorizontalAlign", "guiSetPosition", "guiGetInputMode" } }
files["resources/**/anticheat/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "refreshFields", "isIdleKickEnabled", "setIdleKickEnabled", "toggleIdleKick", "getMaxTabOutTime", "setMaxTabOutTime" } }
files["resources/**/chat/server/**"] = { std = "lua51+mta_shared+mta_server", globals = { "getRadio", "setChatMode", "sendAs", "sendGlobalExternal" } }
files["resources/**/chat/client/**"] = { std = "lua51+mta_shared+mta_client", globals = { "radioOpen" } }
-- getMaxPlayers/getServerName and the Discord Rich Presence functions postdate the generated .luacheck lists
files["resources/**/presence/server/**"] = { std = "lua51+mta_shared+mta_server", read_globals = { "getMaxPlayers", "getServerName" } }
files["resources/**/presence/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "isDiscordRichPresenceConnected", "resetDiscordRichPresenceData", "setDiscordApplicationID", "setDiscordRichPresenceButton", "setDiscordRichPresenceDetails", "setDiscordRichPresencePartySize", "setDiscordRichPresenceStartTime", "setDiscordRichPresenceState" } }
files["resources/**/house_shell/client/**"] = { std = "lua51+mta_shared+mta_client", read_globals = { "engineRestoreCOL", "engineRestreamWorld", "engineRestoreModel" } }
