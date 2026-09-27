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
return rules
