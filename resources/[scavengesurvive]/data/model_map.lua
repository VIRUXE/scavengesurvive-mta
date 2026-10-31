-- SA-MP-only object ids (18631+ and 11682-11753) have no model in MTA. The `models` resource loads the real ones on
-- each client (tools/extract_samp_models.py); these vanilla stand-ins are what clients show while it is not running.
-- Keys: SA-MP model -> MTA vanilla model.
local M = { DEFAULT = 1271 }
M.byModel = {
    [18632] = 1974,
    [18633] = 1974,
    [18634] = 1974,
    [18635] = 1974,
    [18644] = 1974,
    [18890] = 1974,
    [19348] = 1974,
    [18637] = 1575,
    [18641] = 1279,
    [18642] = 1279,
    [18643] = 1279,
    [18865] = 1279,
    [18875] = 1279,
    [19418] = 1279,
    [19998] = 1279,
    [19346] = 2703,
    [19345] = 2703,
    [19468] = 1271,
    [19471] = 1271,
    [19515] = 1242,
    -- the re-pivoted defence doors (models/defences.lua, tools/port_defences.py) fall back to their hinged originals
    [20301] = 1965,
    [20302] = 3062,
    [20303] = 2944,
}
function M.isSampOnly(model)
    return model >= 18631 or (model >= 11682 and model <= 11753)
end
function M.resolve(model)
    if M.isSampOnly(model) then
        return M.byModel[model] or M.DEFAULT, true
    end
    return model, false
end
return M
