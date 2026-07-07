local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local abbr = require("awards53.abbreviations")

-- 1. Перемістити офіцерів на початок списку
function M.sort_officers_first()
    local cfg = require("awards53")
    -- Беремо налаштування за замовчуванням або Поле 3 (де зазвичай звання)
    local field = "2" or cfg.config.default_sort
    
    -- Перевіряємо чи є взагалі записи
    if not state.records or #state.records == 0 then 
        utils.warn("Список записів порожній")
        return 
    end

    state.snapshot()

    local officer_keywords = {
        "лейтенант", "капітан", "майор", "полковник", "генерал"
    }

    local function is_officer(rec)
        local val = rec[field]
        if not val then return false end
        local text = type(val) == "table" and table.concat(val, " ") or tostring(val)
        text = text:lower()

        for _, kw in ipairs(officer_keywords) do
            if text:find(kw, 1, true) then
                return true
            end
        end
        return false
    end

    -- Тимчасово додаємо кожному запису його поточний індекс для стабільного сортування
    for idx, rec in ipairs(state.records) do
        rec.__original_index = idx
    end

    -- Сортуємо ОРИГІНАЛЬНИЙ масив state.records
    table.sort(state.records, function(a, b)
        local a_off = is_officer(a)
        local b_off = is_officer(b)
        
        if a_off and not b_off then return true end
        if not a_off and b_off then return false end
        
        -- Якщо обидва офіцери або обидва ні — зберігаємо початковий порядок
        return a.__original_index < b.__original_index
    end)

    -- Очищаємо тимчасові індекси
    for _, rec in ipairs(state.records) do
        rec.__original_index = nil
    end

    -- Викликаємо обов'язкові методи оновлення стану з вашого state.lua
    state.renumber()
    state.is_changed = true
    utils.info("Офіцерів переміщено на початок списку (поле " .. field .. ")")
end

-- 2. Форматування РНОКПП (перенос на новий рядок у Полі 2)
function M.format_rnokpp_in_current_card()
    local record = state.current_record()
    if not record then return end
    
    -- Працюємо з Полем 2
    local lines = record["2"] or {}
    if #lines == 0 then return end
    
    local text = table.concat(lines, "\n")
    local p_rnokpp = "%f[%d]%d%d%d%d%d%d%d%d%d%d%f[%D]"
    local start_idx, end_idx = text:find(p_rnokpp)
    
    if not start_idx then
        utils.warn("РНОКПП у Полі 2 не знайдено")
        return
    end
    
    state.snapshot()
    
    local rnokpp = text:sub(start_idx, end_idx)
    local before = text:sub(1, start_idx - 1)
    local after = text:sub(end_idx + 1)
    
    before = before:gsub("[%s%,%.%;%-]+$", "")
    
    local new_text = before .. "\n" .. rnokpp .. after
    record["2"] = vim.split(new_text, "\n", { trimempty = false })
    
    state.is_changed = true
    utils.info("РНОКПП перенесено в кінець рядка")
end

-- 3. Розгортання абревіатур для ПОТОЧНОЇ картки за запитом
function M.expand_abbr_in_current_card()
    local record = state.current_record()
    if not record then return end
    
    state.snapshot()
    local changed = false
    
    -- Проходимо по всіх полях картки і розгортаємо скорочення
    for _, field in ipairs(state.headers_list()) do
        local lines = record[field]
        if lines and #lines > 0 then
            local expanded = abbr.expand_lines(lines)
            -- Перевіряємо, чи взагалі щось змінилося, щоб марно не смикати стан
            if table.concat(expanded, "\n") ~= table.concat(lines, "\n") then
                record[field] = expanded
                changed = true
            end
        end
    end
    
    if changed then
        state.is_changed = true
        utils.info("Скорочення розгорнуто")
    else
        utils.info("Нічого розгортати")
    end
end

return M
