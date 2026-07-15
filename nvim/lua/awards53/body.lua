-- lua/awards53/body.lua
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
        local is_active = (i == state.field_index())

        -- Заголовок поля і роздільник
        if is_active then
            table.insert(lines, "[  Поле " .. field .. ":  j▲ k▼ i►󰏫 F/F➕ J/K↧(space-j/k:⇊) 0∅ B  ]")
            table.insert(lines, "" .. hr(55)) -- Верхня границя блока
        else
            table.insert(lines, "[" .. field .. "]") 
        end

        local value = record[field] or {}

        -- Вміст поля
        if type(value) == "table" then
            for _, line in ipairs(value) do
                if is_active then
                    -- Відступ і вертикальна лінія для АКТИВНОГО блока 
                    table.insert(lines, "  " .. line)
                else
                    table.insert(lines, "" .. line)
                end
            end
        else
            if is_active then
                table.insert(lines, "  " .. tostring(value))
            else
                table.insert(lines, "" .. tostring(value))
            end
        end

        -- Нижня границя активного блока або порожній рядок
        table.insert(lines, "")
    end
 
    return lines
end

return M
