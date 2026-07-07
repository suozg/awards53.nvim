local M = {}

local state = require("awards53.state")

local function hr(width)
    return string.rep("─", width)
end

function M.render()

    local record = state.current_record()
    local lines = {}
    
    table.insert(lines, "")

    for i, field in ipairs(state.headers_list()) do
        if i == state.field_index() then
            table.insert(lines, "► Поле " .. field)
        else
            table.insert(lines, "  Поле " .. field)
        end

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
 
    return lines

end

return M
