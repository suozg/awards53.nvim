local M = {}

function M.build(data)
    local cfg = require("awards53")
    local out = {}
    
    table.insert(out, "") -- Початковий відступ для краси Org-mode
    
    for i, record in ipairs(data.records) do
        -- Рахуємо, скільки реально полів заповнено у цієї конкретної людини
        local active_fields_count = 0
        for _, field in ipairs(data.headers) do
            if record[field] and #record[field] > 0 then
                active_fields_count = tonumber(field)
            end
        end

        -- Виводимо поля по черзі
        for field_idx = 1, active_fields_count do
            local field_key = tostring(field_idx)
            local value = record[field_key] or {}

            -- Записуємо весь текст поля
            for _, line in ipairs(value) do
                table.insert(out, line)
            end

            -- Якщо це ще не останнє поле ЦІЄЇ людини, ставимо між ними ::
            if field_idx < active_fields_count then
                table.insert(out, cfg.config.separator)
            end
        end

        -- Якщо це не остання ЛЮДИНА у списку, розділяємо їх через ===
        if i < #data.records then
            table.insert(out, cfg.config.record_separator)
        end
    end

    -- Заміна «ялинок» на подвійні лапки
    for i, line in ipairs(out) do
        out[i] = line:gsub("«", '"'):gsub("»", '"')
    end

    return out
end

return M
