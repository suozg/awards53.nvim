-- actions.lua

local M = {}

local state = require("awards53.state") 
local utils = require("awards53.utils") 
local replacement = "53 окремої механізованої бригади імені князя Володимира Мономаха 3 армійського корпусу оперативного командування \"Схід\" Сухопутних військ Збройних Cил України" 

-- ====================================================================
-- Спільне ядро для форматування тексту однієї картки (публічне)
-- ====================================================================
function M.format_text_core(text)
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
    new_text = new_text:gsub("^(.-)(53%s+окремої.*)$", function(before, brigade)
        before = before:gsub("%d+", "")
        before = before:gsub("%s+", " ")
        return before .. brigade
    end)

    return new_text
end

-- Допоміжна функція для форматування конкретного поля в записі
local function process_field(record, field_id)
    local lines = record[field_id] or {}
    if #lines == 0 then return nil end

    local text = table.concat(lines, "\n")
    local formatted = M.format_text_core(text)
    if not formatted then return nil end

    return vim.split(formatted, "\n", { trimempty = false })
end

-- Допоміжна функція отримання активного поля з перевіркою
local function get_active_field()
    local field_id = state.field_name()
    if not field_id then
        utils.warn("Не вдалося визначити поточне поле")
    end
    return field_id
end

-- ====================================================================
-- 1. Перемістити офіцерів на початок списку
-- ====================================================================
function M.sort_officers_first()
    local cfg = require("awards53") 
    
    if not state.records or #state.records == 0 then 
        utils.warn("Список записів порожній") 
        return 
    end 

    -- Ключові слова та скорочення
    local officer_keywords = { 
        "лейтенант", 
        "капітан", 
        "майор",
        "підполков",
        "полковник", 
        "генерал" 
    } 

    -- Перевірка звання ВИКЛЮЧНО в полі "2" (або [2])
    local function is_officer(rec)
        -- Перевіряємо за ключем "2" або числовому індексу 2
        local val = rec["2"] or rec[2]
        if not val then return false end 

        local text = ""
        if type(val) == "table" then
            text = table.concat(val, " ")
        elseif type(val) == "string" or type(val) == "number" then
            text = tostring(val)
        end
        
        text = text:lower()
        for _, kw in ipairs(officer_keywords) do 
            if text:find(kw, 1, true) then 
                return true 
            end 
        end 
        return false 
    end 

    -- 1. Фіксуємо активну картку та збираємо кількість офіцерів у 2 полі
    local current_rec = state.records[state.current]
    local officer_count = 0

    for idx, rec in ipairs(state.records) do 
        rec.__original_index = idx 
        if is_officer(rec) then
            officer_count = officer_count + 1
        end
        if state.bookmarks then
            rec._is_bookmarked = state.bookmarks[idx] == true
        end
    end 

    -- Якщо офіцерів у 2 полі не знайдено
    if officer_count == 0 then
        utils.warn("У 2-му полі офіцерських звань не знайдено!")
        for idx, rec in ipairs(state.records) do rec.__original_index = nil end
        return
    end

    -- 2. Сортуємо (офіцери з 2 поля — на початок)
    table.sort(state.records, function(a, b) 
        local a_off = is_officer(a) 
        local b_off = is_officer(b) 
        if a_off and not b_off then return true end 
        if not a_off and b_off then return false end 
        return a.__original_index < b.__original_index 
    end) 

    -- 3. Відновлюємо індекси закладок та активну картку
    state.bookmarks = {}
    local new_current = 1

    for i, rec in ipairs(state.records) do 
        if rec._is_bookmarked then
            state.bookmarks[i] = true
            rec._is_bookmarked = nil
        end
        if current_rec and rec == current_rec then
            new_current = i
        end
        rec.__original_index = nil 
    end 

    -- 4. Оновлюємо стан та синхронізуємо
    state.current = new_current
    state.is_changed = true

    if type(state.renumber) == "function" then state.renumber() end
    if type(state.save_bookmarks) == "function" then state.save_bookmarks() end
    if type(state.sync_to_disk) == "function" then state.sync_to_disk() end

    -- 5. Примусове перемалювання
    local ui = package.loaded["awards53.ui"] or package.loaded["ui"]
    if ui and type(ui.render) == "function" then
        ui.render()
    elseif type(state.render) == "function" then
        state.render()
    end

    utils.info(string.format("Переміщено офіцерів: %d", officer_count)) 
end

-- ====================================================================
-- 2. Форматування вибраного поля ДЛЯ ПОТОЧНОЇ КАРТКИ
-- ====================================================================
function M.format_rnokpp_in_current_card()
    local record = state.current_record() 
    if not record then return end 
 
    local field_id = get_active_field()
    if not field_id then return end

    local formatted_lines = process_field(record, field_id)
    if not formatted_lines then
        utils.warn("РНОКПП (10 цифр підряд) у Полі [" .. field_id .. "] не знайдено") 
        return
    end
 
    state.snapshot() 
    record[field_id] = formatted_lines
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

    local field_id = get_active_field()
    if not field_id then return end

    state.snapshot()  

    local result = {}
    for i, record in ipairs(state.records) do
        local formatted_lines = process_field(record, field_id)
        if (record[field_id] or {} )[1] and not formatted_lines then
            utils.warn("РНОКПП (10 цифр) не знайдено у картці №" .. i)
            return
        end
        if formatted_lines then
            result[i] = formatted_lines
        end
    end

    for i, formatted_lines in pairs(result) do
        state.records[i][field_id] = formatted_lines
    end

    state.is_changed = true
    utils.info("Автозаміну Поля [" .. field_id .. "] успішно застосовано до " .. tostring(#result) .. " карток!")
end

return M
