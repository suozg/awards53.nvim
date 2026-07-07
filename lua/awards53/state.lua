local M = {}

local cfg = require("awards53")
local utils = require("awards53.utils")
local serializer = require("awards53.serializer")
local parser = require("awards53.parser")

M.is_changed = false
M.records = {}
M.headers = {}
M.current = 1
M.field = 1
M.current_mode = "NORMAL"
M.clipboard = nil
M.undo = nil
M.source_buffer = nil
M.source_win = nil
M.last_search = nil
M.last_search_field = nil


function M.set_source_win(win)
    M.source_win = win
end

function M.get_source_win()
    return M.source_win
end

function M.set_source_buffer(buf)
    M.source_buffer = buf
end

function M.get_source_buffer()
    return M.source_buffer
end


function M.data()
    return {
        headers = M.headers,
        records = M.records,
    }
end


function M.find(text, step, field)

    field = field or M.last_search_field or cfg.config.default_sort
    text = utils.normalize(text)
    step = step or 1

    M.last_search = text
    M.last_search_field = field

    local n = #M.records
    local start = M.current

    for _ = 1, n do
        start = start + step

        if start > n then
            start = 1
        elseif start < 1 then
            start = n
        end

        local rec = M.records[start]

        local value = utils.normalize(
            table.concat(rec[field] or {}, " ")
        )

        if value:find(text, 1, true) then
            M.current = start
            return true
        end
    end

    return false
end

function M.find_next(step)
    if not M.last_search then
        return false
    end

    return M.find(
        M.last_search,
        step or 1,
        M.last_search_field
    )
end

function M.snapshot()

    M.undo = {
        records = vim.deepcopy(M.records),
        current = M.current,
        field = M.field,
    }

end


function M.undo_last()

    if not M.undo then
        return false
    end

    M.records = M.undo.records
    M.current = M.undo.current
    M.field = M.undo.field

    M.undo = nil

    return true

end


-- Копіювання поточної картки у системний буфер обміну ОС (регістр +)
function M.copy_current()
    local current_rec = M.current_record()
    if not current_rec then return false end

    -- Пакуємо одну картку для серіалізатора
    local dummy_data = {
        headers = M.headers,
        records = { vim.deepcopy(current_rec) }
    }
    
    -- Генеруємо текст
    local lines = serializer.build(dummy_data)
    
    -- Очищаємо початкові порожні рядки, які серіалізатор додає "для краси"
    while #lines > 0 and vim.trim(lines[1]) == "" do
        table.remove(lines, 1)
    end
    
    local text = table.concat(lines, "\n")

    -- Записуємо чистий текст полів у системний кліпборд
    vim.fn.setreg("+", text)
    return true
end


-- Вставка картки із системного буфера обміну ОС
function M.paste_after()
    -- 1. Якщо у файлі взагалі немає карток, ініціалізуємо records як порожній масив
    if not M.records then M.records = {} end

    -- 2. Захист індексу: якщо поточний індекс виходить за межі існуючих карток,
    -- скидаємо його на кінець масиву (або на 1, якщо файл порожній)
    if #M.records == 0 then
        M.current = 0
    elseif M.current > #M.records then
        M.current = #M.records
    elseif M.current < 1 then
        M.current = 1
    end

    -- Робимо знімок для скасування (undo) вже після валідації індексів
    M.snapshot()

    -- 3. Читаємо текст із кліпборда ОС
    local text = vim.fn.getreg("+")
    if not text or vim.trim(text) == "" then
        return false
    end

    -- Розбиваємо на рядки
    local lines = vim.split(text, "\n", { trimempty = false })
    
    -- Парсимо картку з урахуванням сепаратора
    local parsed = parser.parse(lines, cfg.config.separator)

    if not parsed.records or #parsed.records == 0 then
        return false
    end

    -- Беремо повністю відновлену картку
    local new_rec = parsed.records[1]

    -- 4. Динамічно розширюємо заголовки, якщо вставлена картка має більше полів
    for _, parsed_header in ipairs(parsed.headers) do
        local exists = false
        for _, current_header in ipairs(M.headers) do
            if current_header == parsed_header then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(M.headers, parsed_header)
        end
    end

    -- 5. Визначаємо точне і безпечне місце для вставки
    -- Якщо файл був порожній (M.current = 0), вставиться на позицію 1
    local insert_pos = M.current + 1

    table.insert(
        M.records,
        insert_pos,
        vim.deepcopy(new_rec)
    )

    -- Переводимо фокус на щойно вставлену картку
    M.current = insert_pos
    M.is_changed = true
    M.renumber()

    return true
