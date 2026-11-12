-- Email confirmation (port addition, no upstream counterpart): every account confirms an email address before it
-- may play. The server mails a 6-digit code (a row in email_outbox, sent by ops/mailer) and the player types it
-- into an input dialog. Pure: validation, the code checks and the dialog and mail texts; the server keeps the
-- state per player and passes tr (its translation for the player's dialog language), identity by default.
local email = {}

email.MAX_LEN = 254 -- RFC 5321 path limit
email.MAX_LOCAL = 64
email.CODE_DIGITS = 6
email.CODE_TTL_MS = 15 * 60 * 1000
email.MAX_WRONG = 5 -- wrong codes before the code is void and a new one has to be sent
email.RESEND_MS = 60 * 1000
email.MAX_SENDS = 5 -- codes mailed per connection
email.MAX_ACCOUNTS = 3 -- confirmed accounts sharing one address

local function identity(s)
    return s
end

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The address as stored: trimmed and in lower case (the column compares without case anyway).
function email.normalize(s)
    return string.lower(trim(s))
end

local LOCAL_CHARS = "^[%w%.!#%$%%&'%*%+/=%?%^_`{|}~%-]+$"

-- ok, reason: "EMPTY" | "TOO_LONG" | "SPACES" | "FORMAT" (not local@domain.tld)
function email.validate(s)
    s = tostring(s or "")
    if s == "" then
        return false, "EMPTY"
    end
    if #s > email.MAX_LEN then
        return false, "TOO_LONG"
    end
    if s:find("%s") then
        return false, "SPACES"
    end
    local at = s:find("@", 1, true)
    if not at or s:find("@", at + 1, true) then
        return false, "FORMAT"
    end
    local localPart, domain = s:sub(1, at - 1), s:sub(at + 1)
    if localPart == "" or #localPart > email.MAX_LOCAL or not localPart:find(LOCAL_CHARS) then
        return false, "FORMAT"
    end
    if localPart:sub(1, 1) == "." or localPart:sub(-1) == "." or localPart:find("..", 1, true) then
        return false, "FORMAT"
    end
    local labels = {}
    for label in (domain .. "."):gmatch("([^%.]*)%.") do
        labels[#labels + 1] = label
    end
    if #labels < 2 then
        return false, "FORMAT"
    end
    for _, label in ipairs(labels) do
        if label == "" or #label > 63 or not label:find("^[%w%-]+$") then
            return false, "FORMAT"
        end
        if label:sub(1, 1) == "-" or label:sub(-1) == "-" then
            return false, "FORMAT"
        end
    end
    if not labels[#labels]:find("^%a%a+$") then
        return false, "FORMAT"
    end
    return true
end

-- What a line typed into the code dialog is: "empty" (send another code), "code" (6 digits, spaces ignored),
-- "email" (anything with an @: a new address) or "other".
function email.classify(text)
    local s = trim(text)
    if s == "" then
        return "empty", s
    end
    if s:find("@", 1, true) then
        return "email", email.normalize(s)
    end
    local digits = s:gsub("[%s%-]", "")
    if #digits == email.CODE_DIGITS and digits:find("^%d+$") then
        return "code", digits
    end
    return "other", s
end

-- A code from a random number in 0..999999, zero padded.
function email.formatCode(n)
    return string.format("%06d", math.floor(tonumber(n) or 0) % 1000000)
end

-- May another code be mailed now? state = { sends, lastSend (tick or nil) }; force skips the cooldown (a new
-- address). ok, code ("COOLDOWN" with the seconds left | "LIMIT").
function email.canSend(state, now, force)
    if (state.sends or 0) >= email.MAX_SENDS then
        return false, "LIMIT"
    end
    if not force and state.lastSend and now - state.lastSend < email.RESEND_MS then
        return false, "COOLDOWN", math.ceil((email.RESEND_MS - (now - state.lastSend)) / 1000)
    end
    return true
end

-- A typed code against the pending one: "OK" | "NONE" (no code pending) | "EXPIRED" | "WRONG" | "LOCKED" (this
-- was the last wrong try). Counts the wrong try on state.wrong.
function email.check(state, typed, now)
    if not state.code then
        return "NONE"
    end
    if now >= (state.expires or 0) then
        return "EXPIRED"
    end
    if typed == state.code then
        return "OK"
    end
    state.wrong = (state.wrong or 0) + 1
    if state.wrong >= email.MAX_WRONG then
        return "LOCKED"
    end
    return "WRONG"
end

-- lang:begin
email.TEXTS = {
    emailTitle = "Confirm your email",
    codeTitle = "Enter your confirmation code",
    registerNote = "Next you will need a VALID email address: we send a code to it and you cannot play until you"
        .. " confirm it.",
    emailBody = "Type a VALID email address you can open right now.\nWe will send a 6-digit code to it, and you"
        .. " cannot join the game until you type that code here.\nWe only use it for your account.",
    codeBody = "We sent a 6-digit code to %s.\nType it below and press Accept.\n\nCheck your inbox and spam folder;"
        .. " it can take a minute.\nWrong address? Type the right one in the box instead.\nNothing arrived? Leave the"
        .. " box empty and press Accept for a new code (once a minute).",
    EMPTY = "Type your email address.",
    TOO_LONG = "That email address is too long.",
    SPACES = "An email address has no spaces.",
    FORMAT = "That is not a valid email address (name@example.com).",
    TAKEN = "That email address is already used by 3 accounts. Use another one.",
    DB_ERROR = "Something went wrong, try again.",
    COOLDOWN = "Wait %d seconds before asking for another code.",
    SENT = "A new code is on its way.",
    WRONG = "Wrong code, %d tries left.",
    EXPIRED = "That code has expired. A new one is on its way.",
    LOCKED = "Too many wrong codes. A new one is on its way.",
    NOT_CODE = "Type the 6-digit code from the email.",
    leftReason = "Left without confirming email",
    limitReason = "Too many confirmation emails, rejoin later",
    mailSubject = "Your Scavenge & Survive confirmation code: %s",
    mailBody = "Hello %s,\n\nYour Scavenge & Survive confirmation code is:\n\n    %s\n\nType it into the dialog in"
        .. " the game. It is valid for 15 minutes.\n\nIf you didn't request this, ignore this email.\n\n"
        .. "Scavenge & Survive",
}
-- lang:end

local function fmt(tr, key, ...)
    local ok, out = pcall(string.format, tr(email.TEXTS[key]), ...)
    if ok then
        return out
    end
    return string.format(email.TEXTS[key], ...)
end

local ERROR_COLOUR, TEXT_COLOUR = "#FF6060", "#FFFFFF"

-- title, body of a dialog: kind = "email" | "code"; note = { key, args... } shown above the body in red (a
-- refusal) or nil; addr = the address the code went to.
function email.dialog(kind, addr, note, tr)
    tr = tr or identity
    local body
    if kind == "code" then
        body = fmt(tr, "codeBody", tostring(addr or ""))
    else
        body = tr(email.TEXTS.emailBody)
    end
    body = TEXT_COLOUR .. body
    if note and note[1] then
        body = ERROR_COLOUR .. fmt(tr, note[1], unpack(note, 2)) .. "\n\n" .. body
    end
    return tr(email.TEXTS[kind == "code" and "codeTitle" or "emailTitle"]), body
end

-- subject, body of the mail carrying a code.
function email.message(accountName, code, tr)
    tr = tr or identity
    return fmt(tr, "mailSubject", code), fmt(tr, "mailBody", tostring(accountName), code)
end

-- SQL: confirmed accounts other than this one using an address.
email.TAKEN_SQL = "SELECT COUNT(*) AS n FROM accounts WHERE email = ? AND email_verified_at IS NOT NULL AND id <> ?"
-- SQL: confirm the address on the account unless MAX_ACCOUNTS others confirmed it meanwhile (affected rows 0).
-- The derived table works around MariaDB's 1093 (an UPDATE reading its own table in a subquery).
email.CONFIRM_SQL = "UPDATE accounts SET email = ?, email_verified_at = NOW() WHERE id = ? AND (SELECT n FROM"
    .. " (SELECT COUNT(*) AS n FROM accounts WHERE email = ? AND email_verified_at IS NOT NULL AND id <> ?) x) < "
    .. email.MAX_ACCOUNTS

return email
