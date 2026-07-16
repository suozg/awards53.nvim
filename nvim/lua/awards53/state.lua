local M = {}

local cfg = require("awards53") 
local utils = require("awards53.utils") 
local serializer = require("awards53.serializer") 
local parser = require("awards53.parser") 

-- Початковий стан
M.is_changed = false 
M.records = {} 
M.headers = {} 
M.current = 1 
M.field = 1 
M.last_field = 1 
M.current_mode = "NORMAL" 
M.clipboard = nil 
M.undo = nil 
M.source_buffer = nil 
M.source_win = nil 
M.last_search = nil 
M.last_search_field = nil 

-- Швидкі inline-геттери/сеттери
function M.set_source_win(win) M.source_win = win end 
function M.get_source_win() return M.source_win end 
function M.set_source_buffer(buf) M.source_buffer = buf end 
function M.get_source_buffer() return M.source_buffer end 
function M.data() return { headers = M.headers, records = M.records } end 
function M.mode() return M.current_mode end 
function M.set_mode(mode) M.current_mode = mode end 
function M.count() return #M.records end 
function M.index() return M.current end 
function M.current_record() return M.records[M.current] end 
function M.headers_list() return M.headers end 
function M.field_index() return M.field end 
function M.field_name() return M.headers[M.field] end 

-- Оновлення порядкових номерів
function M.renumber()
    for i, rec in ipairs(M.records) do rec.N = i end 
end

-- Снапшот та Undo механізм
function M.snapshot()
    M.undo = {
        records = vim.deepcopy(M.records),
        current = M.current,
        field = M.field,
        is_changed = M.is_changed, 
    }
end

function M.undo_last()
    if not M.undo then return false end 

    M.records, M.current, M.field, M.is_changed = M.undo.records, M.undo.current, M.undo.field, M.undo.is_changed 
    M.undo = nil 
    M.renumber() 

    if not M.is_changed and M.source_buffer and vim.api.nvim_buf_is_valid(M.source_buffer) then 
        vim.bo[M.source_buffer].modified = false 
    end
    return true
end

