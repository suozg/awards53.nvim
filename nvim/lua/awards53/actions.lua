-- actions.lua

local M = {}

local state = require("awards53.state")
local utils = require("awards53.utils")
local config = require("awards53.config")
local rnokpp = require("awards53.rnokpp")

-- ====================================================================
-- Допоміжні функції внутрішньої синхронізації
-- ====================================================================

-- Фіксує та зберігає незавершені редагування (якщо відкритий editor або inline)
local function sync_active_editors()
    -- 1. Якщо відкритий окремий буфер редактора (editor.lua)
    local ok_ed, editor = pcall(require, "awards53.editor")
    if ok_ed and editor.buf and vim.api.nvim_buf_is_valid(editor.buf) then
        editor.save_core(editor.buf)
    end

    -- 2. Якщо активний режим inline-редагування (ui/inline.lua)
    local ok_inl, inline = pcall(require, "awards53.ui.inline")
    if ok_inl and inline.edit_state and inline.edit_state.active then
        local ui = require("awards53.ui")
        inline.commit(ui.state, nil)
    end
end

-- Перемальовує UI або активні буфери після внесення змін
local function refresh_all()
    local ok_ed, editor = pcall(require, "awards53.editor")
    if ok_ed and editor.buf and vim.api.nvim_buf_is_valid(editor.buf) then
        editor.refresh_editor_buffer(editor.buf)
    end

    local ok_ui, ui = pcall(require, "awards53.ui")
    if ok_ui then
        ui.redraw()
    end
end

-- Допоміжна функція отримання активного поля з перевіркою
local function get_active_field()
    local field_id = state.field_name()
    if not field_id then
        utils.warn("Не вдалося визначити поточне поле")
    end
    return field_id
end

-- Допоміжна функція витягування назви нагороди з тексту картки
local function extract_award_name(rec)
    if type(rec) ~= "table" then
        return nil
    end

    -- Собираем ВСЮ карточку, а не только активное поле.
    local parts = {}

    for k, v in pairs(rec) do
        -- Игнорируем служебные поля
        if type(k) ~= "string"
            or (not k:match("^__") and not k:match("^_")) then

            if type(v) == "table" then
                for _, line in ipairs(v) do
                    if type(line) == "string" and line ~= "" then
                        table.insert(parts, line)
                    end
                end

            elseif type(v) == "string" and v ~= "" then
                table.insert(parts, v)

            elseif type(v) == "number" then
                table.insert(parts, tostring(v))
            end
        end
    end

    local text = table.concat(parts, " ")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")

    if text == "" then
        return nil
    end

    -- ---------------------------------------------------------------
    -- 1. Назва в лапках.
    -- Наприклад:
    -- нагороджено відзнакою "Золотий хрест"
    -- нагороджено "За мужність"
    -- ---------------------------------------------------------------

    local award =
        text:match('["«“]([^"»”]+)["»”]%s*%.?%s*$')

    if award and award ~= "" then
        return award
    end

    -- ---------------------------------------------------------------
    -- 2. Назва після "знаком", "відзнакою", "медаллю", "орденом"
    -- ---------------------------------------------------------------

    award =
        text:match('знаком%s*[%-%—%–]?%s*["«“]([^"»”]+)["»”]')
        or text:match('відзнакою%s*[%-%—%–]?%s*["«“]([^"»”]+)["»”]')
        or text:match('медаллю%s*[%-%—%–]?%s*["«“]([^"»”]+)["»”]')
        or text:match('орденом%s*[%-%—%–]?%s*["«“]([^"»”]+)["»”]')

    if award and award ~= "" then
        return award
    end

    -- ---------------------------------------------------------------
    -- 3. "почесним нагрудним знаком ..."
    -- ---------------------------------------------------------------

    award = text:match(
        "почесним%s+нагрудним%s+знаком%s+([^%.]+)"
    )

    if award and award ~= "" then
        return award:gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- ---------------------------------------------------------------
    -- 4. "знаком ГК ЗСУ — ..."
    -- ---------------------------------------------------------------

    award = text:match(
        "знаком%s+ГК%s+ЗСУ%s*[%-%—%–]%s*([^%.]+)"
    )

    if award and award ~= "" then
        return award:gsub("^%s+", ""):gsub("%s+$", "")
    end

    -- ---------------------------------------------------------------
    -- 5. "відзнакою — ..."
    -- ---------------------------------------------------------------

    award = text:match(
        "відзнакою%s*[%-%—%–]%s*([^%.]+)"
    )

    if award and award ~= "" then
        return award:gsub("^%s+", ""):gsub("%s+$", "")
    end

    return nil