end


function M.set(data)

    data = data or {}

    M.records = data.records or {}
    M.headers = data.headers or {}
    M.current = 1
    M.field = 1
    M.current_mode = "NORMAL"
    M.is_changed = false -- Картки щойно відкриті, змін немає
    M.renumber()
end


function M.renumber()

    for i, rec in ipairs(M.records) do
        rec.N = i
    end

end


function M.mode()
    return M.current_mode
end


function M.set_mode(mode)
    M.current_mode = mode
end


function M.count()
    return #M.records
end


function M.index()
    return M.current
end


function M.current_record()
    return M.records[M.current]
end


function M.headers_list()
    return M.headers
end


function M.field_index()
    return M.field
end


function M.field_name()
    return M.headers[M.field]
end


function M.next()

    if M.current < #M.records then
        M.current = M.current + 1
        M.field = 1
    return true
    end

    return false
end


function M.prev()

    if M.current > 1 then
        M.current = M.current - 1
        M.field = 1
        return true
    end

    return false
end


function M.goto_record(n)

    if n >= 1 and n <= #M.records then
        M.current = n
        M.field = 1
        return true
    end

    return false
end


function M.first()

    M.current = 1
    M.field = 1
end


function M.last()

    if #M.records > 0 then
        M.current = #M.records
        M.field = 1
    end

end


function M.jump(offset)

    local n = M.current + offset

    if n < 1 then
        n = 1
    elseif n > #M.records then
        n = #M.records
    end

    M.current = n
    M.field = 1

end


function M.next_field()

    if M.field < #M.headers then
        M.field = M.field + 1
        return true
    end

    return false
end


function M.prev_field()

    if M.field > 1 then
        M.field = M.field - 1
        return true
    end

    return false
end


function M.renumber()
    for i, rec in ipairs(M.records) do
        rec.N = i
    end
end


function M.sort_by(field)

    M.snapshot()
    local function norm(v)
        if type(v) == "table" then
            -- склеиваем строки и убираем лишние пробелы/переносы
            return table.concat(v, " "):gsub("%s+", " "):lower()
        end
        return (v or ""):gsub("%s+", " "):lower()
    end

    table.sort(M.records, function(a, b)
        return norm(a[field]) < norm(b[field])
    end)

    M.renumber()
    M.is_changed = true

end


function M.new_record()

    M.snapshot()
    local rec = {}

    for _, field in ipairs(M.headers) do
        rec[field] = { "" }
    end

    table.insert(M.records, rec)

    M.renumber()

    M.current = #M.records
    M.field = 1

    M.is_changed = true
end


function M.delete_current()

    M.snapshot()
    if #M.records <= 1 then
        return false
    end

    table.remove(M.records, M.current)

    if M.current > #M.records then
        M.current = #M.records
    end

    M.field = 1

    M.is_changed = true
    M.renumber()

    return true

end

function M.new_field()
    M.snapshot()

    -- Визначаємо номер нового поля (наприклад, якщо було 3, стане "4")
    local new_idx = #M.headers + 1
    local new_field_name = tostring(new_idx)

    -- Додаємо новий заголовок у список полів файлу
    table.insert(M.headers, new_field_name)

    -- Для кожної існуючої картки ініціалізуємо це нове поле порожнім рядком,
    -- щоб уникнути помилок nil під час рендеру чи редагування
    for _, rec in ipairs(M.records) do
        if not rec[new_field_name] then
            rec[new_field_name] = { "" }
        end
    end

    -- Переміщуємо фокус вибору поля на щойно створене
    M.field = new_idx
    M.is_changed = true

    return true
end
return M
