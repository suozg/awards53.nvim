local M = {}

M.records = {}
M.headers = {}
M.current = 1
M.field = 1
M.current_mode = "NORMAL"
M.clipboard = nil
M.undo = nil
M.source_buffer = nil
M.source_win = nil

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


function M.find(text)

    text = text:lower()

    for i, rec in ipairs(M.records) do

        local pib = table.concat(rec["ПІБ"] or {}, " ")

        if pib:lower():find(text, 1, true) then
            M.current = i
            return true
        end

    end

    return false
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


function M.copy_current()

    M.clipboard = vim.deepcopy(M.current_record())

    return true

end


function M.paste_after()
    
    M.snapshot()

    if not M.clipboard then
        return false
    end

    table.insert(
        M.records,
        M.current + 1,
        vim.deepcopy(M.clipboard)
    )

    M.current = M.current + 1

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

    M.renumber()

    return true

end


return M