end
-- ====================================================================
-- Спільне ядро для форматування тексту однієї картки (публічне)
-- ====================================================================
function M.format_text_core(text)
    local code, start_idx, end_idx = rnokpp.find_in_text(text)
    if not code then return nil end

    local replacement = config.options.replacement or ""
    local patterns = config.options.replacement_patterns or {}
    local unit_num = config.options.unit_number or "53"

    local before = text:sub(1, start_idx - 1)
    local after  = text:sub(end_idx + 1)

    before = before:gsub("[%s%,%.%;%-]+$", "")
    local new_text = before .. "\n" .. code .. after

    -- 1. Проводимо базові заміни за всіма шаблонами з конфіга
    for _, pattern in ipairs(patterns) do
        new_text = new_text:gsub(pattern, replacement)
    end

    -- 2. Видаляємо цифри перед назвою бригади (динамічно за номером з config.unit_number)
    local brigade_pattern = "^(.-)(" .. unit_num .. "%s+окремої.*)$"
    new_text = new_text:gsub(brigade_pattern, function(prefix, brigade)
        prefix = prefix:gsub("%d+", "")
        prefix = prefix:gsub("%s+", " ")
        return prefix .. brigade
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

-- ====================================================================
-- 1. Перемістити офіцерів на початок списку
-- ====================================================================
function M.sort_officers_first()
    if not state.records or #state.records == 0 then 
        utils.warn("Список записів порожній") 
        return 
    end 
      
    local officer_keywords = config.options.officer_keywords or {}

    local function is_officer(rec)
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

    if officer_count == 0 then
        utils.warn("У 2-му полі офіцерських звань не знайдено!")
        for _, rec in ipairs(state.records) do rec.__original_index = nil end
        return
    end

    table.sort(state.records, function(a, b) 
        local a_off = is_officer(a) 
        local b_off = is_officer(b) 
        if a_off and not b_off then return true end 
        if not a_off and b_off then return false end 
        return a.__original_index < b.__original_index 
    end) 

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

    state.current = new_current
    state.is_changed = true

    if type(state.renumber) == "function" then state.renumber() end
    if type(state.save_bookmarks) == "function" then state.save_bookmarks() end
    if type(state.sync_to_disk) == "function" then state.sync_to_disk() end

    refresh_all()
    utils.info(string.format("Переміщено офіцерів: %d", officer_count)) 
end

-- ====================================================================
-- 2. Сортування карток за назвою нагороди
-- ====================================================================
function M.sort_by_award()
    sync_active_editors()

    if type(state.records) ~= "table" or #state.records == 0 then
        utils.warn("Список записів порожній")
        return
    end

    state.snapshot()

    local current_rec = state.records[state.current]
    local found_count = 0

    -- ================================================================
    -- Підготовка
    -- ================================================================

    for idx, rec in ipairs(state.records) do
        if type(rec) == "table" then

            rec.__original_index = idx

            local award = extract_award_name(rec)

            if award then
                award = award:gsub("^%s+", "")
                award = award:gsub("%s+$", "")
                award = award:gsub("%s+", " ")

                rec.__award_name = award:lower()

                found_count = found_count + 1
            else
                -- Без нагороди — після всіх знайдених.
                rec.__award_name = "\255\255\255"
            end

            if state.bookmarks then
                rec._is_bookmarked =
                    state.bookmarks[idx] == true
            end
        end
    end

    -- ================================================================
    -- Перевірка
    -- ================================================================

    if found_count == 0 then

        for _, rec in ipairs(state.records) do
            rec.__original_index = nil
            rec.__award_name = nil
            rec._is_bookmarked = nil
        end

        utils.warn(
            "Не вдалося знайти назви нагород у картках"
        )

        return
    end

    -- ================================================================
    -- СОРТУВАННЯ
    -- ================================================================

    table.sort(state.records, function(a, b)

        if a.__award_name ~= b.__award_name then
            return a.__award_name < b.__award_name
        end

        -- Однакові нагороди залишаються
        -- у тому самому порядку.
        return a.__original_index < b.__original_index
    end)

    -- ================================================================
    -- Відновлення закладок і поточної картки
    -- ================================================================

    state.bookmarks = {}

    local new_current = 1

    for idx, rec in ipairs(state.records) do

        if rec._is_bookmarked then
            state.bookmarks[idx] = true
        end

        if current_rec and rec == current_rec then
            new_current = idx
        end

        rec._is_bookmarked = nil
        rec.__original_index = nil
        rec.__award_name = nil
    end

    state.current = new_current
    state.is_changed = true

    -- ================================================================
    -- Збереження
    -- ================================================================

    if type(state.renumber) == "function" then
        state.renumber()
    end

    if type(state.save_bookmarks) == "function" then
        state.save_bookmarks()
    end

    if type(state.sync_to_disk) == "function" then
        state.sync_to_disk()
    end

    refresh_all()

    utils.info(
        string.format(
            "Відсортовано за нагородою: %d з %d",
            found_count,
            #state.records
        )
    )
end

-- ====================================================================
-- 3. Вхідні точки для гарячих клавіш R, X, T, C
-- ====================================================================

--- ДІЯ R: Форматування РНОКПП для ПОТОЧНОЇ картки
function M.action_R()
    sync_active_editors()

    local record = state.current_record() 
    if not record then return end 

    local field_id = get_active_field()
    if not field_id then return end

    local formatted_lines = process_field(record, field_id)
    if not formatted_lines then
        utils.warn("РНОКПП (10 цифр) у Полі [" .. field_id .. "] не знайдено") 
        return
    end

    state.snapshot() 
    record[field_id] = formatted_lines
    state.is_changed = true 
    
    refresh_all()
    utils.info("Поле [" .. field_id .. "] відформатоване") 
end

--- ДІЯ X: Форматування РНОКПП для ВСІХ карток
function M.action_X()
    sync_active_editors()

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
        if (record[field_id] or {})[1] and not formatted_lines then
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
    
    refresh_all()
    utils.info("Автозаміну Поля [" .. field_id .. "] застосовано до " .. tostring(#result) .. " карток!")
end

--- ДІЯ T: Сплющування тексту для ПОТОЧНОГО поля
function M.action_S()
    sync_active_editors()

    local field_id = get_active_field()
    if not field_id then return end

    if type(state.flatten_current_field) == "function" then
        state.flatten_current_field()
    else
        local rec = state.current_record()
        if rec and rec[field_id] then
            state.snapshot()
            local flat_str = table.concat(rec[field_id], " "):gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
            rec[field_id] = { flat_str }
            state.is_changed = true
        end
    end

    refresh_all()
    utils.info("Поле [" .. field_id .. "] сплющено в один рядок")
end

--- ДІЯ C: Сплющування тексту для ПОЛЯ У ВСІХ КАРТКАХ
function M.action_E()
    sync_active_editors()

    local field_id = get_active_field()
    if not field_id then return end

    if type(state.flatten_field_globally) == "function" then
        state.flatten_field_globally()
    else
        if state.records then
            state.snapshot()
            for _, rec in ipairs(state.records) do
                if rec[field_id] then
                    local flat_str = table.concat(rec[field_id], " "):gsub("%s+", " "):gsub("^%s*", ""):gsub("%s*$", "")
                    rec[field_id] = { flat_str }
                end
            end
            state.is_changed = true
        end
    end

    refresh_all()
    utils.info("Поле [" .. field_id .. "] сплющено у всіх картках")
end

-- Аліаси для зворотної сумісності
M.format_rnokpp_in_current_card = M.action_R
M.format_rnokpp_in_all_cards = M.action_X

return M
