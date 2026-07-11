local M = {}

local cfg = require("awards53") --
local utils = require("awards53.utils") --
local serializer = require("awards53.serializer") --
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

    -- Синхронізація унікальних заголовків
    for _, ph in ipairs(parsed.headers) do
        if not vim.tbl_contains(M.headers, ph) then table.insert(M.headers, ph) end
    end

    local insert_pos = M.current + 1
    table.insert(M.records, insert_pos, vim.deepcopy(parsed.records[1])) 

    M.current, M.is_changed = insert_pos, true 
    M.renumber() 
    return true
end

-- Ініціалізація та модифікація даних реєстру
function M.set(data)
    data = data or {} 
    M.records, M.headers = data.records or {}, data.headers or {} 
    M.current, M.field, M.current_mode, M.is_changed = 1, 1, "NORMAL", false 
    M.renumber() 
end

function M.sort_by(field)
    M.snapshot() 
    local function norm(v)
        return table.concat(type(v) == "table" and v or {v or ""}, " "):gsub("%s+", " "):lower() 
    end
    table.sort(M.records, function(a, b) return norm(a[field]) < norm(b[field]) end) 
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

function M.new_field()
    M.snapshot() 
    local new_field_name = tostring(#M.headers + 1) 

    table.insert(M.headers, new_field_name) 
    for _, rec in ipairs(M.records) do
        if not rec[new_field_name] then rec[new_field_name] = { "" } end 
    end

    M.field = #M.headers 
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
