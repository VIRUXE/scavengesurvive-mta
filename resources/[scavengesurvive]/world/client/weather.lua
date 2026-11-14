-- A weather only this player sees (staff /weather window): the server sends the id on a set, an expiry and after
-- every world weather change, since the global setWeather reaches this client too.
addEventHandler("playerWeatherChanged", root, function(id)
    if type(id) == "number" then
        setWeather(id)
    end
end)
