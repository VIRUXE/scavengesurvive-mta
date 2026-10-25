local rules = {}
function rules.validatePassword(pw)
    if type(pw) ~= "string" then
        return false, "WEAK_PASSWORD"
    end
    if #pw < 4 or #pw > 32 then
        return false, "WEAK_PASSWORD"
    end
    return true
end
function rules.validateName(name)
    if type(name) ~= "string" or #name < 1 or #name > 22 then
        return false, "BAD_NAME"
    end
    if name:find("[^%w%p]") then
        return false, "BAD_NAME"
    end
    return true
end
-- /changepass (upstream commands.pwn): the reply line and its colour for each outcome of accounts.changePassword
local CHANGE_PASSWORD_REPLIES = {
    OK = { key = "PASSCHANGED", color = { 255, 255, 0 } },
    NO_MATCH = { key = "PASSCHNOMAT", color = { 255, 80, 80 } },
    WEAK_PASSWORD = { key = "PASSWORDREQ", color = { 255, 255, 0 } },
}
function rules.changePasswordReply(code)
    return CHANGE_PASSWORD_REPLIES[code] or { key = "PASSCHERROR", color = { 255, 80, 80 } }
end
return rules
