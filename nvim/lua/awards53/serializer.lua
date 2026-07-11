local M = {}

function M.build(data)
    local cfg = require("awards53")
    local out = {}
    
    table.insert(out, "") -- Отступ для Org-mode
    
    for i, record in ipairs(data.records) do
        -- Количество полей теперь строго равно размеру массива заголовков
        local active_fields_count = #data.headers

        for field_idx = 1, active_fields_count do
            local field_key = tostring(field_idx)
            local value = record[field_key] or {}

            for _, line in ipairs(value) do
                table.insert(out, line)
            end
            
            if field_idx < active_fields_count then
                table.insert(out, cfg.config.separator)
            end
        end

        if i < #data.records then
            table.insert(out, cfg.config.record_separator)
        end
    end

    for i, line in ipairs(out) do
        out[i] = line:gsub("«", '"'):gsub("»", '"')
    end

    return out
end

return M
