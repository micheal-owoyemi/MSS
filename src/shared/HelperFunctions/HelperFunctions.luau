--[[

    Returns two tables, additions and deletions

    If value found in old table but not new table, deletion
    If value found in new table but not old table, addition
]]

local HelperFunctions = {}

function HelperFunctions.compareTables(new_table, old_table)
    local additions = {}
    local deletions = {}

    -- FIND ADDITIONS
    for key, value in new_table do
        if old_table[key] == nil then
            additions[key] = value
        end
    end

    for key, value in old_table do
        if new_table[key] == nil then
            deletions[key] = value
        end
    end

    return additions, deletions
end

return HelperFunctions