-- схлопування порожніх полів по всьому файлу 
function M.collapse_empty_fields_globally()
    M.snapshot()

    local original_headers_count = #M.headers
    if original_headers_count <= 1 then
        utils.info("У базі лише 1 поле. Нічого видаляти.")
        return false
    end

    local max_non_empty_index = 1
    local record_with_max_fields = 1

    -- Крок 1. Спочатку зсуваємо заповнені поля вліво всередині кожної картки окремо
    for r_idx, record in ipairs(M.records) do
        local non_empty_values = {}
        
        for idx = 1, original_headers_count do
            local key = tostring(idx)
            local val = record[key]
            
            local has_text = false
            if type(val) == "table" then
                for _, line in ipairs(val) do
                    if vim.trim(line) ~= "" then
                        has_text = true
                        break
                    end
                end
            elseif type(val) == "string" and vim.trim(val) ~= "" then
                has_text = true
            end

            if has_text then
                table.insert(non_empty_values, val)
            end
        end

        -- Шукаємо, у якій саме картці найбільше заповнених полів
        if #non_empty_values > max_non_empty_index then
            max_non_empty_index = #non_empty_values
            record_with_max_fields = r_idx
        end

        -- Тимчасово очищуємо хвости в рекорді
        for idx = 1, original_headers_count do
            local key = tostring(idx)
            if idx <= #non_empty_values then
                record[key] = non_empty_values[idx]
            else
                record[key] = nil
            end
        end
    end

    -- Крок 2. Скорочуємо глобальну структуру (M.headers) до фактичного максимуму заповнених полів
    local new_headers = {}
    for i = 1, max_non_empty_index do
        table.insert(new_headers, tostring(i))
    end
    M.headers = new_headers

    -- Крок 3. Повертаємо порожні поля-заглушки для тих карток, які мають менше полів, ніж лідер
    for _, record in ipairs(M.records) do
        for idx = 1, max_non_empty_index do
            local key = tostring(idx)
            if record[key] == nil then
                record[key] = { "" }
            end
        end
    end

    -- Крок 4. Коригуємо позицію активного поля
    if M.field > #M.headers then
        M.field = #M.headers
    end
    M.last_field = M.field
    M.is_changed = true

    -- Крок 5. Рахуємо статистику для повідомлення користувачеві
    local deleted_count = original_headers_count - max_non_empty_index
    
    -- Рахуємо мінімальну кількість полів серед усіх карток, щоб знайти порожні "хвости"
    local min_non_empty_index = max_non_empty_index
    for _, record in ipairs(M.records) do
        local current_count = 0
        for idx = 1, max_non_empty_index do
            local val = record[tostring(idx)]
            -- Перевіряємо чи поле реально заповнене
            local has_text = false
            if type(val) == "table" then
                for _, line in ipairs(val) do
                    if vim.trim(line) ~= "" then has_text = true break end
                end
            elseif type(val) == "string" and vim.trim(val) ~= "" then
                has_text = true
            end
            if has_text then current_count = current_count + 1 end
        end
        if current_count < min_non_empty_index then
            min_non_empty_index = current_count
        end
    end

    -- Формуємо діапазон видалених глобальних полів
    local deleted_range = ""
    if deleted_count == 1 then
        deleted_range = tostring(original_headers_count)
    elseif deleted_count > 1 then
        deleted_range = string.format("%d-%d", max_non_empty_index + 1, original_headers_count)
    end

    -- Формуємо діапазон порожніх полів, що залишилися внизу інших карток через лідера
    local left_empty_range = ""
    if max_non_empty_index > min_non_empty_index then
        if (max_non_empty_index - min_non_empty_index) == 1 then
            left_empty_range = tostring(max_non_empty_index)
        else
            left_empty_range = string.format("%d-%d", min_non_empty_index + 1, max_non_empty_index)
        end
    end

    -- Виводимо інформацію користувачу
    local deleted_count = original_headers_count - max_non_empty_index

    local deleted_range = deleted_count == 1 and tostring(original_headers_count) 
        or string.format("%d-%d", max_non_empty_index + 1, original_headers_count)

    local left_empty_range = ""
    if max_non_empty_index > min_non_empty_index then
        left_empty_range = (max_non_empty_index - min_non_empty_index) == 1 and tostring(max_non_empty_index)
            or string.format("%d-%d", min_non_empty_index + 1, max_non_empty_index)
    end

    if deleted_count > 0 and left_empty_range ~= "" then
        utils.info(string.format(
            "Видалено [%s] порожніх полів. Але через Картку №%d (має %d) в інших залишилися порожніми поля [%s].",
            deleted_range, record_with_max_fields, max_non_empty_index, left_empty_range
        ))
    elseif deleted_count > 0 then
        utils.info(string.format(
            "Успішно видалено [%s] порожніх полів. Тепер у всіх картках порівну полів (%d).",
            deleted_range, max_non_empty_index
        ))
    elseif left_empty_range ~= "" then
        utils.info(string.format(
            "Порожні поля не видалялися. Через Картку №%d (має %d полів) в інших картках порожніють поля [%s].",
            record_with_max_fields, max_non_empty_index, left_empty_range
        ))
    else
        utils.info(string.format(
            "Всі %d полів повністю заповнені в усіх картках. Нічого видаляти.",
            original_headers_count
        ))
    end

    return true
end


-- =========================================================================
-- Допоміжна функція для обробки та переформатування тексту поля
-- =========================================================================
local function process_flat_field(record, key)
    local val = record[key]
    if not val then return nil end

    local combined = type(val) == "table" and table.concat(val, " ") or tostring(val)
    combined = combined:gsub("%s+", " ")

    -- Використовуємо спільну логіку форматування з actions.lua
    local actions = require("awards53.actions")
    local formatted = actions.format_text_core(combined)

    if formatted then
        return vim.split(formatted, "\n", { trimempty = false })
    else
        return { combined }
    end
end

-- Обробка ТІЛЬКИ для поточної картки
function M.flatten_current_field()
    local record = M.current_record()
    if not record then return false end
    
    local key = tostring(M.field)
    local result = process_flat_field(record, key)
    if not result then return false end

    M.snapshot()
    record[key] = result
    M.is_changed = true
    utils.info("Поточне поле успішно відформатовано та замінено в/ч")
    return true
end

