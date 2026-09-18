-- state.lua (Ядро керування)
--│   └── Функції: Зберігають інформацію про відкриті записи та закладки,
--                делегують історію змін (undo/redo) нативному буферу Neovim,
--                навігацію та блокування між процесами/терміналами.

local M = {}

local cfg = require("awards53")
local utils = require("awards53.utils")
local serializer = require("awards53.serializer")
local parser = require("awards53.parser")

local uv = vim.loop or vim.uv
local lock_file_path = vim.fn.stdpath("data") .. "/awards53.lock"

-- Початковий стан
M.is_changed = false
M.records = {}
M.headers = {}
M.current = 1
M.field = 1
M.last_field = 1
M.current_mode = "NORMAL"
M.clipboard = nil
M.source_buffer = nil
M.source_win = nil
M.last_search = nil
M.last_search_field = nil
M.opened_editors = {}
M.bookmarks = {}

-- Ідентифікатори станів
M.next_state_id = 0
M.current_state_id = 0
M.saved_state_id = 0

local function update_is_changed_status()
    M.is_changed = M.current_state_id ~= M.saved_state_id
end

function M.mark_as_clean()
    M.saved_state_id = M.current_state_id
    M.is_changed = false
end

-- ==========================================
-- Межпроцесне блокування (Lock-файл для терміналів)
-- ==========================================

function M.is_busy()
    -- 1. Перевірка всередині поточного процесу Neovim
    if M.source_buffer ~= nil and vim.api.nvim_buf_is_valid(M.source_buffer) then
        return true
    end

    -- 2. Перевірка між РІЗНИМИ терміналами через lock-файл
    local _, stat = uv.fs_stat(lock_file_path)
    if stat then
        local f = io.open(lock_file_path, "r")
        if f then
            local pid = tonumber(f:read("*l"))
            f:close()

            if pid then
                -- Перевіряємо, чи живий процесс PID у системі
                local is_alive = (vim.fn.jobwait({ vim.fn.jobstart({ "kill", "-0", tostring(pid) }) }, 500)[1] == 0)
                if is_alive then
                    return true -- Процес існує в іншому терміналі
                else
                    -- Процес завершився аварійно, підчищаємо старий lock
                    os.remove(lock_file_path)
                end
            end
        end
    end

    return false
end

function M.acquire_lock(buf)
    M.source_buffer = buf

    local pid = vim.fn.getpid()
    local f = io.open(lock_file_path, "w")
    if f then
        f:write(tostring(pid) .. "\n")
        f:close()
    end
end

function M.release_lock()
    M.source_buffer = nil
    M.source_win = nil

    os.remove(lock_file_path)
end

-- ==========================================
-- Перепарсинг та синхронізація
-- ==========================================

