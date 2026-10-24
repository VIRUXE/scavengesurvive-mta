-- The login and register dialogs as upstream showed them (accounts.pwn DisplayLoginPrompt / DisplayRegisterPrompt,
-- welcome-message.pwn): which dialog a player gets, with which language keys, what a refused attempt leads to,
-- and the welcome message a fresh account reads before playing. Pure: the server fills the keys through data's
-- t(), the client draws through ui's password/msgbox dialogs.
local prompt = {}

prompt.MAX_ATTEMPTS = 5
prompt.BUTTONS = { "Accept", "Leave" }

-- The dialog for a mode ("login" | "register"); attempts > 0 is the "Incorrect password! N out of 5 tries" body.
function prompt.dialog(mode, name, attempts)
    if mode == "register" then
        return { titleKey = "ACCREGITITL", bodyKey = "ACCREGIBODY", args = { name } }
    end
    if (attempts or 0) > 0 then
        return { titleKey = "ACCLOGITITL", bodyKey = "ACCLOGWROPW", args = { attempts } }
    end
    return { titleKey = "ACCLOGITITL", bodyKey = "ACCLOGIBODY", args = { name } }
end

-- What follows a refused login or registration (accounts.lua codes):
-- { action = "reprompt" (mode, attempts) | "lookup" (account state changed, decide again) | "leave" (kick with the
--   grey broadcast) | "kick" (reason) | "none" (another path handles it), chatKey = language line to print first }
function prompt.onRefused(code, attempts)
    if code == "WEAK_PASSWORD" then
        return { action = "reprompt", mode = "register", chatKey = "PASSWORDREQ" }
    elseif code == "BAD_PASSWORD" then
        if (attempts or 0) < prompt.MAX_ATTEMPTS then
            return { action = "reprompt", mode = "login", attempts = attempts }
        end
        return { action = "leave" }
    elseif code == "TOO_MANY_ATTEMPTS" then
        return { action = "leave" }
    elseif code == "NO_ACCOUNT" or code == "EXISTS" then
        return { action = "lookup" }
    elseif code == "INACTIVE" then
        return { action = "kick", reason = "Account inactive" }
    elseif code == "NOT_WHITELISTED" then
        return { action = "none" }
    end
    return { action = "kick", reason = "Account load failed" }
end

-- The grey line everyone reads when a player leaves the dialog (upstream ChatMsgAll GREY).
function prompt.leftMessage(name, mode)
    local what = mode == "register" and "registering" or "logging in"
    return string.format(" >  %s left the server without %s.", name, what)
end

-- Welcome message (welcome-message.pwn): a message box whose only button counts down from 10 before it reads
-- Accept; closing it earlier shows it again. Upstream hardcoded the English text.
prompt.WELCOME_TITLE = "Welcome to the Server"
prompt.WELCOME_COUNTDOWN = 10
prompt.WELCOME_BODY = table.concat({
    "#FFFFFFYou have to fight to survive in an apocalyptic wasteland.",
    "",
    "You will have a better chance in a group, but be careful who you trust.",
    "",
    "Supplies can be found scattered around, weapons are rare though.",
    "",
    "Avoid attacking unarmed players, they frighten easily but will return, and in greater numbers...",
    "",
    "",
    "#008080Please take some time to look at the #33CCFF/rules #008080and #33CCFF/help #008080before diving into the"
        .. " game.",
    "",
    "Visit #FFFF00scavenge-survive.wikia.com #008080for more information.",
}, "\n")

function prompt.welcomeButton(secondsLeft)
    if (secondsLeft or 0) > 0 then
        return tostring(secondsLeft)
    end
    return "Accept"
end

return prompt
