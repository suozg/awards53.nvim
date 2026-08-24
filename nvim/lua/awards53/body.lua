local M = {}

local state = require("awards53.state")

local function hr(target_width)
    local pattern = ". . "
    local pattern_len = #pattern
    local count = math.ceil(target_width / pattern_len)
    return string.sub(string.rep(pattern, count), 1, target_width)
end

function M.render()
    local record = state.current_record()
    local lines = {}
    
    table.insert(lines, "")

    for i, field in ipairs(state.headers_list()) do
        local is_active = (i == state.field_index())

        if is_active then
            local total_fields = #state.headers_list()
            local header_text = string.format(" 󰓻 Поле %s/%d     j▲ k▼ #f    🖊:i► F-    ⇊:J/K  ", field, total_fields)
            
            -- Рахуємо довжину для активного поля теж, щоб не було nil
            local current_hr_width = vim.fn.strdisplaywidth(header_text)

            table.insert(lines, "")
            table.insert(lines, header_text)

            local value = record[field] or {}

            if type(value) == "table" then
                for _, line in ipairs(value) do
                    table.insert(lines, "    " .. line)
                end
                --table.insert(lines, hr(current_hr_width))
                table.insert(lines, "")
            else
                table.insert(lines, "    " .. tostring(value))
                --table.insert(lines, hr(current_hr_width))
            end

            table.insert(lines, "")
        else
            -- 1. Створюємо рядок заголовка неактивного поля
            local header_line = "[" .. field .. "]"
            table.insert(lines, header_line)
            
            -- 2. Рахуємо його реальну довжину в символах за допомогою #
            local current_hr_width = vim.fn.strdisplaywidth(header_line)
            
            local value = record[field] or {}

            -- Вміст поля
            if type(value) == "table" then
                for _, line in ipairs(value) do
                    table.insert(lines, "    " .. line)
                end
                -- 3. Вставляємо лінію нижче з отриманою довжиною
                table.insert(lines, hr(current_hr_width))
            else
                table.insert(lines, "    " .. tostring(value))
                table.insert(lines, hr(current_hr_width))
            end

            table.insert(lines, "")
        end
    end
 
    return lines
end

return M
