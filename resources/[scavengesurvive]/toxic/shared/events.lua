-- client to server (handler registered with net.handler)
addEvent("toxicCloudRequested", true) -- a (re)started client asks for the cloud in the air, if any
addEvent("toxicShelterReported", true) -- a client in the gas: the openness it measures where it stands, 0..1
-- server to client
addEvent("toxicCloudStarted", true) -- cloud plan, its age in seconds
addEvent("toxicCloudEnded", true)
addEvent("characterSkillsSynced", true) -- fired by character: the skill rows (Poison Resistance for the gauge)
addEvent("toxicExposureSynced", true) -- to one player: the gas strength around them, the openness of where they are