-- Глобальна обробка ДЛЯ ВСІХ КАРТОК
function M.flatten_field_globally()
    M.snapshot()
    local key = tostring(M.field)
    local count = 0

    for _, record in ipairs(M.records) do
        local result = process_flat_field(record, key)
        if result then
            record[key] = result
            count = count + 1
        end
    end

    if count > 0 then
        M.is_changed = true
        utils.info("Глобально відформатовано карток із заміною в/ч: " .. count)
        return true
    else
        utils.info("Не знайдено карток для обробки")
        return false
    end
end


-- Навігація по картках 
local function adjust_navigation(new_pos)
    if new_pos >= 1 and new_pos <= #M.records then
        M.current = new_pos
        M.field = M.last_field
        return true
    end
    return false
end

function M.next() return adjust_navigation(M.current + 1) end 
function M.prev() return adjust_navigation(M.current - 1) end 
function M.goto_record(n) return adjust_navigation(n) end 
function M.first() adjust_navigation(1) end 
function M.last() adjust_navigation(#M.records) end 

function M.jump(offset)
    local n = math.max(1, math.min(#M.records, M.current + offset))
    adjust_navigation(n)
end

-- Навігація по полях
function M.next_field()
    if M.field < #M.headers then M.field = M.field + 1; M.last_field = M.field; return true end 
    return false
end

function M.prev_field()
    if M.field > 1 then M.field = M.field - 1; M.last_field = M.field; return true end 
    return false
end

-- Пошукова логіка
function M.find(text, step, field)
    field = field or M.last_search_field or cfg.config.default_sort 
    text, step = utils.normalize(text), step or 1 
    M.last_search, M.last_search_field = text, field 

    local n = #M.records
    local start = M.current

    for _ = 1, n do
        start = start + step
        if start > n then start = 1 elseif start < 1 then start = n end 

        local rec = M.records[start]
        local value = utils.normalize(table.concat(rec[field] or {}, " ")) 

        if value:find(text, 1, true) then
            M.current = start
            return true
        end
    end
    return false
end

function M.find_next(step)
    return M.last_search and M.find(M.last_search, step or 1, M.last_search_field) or false 
end

-- Копіювання та Вставка (Робота з буфером)
function M.copy_current()
    local current_rec = M.current_record()
    if not current_rec then return false end 

    local lines = serializer.build({ headers = M.headers, records = { vim.deepcopy(current_rec) } }) 
    while #lines > 0 and vim.trim(lines[1]) == "" do table.remove(lines, 1) end 
    
    vim.fn.setreg("+", table.concat(lines, "\n")) 
    return true
end

function M.paste_after()
    M.records = M.records or {} 
    M.current = #M.records == 0 and 0 or math.max(1, math.min(#M.records, M.current)) 

    M.snapshot() 

    local text = vim.fn.getreg("+")
    if not text or vim.trim(text) == "" then return false end 

    local parsed = parser.parse(vim.split(text, "\n", { trimempty = false }), cfg.config.separator) 
    if not parsed.records or #parsed.records == 0 then return false end 

    for _, ph in ipairs(parsed.headers) do
        if not vim.tbl_contains(M.headers, ph) then table.insert(M.headers, ph) end
    end

    local insert_pos = M.current + 1
    table.insert(M.records, insert_pos, vim.deepcopy(parsed.records[1])) 

    M.current, M.is_changed = insert_pos, true 
    M.renumber() 
    return true
end


-- =========================================================================
-- ЛОКАЛЬНЕ ПЕРЕМІЩЕННЯ (Тільки в поточній картці)
-- =========================================================================

function M.move_field_content_up()
    local idx = M.field
    if idx <= 1 then return false end 

    M.snapshot()
    local record = M.current_record()
    if not record then return false end

    local current_key = tostring(idx)
    local prev_key = tostring(idx - 1)

    record[current_key], record[prev_key] = record[prev_key], record[current_key]
    
    M.field = idx - 1
    M.last_field = M.field
    M.is_changed = true
    return true
end

function M.move_field_content_down()
    local idx = M.field
    if idx >= #M.headers then return false end 

    M.snapshot()
    local record = M.current_record()
    if not record then return false end

    local current_key = tostring(idx)
    local next_key = tostring(idx + 1)

    record[current_key], record[next_key] = record[next_key], record[current_key]
    
    M.field = idx + 1
    M.last_field = M.field
    M.is_changed = true
    return true
end

-- =========================================================================
-- ГЛОБАЛЬНЕ ПЕРЕМІЩЕННЯ (Структурне, для всіх карток разом)
-- =========================================================================

function M.move_field_globally_up()
    local idx = M.field
    if idx <= 1 then return false end 

    M.snapshot()
    local current_key = tostring(idx)
    local prev_key = tostring(idx - 1)

    for _, record in ipairs(M.records) do
        record[current_key], record[prev_key] = record[prev_key], record[current_key]
    end
    
    M.field = idx - 1
    M.last_field = M.field
    M.is_changed = true
    utils.info("Поле переміщено вгору у всіх картках!")
    return true
end

function M.move_field_globally_down()
    local idx = M.field
    if idx >= #M.headers then return false end 

    M.snapshot()
    local current_key = tostring(idx)
    local next_key = tostring(idx + 1)

    for _, record in ipairs(M.records) do
        record[current_key], record[next_key] = record[next_key], record[current_key]
    end
    
    M.field = idx + 1
    M.last_field = M.field
    M.is_changed = true
    utils.info("Поле переміщено вниз у всіх картках!")
    return true
end

function M.set(data)
    data = data or {} 
    M.records, M.headers = data.records or {}, data.headers or {} 
    M.current, M.field, M.current_mode, M.is_changed = 1, 1, "NORMAL", false 
    M.renumber() 
end

-- ФУНКЦІЯ СОРТУВАННЯ
function M.sort_by(field)
    M.snapshot()

    local char2nr = vim.fn.char2nr
    
    local function norm(v)
        return table.concat(type(v) == "table" and v or {v or ""}, " ")
            :gsub("%s+", " ")
    end

    local alphabet = {}

    for i, c in ipairs(vim.fn.split(
        "АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ", "\\zs")) do
        alphabet[c] = i
    end

    local function uk_cmp(a, b)
        a = vim.fn.toupper(a)
        b = vim.fn.toupper(b)

        local aa = vim.fn.split(a, "\\zs")
        local bb = vim.fn.split(b, "\\zs")

        local n = math.max(#aa, #bb)

        for i = 1, n do
            local ca = aa[i]
            local cb = bb[i]

            if ca == nil then return true end
            if cb == nil then return false end

            local va = alphabet[ca] or (1000 + char2nr(ca))
            local vb = alphabet[cb] or (1000 + char2nr(cb))
            if va ~= vb then
                return va < vb
            end
        end

        return false
    end

    table.sort(M.records, function(a, b)
        return uk_cmp(norm(a[field]), norm(b[field]))
    end)

    M.renumber()
    M.is_changed = true
end


function M.new_record()
    M.snapshot() 
    local rec = {}
    for _, f in ipairs(M.headers) do rec[f] = { "" } end 
    
    table.insert(M.records, rec) 
    M.renumber() 
    M.current, M.field, M.is_changed = #M.records, 1, true 
end

function M.delete_current()
    M.snapshot() 
    if #M.records <= 1 then return false end 

    table.remove(M.records, M.current) 
    M.current = math.min(M.current, #M.records) 
    M.field, M.is_changed = 1, true 
    M.renumber() 
    return true
end

function M.new_field(default_value)
    M.snapshot() 

    local current_idx = M.field or #M.headers
    local insert_idx = current_idx + 1
    local total_headers = #M.headers

    local val = default_value or ""

    for _, record in ipairs(M.records) do
        for i = total_headers, insert_idx, -1 do
            record[tostring(i + 1)] = record[tostring(i)]
        end
        record[tostring(insert_idx)] = { val }
    end

    table.insert(M.headers, tostring(total_headers + 1)) 

    M.field = insert_idx
    M.last_field, M.is_changed = M.field, true 
    return true
end

function M.delete_field()
    if #M.headers <= 1 then return false end 
    M.snapshot() 

    local idx, total = M.field, #M.headers 
    for _, record in ipairs(M.records) do
        for i = idx, total - 1 do
            record[tostring(i)] = record[tostring(i + 1)] 
        end
        record[tostring(total)] = nil 
    end

    table.remove(M.headers, total) 
    M.field, M.last_field, M.is_changed = 1, 1, true 
    return true
end

function M.sync_to_disk()
    require("awards53.commands").sync_org_buffer()
end

return M
