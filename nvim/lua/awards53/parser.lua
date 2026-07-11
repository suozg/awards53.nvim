local M = {}

-- Функція для очищення пустих рядків з початку та кінця масиву
local function trim_field_lines(lines)
    if not lines or #lines == 0 then return {} end

    -- 1. Знаходимо перший непустий рядок
    local first = 0
    for i = 1, #lines do
        if vim.trim(lines[i]) ~= "" then
            first = i
            break
        end
    end

    -- Якщо все поле складається з пустих рядків
    if first == 0 then return {} end

    -- 2. Знаходимо останній непустий рядок
    local last = #lines
    for i = #lines, 1, -1 do
        if vim.trim(lines[i]) ~= "" then
            last = i
            break
        end
    end

    -- 3. Вирізаємо лише корисний вміст
    local cleaned = {}
    for i = first, last do
        table.insert(cleaned, lines[i])
    end

    return cleaned
end

function M.parse(lines, separator)
    local cfg = require("awards53")
    separator = separator or cfg.config.separator
    
    local records = {}
    local max_fields = 0

    local current_record = {}
    local field_idx = 1
    current_record[tostring(field_idx)] = {}

    local function finish_record()
        if current_record and next(current_record) ~= nil then
            
            -- Очищаємо кожне поле поточної картки від пустих рядків на початку/кінці
            for k, v in pairs(current_record) do
                current_record[k] = trim_field_lines(v)
            end

            if field_idx > max_fields then
                max_fields = field_idx
            end
            table.insert(records, current_record)
        end
        current_record = {}
        field_idx = 1
        current_record[tostring(field_idx)] = {}
    end

    for _, line in ipairs(lines) do
        local trimmed = vim.trim(line)

        if trimmed == cfg.config.record_separator then
            finish_record()
        elseif trimmed == separator then
            field_idx = field_idx + 1
            current_record[tostring(field_idx)] = {}
        else
            table.insert(current_record[tostring(field_idx)], line)
        end
    end

    finish_record()

    local headers = {}
    for i = 1, max_fields do
        table.insert(headers, tostring(i))
    end

    return {
        headers = headers,
        records = records,
    }
end

return M
