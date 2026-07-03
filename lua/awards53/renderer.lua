local M = {}

local state = require("awards53.state")

local function hr(width)
    return string.rep("─", width)
end

function M.render(record, index, total)

    local lines = {}

    table.insert(lines, "")
    table.insert(lines,
        string.format("          НАГОРОДНИЙ ЛИСТ %d/%d", index, total))
    table.insert(lines, "")

    for _, field in ipairs(state.headers_list()) do
        table.insert(lines, field)
        table.insert(lines, hr(60))

    local value = record[field] or {}

    if type(value) == "table" then
        for _, line in ipairs(value) do
            table.insert(lines, line)
        end
    else
        table.insert(lines, tostring(value))
    end

        table.insert(lines, "")

    end

    table.insert(lines, "")
    table.insert(lines, hr(60))
    table.insert(lines,
        "h l | [[ ]] | ^B ^F | Ns | q"
    )
    return lines

end

return M
