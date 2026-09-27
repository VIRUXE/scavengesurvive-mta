local net = { buckets = {}, tokens = {} }

local function allowed(player, name, rate)
    local now = getTickCount()
    local key = tostring(player) .. "|" .. name
    local b = net.buckets[key]
    if not b or now - b.start >= 1000 then
        b = { start = now, n = 0 }
        net.buckets[key] = b
    end
    b.n = b.n + 1
    return b.n <= rate
end

function net.handler(name, fn, opts)
    opts = opts or {}
    local rate = opts.rate or 10
    addEvent(name, true)
    addEventHandler(name, root, function(...)
        if not isElement(client) or client ~= source then
            return
        end
        if not allowed(client, name, rate) then
            return
        end
        fn(client, ...)
    end)
end

function net.issueToken(player, purpose, ttlSeconds)
    local token = tostring(math.random(1, 2 ^ 30)) .. "-" .. tostring(getTickCount())
    net.tokens[tostring(player) .. "|" .. purpose .. "|" .. token] = getTickCount() + (ttlSeconds or 30) * 1000
    return token
end

function net.consumeToken(player, purpose, token)
    local key = tostring(player) .. "|" .. purpose .. "|" .. tostring(token)
    local expires = net.tokens[key]
    net.tokens[key] = nil
    return expires ~= nil and getTickCount() <= expires
end

return net
