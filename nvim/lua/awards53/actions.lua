local M = {}

local state = require("awards53.state") 
local utils = require("awards53.utils") 
local replacement = "53 окремої механізованої бригади імені князя Володимира Мономаха 3 армійського корпусу оперативного командування \"Схід\" Сухопутних військ Збройних сил України" 

-- ====================================================================
-- Спільне ядро для форматування тексту однієї картки
-- ====================================================================
local function format_text_core(text)
    local rnokpp_start, rnokpp_end = text:find("(%d%d%d%d%d%d%d%d%d%d)")
    if not rnokpp_start then return nil end

    local rnokpp = text:sub(rnokpp_start, rnokpp_end)
    local before = text:sub(1, rnokpp_start - 1)
    local after  = text:sub(rnokpp_end + 1)
 
    before = before:gsub("[%s%,%.%;%-]+$", "")
    local new_text = before .. "\n" .. rnokpp .. after

    -- 1. Проводимо базові заміни бригади/вч
    new_text = new_text:gsub("53%s+окремої%s+.-%s+України", replacement)
    new_text = new_text:gsub("військової%s+частини%s+А0536", replacement)

    -- 2. Видаляємо цифри перед назвою бригади
    local safe_replacement = replacement:gsub("([^%w])", "%%%1")
    new_text = new_text:gsub("^(.-)(" .. safe_replacement .. ")", function(prefix, brigade)
        return prefix:gsub("%d", "") .. brigade
    end)

    return new_text
end

-- ====================================================================
-- 1. Перемістити офіцерів на початок списку
-- ====================================================================
function M.sort_officers_first()
    local cfg = require("awards53") 
    local field = "2" or cfg.config.default_sort 
    
    if not state.records or #state.records == 0 then 
        utils.warn("Список записів порожній") 
        return 
    end 

    state.snapshot() 

    local officer_keywords = { "лейтенант", "капітан", "майор", "полковник", "генерал" } 

    local function is_officer(rec) 
        local val = rec[field] 
        if not val then return false end 
        local text = type(val) == "table" and table.concat(val, " ") or tostring(val) 
        text = text:lower() 
        for _, kw in ipairs(officer_keywords) do 
            if text:find(kw, 1, true) then return true end 
        end 
        return false 
    end 

    for idx, rec in ipairs(state.records) do rec.__original_index = idx end 

    table.sort(state.records, function(a, b) 
        local a_off = is_officer(a) 
        local b_off = is_officer(b) 
        if a_off and not b_off then return true end 
        if not a_off and b_off then return false end 
        return a.__original_index < b.__original_index 
    end) 

    for _, rec in ipairs(state.records) do rec.__original_index = nil end 

    state.renumber() 
    state.is_changed = true 
    utils.info("Офіцерів переміщено на початок списку (поле " .. field .. ")") 
end


-- ====================================================================
-- 2. Форматування вибраного поля ДЛЯ ПОТОЧНОЇ КАРТКИ
-- ====================================================================
function M.format_rnokpp_in_current_card()
    local record = state.current_record() 
    if not record then return end 
 
    local field_id = state.field_name() 
    if not field_id then 
        utils.warn("Не вдалося визначити поточне поле") 
        return 
    end 

    local lines = record[field_id] or {} 
    if #lines == 0 then return end 
 
    state.snapshot() 
    local text = table.concat(lines, "\n") 
 
    -- Викликаємо наше спільне ядро
    local formatted_text = format_text_core(text)
 
    if not formatted_text then
        utils.warn("РНОКПП (10 цифр підряд) у Полі [" .. field_id .. "] не знайдено") 
        return
    end
 
    record[field_id] = vim.split(formatted_text, "\n", { trimempty = false }) 
    state.is_changed = true 
    utils.info("Поле [" .. field_id .. "] відформатоване") 
end


-- ====================================================================
-- 3. Форматування вибраного поля ДЛЯ ВСІХ КАРТОК ОДНОЧАСНО
-- ====================================================================
function M.format_rnokpp_in_all_cards()
    if not state.records or #state.records == 0 then  
        utils.warn("Список записів порожній") 
        return  
    end 

    local field_id = state.field_name() 
    if not field_id then 
        utils.warn("Не вдалося визначити поточне поле") 
        return 
    end 

    state.snapshot()  
    local counter = 0

    for _, record in ipairs(state.records) do 
        local lines = record[field_id] or {} 
        if #lines > 0 then 
            local text = table.concat(lines, "\n") 
            
            -- Викликаємо те саме спільне ядро для кожної картки в циклі
            local formatted_text = format_text_core(text)
         
            if formatted_text then
                record[field_id] = vim.split(formatted_text, "\n", { trimempty = false }) 
                counter = counter + 1
            end
        end 
    end 

    if counter > 0 then
        state.is_changed = true 
        utils.info("Автозаміну Поля [" .. field_id .. "] успішно застосовано до " .. counter .. " карток!") 
    else
        utils.warn("РНОКПП (10 цифр) не знайдено в полі [" .. field_id .. "] жодної картки") 
    end
end

return M 
