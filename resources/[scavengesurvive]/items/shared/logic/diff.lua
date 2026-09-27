local diff = {}

-- sent: set {[id]=true} of ids the client already has; rows: current visible rows from the DB
function diff.compute(sent, rows)
    local add, remove, newSent = {}, {}, {}
    for _, row in ipairs(rows) do
        newSent[row.id] = true
        if not sent[row.id] then
            add[#add + 1] = row
        end
    end
    for id in pairs(sent) do
        if not newSent[id] then
            remove[#remove + 1] = id
        end
    end
    table.sort(remove)
    return add, remove, newSent
end

return diff