function M.reload_from_buffer()
    if not M.source_buffer or not vim.api.nvim_buf_is_valid(M.source_buffer) then
        return false
    end

    local lines = vim.api.nvim_buf_get_lines(M.source_buffer, 0, -1, false)

    local cleaned_lines = {}
    for _, line in ipairs(lines) do
        if not line:match("^%*%s+AWARDS53") then
            table.insert(cleaned_lines, line)
        end
    end

    local parsed = parser.parse(cleaned_lines, cfg.config.separator)

    M.records = parsed.records or {}
    M.headers = parsed.headers or {}

    if M.records[1] and M.records[1]["1"] then
        local val = M.records[1]["1"]
        if type(val) == "table" then
            for i = #val, 1, -1 do
                if val[i]:match("AWARDS53") then
                    table.remove(val, i)
                end
            end
            if #val == 0 then M.records[1]["1"] = { "" } end
        elseif type(val) == "string" and val:match("AWARDS53") then
            M.records[1]["1"] = { "" }
        end
    end

    M.current = math.max(1, math.min(M.current or 1, math.max(1, #M.records)))
    M.field = math.max(1, math.min(M.field or 1, math.max(1, #M.headers)))

    M.renumber()
    update_is_changed_status()

    return true
end

function M.snapshot()
    M.next_state_id = M.next_state_id + 1
    M.current_state_id = M.next_state_id
    update_is_changed_status()
end

-- ==========================================
-- Undo / Redo
-- ==========================================

function M.undo_last()
    if not M.source_buffer or not vim.api.nvim_buf_is_valid(M.source_buffer) then
        utils.warn("Джерельний буфер недоступний")
        return false
    end

    local tick_before = vim.api.nvim_buf_get_changedtick(M.source_buffer)

    vim.api.nvim_buf_call(M.source_buffer, function()
        vim.cmd("silent! undo")
    end)

    local tick_after = vim.api.nvim_buf_get_changedtick(M.source_buffer)

    if tick_before == tick_after then
        utils.warn("Немає дій для скасування (Undo)")
        return false
    end

    M.reload_from_buffer()
    utils.info("Скасовано (Undo)")

    return true
end

function M.redo_last()
    if not M.source_buffer or not vim.api.nvim_buf_is_valid(M.source_buffer) then
        utils.warn("Джерельний буфер недоступний")
        return false
    end

    local tick_before = vim.api.nvim_buf_get_changedtick(M.source_buffer)

    vim.api.nvim_buf_call(M.source_buffer, function()
        vim.cmd("silent! redo")
    end)

    local tick_after = vim.api.nvim_buf_get_changedtick(M.source_buffer)

    if tick_before == tick_after then
        utils.warn("Немає дій для повтору (Redo)")
        return false
    end

    M.reload_from_buffer()
    utils.info("Повторено (Redo)")

    return true
end

function M.get_undo_list()
    if not M.source_buffer or not vim.api.nvim_buf_is_valid(M.source_buffer) then
        return {}
    end

    local tree = vim.api.nvim_buf_call(M.source_buffer, function()
        return vim.fn.undotree()
    end)

    local entries = {}
    local current_seq = tree.seq_cur

    local function traverse(nodes)
        for _, node in ipairs(nodes) do
            local is_cur = (node.seq == current_seq)
            local time_str = os.date("%H:%M:%S", node.time)
            local preview = node.seq == 0 and "Початковий стан" or string.format("Запис #%d", node.seq)

            table.insert(entries, {
                seq = node.seq,
                time = time_str,
                is_current = is_cur,
                save = node.save,
                preview = preview,
            })

            if node.alt then
                traverse(node.alt)
            end
        end
    end

    if tree.entries then
        traverse(tree.entries)
    end

    return entries
end

function M.restore_to_seq(seq)
    if not M.source_buffer or not vim.api.nvim_buf_is_valid(M.source_buffer) then
        utils.warn("Джерельний буфер недоступний")
        return false
    end

    vim.api.nvim_buf_call(M.source_buffer, function()
        vim.cmd("silent! undo " .. seq)
    end)

    M.reload_from_buffer()
    utils.info("Відновлено стан №" .. seq)

    return true
end

-- ==========================================
-- Геттери та Сеттери
-- ==========================================

function M.set_source_win(win)
    M.source_win = win
end

function M.get_source_win()
    return M.source_win
end

function M.set_source_buffer(buf)
    if buf == nil then
        M.release_lock()
    else
        M.acquire_lock(buf)
    end
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

-- ==========================================
-- Закладки
-- ==========================================

function M.toggle_bookmark()
    local idx = M.current

    if M.bookmarks[idx] then
        M.bookmarks[idx] = nil
        utils.info("Закладку знято з картки № " .. idx)
    else
        M.bookmarks[idx] = true
        utils.info("Встановлено закладку на картку № " .. idx)
    end

    M.is_changed = true
    return true
end

function M.has_bookmark(idx)
    idx = idx or M.current
    return M.bookmarks[idx] == true
end

function M.next_bookmark()
    local n = #M.records
    if n == 0 then return false end

    local start = M.current
    for _ = 1, n do
        start = start + 1
        if start > n then start = 1 end

        if M.bookmarks[start] then
            M.current = start
            M.field = M.last_field
            return true
        end
    end

    utils.info("Закладок не знайдено")
    return false
end

function M.prev_bookmark()
    local n = #M.records
    if n == 0 then return false end

    local start = M.current
    for _ = 1, n do
        start = start - 1
        if start < 1 then start = n end

        if M.bookmarks[start] then
            M.current = start
            M.field = M.last_field
            return true
        end
    end

    utils.info("Закладок не знайдено")
    return false
end

-- ==========================================
-- Модифікація даних картки
-- ==========================================

function M.renumber()
    for i, rec in ipairs(M.records) do
        rec.N = i
    end
end

function M.collapse_empty_fields_globally()
    local original_headers_count = #M.headers

    if original_headers_count <= 1 then
        utils.info("У базі лише 1 поле. Нічого видаляти.")
        return false
    end

    M.snapshot()

    local max_non_empty_index = 1

    for _, record in ipairs(M.records) do
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

        if #non_empty_values > max_non_empty_index then
            max_non_empty_index = #non_empty_values
        end

        for idx = 1, original_headers_count do
            local key = tostring(idx)

            if idx <= #non_empty_values then
                record[key] = non_empty_values[idx]
            else
                record[key] = nil
            end
        end
    end

    local new_headers = {}
    for i = 1, max_non_empty_index do
        table.insert(new_headers, tostring(i))
    end
    M.headers = new_headers

    for _, record in ipairs(M.records) do
        for idx = 1, max_non_empty_index do
            local key = tostring(idx)
            if record[key] == nil then
                record[key] = { "" }
            end
        end
    end

    if M.field > #M.headers then
        M.field = #M.headers
    end

    M.last_field = M.field
    M.is_changed = true

    M.sync_to_disk()
    utils.info(string.format("Успішно видалено порожні поля. Максимум полів: %d", max_non_empty_index))

    return true
end

local function process_flat_field(record, key)
    local val = record[key]
    if not val then return nil end

    local combined = type(val) == "table" and table.concat(val, " ") or tostring(val)
    combined = combined:gsub("%s+", " ")

    return { combined }
end

function M.flatten_current_field()
    local record = M.current_record()
    if not record then return false end

    local key = tostring(M.field)
    local result = process_flat_field(record, key)
    if not result then return false end

    M.snapshot()
    record[key] = result
    M.is_changed = true

    M.sync_to_disk()
    utils.info("Усі рядки в полі сплющено")

    return true
end

function M.flatten_field_globally()
    local key = tostring(M.field)
    local count = 0

    for _, record in ipairs(M.records) do
        if process_flat_field(record, key) then
            count = count + 1
        end
    end

    if count == 0 then
        utils.info("Не знайдено карток для обробки")
        return false
    end

    M.snapshot()

    for _, record in ipairs(M.records) do
        local result = process_flat_field(record, key)
        if result then
            record[key] = result
        end
    end

    M.is_changed = true
    M.sync_to_disk()

    utils.info(count .. " карток сплющено")
    return true
end

-- ==========================================
-- Навігація та Пошук
-- ==========================================

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

function M.next_field()
    if M.field < #M.headers then
        M.field = M.field + 1
        M.last_field = M.field
        return true
    end
    return false
end

function M.prev_field()
    if M.field > 1 then
        M.field = M.field - 1
        M.last_field = M.field
        return true
    end
    return false
end

function M.find(text, step, field)
    field = field or M.last_search_field or cfg.config.default_sort
    text, step = utils.normalize(text), step or 1
    M.last_search, M.last_search_field = text, field

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

-- ==========================================
-- Буфер обміну та структура полів
-- ==========================================

function M.copy_current()
    local current_rec = M.current_record()
    if not current_rec then return false end

    local lines = serializer.build({
        headers = M.headers,
        records = { vim.deepcopy(current_rec) },
    })

    while #lines > 0 and vim.trim(lines[1]) == "" do
        table.remove(lines, 1)
    end

    vim.fn.setreg("+", table.concat(lines, "\n"))
    return true
end

function M.paste_after()
    M.records = M.records or {}
    M.current = #M.records == 0 and 0 or math.max(1, math.min(#M.records, M.current))

    local text = vim.fn.getreg("+")
    if not text or vim.trim(text) == "" then return false end

    text = utils.clean_invisible_chars(text)
    local parsed = parser.parse(vim.split(text, "\n", { trimempty = false }), cfg.config.separator)

    if not parsed.records or #parsed.records == 0 then return false end

    M.snapshot()

    for _, ph in ipairs(parsed.headers) do
        if not vim.tbl_contains(M.headers, ph) then
            table.insert(M.headers, ph)
        end
    end

    local insert_pos = M.current + 1
    table.insert(M.records, insert_pos, vim.deepcopy(parsed.records[1]))

    M.current = insert_pos
    M.is_changed = true

    M.renumber()
    M.sync_to_disk()

    return true
end

function M.move_field_content_up()
    local idx = M.field
    if idx <= 1 then return false end

    local record = M.current_record()
    if not record then return false end

    M.snapshot()
    local current_key, prev_key = tostring(idx), tostring(idx - 1)

    record[current_key], record[prev_key] = record[prev_key], record[current_key]

    M.field = idx - 1
    M.last_field = M.field
    M.is_changed = true

    M.sync_to_disk()
    return true
end

function M.move_field_content_down()
    local idx = M.field
    if idx >= #M.headers then return false end

    local record = M.current_record()
    if not record then return false end

    M.snapshot()
    local current_key, next_key = tostring(idx), tostring(idx + 1)

    record[current_key], record[next_key] = record[next_key], record[current_key]

    M.field = idx + 1
    M.last_field = M.field
    M.is_changed = true

    M.sync_to_disk()
    return true
end

function M.move_field_globally_up()
    local idx = M.field
    if idx <= 1 then return false end

    M.snapshot()
    local current_key, prev_key = tostring(idx), tostring(idx - 1)

    for _, record in ipairs(M.records) do
        record[current_key], record[prev_key] = record[prev_key], record[current_key]
    end

    M.field = idx - 1
    M.last_field = M.field
    M.is_changed = true

    M.sync_to_disk()
    utils.info("Поле переміщено вгору у всіх картках!")

    return true
end

function M.move_field_globally_down()
    local idx = M.field
    if idx >= #M.headers then return false end

    M.snapshot()
    local current_key, next_key = tostring(idx), tostring(idx + 1)

    for _, record in ipairs(M.records) do
        record[current_key], record[next_key] = record[next_key], record[current_key]
    end

    M.field = idx + 1
    M.last_field = M.field
    M.is_changed = true

    M.sync_to_disk()
    utils.info("Поле переміщено вниз у всіх картках!")

    return true
end

function M.set(data)
    data = data or {}

    M.records = data.records or {}
    M.headers = data.headers or {}
    M.bookmarks = data.bookmarks or {}

    M.current = math.max(1, math.min(M.current or 1, math.max(1, #M.records)))
    M.field = math.max(1, math.min(M.field or 1, math.max(1, #M.headers)))
    M.current_mode = "NORMAL"

    M.next_state_id = M.next_state_id + 1
    M.current_state_id = M.next_state_id
    M.saved_state_id = M.current_state_id

    M.is_changed = false
    M.renumber()
end

function M.sort_by(field)
    M.snapshot()

    local char2nr = vim.fn.char2nr
    local function norm(v)
        return table.concat(type(v) == "table" and v or { v or "" }, " "):gsub("%s+", " ")
    end

    local alphabet = {}
    for i, c in ipairs(vim.fn.split("АБВГҐДЕЄЖЗИІЇЙКЛМНОПРСТУФХЦЧШЩЬЮЯ", "\\zs")) do
        alphabet[c] = i
    end

    local function uk_cmp(a, b)
        a, b = vim.fn.toupper(a), vim.fn.toupper(b)
        local aa = vim.fn.split(a, "\\zs")
        local bb = vim.fn.split(b, "\\zs")

        for i = 1, math.max(#aa, #bb) do
            local ca, cb = aa[i], bb[i]
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
    M.sync_to_disk()
end

function M.new_record()
    M.snapshot()

    local rec = {}
    for _, f in ipairs(M.headers) do
        rec[f] = { "" }
    end

    table.insert(M.records, rec)
    M.renumber()

    M.current = #M.records
    M.field = 1
    M.is_changed = true

    M.sync_to_disk()
end

function M.delete_current()
    if #M.records <= 1 then return false end

    M.snapshot()
    table.remove(M.records, M.current)

    M.current = math.min(M.current, #M.records)
    M.field = 1
    M.is_changed = true

    M.renumber()
    M.sync_to_disk()

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
    M.last_field = M.field
    M.is_changed = true

    M.sync_to_disk()
    return true
end

function M.delete_field()
    if #M.headers <= 1 then return false end

    M.snapshot()

    local idx = M.field
    local total = #M.headers

    for _, record in ipairs(M.records) do
        for i = idx, total - 1 do
            record[tostring(i)] = record[tostring(i + 1)]
        end
        record[tostring(total)] = nil
    end

    table.remove(M.headers, idx)

    M.field = 1
    M.last_field = 1
    M.is_changed = true

    M.sync_to_disk()
    return true
end

function M.sync_to_disk()
    local ok, commands = pcall(require, "awards53.commands")
    if ok and type(commands.sync_org_buffer) == "function" then
        pcall(commands.sync_org_buffer)
    end
end

return M
