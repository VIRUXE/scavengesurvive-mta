-- GTA's ambient gunfire (distant shots in the hood zones at night) sounds like real players shooting nearby, so
-- it is off for everyone; the general ambience stays.
addEventHandler("onClientResourceStart", resourceRoot, function()
    setAmbientSoundEnabled("gunfire", false)
end)
