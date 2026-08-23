local M = {}

local state = require("awards53.state")

local function hr(width)
    return string.rep("~", width)
end

function M.render()
    local record = state.current_record()
    local lines = {}
    
    table.insert(lines, "")

    for i, field in ipairs(state.headers_list()) do
        local is_active = (i == state.field_index())

        -- Заголовок активного поля у вигляді чистого рядка
        if is_active then
            local total_fields = #state.headers_list()
            local header_text = string.format(" 󰓻 Поле %s/%d     j▲ k▼ #f    🖊:i► F-    ⇊:J/K  ", field, total_fields)
            table.insert(lines, header_text)
        else
            table.insert(lines, "   [" .. field .. "]") 
        end

        local value = record[field] or {}

        -- Вміст поля (без зайвих відступів, щоб не викликати суцільне підсвічування)
        if type(value) == "table" then
            for _, line in ipairs(value) do
                table.insert(lines, "   " .. line)
            end
            table.insert(lines, "   " .. hr(58))
        else
            table.insert(lines, "   " .. tostring(value))
        end

        table.insert(lines, "")
    end
 
    return lines
end

return M
