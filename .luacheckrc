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
